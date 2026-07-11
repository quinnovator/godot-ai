# Validation workflows

The macOS workflow requires Apple Silicon, Xcode Command Line Tools, and
[`uv`](https://docs.astral.sh/uv/) with `uvx` on `PATH`. Install the command-line
tools with `xcode-select --install`. Blender is optional for the engine build;
the production Pixiball asset acceptance uses Blender 4.5 LTS when it is
installed.

The wrappers resolve the repository root themselves, so they can be launched
from any working directory:

```sh
tools/godot-ai/check.sh
```

`build-macos.sh` pins SCons 4.10.1. `check.sh` additionally pins clang-format
22.1.5, Ruff 0.15.21, and mypy 1.19.1, runs the sidecar through its committed
`uv.lock`, validates the semantic runtime contract, and executes Pixiball's
simulation, character, and full-game acceptance tests.
`uvx` downloads those exact tool versions into its cache on first use. Set
`JOBS` to change the default SCons parallelism.

The macOS build always emits both the command-line binary and a native app
bundle. Launch the bundle for GPU-backed editor and runtime loops so UI agents
can address this fork without opening a separately installed stock Godot:

```sh
open -n bin/godot_macos_editor_dev.app --args \
  --editor --path "$PWD/examples/agent_smoke"
```

The bundle identifier for native Computer Use is
`org.godotengine.godot.custom_build`. Headless validation continues to use
`bin/godot.macos.editor.dev.arm64` directly.

In another terminal:

```sh
uv run --project agent python tools/godot-ai/smoke_scene.py
uv run --project agent python tools/godot-ai/runtime_smoke.py
```

`smoke_scene.py` constructs and validates the real 3D scene through the editor API, selects its camera, captures the editor viewport, and launches the game. `runtime_smoke.py` inspects the running scene, exercises the opt-in semantic gameplay driver (including undeclared and oversized intent rejection), pauses it, drives mapped input for exactly 30 physics ticks, verifies motion, raycasts against generated collision, queries navigation, captures the runtime viewport, and checks mutation boundaries.

Production Blender companions use Blender 4.5 LTS. Point the editor setting
`filesystem/import/blender/blender_path` at the executable inside the app
bundle (normally `/Applications/Blender.app/Contents/MacOS/Blender`). The
sidecar discovers that same path automatically, while `--blender` or the
`BLENDER` environment variable can pin a different executable. Pixiball's
production ballplayer exercises the real Blender export, Godot import,
rig/material/socket, and animation acceptance path.

The smoke example and Pixiball benchmark vendor the canonical runtime add-on so they work when copied out of this source tree. After changing `runtime/addons/godot_ai_runtime`, refresh and verify both copies with:

```sh
tools/godot-ai/sync-runtime-addon.sh
tools/godot-ai/sync-runtime-addon.sh --check
```
