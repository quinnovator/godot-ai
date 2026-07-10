from __future__ import annotations

import time
import unittest

from godot_agent import (
    DomainError,
    Endpoint,
    GodotAgentClient,
    ProtocolError,
    RuntimeTimeoutError,
)
from test_client import FakeRpcServer


def rpc_response(request, result):
    return {"jsonrpc": "2.0", "id": request["id"], "result": result}


def pending_result(command_id=41):
    return {
        "id": command_id,
        "session_id": 2,
        "status": "pending",
        "timeout_ms": 30_000,
    }


def completed_result(data, command_id=41):
    return {
        "id": command_id,
        "session_id": 2,
        "status": "completed",
        "ok": True,
        "data": data,
    }


class RuntimeClientTests(unittest.TestCase):
    def test_runtime_helpers_unwrap_domain_data_and_send_exact_params(self):
        responses = [
            {"ok": True, "data": {"active_session_count": 1}},
            {"ok": True, "data": pending_result()},
            {"ok": True, "data": completed_result({"paused": False})},
        ]

        def response(request, index):
            return rpc_response(request, responses[index])

        params = {"node_path": "Player", "nested": {"token": "runtime-value"}}
        with FakeRpcServer(response, expected_requests=3) as server:
            client = GodotAgentClient(Endpoint(server.host, server.port, "editor-token", 1))
            self.assertEqual(client.runtime_status(), {"active_session_count": 1})
            self.assertEqual(
                client.runtime_command("node.get_properties", params, session_id=2),
                pending_result(),
            )
            self.assertEqual(
                client.runtime_result(41, consume=True),
                completed_result({"paused": False}),
            )

        self.assertEqual(
            params,
            {"node_path": "Player", "nested": {"token": "runtime-value"}},
        )
        self.assertEqual(
            [request["method"] for request in server.requests],
            ["runtime.status", "runtime.command", "runtime.result"],
        )
        self.assertEqual(
            server.requests[1]["params"],
            {
                "method": "node.get_properties",
                "command_params": params,
                "session_id": 2,
                "token": "editor-token",
            },
        )
        self.assertEqual(
            server.requests[2]["params"],
            {"id": 41, "consume": True, "token": "editor-token"},
        )

    def test_runtime_call_polls_then_consumes_and_returns_runtime_data(self):
        terminal = completed_result({"hit": {"collider": "Wall"}})

        def response(request, index):
            if index == 0:
                result = {"ok": True, "data": pending_result()}
            elif index == 1:
                result = {"ok": True, "data": pending_result()}
            else:
                result = {"ok": True, "data": terminal}
            return rpc_response(request, result)

        with FakeRpcServer(response, expected_requests=4) as server:
            client = GodotAgentClient(Endpoint(server.host, server.port, "token", 1))
            result = client.runtime_call(
                "physics.raycast",
                {"from": [0, 0, 0], "to": [0, 0, 10]},
                session_id=2,
                timeout=1.0,
                poll_interval=0.001,
            )

        self.assertEqual(result, {"hit": {"collider": "Wall"}})
        self.assertEqual(
            [request["method"] for request in server.requests],
            ["runtime.command", "runtime.result", "runtime.result", "runtime.result"],
        )
        self.assertNotIn("consume", server.requests[1]["params"])
        self.assertNotIn("consume", server.requests[2]["params"])
        self.assertTrue(server.requests[3]["params"]["consume"])

    def test_runtime_call_raises_structured_editor_domain_error(self):
        def response(request, _index):
            return rpc_response(
                request,
                {
                    "ok": False,
                    "error": {
                        "code": "runtime_not_running",
                        "message": "No active runtime debugger session is available",
                        "details": {"playing": False},
                    },
                },
            )

        with FakeRpcServer(response) as server:
            client = GodotAgentClient(Endpoint(server.host, server.port, "token", 1))
            with self.assertRaises(DomainError) as raised:
                client.runtime_call("runtime.health")

        self.assertEqual(raised.exception.code, "runtime_not_running")
        self.assertEqual(raised.exception.method, "runtime.command")
        self.assertIsNone(raised.exception.command_id)
        self.assertEqual(raised.exception.details, {"playing": False})

    def test_runtime_call_raises_structured_runtime_command_error(self):
        failure = {
            "id": 41,
            "session_id": 2,
            "status": "completed",
            "ok": False,
            "error": {
                "code": "node_not_found",
                "message": "The runtime node does not exist",
                "details": {"node_path": "Missing"},
            },
        }

        def response(request, index):
            result = {"ok": True, "data": pending_result() if index == 0 else failure}
            return rpc_response(request, result)

        with FakeRpcServer(response, expected_requests=3) as server:
            client = GodotAgentClient(Endpoint(server.host, server.port, "token", 1))
            with self.assertRaises(DomainError) as raised:
                client.runtime_call(
                    "node.get_properties",
                    {"node_path": "Missing"},
                    timeout=1.0,
                )

        self.assertEqual(raised.exception.code, "node_not_found")
        self.assertEqual(raised.exception.method, "node.get_properties")
        self.assertEqual(raised.exception.command_id, 41)
        self.assertTrue(server.requests[-1]["params"]["consume"])

    def test_runtime_call_has_a_bounded_client_side_timeout(self):
        def response(request, index):
            return rpc_response(request, {"ok": True, "data": pending_result()})

        with FakeRpcServer(response, expected_requests=2) as server:
            client = GodotAgentClient(Endpoint(server.host, server.port, "token", 1))
            started = time.monotonic()
            with self.assertRaises(RuntimeTimeoutError) as raised:
                client.runtime_call(
                    "time.advance_physics_frames",
                    {"frames": 600},
                    timeout=0.03,
                    poll_interval=1.0,
                )
            elapsed = time.monotonic() - started

        self.assertEqual(raised.exception.command_id, 41)
        self.assertLess(elapsed, 0.25)
        self.assertNotIn("consume", server.requests[-1]["params"])

    def test_runtime_helpers_reject_malformed_domain_and_result_shapes(self):
        malformed_responses = [
            {"ok": "yes", "data": {}},
            {"ok": True, "data": {"id": True, "status": "pending"}},
            {"ok": True, "data": {"id": 41, "status": "mystery"}},
        ]

        for malformed in malformed_responses:
            with self.subTest(response=malformed):

                def response(request, _index, result=malformed):
                    return rpc_response(request, result)

                with FakeRpcServer(response) as server:
                    client = GodotAgentClient(Endpoint(server.host, server.port, "token", 1))
                    with self.assertRaises(ProtocolError):
                        if malformed is malformed_responses[0]:
                            client.runtime_status()
                        elif malformed is malformed_responses[1]:
                            client.runtime_command("runtime.health")
                        else:
                            client.runtime_result(41)


if __name__ == "__main__":
    unittest.main()
