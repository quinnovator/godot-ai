#!/bin/sh

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"

godot=${GODOT_BIN:-bin/godot.macos.editor.dev.arm64}
project=games/pixiball

if [ ! -x "$godot" ]; then
	echo "error: Pixiball test binary is not executable: $godot" >&2
	exit 127
fi

find "$project" -type f -name 'test_*.gd' -print | sort |
while IFS= read -r test_path; do
	resource_path=res://${test_path#"$project"/}
	echo "Pixiball test: $resource_path"
	"$godot" --headless --path "$project" --script "$resource_path"
done

# This is both a construction test and an editor-tool script smoke. It is
# intentionally outside the test_*.gd convention because it doubles as the
# optional visual gallery's runtime entry point.
echo "Pixiball test: res://characters/character_smoke.gd"
"$godot" --headless --path "$project" --script res://characters/character_smoke.gd
