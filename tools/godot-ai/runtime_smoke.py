#!/usr/bin/env python3
"""Exercise the debugger-mediated runtime loop against the real smoke game."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "agent"))

from godot_agent import DomainError, GodotAgentClient  # noqa: E402


def tagged(type_name: str, *args: float) -> dict[str, Any]:
    return {"@type": type_name, "args": list(args)}


def require(result: Any, operation: str) -> Any:
    if not isinstance(result, dict) or not result.get("ok"):
        raise RuntimeError("{0} failed: {1}".format(operation, result))
    return result.get("data")


def runtime_paths(node: dict[str, Any]) -> set[str]:
    paths = {str(node["path"])}
    for child in node.get("children", []):
        paths.update(runtime_paths(child))
    return paths


def wait_for_idle(client: GodotAgentClient, timeout: float = 10.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        game = require(client.call("game.status"), "game.status")
        runtime = client.runtime_status()
        if not game["playing"] and runtime.get("active_session_count", 0) == 0:
            return
        time.sleep(0.05)
    raise RuntimeError("the previous runtime did not stop within {0:g}s".format(timeout))


def wait_for_runtime(
    client: GodotAgentClient,
    timeout: float = 10.0,
) -> tuple[dict[str, Any], dict[str, Any]]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = client.runtime_status()
        if status.get("ready_session_count", 0) > 0:
            try:
                health = client.runtime_call("runtime.health", timeout=1.0)
                return status, health
            except DomainError as error:
                if error.code not in {"runtime_not_running", "runtime_not_ready"}:
                    raise
        time.sleep(0.05)
    raise RuntimeError("runtime probe did not become ready within {0:g}s".format(timeout))


def expect_runtime_error(
    client: GodotAgentClient,
    method: str,
    params: dict[str, Any],
    expected_code: str,
) -> str:
    try:
        client.runtime_call(method, params)
    except DomainError as error:
        if error.code != expected_code:
            raise RuntimeError("{0} returned {1}, expected {2}".format(method, error.code, expected_code)) from error
        return str(error.code)
    raise RuntimeError("{0} unexpectedly succeeded".format(method))


def run(project: Path, require_capture: bool = True) -> dict[str, Any]:
    client = GodotAgentClient.for_project(project, timeout=15.0)
    if require(client.call("game.status"), "game.status")["playing"]:
        require(client.stop(), "game.stop")
    wait_for_idle(client)
    require(client.play("res://main.tscn"), "game.play")
    try:
        status, health = wait_for_runtime(client)
        tree = client.runtime_call("scene.get_tree", {"max_depth": 8})
        requested = {"node_path": "AgentMover", "properties": ["position", "speed", "physics_ticks"]}
        physics_probe_request = {
            "node_path": "PhysicsProbe",
            "properties": ["position", "linear_velocity"],
        }
        client.runtime_call(
            "node.set_property",
            {"node_path": "AgentMover", "property": "speed", "value": 4.0},
        )
        client.runtime_call("time.set_paused", {"paused": True})
        before = client.runtime_call("node.get_properties", requested)
        physics_before = client.runtime_call("node.get_properties", physics_probe_request)
        client.runtime_call("input.action_press", {"action": "ui_right", "strength": 1.0})
        advanced = client.runtime_call("time.advance_physics_frames", {"frames": 30})
        client.runtime_call("input.action_release", {"action": "ui_right"})
        after = client.runtime_call("node.get_properties", requested)
        physics_after = client.runtime_call("node.get_properties", physics_probe_request)
        client.runtime_call(
            "node.set_property",
            {"node_path": "AgentMover", "property": "speed", "value": 3.0},
        )

        raycast = client.runtime_call(
            "physics.raycast",
            {
                "from": tagged("Vector3", 0.0, 5.0, 0.0),
                "to": tagged("Vector3", 0.0, -2.0, 0.0),
            },
        )
        navigation = client.runtime_call(
            "navigation.map_path",
            {
                "origin": tagged("Vector3", 0.0, 0.0, 0.0),
                "target": tagged("Vector3", 4.0, 0.0, 4.0),
            },
        )
        if require_capture:
            capture = client.runtime_call(
                "viewport.capture",
                {"path": "res://.godot/agent/captures/runtime-smoke.png"},
            )
        else:
            capture = {"unavailable": True, "reason": "headless smoke mode"}
        blocked = {
            "traversal": expect_runtime_error(
                client,
                "node.get_properties",
                {"node_path": "../AgentMover"},
                "invalid_node_path",
            ),
            "script_mutation": expect_runtime_error(
                client,
                "node.set_property",
                {"node_path": "AgentMover", "property": "script", "value": None},
                "property_blocked",
            ),
        }

        before_position = before["properties"]["position"]["value"]["args"]
        after_position = after["properties"]["position"]["value"]["args"]
        before_ticks = before["properties"]["physics_ticks"]["value"]
        after_ticks = after["properties"]["physics_ticks"]["value"]
        physics_before_position = physics_before["properties"]["position"]["value"]["args"]
        physics_after_position = physics_after["properties"]["position"]["value"]["args"]
        physics_delta_x = physics_after_position[0] - physics_before_position[0]
        if health["scene_path"] != "res://main.tscn":
            raise RuntimeError("runtime opened an unexpected scene: {0}".format(health))
        observed_runtime_paths = runtime_paths(tree["root"])
        required_runtime_paths = {
            "AgentMover",
            "ImportedAsset",
            "Navigation",
            "PhysicsProbe",
            "PhysicsProbe/ProbeCollision",
        }
        if tree["node_count"] < 12 or tree["truncated"] or not required_runtime_paths.issubset(observed_runtime_paths):
            raise RuntimeError("runtime semantic tree was incomplete: {0}".format(tree))
        if advanced["frames"] != 30 or not advanced["paused"]:
            raise RuntimeError("physics frame advancement was incorrect: {0}".format(advanced))
        if advanced["end_physics_frame"] - advanced["start_physics_frame"] != 30:
            raise RuntimeError("engine physics frame counter did not advance exactly 30 ticks: {0}".format(advanced))
        if after_position[0] <= before_position[0] + 1.5 or after_ticks != before_ticks + 30:
            raise RuntimeError("mapped input did not move the actor for 30 ticks")
        if not 0.48 <= physics_delta_x <= 0.51:
            raise RuntimeError(
                "physics server did not integrate the rigid body for exactly 30 ticks: {0:g}".format(physics_delta_x)
            )
        if not raycast["hit"] or raycast["collider_path"] not in {"GeneratedOrb", "Pedestal", "Ground"}:
            raise RuntimeError("runtime raycast missed authored collision: {0}".format(raycast))
        if navigation["truncated"] or navigation["point_count"] < 2:
            raise RuntimeError("runtime navigation query returned no traversable path: {0}".format(navigation))
        if require_capture and (capture["width"] <= 0 or capture["height"] <= 0):
            raise RuntimeError("runtime capture had no pixels: {0}".format(capture))

        return {
            "ready_sessions": status["ready_session_count"],
            "scene_nodes": tree["node_count"],
            "motion": {
                "before_x": before_position[0],
                "after_x": after_position[0],
                "physics_ticks": [before_ticks, after_ticks],
            },
            "physics_probe": {
                "before_x": physics_before_position[0],
                "after_x": physics_after_position[0],
                "delta_x": physics_delta_x,
            },
            "advance": advanced,
            "raycast": raycast,
            "navigation": navigation,
            "capture": capture,
            "blocked": blocked,
        }
    finally:
        try:
            client.runtime_call("input.action_release", {"action": "ui_right"}, timeout=2.0)
            client.runtime_call("time.set_paused", {"paused": False}, timeout=2.0)
        except Exception:
            pass
        client.stop()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project",
        type=Path,
        default=ROOT / "examples" / "agent_smoke",
    )
    parser.add_argument(
        "--allow-missing-capture",
        action="store_true",
        help="permit capture_unavailable in a headless runtime",
    )
    args = parser.parse_args()
    print(
        json.dumps(
            run(args.project.resolve(), require_capture=not args.allow_missing_capture),
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
