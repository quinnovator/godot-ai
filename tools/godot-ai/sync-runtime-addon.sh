#!/bin/sh

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
source_dir="$root/runtime/addons/godot_ai_runtime"
example_dir="$root/examples/agent_smoke/addons/godot_ai_runtime"

if [ "${1:-}" = "--check" ]; then
	for file in godot_ai_runtime.gd godot_ai_runtime.gd.uid plugin.gd plugin.gd.uid plugin.cfg; do
		cmp "$source_dir/$file" "$example_dir/$file"
	done
	exit 0
fi

mkdir -p "$example_dir"
for file in godot_ai_runtime.gd godot_ai_runtime.gd.uid plugin.gd plugin.gd.uid plugin.cfg; do
	cp "$source_dir/$file" "$example_dir/$file"
done
