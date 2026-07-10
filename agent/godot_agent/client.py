"""Synchronous JSON-RPC client for the Godot agent endpoint.

The editor publishes connection information beneath the project's ``.godot``
directory.  Connections are intentionally short lived: each call opens a TCP
socket, sends one LSP-framed JSON-RPC request, receives one response, and
closes the socket.
"""

from __future__ import annotations

import ipaddress
import itertools
import json
import math
import socket
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Optional

DEFAULT_TIMEOUT = 10.0
DEFAULT_RUNTIME_TIMEOUT = 30.0
DEFAULT_RUNTIME_POLL_INTERVAL = 0.05
DEFAULT_MAX_MESSAGE_BYTES = 8 * 1024 * 1024
MAX_HEADER_BYTES = 16 * 1024
SUPPORTED_PROTOCOL_VERSION = 1


class GodotAgentError(Exception):
    """Base class for expected client failures."""


class EndpointError(GodotAgentError):
    """The endpoint file is missing or invalid."""


class TransportError(GodotAgentError):
    """The editor could not be reached or closed the connection early."""


class ProtocolError(GodotAgentError):
    """The peer sent an invalid JSON-RPC or framing response."""


class RpcError(GodotAgentError):
    """A JSON-RPC error returned by the Godot editor."""

    def __init__(
        self,
        code: int,
        message: str,
        data: Any = None,
        request_id: Optional[int] = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.data = data
        self.request_id = request_id

    def __str__(self) -> str:
        detail = "JSON-RPC error {0}: {1}".format(self.code, self.message)
        if self.data is not None:
            detail += " ({0})".format(self.data)
        return detail


class DomainError(GodotAgentError):
    """A structured, expected failure returned by an editor or runtime method."""

    def __init__(
        self,
        code: str,
        message: str,
        details: Any = None,
        method: Optional[str] = None,
        command_id: Optional[int] = None,
    ) -> None:
        super().__init__(message)
        self.code: str = code
        self.message: str = message
        self.details: Any = details
        self.method: Optional[str] = method
        self.command_id: Optional[int] = command_id

    def __str__(self) -> str:
        context = "domain operation"
        if self.method is not None:
            context = self.method
        if self.command_id is not None:
            context += " command {0}".format(self.command_id)
        detail = "{0} failed [{1}]: {2}".format(context, self.code, self.message)
        if self.details is not None:
            detail += " ({0})".format(self.details)
        return detail


class RuntimeTimeoutError(GodotAgentError):
    """A runtime command did not finish within the caller's polling deadline."""

    def __init__(
        self,
        method: str,
        timeout: float,
        command_id: Optional[int] = None,
    ) -> None:
        self.method = method
        self.timeout = timeout
        self.command_id = command_id
        command = "runtime command {0!r}".format(method)
        if command_id is not None:
            command += " (id {0})".format(command_id)
        super().__init__("{0} did not finish within {1:g} seconds".format(command, timeout))


def _normalize_loopback_host(value: Any, source: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise EndpointError("{0} field 'host' must be a non-empty string".format(source))
    try:
        address = ipaddress.ip_address(value.strip())
    except ValueError as exc:
        raise EndpointError("{0} field 'host' must be a numeric loopback address".format(source)) from exc
    if not address.is_loopback:
        raise EndpointError("{0} field 'host' must be a loopback address".format(source))
    return str(address)


@dataclass(frozen=True)
class Endpoint:
    """Connection details published by a running Godot editor."""

    host: str
    port: int
    token: str
    protocol_version: int

    def __post_init__(self) -> None:
        object.__setattr__(self, "host", _normalize_loopback_host(self.host, "endpoint"))
        _validate_protocol_version(self.protocol_version, "endpoint")

    @classmethod
    def load(cls, project: str | Path = ".") -> Endpoint:
        path = endpoint_path(project)
        try:
            raw = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            raise EndpointError("cannot read endpoint file {0}: {1}".format(path, exc)) from exc

        try:
            value = json.loads(
                raw,
                object_pairs_hook=_reject_duplicate_object_keys,
                parse_constant=_reject_json_constant,
            )
        except (ValueError, RecursionError) as exc:
            raise EndpointError("endpoint file {0} is not valid JSON: {1}".format(path, exc)) from exc

        if not isinstance(value, dict):
            raise EndpointError("endpoint file {0} must contain a JSON object".format(path))
        return cls.from_mapping(value, source=str(path))

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any], source: str = "endpoint") -> Endpoint:
        required = ("host", "port", "token", "protocol_version")
        missing = [key for key in required if key not in value]
        if missing:
            raise EndpointError("{0} is missing required field(s): {1}".format(source, ", ".join(missing)))

        host = value["host"]
        port = value["port"]
        token = value["token"]
        protocol_version = value["protocol_version"]

        normalized_host = _normalize_loopback_host(host, source)
        if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
            raise EndpointError("{0} field 'port' must be an integer from 1 to 65535".format(source))
        if not isinstance(token, str) or not token:
            raise EndpointError("{0} field 'token' must be a non-empty string".format(source))
        _validate_protocol_version(protocol_version, source)

        return cls(
            host=normalized_host,
            port=port,
            token=token,
            protocol_version=protocol_version,
        )


