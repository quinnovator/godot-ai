"""Deterministic semantic gameplay scenarios for a running Godot project."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Mapping, Optional, Protocol, cast

MAX_STEPS = 1_000
MAX_ADVANCE_FRAMES = 600
MAX_WAIT_FRAMES = 100_000


class RuntimeClient(Protocol):
    def runtime_call(
        self,
        method: str,
        params: Optional[Mapping[str, Any]] = None,
        session_id: Optional[int] = None,
        *,
        timeout: float,
        poll_interval: float,
    ) -> Any: ...


class ScenarioFailure(ValueError):
    """Raised when a scenario is malformed or an assertion is not satisfied."""


def load_scenario(path: str | Path) -> dict[str, Any]:
    source_path = Path(path).expanduser()
    try:
        value = json.loads(source_path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ScenarioFailure("cannot read scenario file {0}: {1}".format(source_path, exc)) from exc
    except json.JSONDecodeError as exc:
        raise ScenarioFailure("scenario file must contain valid JSON: {0}".format(exc)) from exc
    if not isinstance(value, dict):
        raise ScenarioFailure("scenario file must decode to a JSON object")
    return value


def run_scenario(
    client: RuntimeClient,
    scenario: Mapping[str, Any],
    *,
    session_id: Optional[int] = None,
    timeout: float = 30.0,
    poll_interval: float = 0.02,
) -> dict[str, Any]:
    """Run a bounded scenario against the opt-in semantic gameplay driver."""

    if not isinstance(scenario, Mapping):
        raise ScenarioFailure("scenario must be an object")
    unknown = sorted(set(scenario) - {"name", "pause", "restore_pause", "steps"})
    if unknown:
        raise ScenarioFailure("scenario has unsupported fields: {0}".format(", ".join(unknown)))
    name = scenario.get("name", "scenario")
    if not isinstance(name, str) or not name.strip() or len(name) > 128:
        raise ScenarioFailure("scenario name must contain 1 to 128 characters")
    steps = scenario.get("steps")
    if not isinstance(steps, list) or not steps:
        raise ScenarioFailure("scenario steps must be a non-empty array")
    if len(steps) > MAX_STEPS:
        raise ScenarioFailure("scenario exceeds the {0}-step limit".format(MAX_STEPS))
    pause = scenario.get("pause", True)
    restore_pause = scenario.get("restore_pause", True)
    if not isinstance(pause, bool) or not isinstance(restore_pause, bool):
        raise ScenarioFailure("pause and restore_pause must be booleans")

    call = _Caller(client, session_id, timeout, poll_interval)
    records: list[dict[str, Any]] = []
    previous_pause: Optional[bool] = None
    try:
        if pause:
            pause_result = call("time.set_paused", {"paused": True})
            if isinstance(pause_result, dict) and isinstance(pause_result.get("previous"), bool):
                previous_pause = pause_result["previous"]
        for index, raw_step in enumerate(steps):
            try:
                records.append(_run_step(call, index, raw_step))
            except ScenarioFailure as exc:
                raise ScenarioFailure("step {0}: {1}".format(index + 1, exc)) from exc
        final_state = _state(call)
    finally:
        if pause and restore_pause and previous_pause is not None:
            call("time.set_paused", {"paused": previous_pause})

    return {
        "ok": True,
        "name": name,
        "step_count": len(records),
        "steps": records,
        "final_state": final_state,
    }


class _Caller:
    def __init__(
        self,
        client: RuntimeClient,
        session_id: Optional[int],
        timeout: float,
        poll_interval: float,
    ) -> None:
        self.client = client
        self.session_id = session_id
        self.timeout = timeout
        self.poll_interval = poll_interval

    def __call__(self, method: str, params: Optional[Mapping[str, Any]] = None) -> Any:
        return self.client.runtime_call(
            method,
            params,
            session_id=self.session_id,
            timeout=self.timeout,
            poll_interval=self.poll_interval,
        )


def _run_step(call: _Caller, index: int, raw_step: Any) -> dict[str, Any]:
    if not isinstance(raw_step, dict) or len(raw_step) != 1:
        raise ScenarioFailure("each step must be an object containing exactly one operation")
    operation, value = next(iter(raw_step.items()))
    if operation == "intent":
        if not isinstance(value, dict):
            raise ScenarioFailure("intent must be an object")
        unknown = sorted(set(value) - {"name", "params"})
        if unknown:
            raise ScenarioFailure("intent has unsupported fields: {0}".format(", ".join(unknown)))
        intent_name = value.get("name")
        params = value.get("params", {})
        if not isinstance(intent_name, str) or not intent_name:
            raise ScenarioFailure("intent name must be a non-empty string")
        if not isinstance(params, dict):
            raise ScenarioFailure("intent params must be an object")
        result = call("gameplay.intent", {"name": intent_name, "params": params})
        accepted = result.get("result", {}).get("accepted") if isinstance(result, dict) else None
        if accepted is not True:
            raise ScenarioFailure("game rejected intent {0!r}: {1!r}".format(intent_name, result))
        return {"index": index + 1, "operation": operation, "name": intent_name, "result": result}
    if operation in ("advance", "advance_frames"):
        frames = _bounded_int(value, "advance frame count", 1, MAX_ADVANCE_FRAMES)
        result = call("time.advance_physics_frames", {"frames": frames})
        return {"index": index + 1, "operation": "advance", "frames": frames, "result": result}
    if operation == "observe":
        if value not in (True, None) and not isinstance(value, str):
            raise ScenarioFailure("observe must be true, null, or a snapshot label")
        return {"index": index + 1, "operation": operation, "label": value, "state": _state(call)}
    if operation == "assert":
        assertion = _validate_condition(value, "assert")
        state = _state(call)
        actual = _resolve_path(state, assertion["path"])
        _assert_condition(actual, assertion)
        return {
            "index": index + 1,
            "operation": operation,
            "path": assertion["path"],
            "actual": actual,
        }
    if operation == "wait":
        if not isinstance(value, dict):
            raise ScenarioFailure("wait must be an object")
        condition_fields = {key: item for key, item in value.items() if key not in {"max_frames", "step_frames"}}
        assertion = _validate_condition(condition_fields, "wait")
        max_frames = _bounded_int(value.get("max_frames", 600), "wait max_frames", 1, MAX_WAIT_FRAMES)
        step_frames = _bounded_int(value.get("step_frames", 10), "wait step_frames", 1, MAX_ADVANCE_FRAMES)
        advanced = 0
        while True:
            state = _state(call)
            actual = _resolve_path(state, assertion["path"])
            if _condition_matches(actual, assertion):
                break
            if advanced >= max_frames:
                raise ScenarioFailure(
                    "wait timed out after {0} frames at {1!r}; actual value is {2!r}".format(
                        advanced, assertion["path"], actual
                    )
                )
            frames = min(step_frames, max_frames - advanced)
            call("time.advance_physics_frames", {"frames": frames})
            advanced += frames
        return {
            "index": index + 1,
            "operation": operation,
            "path": assertion["path"],
            "actual": actual,
            "advanced_frames": advanced,
        }
    if operation == "capture":
        if isinstance(value, str):
            path = value
        elif isinstance(value, dict) and set(value) == {"path"} and isinstance(value.get("path"), str):
            path = value["path"]
        else:
            raise ScenarioFailure("capture must be a path string or an object containing only path")
        result = call("viewport.capture", {"path": path})
        return {"index": index + 1, "operation": operation, "path": path, "result": result}
    raise ScenarioFailure("unsupported operation {0!r}".format(operation))


def _state(call: _Caller) -> dict[str, Any]:
    result = call("gameplay.state", {})
    if not isinstance(result, dict) or not isinstance(result.get("state"), dict):
        raise ScenarioFailure("gameplay.state returned an invalid response")
    return cast(dict[str, Any], result["state"])


def _validate_condition(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ScenarioFailure("{0} condition must be an object".format(label))
    comparison_keys = [key for key in ("equals", "not_equals", "in", "contains", "exists") if key in value]
    unknown = sorted(set(value) - {"path", *comparison_keys})
    if unknown or len(comparison_keys) != 1:
        raise ScenarioFailure(
            "{0} requires path and exactly one of equals, not_equals, in, contains, or exists".format(label)
        )
    path = value.get("path")
    if not isinstance(path, str) or not path or len(path) > 512:
        raise ScenarioFailure("{0} path must be a non-empty string".format(label))
    if comparison_keys[0] == "exists" and not isinstance(value["exists"], bool):
        raise ScenarioFailure("exists comparison must be a boolean")
    return dict(value)


def _resolve_path(state: Any, path: str) -> Any:
    current = state
    for component in path.split("."):
        if not component:
            raise ScenarioFailure("state path contains an empty component")
        if isinstance(current, dict) and component in current:
            current = current[component]
        elif isinstance(current, list) and component.isdigit() and int(component) < len(current):
            current = current[int(component)]
        else:
            return _Missing(path)
    return current


class _Missing:
    def __init__(self, path: str) -> None:
        self.path = path

    def __repr__(self) -> str:
        return "<missing {0}>".format(self.path)


def _assert_condition(actual: Any, assertion: Mapping[str, Any]) -> None:
    if not _condition_matches(actual, assertion):
        comparison = next(key for key in ("equals", "not_equals", "in", "contains", "exists") if key in assertion)
        raise ScenarioFailure(
            "assertion failed at {0!r}: actual {1!r}, expected {2} {3!r}".format(
                assertion["path"], actual, comparison, assertion[comparison]
            )
        )


def _condition_matches(actual: Any, assertion: Mapping[str, Any]) -> bool:
    if "exists" in assertion:
        return (not isinstance(actual, _Missing)) is assertion["exists"]
    if isinstance(actual, _Missing):
        return False
    if "equals" in assertion:
        return bool(actual == assertion["equals"])
    if "not_equals" in assertion:
        return bool(actual != assertion["not_equals"])
    if "in" in assertion:
        container = assertion["in"]
        return isinstance(container, (list, str, dict)) and actual in container
    if "contains" in assertion:
        return isinstance(actual, (list, str, dict)) and assertion["contains"] in actual
    return False


def _bounded_int(value: Any, label: str, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum or value > maximum:
        raise ScenarioFailure("{0} must be an integer from {1} to {2}".format(label, minimum, maximum))
    return int(value)
