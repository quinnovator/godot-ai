from __future__ import annotations

import io
import json
import struct
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

from godot_agent.blender import BLENDER_INVOCATION_SCHEMA_VERSION, BlenderBuildError
from godot_agent.blender_batch import (
    BLENDER_BATCH_SCHEMA_VERSION,
    build_blender_batch,
    load_blender_batch,
)
from godot_agent.cli import main


def valid_glb() -> bytes:
    json_chunk = b"{}  "
    size = 12 + 8 + len(json_chunk)
    return struct.pack("<4sII", b"glTF", 2, size) + struct.pack("<I4s", len(json_chunk), b"JSON") + json_chunk


def make_executable(path: Path) -> Path:
    path.write_text("fake blender", encoding="utf-8")
    path.chmod(0o755)
    return path


def argument_value(command, name):
    return command[command.index(name) + 1]


def write_recipe(project: Path, name: str = "build_candidate.py") -> Path:
    script = project / "tools" / name
    script.parent.mkdir(parents=True, exist_ok=True)
    script.write_text("import bpy\n", encoding="utf-8")
    return script


def write_batch(project: Path, jobs, **overrides) -> Path:
    value = {
        "schema_version": BLENDER_BATCH_SCHEMA_VERSION,
        "name": "test candidates",
        "max_workers": 2,
        "result": "res://results/test-batch.json",
        "jobs": jobs,
    }
    value.update(overrides)
    path = project / "batch.json"
    path.write_text(json.dumps(value), encoding="utf-8")
    return path


def complete_blender(command, *, stdout="done", stderr=""):
    Path(argument_value(command, "--output")).write_bytes(valid_glb())
    if "--blend" in command:
        Path(argument_value(command, "--blend")).write_bytes(b"BLENDER-v400")
    Path(argument_value(command, "--receipt")).write_text(
        json.dumps(
            {
                "blender_version": "4.3.2",
                "invocation_schema_version": BLENDER_INVOCATION_SCHEMA_VERSION,
            }
        ),
        encoding="utf-8",
    )
    return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr=stderr)


