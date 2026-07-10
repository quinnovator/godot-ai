"""Bootstrap executed by Blender, not by the regular Python client."""

from __future__ import annotations

import argparse
import json
import os
import runpy
import sys


def _arguments():
    try:
        separator = sys.argv.index("--")
    except ValueError as exc:
        raise RuntimeError("Godot Agent Blender arguments are missing") from exc

    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--schema-version", type=int, required=True)
    parser.add_argument("--script", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--blend")
    parser.add_argument("--receipt", required=True)
    return parser.parse_args(sys.argv[separator + 1 :])


def main():
    import bpy

    args = _arguments()
    original_argv = sys.argv
    try:
        sys.argv = [args.script]
        runpy.run_path(args.script, run_name="__main__")
    finally:
        sys.argv = original_argv

    if args.blend:
        os.makedirs(os.path.dirname(args.blend), exist_ok=True)
        result = bpy.ops.wm.save_as_mainfile(filepath=args.blend, check_existing=False)
        if "FINISHED" not in result:
            raise RuntimeError("Blender did not finish saving the .blend file")

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    result = bpy.ops.export_scene.gltf(
        filepath=args.output,
        export_format="GLB",
        export_extras=True,
        check_existing=False,
    )
    if "FINISHED" not in result:
        raise RuntimeError("Blender did not finish exporting the GLB")

    receipt = {
        "blender_version": bpy.app.version_string,
        "invocation_schema_version": args.schema_version,
    }
    with open(args.receipt, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(receipt, handle, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        handle.write("\n")


if __name__ == "__main__":
    main()
