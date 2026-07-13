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
	core/input/input.cpp \
	core/input/input.h \
	drivers/sdl/dualsense_effect_sdl.cpp \
	drivers/sdl/dualsense_effect_sdl.h \
	drivers/sdl/joypad_sdl.cpp \
	drivers/sdl/joypad_sdl.h \
	editor/editor_external_changes.h \
	core/os/main_loop.h \
	modules/godot_agent/*.cpp modules/godot_agent/*.h \
	modules/godot_ai_model/*.cpp modules/godot_ai_model/*.h \
	modules/godot_ai_model/tests/*.h \
	main/main.cpp \
	editor/editor_interface.cpp \
	editor/editor_node.cpp \
	editor/editor_node.h \
	editor/settings/project_settings_editor.cpp \
	editor/settings/project_settings_editor.h \
	editor/scene/3d/node_3d_editor_plugin.cpp \
	editor/scene/3d/node_3d_editor_plugin.h \
	scene/main/scene_tree.cpp \
	scene/main/scene_tree.h \
	tests/drivers/sdl/test_dualsense_effect_sdl.cpp \
	tests/editor/test_editor_external_changes.cpp
uvx --from 'ruff==0.15.21' ruff check --no-fix agent tools/godot-ai/*.py \
	examples/blender_asset/build_beacon.py \
	games/pixiball/tools/validate_native_pixel_art.py \
	modules/godot_agent/config.py
uvx --from 'mypy==1.19.1' mypy agent/godot_agent
tools/godot-ai/build-macos.sh tests=yes
test -x bin/godot_macos_editor_dev.app/Contents/MacOS/Godot
test "$(plutil -extract CFBundleIdentifier raw \
	bin/godot_macos_editor_dev.app/Contents/Info.plist)" = \
	"org.godotengine.godot.custom_build"
bin/godot.macos.editor.dev.arm64 --headless \
	--script runtime/addons/godot_ai_runtime/godot_ai_runtime.gd --check-only
bin/godot.macos.editor.dev.arm64 --headless --editor \
	--script runtime/addons/godot_ai_runtime/plugin.gd --check-only
bin/godot.macos.editor.dev.arm64 --headless --path examples/agent_smoke \
	--script res://runtime_gameplay_test.gd
tools/godot-ai/test-pixiball.sh
pixiball_pack="${TMPDIR:-/tmp}/pixiball-export-smoke-$$.pck"
native_test_dir="${TMPDIR:-/tmp}/godot-ai-native-tests-$$"
mkdir -p "$native_test_dir"
trap 'rm -f "$pixiball_pack"; rm -rf "$native_test_dir"' EXIT HUP INT TERM
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
	--export-pack macOS "$pixiball_pack" >/dev/null
test -s "$pixiball_pack"
rm -f "$pixiball_pack"
(
	cd "$native_test_dir"
	"$root/bin/godot.macos.editor.dev.arm64" --test --test-case='[AITreeModel]*'
	"$root/bin/godot.macos.editor.dev.arm64" --test --test-case='[SDL][DualSense]*'
	"$root/bin/godot.macos.editor.dev.arm64" --test \
		--test-case='[Editor] External changes only auto-reload when safe'
)
uv run --locked --project agent python -m unittest discover -s agent/tests -v
uv run --locked --project agent python -m py_compile \
	examples/blender_asset/build_beacon.py \
	games/pixiball/tools/validate_native_pixel_art.py