class BlenderBatchTests(unittest.TestCase):
    def test_dry_run_validates_without_blender_or_writes(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            write_recipe(project)
            batch = write_batch(
                project,
                [
                    {
                        "id": "pitcher-a",
                        "script": "res://tools/build_candidate.py",
                        "output": "res://assets/pitcher-a.glb",
                        "parameters": {"role": "pitcher"},
                    },
                    {
                        "id": "glove-a",
                        "script": "res://tools/build_candidate.py",
                        "output": "res://assets/glove-a.glb",
                        "blend": "res://sources/glove-a.blend",
                        "parameters": {"kind": "glove"},
                    },
                ],
            )

            with mock.patch("godot_agent.blender_batch.locate_blender") as locate, mock.patch(
                "godot_agent.blender.subprocess.run"
            ) as runner:
                result = build_blender_batch(project, batch, dry_run=True, max_workers=1)

            locate.assert_not_called()
            runner.assert_not_called()
            self.assertTrue(result["ok"])
            self.assertTrue(result["dry_run"])
            self.assertEqual(result["status"], "planned")
            self.assertEqual(result["max_workers"], 1)
            self.assertEqual([job["id"] for job in result["jobs"]], ["pitcher-a", "glove-a"])
            self.assertEqual(result["jobs"][0]["paths"]["log"], "res://assets/pitcher-a.glb.agent.log")
            self.assertEqual(result["jobs"][0]["paths"]["manifest"], "res://assets/pitcher-a.glb.agent.json")
            self.assertFalse((project / "results" / "test-batch.json").exists())
            self.assertFalse((project / "assets").exists())

    def test_jobs_run_concurrently_and_results_remain_source_ordered(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            write_recipe(project)
            executable = make_executable(project / "fake-blender")
            batch = write_batch(
                project,
                [
                    {
                        "id": "slow-first",
                        "script": "res://tools/build_candidate.py",
                        "output": "res://assets/slow.glb",
                        "parameters": {"delay": 0.08, "variant": "slow"},
                    },
                    {
                        "id": "fast-second",
                        "script": "res://tools/build_candidate.py",
                        "output": "res://assets/fast.glb",
                        "parameters": {"delay": 0.01, "variant": "fast"},
                    },
                    {
                        "id": "third",
                        "script": "res://tools/build_candidate.py",
                        "output": "res://assets/third.glb",
                        "blend": "res://sources/third.blend",
                        "parameters": {"delay": 0.02, "variant": "third"},
                    },
                ],
            )
            lock = threading.Lock()
            active = 0
            maximum_active = 0
            completion_order = []

            def concurrent_blender(command, **_kwargs):
                nonlocal active, maximum_active
                parameters = json.loads(Path(argument_value(command, "--parameters")).read_text(encoding="utf-8"))
                with lock:
                    active += 1
                    maximum_active = max(maximum_active, active)
                try:
                    time.sleep(parameters["delay"])
                    completed = complete_blender(command, stdout="built " + parameters["variant"])
                    with lock:
                        completion_order.append(parameters["variant"])
                    return completed
                finally:
                    with lock:
                        active -= 1

            with mock.patch("godot_agent.blender.subprocess.run", side_effect=concurrent_blender):
                result = build_blender_batch(project, batch, blender=executable, max_workers=2)

            self.assertTrue(result["ok"])
            self.assertEqual(maximum_active, 2)
            self.assertNotEqual(completion_order, ["slow", "fast", "third"])
            self.assertEqual(
                [job["id"] for job in result["jobs"]],
                ["slow-first", "fast-second", "third"],
            )
            self.assertEqual(result["summary"], {"failed": 0, "planned": 0, "succeeded": 3, "total": 3})
            for job in result["jobs"]:
                output = project / job["paths"]["output"].removeprefix("res://")
                manifest = project / job["paths"]["manifest"].removeprefix("res://")
                log = project / job["paths"]["log"].removeprefix("res://")
                self.assertTrue(output.is_file())
                self.assertTrue(manifest.is_file())
                self.assertEqual(json.loads(log.read_text(encoding="utf-8"))["status"], "succeeded")
                self.assertEqual(
                    json.loads(manifest.read_text(encoding="utf-8"))["parameters"],
                    job["parameters"],
                )
            persisted = json.loads((project / "results" / "test-batch.json").read_text(encoding="utf-8"))
            self.assertEqual(persisted, result)

    def test_partial_failure_keeps_success_and_returns_cli_json(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            write_recipe(project)
            executable = make_executable(project / "fake-blender")
            batch = write_batch(
                project,
                [
                    {
                        "id": "good",
                        "script": "res://tools/build_candidate.py",
                        "output": "res://assets/good.glb",
                        "parameters": {"fail": False},
                    },
                    {
                        "id": "bad",
                        "script": "res://tools/build_candidate.py",
                        "output": "res://assets/bad.glb",
                        "parameters": {"fail": True},
                    },
                ],
            )
            (project / "assets").mkdir()
            (project / "assets" / "bad.glb").write_bytes(b"existing bad target")

            def partially_failing_blender(command, **_kwargs):
                parameters = json.loads(Path(argument_value(command, "--parameters")).read_text(encoding="utf-8"))
                if parameters["fail"]:
                    return subprocess.CompletedProcess(command, 7, stdout="", stderr="candidate failed")
                return complete_blender(command)

            stdout = io.StringIO()
            stderr = io.StringIO()
            with mock.patch("godot_agent.blender.subprocess.run", side_effect=partially_failing_blender):
                exit_code = main(
                    [
                        "--project",
                        str(project),
                        "--compact",
                        "blender-batch",
                        str(batch),
                        "--blender",
                        str(executable),
                        "--max-workers",
                        "2",
                    ],
                    stdout=stdout,
                    stderr=stderr,
                )

            self.assertEqual(exit_code, 1)
            self.assertEqual(stderr.getvalue(), "")
            result = json.loads(stdout.getvalue())
            self.assertFalse(result["ok"])
            self.assertEqual(result["status"], "partial_failure")
            self.assertEqual(result["summary"]["succeeded"], 1)
            self.assertEqual(result["summary"]["failed"], 1)
            self.assertTrue((project / "assets" / "good.glb").is_file())
            self.assertTrue((project / "assets" / "good.glb.agent.json").is_file())
            self.assertEqual((project / "assets" / "bad.glb").read_bytes(), b"existing bad target")
            self.assertFalse((project / "assets" / "bad.glb.agent.json").exists())
            bad_log = json.loads((project / "assets" / "bad.glb.agent.log").read_text(encoding="utf-8"))
            self.assertEqual(bad_log["status"], "failed")
            self.assertIn("status 7", bad_log["error"])
            self.assertTrue((project / "results" / "test-batch.json").is_file())
            self.assertFalse((project / ".godot" / "agent" / "endpoint.json").exists())

    def test_missing_blender_still_writes_stable_failure_logs_and_result(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            write_recipe(project)
            batch = write_batch(
                project,
                [
                    {
                        "id": "one",
                        "script": "res://tools/build_candidate.py",
                        "output": "res://assets/one.glb",
                    },
                    {
                        "id": "two",
                        "script": "res://tools/build_candidate.py",
                        "output": "res://assets/two.glb",
                    },
                ],
            )
            with mock.patch(
                "godot_agent.blender_batch.locate_blender",
                side_effect=BlenderBuildError("Blender unavailable"),
            ):
                result = build_blender_batch(project, batch)

            self.assertFalse(result["ok"])
            self.assertEqual([job["id"] for job in result["jobs"]], ["one", "two"])
            for job in result["jobs"]:
                log = project / job["paths"]["log"].removeprefix("res://")
                self.assertEqual(json.loads(log.read_text(encoding="utf-8"))["error"], "Blender unavailable")
            self.assertTrue((project / "results" / "test-batch.json").is_file())

    def test_duplicate_and_conflicting_paths_are_rejected_before_launch(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            write_recipe(project)
            batch = write_batch(
                project,
                [
                    {
                        "id": "one",
                        "script": "res://tools/build_candidate.py",
                        "output": "res://assets/Player.glb",
                    },
                    {
                        "id": "two",
                        "script": "res://tools/build_candidate.py",
                        "output": "res://assets/player.glb",
                    },
                ],
            )
            with mock.patch("godot_agent.blender_batch.locate_blender") as locate, mock.patch(
                "godot_agent.blender.subprocess.run"
            ) as runner:
                with self.assertRaisesRegex(BlenderBuildError, "conflicting Blender batch outputs"):
                    build_blender_batch(project, batch, dry_run=True)
            locate.assert_not_called()
            runner.assert_not_called()

            conflicting_result = write_batch(
                project,
                [
                    {
                        "id": "one",
                        "script": "res://tools/build_candidate.py",
                        "output": "res://assets/model.glb",
                    }
                ],
                result="res://assets/model.glb.agent.json",
            )
            with self.assertRaisesRegex(BlenderBuildError, "conflicting Blender batch outputs"):
                load_blender_batch(project, conflicting_result)

    def test_cli_dry_run_is_json_and_does_not_require_editor_or_blender(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            write_recipe(project)
            batch = write_batch(
                project,
                [
                    {
                        "id": "candidate",
                        "script": "res://tools/build_candidate.py",
                        "output": "res://assets/candidate.glb",
                    }
                ],
            )
            stdout = io.StringIO()
            stderr = io.StringIO()
            with mock.patch("godot_agent.blender_batch.locate_blender") as locate:
                exit_code = main(
                    [
                        "--project",
                        str(project),
                        "--compact",
                        "blender-batch",
                        str(batch),
                        "--dry-run",
                    ],
                    stdout=stdout,
                    stderr=stderr,
                )
            locate.assert_not_called()
            self.assertEqual(exit_code, 0, stderr.getvalue())
            self.assertTrue(json.loads(stdout.getvalue())["dry_run"])
            self.assertFalse((project / ".godot" / "agent" / "endpoint.json").exists())


if __name__ == "__main__":
    unittest.main()
