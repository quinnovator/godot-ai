from __future__ import annotations

import io
import json
import tempfile
import unittest
from pathlib import Path

from godot_agent.cli import main
from test_client import FakeRpcServer, write_endpoint


class CliTests(unittest.TestCase):
    def test_all_ergonomic_commands_and_raw_call(self):
        def response(request, _index):
            return {
                "jsonrpc": "2.0",
                "id": request["id"],
                "result": {"ok": True, "data": {"called": request["method"]}},
            }

        invocations = [
            ["status"],
            ["scene-tree"],
            ["open-scene", "res://levels/arena.tscn"],
            [
                "create-node",
                "Node3D",
                "--parent",
                "Arena",
                "--name",
                "Ball",
                "--properties",
                '{"position":[1,2,3],"visible":true}',
            ],
            [
                "instantiate-scene",
                "res://assets/runner.glb",
                "--parent-path",
                "Arena",
                "--name",
                "Runner",
                "--properties",
                '{"position":{"@type":"Vector3","args":[1,0,2]}}',
            ],
            ["set-property", "Arena/Ball", "position", "[1, 2, 3]"],
            ["save", "res://levels/saved.tscn"],
            ["play", "res://levels/arena.tscn"],
            ["stop"],
            ["call", "custom.inspect", "--params", '{"detail":"full","token":"wrong"}'],
        ]

        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            with FakeRpcServer(response, expected_requests=len(invocations)) as server:
                write_endpoint(project, server, token="cli-token")
                for command in invocations:
                    stdout = io.StringIO()
                    stderr = io.StringIO()
                    exit_code = main(
                        ["--project", str(project), "--compact"] + command,
                        stdout=stdout,
                        stderr=stderr,
                    )
                    self.assertEqual(exit_code, 0, stderr.getvalue())
                    self.assertEqual(stderr.getvalue(), "")
                    self.assertIn("called", json.loads(stdout.getvalue())["data"])

        self.assertEqual(
            [request["method"] for request in server.requests],
            [
                "agent.health",
                "scene.get_tree",
                "scene.open",
                "scene.create_node",
                "scene.instantiate",
                "scene.set_property",
                "scene.save",
                "game.play",
                "game.stop",
                "custom.inspect",
            ],
        )
        params = [request["params"] for request in server.requests]
        self.assertTrue(all(item["token"] == "cli-token" for item in params))
        self.assertEqual(params[2]["path"], "res://levels/arena.tscn")
        self.assertEqual(
            params[3],
            {
                "parent_path": "Arena",
                "type": "Node3D",
                "name": "Ball",
                "properties": {"position": [1, 2, 3], "visible": True},
                "token": "cli-token",
            },
        )
        self.assertEqual(
            params[4],
            {
                "path": "res://assets/runner.glb",
                "parent_path": "Arena",
                "name": "Runner",
                "properties": {
                    "position": {"@type": "Vector3", "args": [1, 0, 2]},
                },
                "token": "cli-token",
            },
        )
        self.assertEqual(params[5]["value"], [1, 2, 3])
        self.assertEqual(params[9], {"detail": "full", "token": "cli-token"})

    def test_reports_missing_endpoint_without_traceback(self):
        with tempfile.TemporaryDirectory() as temporary:
            stdout = io.StringIO()
            stderr = io.StringIO()
            exit_code = main(
                ["--project", temporary, "status"],
                stdout=stdout,
                stderr=stderr,
            )
        self.assertEqual(exit_code, 1)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("cannot read endpoint file", stderr.getvalue())

    def test_domain_failure_returns_nonzero_and_writes_stderr(self):
        def response(request, _index):
            return {
                "jsonrpc": "2.0",
                "id": request["id"],
                "result": {
                    "ok": False,
                    "error": {
                        "code": "scene_not_found",
                        "message": "Scene does not exist",
                        "details": "res://missing.tscn",
                    },
                },
            }

        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            with FakeRpcServer(response) as server:
                write_endpoint(project, server)
                stdout = io.StringIO()
                stderr = io.StringIO()
                exit_code = main(
                    ["--project", str(project), "open-scene", "res://missing.tscn"],
                    stdout=stdout,
                    stderr=stderr,
                )

        self.assertEqual(exit_code, 1)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("scene_not_found", stderr.getvalue())

    def test_malformed_domain_envelopes_return_nonzero(self):
        malformed_results = [
            {"ok": 0, "data": {}},
            {"ok": True, "error": {"code": "unexpected", "message": "bad"}},
            {"ok": False, "data": {}, "error": {"code": "failed", "message": "bad"}},
            {"ok": False, "error": {"code": "failed"}},
        ]
        for malformed_result in malformed_results:
            with self.subTest(result=malformed_result):

                def response(request, _index, result=malformed_result):
                    return {"jsonrpc": "2.0", "id": request["id"], "result": result}

                with tempfile.TemporaryDirectory() as temporary:
                    project = Path(temporary)
                    with FakeRpcServer(response) as server:
                        write_endpoint(project, server)
                        stdout = io.StringIO()
                        stderr = io.StringIO()
                        exit_code = main(
                            ["--project", str(project), "status"],
                            stdout=stdout,
                            stderr=stderr,
                        )

                self.assertEqual(exit_code, 1)
                self.assertEqual(stdout.getvalue(), "")
                self.assertIn("error", stderr.getvalue())

    def test_raw_is_an_alias_for_call(self):
        def response(request, _index):
            return {"jsonrpc": "2.0", "id": request["id"], "result": request["params"]}

        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            with FakeRpcServer(response) as server:
                write_endpoint(project, server, token="raw-token")
                stdout = io.StringIO()
                exit_code = main(
                    [
                        "--project",
                        str(project),
                        "--compact",
                        "raw",
                        "custom.echo",
                        "--params",
                        '{"message":"hello"}',
                    ],
                    stdout=stdout,
                    stderr=io.StringIO(),
                )

        self.assertEqual(exit_code, 0)
        self.assertEqual(json.loads(stdout.getvalue()), {"message": "hello", "token": "raw-token"})
        self.assertEqual(server.requests[0]["method"], "custom.echo")

    def test_runtime_status_and_runtime_call_with_file_params(self):
        pending = {"id": 9, "session_id": 3, "status": "pending"}
        completed = {
            "id": 9,
            "session_id": 3,
            "status": "completed",
            "ok": True,
            "data": {"node_count": 12},
        }

        def response(request, index):
            if index == 0:
                domain_result = {"ok": True, "data": {"ready_session_count": 1}}
            elif index == 1:
                domain_result = {"ok": True, "data": pending}
            elif index == 2:
                domain_result = {"ok": True, "data": pending}
            else:
                domain_result = {"ok": True, "data": completed}
            return {
                "jsonrpc": "2.0",
                "id": request["id"],
                "result": domain_result,
            }

        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            params_path = project / "runtime-params.json"
            params_path.write_text('{"max_depth":4,"include_internal":false}', encoding="utf-8")
            with FakeRpcServer(response, expected_requests=5) as server:
                write_endpoint(project, server, token="runtime-token")

                status_stdout = io.StringIO()
                status_exit = main(
                    ["--project", str(project), "--compact", "runtime-status"],
                    stdout=status_stdout,
                    stderr=io.StringIO(),
                )
                call_stdout = io.StringIO()
                call_stderr = io.StringIO()
                call_exit = main(
                    [
                        "--project",
                        str(project),
                        "--compact",
                        "runtime-call",
                        "scene.get_tree",
                        "--params",
                        "@" + str(params_path),
                        "--session",
                        "3",
                        "--poll-interval",
                        "0.001",
                        "--wait-timeout",
                        "1",
                    ],
                    stdout=call_stdout,
                    stderr=call_stderr,
                )

        self.assertEqual(status_exit, 0)
        self.assertEqual(json.loads(status_stdout.getvalue()), {"ready_session_count": 1})
        self.assertEqual(call_exit, 0, call_stderr.getvalue())
        self.assertEqual(call_stderr.getvalue(), "")
        self.assertEqual(json.loads(call_stdout.getvalue()), {"node_count": 12})
        self.assertEqual(
            [request["method"] for request in server.requests],
            [
                "runtime.status",
                "runtime.command",
                "runtime.result",
                "runtime.result",
                "runtime.result",
            ],
        )
        self.assertEqual(
            server.requests[1]["params"],
            {
                "method": "scene.get_tree",
                "command_params": {"max_depth": 4, "include_internal": False},
                "session_id": 3,
                "token": "runtime-token",
            },
        )
        self.assertNotIn("consume", server.requests[2]["params"])
        self.assertNotIn("consume", server.requests[3]["params"])
        self.assertTrue(server.requests[4]["params"]["consume"])

    def test_runtime_data_that_contains_ok_false_is_not_treated_as_an_editor_failure(self):
        pending = {"id": 9, "session_id": 3, "status": "pending"}
        completed = {
            "id": 9,
            "session_id": 3,
            "status": "completed",
            "ok": True,
            "data": {"ok": False, "reason": "gameplay state"},
        }

        def response(request, index):
            domain_result = {"ok": True, "data": pending if index == 0 else completed}
            return {"jsonrpc": "2.0", "id": request["id"], "result": domain_result}

        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            with FakeRpcServer(response, expected_requests=3) as server:
                write_endpoint(project, server)
                stdout = io.StringIO()
                stderr = io.StringIO()
                exit_code = main(
                    [
                        "--project",
                        str(project),
                        "--compact",
                        "runtime-call",
                        "custom.state",
                    ],
                    stdout=stdout,
                    stderr=stderr,
                )

        self.assertEqual(exit_code, 0, stderr.getvalue())
        self.assertEqual(stderr.getvalue(), "")
        self.assertEqual(json.loads(stdout.getvalue()), {"ok": False, "reason": "gameplay state"})


if __name__ == "__main__":
    unittest.main()