def endpoint_path(project: str | Path) -> Path:
    """Return the endpoint metadata path for *project*."""

    return Path(project).expanduser() / ".godot" / "agent" / "endpoint.json"


def _validate_protocol_version(value: Any, source: str) -> None:
    if isinstance(value, bool) or not isinstance(value, int):
        raise EndpointError(
            "{0} field 'protocol_version' must be integer {1}".format(
                source,
                SUPPORTED_PROTOCOL_VERSION,
            )
        )
    if value != SUPPORTED_PROTOCOL_VERSION:
        raise EndpointError(
            "{0} uses unsupported protocol_version {1}; supported version is {2}".format(
                source,
                value,
                SUPPORTED_PROTOCOL_VERSION,
            )
        )


class GodotAgentClient:
    """Blocking client for one running Godot editor agent server."""

    def __init__(
        self,
        endpoint: Endpoint,
        timeout: float = DEFAULT_TIMEOUT,
        max_message_bytes: int = DEFAULT_MAX_MESSAGE_BYTES,
    ) -> None:
        if not _is_positive_number(timeout):
            raise ValueError("timeout must be greater than zero")
        if isinstance(max_message_bytes, bool) or not isinstance(max_message_bytes, int) or max_message_bytes <= 0:
            raise ValueError("max_message_bytes must be a positive integer")
        self.endpoint = endpoint
        self.timeout = timeout
        self.max_message_bytes = max_message_bytes
        self._request_ids = itertools.count(1)

    @classmethod
    def for_project(
        cls,
        project: str | Path = ".",
        timeout: float = DEFAULT_TIMEOUT,
        max_message_bytes: int = DEFAULT_MAX_MESSAGE_BYTES,
    ) -> GodotAgentClient:
        return cls(
            Endpoint.load(project),
            timeout=timeout,
            max_message_bytes=max_message_bytes,
        )

    def call(self, method: str, params: Optional[Mapping[str, Any]] = None) -> Any:
        """Call *method*, authenticating with the endpoint token.

        Parameters must be a JSON object because the authentication token is
        injected into every request.  A caller-provided ``token`` is always
        replaced, and the caller's mapping is never mutated.
        """

        return self._call_with_timeout(method, params, self.timeout)

    def _call_with_timeout(
        self,
        method: str,
        params: Optional[Mapping[str, Any]],
        request_timeout: float,
    ) -> Any:
        """Perform one call with a bounded per-request timeout."""

        if not isinstance(method, str) or not method.strip():
            raise ValueError("method must be a non-empty string")
        if not _is_positive_number(request_timeout):
            raise ValueError("request_timeout must be greater than zero")
        if params is None:
            request_params: dict[str, Any] = {}
        elif isinstance(params, Mapping):
            request_params = dict(params)
        else:
            raise ValueError("params must be a mapping so the token can be injected")
        request_params["token"] = self.endpoint.token

        request_id = next(self._request_ids)
        request = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": request_params,
        }
        frame = _encode_frame(request)

        try:
            with socket.create_connection(
                (self.endpoint.host, self.endpoint.port), timeout=request_timeout
            ) as connection:
                connection.settimeout(request_timeout)
                connection.sendall(frame)
                response = _receive_frame(connection, self.max_message_bytes)
        except OSError as exc:
            raise TransportError(
                "cannot communicate with Godot agent at {0}:{1}: {2}".format(
                    self.endpoint.host, self.endpoint.port, exc
                )
            ) from exc

        return _response_result(response, request_id)

    def status(self) -> Any:
        return self.call("agent.health")

    def runtime_status(self) -> dict[str, Any]:
        """Return unwrapped debugger-session and runtime-probe status."""

        data = _domain_data(self.call("runtime.status"), "runtime.status")
        return _require_object(data, "runtime.status data")

    def runtime_command(
        self,
        method: str,
        params: Optional[Mapping[str, Any]] = None,
        session_id: Optional[int] = None,
    ) -> dict[str, Any]:
        """Enqueue a runtime command and return its pending result metadata."""

        return self._runtime_command_with_timeout(
            method,
            params,
            session_id,
            self.timeout,
        )

    def _runtime_command_with_timeout(
        self,
        method: str,
        params: Optional[Mapping[str, Any]],
        session_id: Optional[int],
        request_timeout: float,
    ) -> dict[str, Any]:
        if not isinstance(method, str) or not method.strip():
            raise ValueError("runtime method must be a non-empty string")
        if params is None:
            command_params: dict[str, Any] = {}
        elif isinstance(params, Mapping):
            command_params = dict(params)
        else:
            raise ValueError("runtime params must be a mapping")
        if session_id is not None and (
            isinstance(session_id, bool) or not isinstance(session_id, int) or session_id < 0
        ):
            raise ValueError("session_id must be a non-negative integer or None")

        request_params: dict[str, Any] = {
            "method": method,
            "command_params": command_params,
        }
        if session_id is not None:
            request_params["session_id"] = session_id
        data = _domain_data(
            self._call_with_timeout("runtime.command", request_params, request_timeout),
            "runtime.command",
        )
        result = _require_object(data, "runtime.command data")
        _validate_runtime_result(result, "runtime.command data")
        if result["status"] != "pending":
            raise ProtocolError("runtime.command data must have status 'pending'")
        return result

    def runtime_result(self, command_id: int, consume: bool = False) -> dict[str, Any]:
        """Return one retained result record, optionally consuming it."""

        return self._runtime_result_with_timeout(command_id, consume, self.timeout)

    def _runtime_result_with_timeout(
        self,
        command_id: int,
        consume: bool,
        request_timeout: float,
    ) -> dict[str, Any]:
        _validate_command_id(command_id)
        if not isinstance(consume, bool):
            raise ValueError("consume must be a boolean")
        request_params: dict[str, Any] = {"id": command_id}
        if consume:
            request_params["consume"] = True
        data = _domain_data(
            self._call_with_timeout("runtime.result", request_params, request_timeout),
            "runtime.result",
        )
        result = _require_object(data, "runtime.result data")
        _validate_runtime_result(
            result,
            "runtime.result data",
            expected_id=command_id,
        )
        return result

    def runtime_call(
        self,
        method: str,
        params: Optional[Mapping[str, Any]] = None,
        session_id: Optional[int] = None,
        *,
        timeout: float = DEFAULT_RUNTIME_TIMEOUT,
        poll_interval: float = DEFAULT_RUNTIME_POLL_INTERVAL,
        consume: bool = True,
    ) -> Any:
        """Run one runtime command to completion within an overall deadline.

        This convenience method unwraps both the editor domain envelope and
        the completed runtime result. A client-side timeout leaves the pending
        record retained and exposes its ID on :class:`RuntimeTimeoutError`.
        """

        if not _is_positive_number(timeout):
            raise ValueError("runtime timeout must be greater than zero")
        if not _is_positive_number(poll_interval):
            raise ValueError("poll_interval must be greater than zero")
        if not isinstance(consume, bool):
            raise ValueError("consume must be a boolean")

        deadline = time.monotonic() + timeout
        queued = self._runtime_command_before_deadline(
            method,
            params,
            session_id,
            deadline,
            timeout,
        )
        command_id = queued["id"]

        while True:
            result = self._runtime_result_before_deadline(
                command_id,
                False,
                method,
                deadline,
                timeout,
            )
            if result["status"] != "pending":
                if consume:
                    remaining = deadline - time.monotonic()
                    if remaining > 0:
                        result = self._runtime_result_before_deadline(
                            command_id,
                            True,
                            method,
                            deadline,
                            timeout,
                        )
                return _runtime_result_data(result, method)

            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeTimeoutError(method, timeout, command_id)
            time.sleep(min(poll_interval, remaining))

    def _runtime_command_before_deadline(
        self,
        method: str,
        params: Optional[Mapping[str, Any]],
        session_id: Optional[int],
        deadline: float,
        timeout: float,
    ) -> dict[str, Any]:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeTimeoutError(method, timeout)
        try:
            return self._runtime_command_with_timeout(
                method,
                params,
                session_id,
                min(self.timeout, remaining),
            )
        except TransportError as exc:
            if time.monotonic() >= deadline and isinstance(exc.__cause__, TimeoutError):
                raise RuntimeTimeoutError(method, timeout) from exc
            raise

    def _runtime_result_before_deadline(
        self,
        command_id: int,
        consume: bool,
        method: str,
        deadline: float,
        timeout: float,
    ) -> dict[str, Any]:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeTimeoutError(method, timeout, command_id)
        try:
            return self._runtime_result_with_timeout(
                command_id,
                consume,
                min(self.timeout, remaining),
            )
        except TransportError as exc:
            if time.monotonic() >= deadline and isinstance(exc.__cause__, TimeoutError):
                raise RuntimeTimeoutError(method, timeout, command_id) from exc
            raise

    def scene_tree(self) -> Any:
        return self.call("scene.get_tree")

    def open_scene(self, path: str) -> Any:
        return self.call("scene.open", {"path": path})

    def create_node(
        self,
        node_type: str,
        parent_path: str = ".",
        name: Optional[str] = None,
        properties: Optional[Mapping[str, Any]] = None,
    ) -> Any:
        params: dict[str, Any] = {"parent_path": parent_path, "type": node_type}
        if name is not None:
            params["name"] = name
        if properties is not None:
            if not isinstance(properties, Mapping):
                raise ValueError("properties must be a mapping")
            params["properties"] = dict(properties)
        return self.call("scene.create_node", params)

    def instantiate_scene(
        self,
        path: str,
        parent_path: str = ".",
        name: Optional[str] = None,
        properties: Optional[Mapping[str, Any]] = None,
    ) -> Any:
        params: dict[str, Any] = {"path": path, "parent_path": parent_path}
        if name is not None:
            params["name"] = name
        if properties is not None:
            if not isinstance(properties, Mapping):
                raise ValueError("properties must be a mapping")
            params["properties"] = dict(properties)
        return self.call("scene.instantiate", params)

    def set_property(self, node_path: str, property_name: str, value: Any) -> Any:
        return self.call(
            "scene.set_property",
            {"node_path": node_path, "property": property_name, "value": value},
        )

    def save(self, path: Optional[str] = None) -> Any:
        params = {} if path is None else {"path": path}
        return self.call("scene.save", params)

    def play(self, scene: Optional[str] = None) -> Any:
        params = {} if scene is None else {"scene": scene}
        return self.call("game.play", params)

    def stop(self) -> Any:
        return self.call("game.stop")


