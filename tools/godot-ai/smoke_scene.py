#!/usr/bin/env python3
"""Build and exercise a real 3D scene exclusively through the agent protocol."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "agent"))

from godot_agent import GodotAgentClient  # noqa: E402


def tagged(type_name: str, *args: float) -> dict[str, Any]:
    return {"@type": type_name, "args": list(args)}


def require(result: Any, operation: str) -> Any:
    if not isinstance(result, dict) or not result.get("ok"):
        raise RuntimeError("{0} failed: {1}".format(operation, result))
    return result.get("data")


def iter_paths(node: dict[str, Any]) -> Iterable[str]:
    yield node["path"]
    for child in node.get("children", []):
        yield from iter_paths(child)


def wait_for_scene(client: GodotAgentClient, path: str, timeout: float = 10.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        health = require(client.status(), "agent.health")
        if health.get("scene_path") == path:
            return
        time.sleep(0.1)
    raise RuntimeError("editor did not open {0} within {1}s".format(path, timeout))


def ensure_node(
    client: GodotAgentClient,
    existing: set[str],
    node_type: str,
    name: str,
    properties: dict[str, Any],
    parent_path: str = ".",
) -> None:
    node_path = name if parent_path == "." else parent_path + "/" + name
    if node_path not in existing:
        require(
            client.create_node(
                node_type,
                parent_path=parent_path,
                name=name,
                properties=properties,
            ),
            "scene.create_node {0}".format(name),
        )
        existing.add(node_path)
        return
    for property_name, value in properties.items():
        require(
            client.set_property(node_path, property_name, value),
            "scene.set_property {0}.{1}".format(name, property_name),
        )


def run(project: Path, require_capture: bool) -> dict[str, Any]:
    client = GodotAgentClient.for_project(project, timeout=15.0)
    health = require(client.status(), "agent.health")
    scene_path = "res://main.tscn"
    scene_file = project / "main.tscn"

    if health.get("scene_path") != scene_path:
        if scene_file.exists():
            require(client.open_scene(scene_path), "scene.open")
            wait_for_scene(client, scene_path)
        elif health.get("scene_path"):
            raise RuntimeError("another edited scene is already open: {0}".format(health["scene_path"]))
        else:
            require(
                client.call(
                    "scene.create",
                    {"type": "Node3D", "name": "AgentSmoke", "path": scene_path},
                ),
                "scene.create",
            )
            wait_for_scene(client, scene_path)

    require(
        client.call(
            "assets.scan",
            {
                "paths": [
                    "res://agent_mover.gd",
                    "res://cycle_probe.tscn",
                    "res://imported_marker.gltf",
                    "res://nav_mesh.tres",
                    "res://probe_shape.tres",
                    "res://rig_probe.tscn",
                ]
            },
        ),
        "assets.scan",
    )
    time.sleep(0.25)
    tree = require(client.scene_tree(), "scene.get_tree")
    existing = set(iter_paths(tree))

    imported: dict[str, Any]
    if "ImportedAsset" not in existing:
        imported = require(
            client.call(
                "scene.instantiate",
                {
                    "path": "res://imported_marker.gltf",
                    "name": "ImportedAsset",
                    "properties": {"position": tagged("Vector3", 2.0, 0.0, 2.0)},
                },
            ),
            "scene.instantiate imported_marker.gltf",
        )
        existing.add("ImportedAsset")
    else:
        imported = require(
            client.call("node.inspect", {"node_path": "ImportedAsset", "properties": ["position"]}),
            "node.inspect ImportedAsset",
        )
    # Godot wraps imported glTF scenes in an instantiation root. glTF node
    # extras belong to the imported child, not that wrapper.
    imported_marker = require(
        client.call("node.inspect", {"node_path": "ImportedAsset/ImportedMarker"}),
        "node.inspect ImportedAsset/ImportedMarker",
    )
    extras = imported_marker.get("metadata", {}).get("extras", {})
    if extras.get("semantic_role") != "ai_import_probe":
        raise RuntimeError("imported glTF extras were not preserved: {0}".format(imported_marker))

    cyclic = client.call("scene.instantiate", {"path": "res://cycle_probe.tscn"})
    if cyclic.get("ok") or cyclic.get("error", {}).get("code") != "cyclic_scene":
        raise RuntimeError("indirect cyclic scene dependency was not rejected: {0}".format(cyclic))

    blocked_instance_mutations = {
        "set_property": client.call(
            "scene.set_property",
            {
                "node_path": "ImportedAsset/ImportedMarker",
                "property": "visible",
                "value": False,
            },
        ),
        "create_child": client.call(
            "scene.create_node",
            {
                "parent_path": "ImportedAsset/ImportedMarker",
                "type": "Node3D",
                "name": "UnsavedChild",
            },
        ),
        "delete": client.call("scene.delete_node", {"node_path": "ImportedAsset/ImportedMarker"}),
    }
    for mutation, result in blocked_instance_mutations.items():
        if result.get("ok") or result.get("error", {}).get("code") != "node_not_editable":
            raise RuntimeError("{0} accepted a non-persistent scene-instance edit: {1}".format(mutation, result))

    blocked_structural_mutations = {
        "owner": client.call(
            "scene.set_property",
            {"node_path": ".", "property": "owner", "value": None},
        ),
        "scene_file_path": client.call(
            "scene.set_property",
            {
                "node_path": ".",
                "property": "scene_file_path",
                "value": "/tmp/godot-ai-path-escape.tscn",
            },
        ),
    }
    for mutation, result in blocked_structural_mutations.items():
        if result.get("ok") or result.get("error", {}).get("code") != "property_blocked":
            raise RuntimeError("{0} accepted a structural scene edit: {1}".format(mutation, result))

    if "RigProbe" not in existing:
        require(
            client.instantiate_scene("res://rig_probe.tscn", name="RigProbe"),
            "scene.instantiate rig_probe.tscn",
        )
        existing.add("RigProbe")
    rig = require(client.call("rig.inspect", {"node_path": "RigProbe"}), "rig.inspect")
    if (
        rig.get("bone_count") != 2
        or [bone.get("name") for bone in rig.get("bones", [])] != ["Root", "Tip"]
        or [bone.get("parent") for bone in rig.get("bones", [])] != [-1, 0]
        or rig["bones"][1].get("pose", {}).get("args", [])[-3:] != [0.0, 1.0, 0.0]
        or rig["bones"][1].get("global_rest", {}).get("args", [])[-3:] != [0.0, 1.0, 0.0]
    ):
        raise RuntimeError("rig hierarchy or known pose was not preserved: {0}".format(rig))

    ensure_node(
        client,
        existing,
        "CSGBox3D",
        "Ground",
        {
            "size": tagged("Vector3", 12.0, 0.5, 12.0),
            "position": tagged("Vector3", 0.0, -0.25, 0.0),
            "use_collision": True,
        },
    )
    ensure_node(
        client,
        existing,
        "CSGBox3D",
        "Pedestal",
        {
            "size": tagged("Vector3", 2.5, 1.0, 2.5),
            "position": tagged("Vector3", 0.0, 0.5, 0.0),
            "use_collision": True,
        },
    )
    ensure_node(
        client,
        existing,
        "CSGSphere3D",
        "GeneratedOrb",
        {
            "radius": 0.85,
            "radial_segments": 32,
            "rings": 16,
            "position": tagged("Vector3", 0.0, 1.85, 0.0),
            "use_collision": True,
        },
    )
    ensure_node(
        client,
        existing,
        "Node3D",
        "AgentMover",
        {
            "position": tagged("Vector3", -3.0, 0.0, 0.0),
            "script": {"@type": "Resource", "path": "res://agent_mover.gd"},
            "speed": 3.0,
        },
    )
    ensure_node(
        client,
        existing,
        "CSGBox3D",
        "Body",
        {
            "size": tagged("Vector3", 0.75, 1.0, 0.75),
            "position": tagged("Vector3", 0.0, 0.5, 0.0),
        },
        parent_path="AgentMover",
    )
    ensure_node(
        client,
        existing,
        "RigidBody3D",
        "PhysicsProbe",
        {
            "position": tagged("Vector3", 3.0, 1.0, 0.0),
            "gravity_scale": 0.0,
            "linear_velocity": tagged("Vector3", 1.0, 0.0, 0.0),
            "linear_damp": 0.0,
            "linear_damp_mode": 1,
            "lock_rotation": True,
        },
    )
    ensure_node(
        client,
        existing,
        "CollisionShape3D",
        "ProbeCollision",
        {"shape": {"@type": "Resource", "path": "res://probe_shape.tres"}},
        parent_path="PhysicsProbe",
    )
    ensure_node(
        client,
        existing,
        "NavigationRegion3D",
        "Navigation",
        {"navigation_mesh": {"@type": "Resource", "path": "res://nav_mesh.tres"}},
    )
    ensure_node(
        client,
        existing,
        "DirectionalLight3D",
        "KeyLight",
        {
            "rotation_degrees": tagged("Vector3", -55.0, -35.0, 0.0),
            "shadow_enabled": True,
            "light_energy": 1.25,
        },
    )
    ensure_node(
        client,
        existing,
        "Camera3D",
        "GameCamera",
        {
            "position": tagged("Vector3", 7.0, 5.0, 7.0),
            "rotation_degrees": tagged("Vector3", -24.0, 45.0, 0.0),
            "current": True,
        },
    )
    ensure_node(
        client,
        existing,
        "Label3D",
        "AgentAuthored",
        {
            "text": "AUTHORED THROUGH GODOT AI",
            "position": tagged("Vector3", 0.0, 3.25, 0.0),
            "font_size": 48,
            "outline_size": 8,
        },
    )

    saved = require(client.save(), "scene.save")
    setting = require(
        client.call(
            "project.set_setting",
            {"key": "application/run/main_scene", "value": scene_path, "save": True},
        ),
        "project.set_setting",
    )
    validation = require(client.call("scene.validate"), "scene.validate")
    snapshot = require(client.scene_tree(), "scene.get_tree final")
    if not validation.get("valid") or validation.get("warning_count") != 0:
        raise RuntimeError("authored scene has configuration warnings: {0}".format(validation))
    required_paths = {
        "Ground",
        "GeneratedOrb",
        "AgentMover/Body",
        "ImportedAsset",
        "Navigation",
        "PhysicsProbe/ProbeCollision",
        "RigProbe",
        "GameCamera",
    }
    actual_paths = set(iter_paths(snapshot))
    if not required_paths.issubset(actual_paths):
        raise RuntimeError("authored scene is incomplete: {0}".format(sorted(actual_paths)))

    require(
        client.call("editor.preview_camera", {"node_path": "GameCamera", "viewport": 0}),
        "editor.preview_camera",
    )
    time.sleep(0.75)
    if require_capture:
        capture_result = client.call("editor.capture", {"path": "res://.godot/agent/captures/smoke.png"})
        capture = require(capture_result, "editor.capture")
    else:
        capture = {"unavailable": True, "reason": "headless smoke mode"}
    # Restore the editor camera so the previewed scene camera can exit cleanly.
    require(
        client.call("editor.preview_camera", {"node_path": "", "viewport": 0}),
        "editor.preview_camera clear",
    )
    # Let the editor viewport restore its own camera before the embedded game
    # workspace resizes it.
    time.sleep(0.5)

    require(client.play(scene_path), "game.play")
    time.sleep(0.5)
    play_status = require(client.call("game.status"), "game.status")
    if not play_status.get("playing"):
        raise RuntimeError("game.play did not start the authored scene: {0}".format(play_status))
    require(client.stop(), "game.stop")

    return {
        "health": health,
        "saved": saved,
        "main_scene_setting": setting,
        "validation": validation,
        "imported_scene": imported,
        "blocked_instance_mutations": {
            operation: result["error"]["code"] for operation, result in blocked_instance_mutations.items()
        },
        "blocked_structural_mutations": {
            operation: result["error"]["code"] for operation, result in blocked_structural_mutations.items()
        },
        "rig": rig,
        "scene": snapshot,
        "capture": capture,
        "play_status": play_status,
    }


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
        help="permit capture failure in a headless editor session",
    )
    args = parser.parse_args()
    report = run(args.project.resolve(), require_capture=not args.allow_missing_capture)
    json.dump(report, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
