from __future__ import annotations

import hashlib
import io
import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from godot_agent import blender_bootstrap
from godot_agent.blender import (
    BLENDER_INVOCATION_SCHEMA_VERSION,
    BlenderBuildError,
    build_blender_asset,
    locate_blender,
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


def successful_blender(command, **_kwargs):
    Path(argument_value(command, "--output")).write_bytes(valid_glb())
    if "--blend" in command:
        Path(argument_value(command, "--blend")).write_bytes(b"BLENDER-v400")
    Path(argument_value(command, "--receipt")).write_text(
        json.dumps({
            "blender_version": "4.3.2",
            "invocation_schema_version": BLENDER_INVOCATION_SCHEMA_VERSION,
        }),
        encoding="utf-8",
    )
    return subprocess.CompletedProcess(command, 0, stdout="Blender done", stderr="")


class BlenderBuildTests(unittest.TestCase):
    def test_bootstrap_exports_semantic_custom_properties_as_gltf_extras(self):
        export_options = {}

        def export_gltf(**options):
            export_options.update(options)
            return {"FINISHED"}

        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            script = directory / "recipe.py"
            script.write_text("pass\n", encoding="utf-8")
            receipt = directory / "receipt.json"
            fake_bpy = SimpleNamespace(
                app=SimpleNamespace(version_string="5.1.2"),
                ops=SimpleNamespace(
                    export_scene=SimpleNamespace(gltf=export_gltf),
                    wm=SimpleNamespace(save_as_mainfile=lambda **_kwargs: {"FINISHED"}),
                ),
            )
            argv = [
                "Blender",
                "--",
                "--schema-version",
                str(BLENDER_INVOCATION_SCHEMA_VERSION),
                "--script",
                str(script),
                "--output",
                str(directory / "asset.glb"),
                "--receipt",
                str(receipt),
            ]
            with mock.patch.dict("sys.modules", {"bpy": fake_bpy}), mock.patch("sys.argv", argv):
                blender_bootstrap.main()

        self.assertTrue(export_options["export_extras"])
        self.assertEqual(export_options["export_format"], "GLB")

    def test_build_stages_validates_and_writes_deterministic_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            script = project / "tools" / "make_runner.py"
            script.parent.mkdir()
            script.write_text("import bpy\n", encoding="utf-8")
            executable = make_executable(project / "fake-blender")

            with mock.patch("godot_agent.blender.subprocess.run", side_effect=successful_blender) as runner:
                first = build_blender_asset(
                    project,
                    "res://tools/make_runner.py",
                    "res://assets/runner.glb",
                    blend="res://assets/runner.blend",
                    blender=executable,
                )
                manifest_path = project / "assets" / "runner.glb.agent.json"
                first_manifest_bytes = manifest_path.read_bytes()
                second = build_blender_asset(
                    project,
                    "tools/make_runner.py",
                    "res://assets/runner.glb",
                    blend="res://assets/runner.blend",
                    blender=executable,
                )

            self.assertEqual(first, second)
            self.assertEqual(first_manifest_bytes, manifest_path.read_bytes())
            self.assertEqual(first["blender_version"], "4.3.2")
            self.assertEqual(first["invocation_schema_version"], BLENDER_INVOCATION_SCHEMA_VERSION)
            self.assertEqual(
                first["paths"],
                {
                    "blend": "res://assets/runner.blend",
                    "manifest": "res://assets/runner.glb.agent.json",
                    "output": "res://assets/runner.glb",
                    "script": "res://tools/make_runner.py",
                },
            )
            self.assertEqual(first["sha256"]["script"], hashlib.sha256(b"import bpy\n").hexdigest())
            self.assertEqual(first["sha256"]["output"], hashlib.sha256(valid_glb()).hexdigest())
            self.assertEqual(first["sha256"]["blend"], hashlib.sha256(b"BLENDER-v400").hexdigest())
            self.assertNotIn(str(project), manifest_path.read_text(encoding="utf-8"))

            command = runner.call_args_list[0].args[0]
            options = runner.call_args_list[0].kwargs
            self.assertEqual(command[0], str(executable.resolve()))
            self.assertIn("--background", command)
            self.assertIn("--factory-startup", command)
            self.assertIn("blender_bootstrap.py", argument_value(command, "--python"))
            self.assertNotEqual(
                argument_value(command, "--output"),
                str(project / "assets" / "runner.glb"),
            )
            self.assertIs(options["shell"], False)
            self.assertEqual(options["cwd"], str(project.resolve()))

    def test_invalid_staged_export_preserves_existing_output(self):
        def invalid_blender(command, **_kwargs):
            Path(argument_value(command, "--output")).write_bytes(b"not a GLB")
            Path(argument_value(command, "--receipt")).write_text(
                json.dumps({
                    "blender_version": "4.3.2",
                    "invocation_schema_version": BLENDER_INVOCATION_SCHEMA_VERSION,
                }),
                encoding="utf-8",
            )
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            script = project / "build.py"
            script.write_text("import bpy\n", encoding="utf-8")
            output = project / "model.glb"
            output.write_bytes(b"existing asset")
            executable = make_executable(project / "fake-blender")

            with mock.patch("godot_agent.blender.subprocess.run", side_effect=invalid_blender):
                with self.assertRaisesRegex(BlenderBuildError, "GLB"):
                    build_blender_asset(
                        project,
                        script,
                        "res://model.glb",
                        blender=executable,
                    )

            self.assertEqual(output.read_bytes(), b"existing asset")
            self.assertFalse((project / "model.glb.agent.json").exists())

    def test_rejects_output_path_escape_before_launch(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            script = project / "build.py"
            script.write_text("import bpy\n", encoding="utf-8")
            executable = make_executable(project / "fake-blender")

            with mock.patch("godot_agent.blender.subprocess.run") as runner:
                with self.assertRaisesRegex(BlenderBuildError, "within the project"):
                    build_blender_asset(
                        project,
                        script,
                        "res://../outside.glb",
                        blender=executable,
                    )
            runner.assert_not_called()

    def test_cli_build_does_not_require_editor_endpoint(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            (project / "build.py").write_text("import bpy\n", encoding="utf-8")
            executable = make_executable(project / "fake-blender")
            stdout = io.StringIO()
            stderr = io.StringIO()

            with mock.patch("godot_agent.blender.subprocess.run", side_effect=successful_blender):
                exit_code = main(
                    [
                        "--project",
                        str(project),
                        "--compact",
                        "blender-build",
                        "build.py",
                        "--output",
                        "res://model.glb",
                        "--blender",
                        str(executable),
                    ],
                    stdout=stdout,
                    stderr=stderr,
                )

            self.assertEqual(exit_code, 0, stderr.getvalue())
            self.assertEqual(json.loads(stdout.getvalue())["paths"]["output"], "res://model.glb")
            self.assertFalse((project / ".godot" / "agent" / "endpoint.json").exists())


class BlenderDiscoveryTests(unittest.TestCase):
    def test_explicit_path_wins_over_environment(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            explicit = make_executable(directory / "explicit-blender")
            configured = make_executable(directory / "configured-blender")
            self.assertEqual(
                locate_blender(explicit, environ={"BLENDER": str(configured)}),
                explicit.resolve(),
            )

    def test_blender_environment_precedes_path_lookup(self):
        with tempfile.TemporaryDirectory() as temporary:
            configured = make_executable(Path(temporary) / "configured-blender")
            with mock.patch("godot_agent.blender.shutil.which") as which:
                found = locate_blender(environ={"BLENDER": str(configured)})
            self.assertEqual(found, configured.resolve())
            which.assert_not_called()


if __name__ == "__main__":
    unittest.main()
