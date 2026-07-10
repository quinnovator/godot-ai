#!/bin/sh

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"

if ! command -v uv >/dev/null 2>&1 || ! command -v uvx >/dev/null 2>&1; then
	echo "error: uv and uvx are required; install uv from https://docs.astral.sh/uv/" >&2
	exit 127
fi

tools/godot-ai/sync-runtime-addon.sh --check
uvx --from 'clang-format==22.1.5' clang-format --dry-run --Werror \
	core/os/main_loop.h \
	modules/godot_agent/*.cpp modules/godot_agent/*.h \
	main/main.cpp \
	editor/editor_interface.cpp \
	editor/editor_node.cpp \
	editor/editor_node.h \
	editor/scene/3d/node_3d_editor_plugin.cpp \
	editor/scene/3d/node_3d_editor_plugin.h \
	scene/main/scene_tree.cpp \
	scene/main/scene_tree.h
uvx --from 'ruff==0.15.21' ruff check --no-fix agent tools/godot-ai/*.py \
	examples/blender_asset/build_beacon.py modules/godot_agent/config.py
uvx --from 'mypy==1.19.1' mypy agent/godot_agent
tools/godot-ai/build-macos.sh
bin/godot.macos.editor.dev.arm64 --headless \
	--script runtime/addons/godot_ai_runtime/godot_ai_runtime.gd --check-only
bin/godot.macos.editor.dev.arm64 --headless --editor \
	--script runtime/addons/godot_ai_runtime/plugin.gd --check-only
uv run --locked --project agent python -m unittest discover -s agent/tests -v
uv run --locked --project agent python -m py_compile \
	examples/blender_asset/build_beacon.py
