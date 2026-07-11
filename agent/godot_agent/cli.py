"""Command-line interface for :mod:`godot_agent`."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any, Optional, Sequence, TextIO

from .blender import build_blender_asset
from .blender_batch import build_blender_batch
from .client import (
    DEFAULT_RUNTIME_POLL_INTERVAL,
    DEFAULT_RUNTIME_TIMEOUT,
    DEFAULT_TIMEOUT,
    DomainError,
    GodotAgentClient,
    GodotAgentError,
    ProtocolError,
)
from .scenario import load_scenario, run_scenario


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="godot-agent",
        description="Control a running AI-enabled Godot editor over local JSON-RPC.",
    )
    parser.add_argument(
        "--project",
        default=".",
        help="Godot project directory containing .godot/agent/endpoint.json (default: .)",
    )
    parser.add_argument(
        "--timeout",
        type=_positive_float,
        default=DEFAULT_TIMEOUT,
        help="socket timeout in seconds (default: %(default)s)",
    )
    parser.add_argument(
        "--compact",
        action="store_true",
        help="print compact JSON instead of indented JSON",
    )

    commands = parser.add_subparsers(dest="command", required=True)

    raw = commands.add_parser(
        "call",
        aliases=["raw"],
        help="call an arbitrary JSON-RPC method (alias: raw)",
    )
    raw.add_argument("method")
    raw.add_argument(
        "--params",
        default="{}",
        metavar="JSON_OR_@FILE",
        help="JSON object, or @path to a JSON file (default: {})",
    )

    commands.add_parser("status", help="check editor agent health")
    commands.add_parser(
        "runtime-status",
        help="show running-game debugger sessions and runtime-probe readiness",
    )

    runtime_call = commands.add_parser(
        "runtime-call",
        help="call a typed method in the running game and wait for its result",
    )
    runtime_call.add_argument("method", help="runtime method, such as runtime.health")
    runtime_call.add_argument(
        "--params",
        default="{}",
        metavar="JSON_OR_@FILE",
        help="JSON object, or @path to a JSON file (default: {})",
    )
    runtime_call.add_argument(
        "--session-id",
        "--session",
        type=_non_negative_int,
        help="target a specific active debugger session (default: choose automatically)",
    )
    runtime_call.add_argument(
        "--poll-interval",
        type=_positive_float,
        default=DEFAULT_RUNTIME_POLL_INTERVAL,
        metavar="SECONDS",
        help="delay between pending-result polls (default: %(default)s)",
    )
    runtime_call.add_argument(
        "--wait-timeout",
        "--runtime-timeout",
        dest="runtime_timeout",
        type=_positive_float,
        default=DEFAULT_RUNTIME_TIMEOUT,
        metavar="SECONDS",
        help="overall enqueue-and-wait deadline (default: %(default)s)",
    )
    commands.add_parser("scene-tree", help="print the current edited scene tree")

    open_scene = commands.add_parser("open-scene", help="open a scene in the editor")
    open_scene.add_argument("path", help="scene path, usually res://.../*.tscn")

    create_node = commands.add_parser("create-node", help="create a node in the edited scene")
    create_node.add_argument("type", help="Godot node type, such as Node3D or Camera3D")
    create_node.add_argument(
        "--parent",
        "--parent-path",
        dest="parent_path",
        default=".",
        help="parent NodePath (default: .)",
    )
    create_node.add_argument("--name", help="optional node name")
    create_node.add_argument(
        "--properties",
        metavar="JSON_OR_@FILE",
        help="optional JSON object of initial properties, or @path to a JSON file",
    )

    instantiate_scene = commands.add_parser(
        "instantiate-scene",
        help="instantiate a PackedScene resource in the edited scene",
    )
    instantiate_scene.add_argument(
        "path",
        help="PackedScene resource path, usually res://.../*.tscn or an imported model",
    )
    instantiate_scene.add_argument(
        "--parent",
        "--parent-path",
        dest="parent_path",
        default=".",
        help="parent NodePath (default: .)",
    )
    instantiate_scene.add_argument("--name", help="optional instance root name")
    instantiate_scene.add_argument(
        "--properties",
        metavar="JSON_OR_@FILE",
        help="optional JSON object of initial root properties, or @path to a JSON file",
    )

    set_property = commands.add_parser("set-property", help="set a node property")
    set_property.add_argument("node_path", help="target NodePath")
    set_property.add_argument("property", help="Godot property name")
    set_property.add_argument(
        "value",
        help="JSON value; input that is not valid JSON is treated as a string",
    )

    save = commands.add_parser("save", help="save the current edited scene")
    save.add_argument("path", nargs="?", help="optional destination scene path")

    play = commands.add_parser("play", help="run the project main scene or a specific scene")
    play.add_argument("scene", nargs="?", help="optional scene path to run")
    play.add_argument(
        "--current",
        action="store_true",
        help="run the currently edited scene instead of the project main scene",
    )

    commands.add_parser("stop", help="stop the running game")

    scenario_run = commands.add_parser(
        "scenario-run",
        help="run a deterministic semantic gameplay scenario from JSON",
    )
    scenario_run.add_argument("file", help="path to the scenario JSON file")
    scenario_run.add_argument(
        "--session-id",
        "--session",
        type=_non_negative_int,
        help="target a specific active debugger session",
    )
    scenario_run.add_argument(
        "--poll-interval",
        type=_positive_float,
        default=DEFAULT_RUNTIME_POLL_INTERVAL,
        metavar="SECONDS",
    )
    scenario_run.add_argument(
        "--wait-timeout",
        dest="runtime_timeout",
        type=_positive_float,
        default=DEFAULT_RUNTIME_TIMEOUT,
        metavar="SECONDS",
    )

    blender_build = commands.add_parser(
        "blender-build",
        help="run a Python asset recipe in headless Blender and export a GLB",
    )
    blender_build.add_argument(
        "script",
        metavar="SCRIPT",
        help="project-relative or res:// path to an authored Blender Python script",
    )
    blender_build.add_argument(
        "--output",
        required=True,
        help="destination GLB as a res:// project path",
    )
    blender_build.add_argument(
        "--blend",
        help="optional .blend destination as a res:// project path",
    )
    blender_build.add_argument(
        "--blender",
        help="Blender executable or Blender.app path",
    )

    blender_batch = commands.add_parser(
        "blender-batch",
        help="validate or run independent Blender jobs from a JSON manifest",
    )
    blender_batch.add_argument(
        "manifest",
        metavar="MANIFEST",
        help="project-relative or res:// path to a Blender batch JSON manifest",
    )
    blender_batch.add_argument(
        "--blender",
        help="Blender executable or Blender.app path",
    )
    blender_batch.add_argument(
        "--max-workers",
        type=_positive_int,
        help="override manifest concurrency (1-32)",
    )
    blender_batch.add_argument(
        "--dry-run",
        action="store_true",
        help="validate and print the resolved plan without locating Blender or writing files",
    )
    return parser


def main(
    argv: Optional[Sequence[str]] = None,
    stdout: Optional[TextIO] = None,
    stderr: Optional[TextIO] = None,
) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    out = stdout if stdout is not None else sys.stdout
    err = stderr if stderr is not None else sys.stderr

    result_failed = False
    try:
        if args.command == "blender-build":
            result = build_blender_asset(
                project=args.project,
                script=args.script,
                output=args.output,
                blend=args.blend,
                blender=args.blender,
            )
        elif args.command == "blender-batch":
            result = build_blender_batch(
                project=args.project,
                manifest=args.manifest,
                blender=args.blender,
                max_workers=args.max_workers,
                dry_run=args.dry_run,
            )
            result_failed = not bool(result.get("ok", False))
        else:
            client = GodotAgentClient.for_project(args.project, timeout=args.timeout)
            result = _dispatch(client, args)
        if args.command not in ("blender-build", "blender-batch", "runtime-call", "runtime-status"):
            _raise_domain_failure(result, args)
    except (GodotAgentError, ValueError) as exc:
        print("godot-agent: error: {0}".format(exc), file=err)
        return 1

    if args.compact:
        json.dump(result, out, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    else:
        json.dump(result, out, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False)
    out.write("\n")
    return 1 if result_failed else 0


def _raise_domain_failure(result: Any, args: argparse.Namespace) -> None:
    if not isinstance(result, dict) or "ok" not in result:
        return
    ok = result["ok"]
    if not isinstance(ok, bool):
        raise ProtocolError("domain response requires a boolean 'ok' field")
    if ok:
        if "error" in result:
            raise ProtocolError("successful domain response must not contain an error")
        return
    if "data" in result:
        raise ProtocolError("failed domain response must not contain data")
    error = result.get("error")
    if not isinstance(error, dict):
        raise ProtocolError("failed domain response must contain an error object")
    code = error.get("code")
    message = error.get("message")
    if not isinstance(code, str) or not code or not isinstance(message, str) or not message:
        raise ProtocolError("domain error requires non-empty string code and message")
    method = args.method if args.command in ("call", "raw") else args.command
    raise DomainError(code, message, details=error.get("details"), method=method)


def _dispatch(client: GodotAgentClient, args: argparse.Namespace) -> Any:
    if args.command in ("call", "raw"):
        return client.call(args.method, _load_params(args.params))
    if args.command == "status":
        return client.status()
    if args.command == "runtime-status":
        return client.runtime_status()
    if args.command == "runtime-call":
        return client.runtime_call(
            args.method,
            _load_params(args.params),
            session_id=args.session_id,
            timeout=args.runtime_timeout,
            poll_interval=args.poll_interval,
        )
    if args.command == "scene-tree":
        return client.scene_tree()
    if args.command == "open-scene":
        return client.open_scene(args.path)
    if args.command == "create-node":
        properties = None if args.properties is None else _load_json_object(args.properties, "--properties")
        return client.create_node(
            args.type,
            parent_path=args.parent_path,
            name=args.name,
            properties=properties,
        )
    if args.command == "instantiate-scene":
        properties = None if args.properties is None else _load_json_object(args.properties, "--properties")
        return client.instantiate_scene(
            args.path,
            parent_path=args.parent_path,
            name=args.name,
            properties=properties,
        )
    if args.command == "set-property":
        return client.set_property(
            args.node_path,
            args.property,
            _parse_property_value(args.value),
        )
    if args.command == "save":
        return client.save(args.path)
    if args.command == "play":
        return client.play(args.scene, current=args.current)
    if args.command == "stop":
        return client.stop()
    if args.command == "scenario-run":
        return run_scenario(
            client,
            load_scenario(args.file),
            session_id=args.session_id,
            timeout=args.runtime_timeout,
            poll_interval=args.poll_interval,
        )
    raise ValueError("unsupported command: {0}".format(args.command))


def _load_params(raw: str) -> dict[str, Any]:
    return _load_json_object(raw, "--params")


def _load_json_object(raw: str, option_name: str) -> dict[str, Any]:
    source = raw
    if raw.startswith("@"):
        path = Path(raw[1:]).expanduser()
        try:
            source = path.read_text(encoding="utf-8")
        except OSError as exc:
            raise ValueError("cannot read {0} file {1}: {2}".format(option_name, path, exc)) from exc
    try:
        value = json.loads(source)
    except json.JSONDecodeError as exc:
        raise ValueError("{0} must be valid JSON: {1}".format(option_name, exc)) from exc
    if not isinstance(value, dict):
        raise ValueError("{0} must decode to a JSON object".format(option_name))
    return value


def _parse_property_value(raw: str) -> Any:
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def _positive_float(raw: str) -> float:
    try:
        value = float(raw)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be a number") from exc
    if not math.isfinite(value) or value <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return value


def _non_negative_int(raw: str) -> int:
    try:
        value = int(raw)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be an integer") from exc
    if value < 0:
        raise argparse.ArgumentTypeError("must be non-negative")
    return value


def _positive_int(raw: str) -> int:
    try:
        value = int(raw)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be an integer") from exc
    if value <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return value


if __name__ == "__main__":
    raise SystemExit(main())
