# Validation workflows

The macOS workflow requires Apple Silicon, Xcode Command Line Tools, and
[`uv`](https://docs.astral.sh/uv/) with `uvx` on `PATH`. Install the command-line
tools with `xcode-select --install`. Blender is optional and is not installed
or exercised by this suite.

The wrappers resolve the repository root themselves, so they can be launched
from any working directory:

```sh
tools/godot-ai/check.sh
```

`build-macos.sh` pins SCons 4.10.1. `check.sh` additionally pins clang-format
22.1.5, Ruff 0.15.21, and mypy 1.19.1, and runs the sidecar through its committed `uv.lock`.
`uvx` downloads those exact tool versions into its cache on first use. Set
`JOBS` to change the default SCons parallelism.

The GPU-backed editor and runtime loops require a running editor:

```sh
bin/godot.macos.editor.dev.arm64 --editor --path examples/agent_smoke
```

In another terminal:

```sh
uv run --project agent python tools/godot-ai/smoke_scene.py
uv run --project agent python tools/godot-ai/runtime_smoke.py
```

`smoke_scene.py` constructs and validates the real 3D scene through the editor API, selects its camera, captures the editor viewport, and launches the game. `runtime_smoke.py` inspects the running scene, pauses it, drives mapped input for exactly 30 physics ticks, verifies motion, raycasts against generated collision, queries navigation, captures the runtime viewport, and checks mutation boundaries.

The current validation host does not have Blender installed. Blender process
discovery, invocation, staging, and manifest behavior are covered with mocked
unit tests, while the example recipe is syntax-checked. A real Blender export
followed by Godot import and rig/material/collision acceptance has not been run
on this host.

The example vendors the canonical runtime add-on so it works when copied out of this source tree. After changing `runtime/addons/godot_ai_runtime`, refresh and verify that copy with:

```sh
tools/godot-ai/sync-runtime-addon.sh
tools/godot-ai/sync-runtime-addon.sh --check
```
