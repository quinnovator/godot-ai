from __future__ import annotations

import json
import socket
import tempfile
import threading
import time
import unittest
from pathlib import Path

from godot_agent import (
    SUPPORTED_PROTOCOL_VERSION,
    Endpoint,
    EndpointError,
    GodotAgentClient,
    ProtocolError,
    RpcError,
)


def write_endpoint(project: Path, server: FakeRpcServer, token: str = "secret-token") -> None:
    path = project / ".godot" / "agent" / "endpoint.json"
    path.parent.mkdir(parents=True)
    path.write_text(
        json.dumps({
            "host": server.host,
            "port": server.port,
            "token": token,
            "protocol_version": 1,
        }),
        encoding="utf-8",
    )


def encode_frame(message):
    body = json.dumps(message, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return b"Content-Length: " + str(len(body)).encode("ascii") + b"\r\n\r\n" + body


def encode_raw_frame(body):
    return b"Content-Length: " + str(len(body)).encode("ascii") + b"\r\n\r\n" + body


def receive_frame(connection):
    data = bytearray()
    marker = b"\r\n\r\n"
    while marker not in data:
        chunk = connection.recv(7)
        if not chunk:
            raise AssertionError("client disconnected before completing headers")
        data.extend(chunk)
    raw_headers, body_start = bytes(data).split(marker, 1)
    headers = {}
    for line in raw_headers.decode("ascii").split("\r\n"):
        name, value = line.split(":", 1)
        headers[name.strip().lower()] = value.strip()
    length = int(headers["content-length"])
    body = bytearray(body_start)
    while len(body) < length:
        chunk = connection.recv(length - len(body))
        if not chunk:
            raise AssertionError("client disconnected before completing body")
        body.extend(chunk)
    return json.loads(bytes(body[:length]).decode("utf-8"))


class FakeRpcServer:
    """Small real-socket server used to verify transport behavior."""

    def __init__(self, response_factory=None, expected_requests=1, fragment_responses=False):
        self.response_factory = response_factory or self._default_response
        self.expected_requests = expected_requests
        self.fragment_responses = fragment_responses
        self.requests = []
        self.errors = []
        self._stop = threading.Event()
        self._listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._listener.bind(("127.0.0.1", 0))
        self._listener.listen()
        self._listener.settimeout(0.1)
        self.host, self.port = self._listener.getsockname()
        self._thread = threading.Thread(target=self._run, daemon=True)

    @staticmethod
    def _default_response(request, _index):
        return {"jsonrpc": "2.0", "id": request["id"], "result": {"ok": True}}

    def __enter__(self):
        self._thread.start()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        deadline = time.monotonic() + 2.0
        while len(self.requests) < self.expected_requests and time.monotonic() < deadline:
            time.sleep(0.005)
        self._stop.set()
        self._listener.close()
        self._thread.join(timeout=2.0)
        if exc_type is None:
            if self.errors:
                raise AssertionError("fake server failed: {0}".format(self.errors[0]))
            if len(self.requests) != self.expected_requests:
                raise AssertionError(
                    "expected {0} requests, received {1}".format(self.expected_requests, len(self.requests))
                )

    def _run(self):
        try:
            while len(self.requests) < self.expected_requests and not self._stop.is_set():
                try:
                    connection, _address = self._listener.accept()
                except socket.timeout:
                    continue
                except OSError:
                    break
                with connection:
                    connection.settimeout(2.0)
                    request = receive_frame(connection)
                    self.requests.append(request)
                    response = self.response_factory(request, len(self.requests) - 1)
                    payload = response if isinstance(response, bytes) else encode_frame(response)
                    if self.fragment_responses:
                        for offset in range(0, len(payload), 3):
                            connection.sendall(payload[offset : offset + 3])
                    else:
                        connection.sendall(payload)
        except BaseException as exc:  # The main test thread reports this cleanly.
            self.errors.append(exc)


class EndpointTests(unittest.TestCase):
    def test_loads_endpoint_from_project_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            with FakeRpcServer() as server:
                write_endpoint(project, server)
                endpoint = Endpoint.load(project)
                self.assertEqual(endpoint.host, "127.0.0.1")
                self.assertEqual(endpoint.port, server.port)
                self.assertEqual(endpoint.token, "secret-token")
                self.assertEqual(endpoint.protocol_version, 1)
                GodotAgentClient(endpoint).status()

    def test_rejects_invalid_endpoint_fields(self):
        for host in ("example.com", "192.0.2.1", "0.0.0.0"):
            with self.subTest(host=host):
                with self.assertRaisesRegex(EndpointError, "host"):
                    Endpoint.from_mapping({"host": host, "port": 6000, "token": "x", "protocol_version": 1})
        with self.assertRaisesRegex(EndpointError, "loopback"):
            Endpoint("192.0.2.1", 6000, "x", 1)
        with self.assertRaisesRegex(EndpointError, "port"):
            Endpoint.from_mapping({"host": "127.0.0.1", "port": True, "token": "x", "protocol_version": 1})
        with self.assertRaisesRegex(EndpointError, "token"):
            Endpoint.from_mapping({"host": "127.0.0.1", "port": 6000, "token": "", "protocol_version": 1})
        with self.assertRaisesRegex(EndpointError, "protocol_version"):
            Endpoint.from_mapping({"host": "127.0.0.1", "port": 6000, "token": "x"})

    def test_rejects_unsupported_or_loosely_typed_protocol_versions(self):
        valid = {"host": "127.0.0.1", "port": 6000, "token": "x"}
        self.assertEqual(SUPPORTED_PROTOCOL_VERSION, 1)
        for protocol_version in (2, 0, "1", True):
            with self.subTest(protocol_version=protocol_version):
                with self.assertRaisesRegex(EndpointError, "protocol_version"):
                    Endpoint.from_mapping({**valid, "protocol_version": protocol_version})

        with self.assertRaisesRegex(EndpointError, "unsupported protocol_version"):
            Endpoint("127.0.0.1", 6000, "x", 2)

    def test_rejects_ambiguous_endpoint_json(self):
        with tempfile.TemporaryDirectory() as temporary:
            endpoint_path = Path(temporary) / ".godot" / "agent" / "endpoint.json"
            endpoint_path.parent.mkdir(parents=True)
            endpoint_path.write_text(
                '{"host":"127.0.0.1","port":6000,"token":"x","protocol_version":2,"protocol_version":1}',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(EndpointError, "duplicate object key"):
                Endpoint.load(temporary)


class ClientTests(unittest.TestCase):
    def test_call_uses_utf8_byte_length_and_injects_token_without_mutation(self):
        def response(request, _index):
            return {"jsonrpc": "2.0", "id": request["id"], "result": request["params"]}

        with FakeRpcServer(response, fragment_responses=True) as server:
            endpoint = Endpoint(server.host, server.port, "real-token", 1)
            params = {"token": "caller-token", "label": "雪だるま ☃"}
            result = GodotAgentClient(endpoint).call("custom.unicode", params)

        self.assertEqual(params["token"], "caller-token")
        self.assertEqual(result, {"token": "real-token", "label": "雪だるま ☃"})
        self.assertEqual(server.requests[0]["jsonrpc"], "2.0")
        self.assertEqual(server.requests[0]["method"], "custom.unicode")

    def test_raises_structured_rpc_error(self):
        def response(request, _index):
            return {
                "jsonrpc": "2.0",
                "id": request["id"],
                "error": {"code": -32001, "message": "scene is locked", "data": {"owner": "import"}},
            }

        with FakeRpcServer(response) as server:
            client = GodotAgentClient(Endpoint(server.host, server.port, "token", 1))
            with self.assertRaises(RpcError) as raised:
                client.save()
        self.assertEqual(raised.exception.code, -32001)
        self.assertEqual(raised.exception.data, {"owner": "import"})
        self.assertIn("scene is locked", str(raised.exception))

    def test_rejects_response_without_content_length(self):
        raw_response = b"Content-Type: application/json\r\n\r\n{}"
        with FakeRpcServer(lambda _request, _index: raw_response) as server:
            client = GodotAgentClient(Endpoint(server.host, server.port, "token", 1))
            with self.assertRaisesRegex(ProtocolError, "Content-Length"):
                client.status()

    def test_rejects_response_larger_than_configured_limit_before_reading_body(self):
        raw_response = b"Content-Length: 1000\r\n\r\n{}"
        with FakeRpcServer(lambda _request, _index: raw_response) as server:
            client = GodotAgentClient(
                Endpoint(server.host, server.port, "token", 1),
                max_message_bytes=128,
            )
            with self.assertRaisesRegex(ProtocolError, "limit is 128"):
                client.status()

    def test_rejects_ambiguous_or_nonstandard_json(self):
        responses = [
            encode_raw_frame(b'{"jsonrpc":"2.0","id":1,"id":1,"result":{}}'),
            encode_raw_frame(b'{"jsonrpc":"2.0","id":1,"result":{"value":NaN}}'),
        ]
        for raw_response in responses:
            with self.subTest(response=raw_response):
                with FakeRpcServer(lambda _request, _index, response=raw_response: response) as server:
                    client = GodotAgentClient(Endpoint(server.host, server.port, "token", 1))
                    with self.assertRaises(ProtocolError):
                        client.status()

    def test_requires_positive_integer_message_limit(self):
        endpoint = Endpoint("127.0.0.1", 6000, "token", 1)
        for invalid_limit in (0, -1, True, 1.5):
            with self.subTest(max_message_bytes=invalid_limit):
                with self.assertRaisesRegex(ValueError, "positive integer"):
                    GodotAgentClient(endpoint, max_message_bytes=invalid_limit)

    def test_instantiate_scene_builds_typed_params_without_mutating_properties(self):
        def response(request, _index):
            return {"jsonrpc": "2.0", "id": request["id"], "result": request["params"]}

        properties = {"position": {"@type": "Vector3", "args": [1, 2, 3]}}
        with FakeRpcServer(response) as server:
            client = GodotAgentClient(Endpoint(server.host, server.port, "token", 1))
            result = client.instantiate_scene(
                "res://characters/runner.glb",
                parent_path="Actors",
                name="Runner",
                properties=properties,
            )

        self.assertEqual(properties, {"position": {"@type": "Vector3", "args": [1, 2, 3]}})
        self.assertEqual(server.requests[0]["method"], "scene.instantiate")
        self.assertEqual(
            result,
            {
                "path": "res://characters/runner.glb",
                "parent_path": "Actors",
                "name": "Runner",
                "properties": properties,
                "token": "token",
            },
        )

    def test_instantiate_scene_rejects_non_mapping_properties(self):
        endpoint = Endpoint("127.0.0.1", 6000, "token", 1)
        client = GodotAgentClient(endpoint)
        with self.assertRaisesRegex(ValueError, "properties must be a mapping"):
            client.instantiate_scene("res://runner.tscn", properties=["not", "a", "mapping"])  # type: ignore[arg-type]


if __name__ == "__main__":
    unittest.main()