def _encode_frame(message: Mapping[str, Any]) -> bytes:
    try:
        body = json.dumps(
            message,
            ensure_ascii=False,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as exc:
        raise ProtocolError("request is not JSON serializable: {0}".format(exc)) from exc
    header = "Content-Length: {0}\r\n\r\n".format(len(body)).encode("ascii")
    return header + body


def _receive_frame(connection: socket.socket, max_message_bytes: int) -> Any:
    marker = b"\r\n\r\n"
    buffered = bytearray()
    while marker not in buffered:
        if len(buffered) >= MAX_HEADER_BYTES:
            raise ProtocolError("response headers exceed {0} bytes".format(MAX_HEADER_BYTES))
        chunk = connection.recv(min(4096, MAX_HEADER_BYTES - len(buffered)))
        if not chunk:
            raise TransportError("connection closed before response headers were complete")
        buffered.extend(chunk)

    raw_headers, raw_body = bytes(buffered).split(marker, 1)
    try:
        header_text = raw_headers.decode("ascii")
    except UnicodeDecodeError as exc:
        raise ProtocolError("response headers must be ASCII") from exc

    content_length: Optional[int] = None
    for line in header_text.split("\r\n"):
        if not line:
            continue
        if ":" not in line:
            raise ProtocolError("malformed response header: {0!r}".format(line))
        name, value = line.split(":", 1)
        if name.strip().lower() != "content-length":
            continue
        if content_length is not None:
            raise ProtocolError("response contains more than one Content-Length header")
        value = value.strip()
        if not value.isdigit():
            raise ProtocolError("Content-Length must be a non-negative integer")
        normalized_value = value.lstrip("0") or "0"
        if len(normalized_value) > 20:
            raise ProtocolError("Content-Length exceeds the supported integer range")
        content_length = int(normalized_value)

    if content_length is None:
        raise ProtocolError("response is missing a Content-Length header")
    if content_length > max_message_bytes:
        raise ProtocolError("response body is {0} bytes; limit is {1}".format(content_length, max_message_bytes))

    body = bytearray(raw_body)
    while len(body) < content_length:
        chunk = connection.recv(min(65536, content_length - len(body)))
        if not chunk:
            raise TransportError("connection closed before response body was complete")
        body.extend(chunk)
    body = body[:content_length]

    try:
        return json.loads(
            body.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_object_keys,
            parse_constant=_reject_json_constant,
        )
    except (UnicodeError, ValueError, RecursionError) as exc:
        raise ProtocolError("response body is not valid UTF-8 JSON: {0}".format(exc)) from exc


def _reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate object key {0!r}".format(key))
        result[key] = value
    return result


def _reject_json_constant(value: str) -> None:
    raise ValueError("non-finite number {0!r}".format(value))


def _response_result(response: Any, request_id: int) -> Any:
    if not isinstance(response, dict):
        raise ProtocolError("JSON-RPC response must be an object")
    if response.get("jsonrpc") != "2.0":
        raise ProtocolError("JSON-RPC response must declare version '2.0'")

    response_id = response.get("id")
    if isinstance(response_id, bool) or response_id != request_id:
        raise ProtocolError("JSON-RPC response id {0!r} does not match request id {1}".format(response_id, request_id))

    has_result = "result" in response
    has_error = "error" in response
    if has_result == has_error:
        raise ProtocolError("JSON-RPC response must contain exactly one of result or error")
    if has_result:
        return response["result"]

    error = response["error"]
    if not isinstance(error, dict):
        raise ProtocolError("JSON-RPC error must be an object")
    code = error.get("code")
    message = error.get("message")
    if isinstance(code, bool) or not isinstance(code, int) or not isinstance(message, str):
        raise ProtocolError("JSON-RPC error requires an integer code and string message")
    raise RpcError(
        code=code,
        message=message,
        data=error.get("data"),
        request_id=request_id,
    )


def _domain_data(response: Any, method: str) -> Any:
    if not isinstance(response, dict):
        raise ProtocolError("{0} domain response must be an object".format(method))
    ok = response.get("ok")
    if not isinstance(ok, bool):
        raise ProtocolError("{0} domain response requires a boolean 'ok' field".format(method))
    if ok:
        if "error" in response:
            raise ProtocolError("{0} successful domain response must not contain 'error'".format(method))
        return response.get("data")

    if "data" in response:
        raise ProtocolError("{0} failed domain response must not contain 'data'".format(method))
    code, message, details = _domain_error_fields(response.get("error"), method)
    raise DomainError(code, message, details=details, method=method)


def _domain_error_fields(error: Any, context: str) -> tuple[str, str, Any]:
    if not isinstance(error, dict):
        raise ProtocolError("{0} domain error must be an object".format(context))
    code = error.get("code")
    message = error.get("message")
    if not isinstance(code, str) or not code:
        raise ProtocolError("{0} domain error requires a non-empty string code".format(context))
    if not isinstance(message, str) or not message:
        raise ProtocolError("{0} domain error requires a non-empty string message".format(context))
    return code, message, error.get("details")


def _require_object(value: Any, context: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ProtocolError("{0} must be an object".format(context))
    return value


def _validate_command_id(command_id: int) -> None:
    if isinstance(command_id, bool) or not isinstance(command_id, int) or command_id <= 0:
        raise ValueError("command_id must be a positive integer")


def _is_positive_number(value: Any) -> bool:
    return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(value) and value > 0


def _validate_runtime_result(
    result: Mapping[str, Any],
    context: str,
    expected_id: Optional[int] = None,
) -> None:
    command_id = result.get("id")
    if isinstance(command_id, bool) or not isinstance(command_id, int) or command_id <= 0:
        raise ProtocolError("{0} requires a positive integer id".format(context))
    if expected_id is not None and command_id != expected_id:
        raise ProtocolError(
            "{0} id {1!r} does not match requested id {2}".format(
                context,
                command_id,
                expected_id,
            )
        )

    status = result.get("status")
    if status not in ("pending", "completed", "failed", "timed_out"):
        raise ProtocolError("{0} has unsupported status {1!r}".format(context, status))
    if status == "pending":
        return

    ok = result.get("ok")
    if not isinstance(ok, bool):
        raise ProtocolError("{0} terminal result requires a boolean 'ok' field".format(context))
    if ok:
        if status != "completed":
            raise ProtocolError("{0} successful result must have status 'completed'".format(context))
        if "error" in result:
            raise ProtocolError("{0} successful result must not contain 'error'".format(context))
    else:
        if "data" in result:
            raise ProtocolError("{0} failed result must not contain 'data'".format(context))
        _domain_error_fields(result.get("error"), context)


def _runtime_result_data(result: Mapping[str, Any], method: str) -> Any:
    if result["status"] == "pending":
        raise ProtocolError("cannot unwrap a pending runtime result")
    if result["ok"]:
        return result.get("data")

    code, message, details = _domain_error_fields(
        result.get("error"),
        "runtime command {0}".format(method),
    )
    raise DomainError(
        code,
        message,
        details=details,
        method=method,
        command_id=result["id"],
    )
