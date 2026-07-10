# Godot AI

Godot AI is a thin, buildable fork of Godot 4.7 for autonomous game-development agents. The long-term target is the complete loop: create and import assets, author gameplay and game AI, compose levels, run the real game, inspect semantic and visual state, diagnose failures, and iterate without relying on a human-only editor workflow.

This repository deliberately does **not** put a language model inside the engine. Godot remains the source of truth for scenes, resources, imports, physics, rendering, navigation, animation, and exports. A model-neutral sidecar owns agent orchestration, source control, builds, credentials, and tools such as Blender. The editor exposes a narrow typed API instead of a remote shell.

## Fork baseline

The `ai-native` branch starts at upstream Godot `4.7-stable` commit `5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`. Most new behavior lives in an isolated engine module, a source-only project add-on, and the external Python package. Narrow core hooks provide truthful scene-save results, programmatic 3D camera preview control, and a post-server physics-step signal; keeping that patch surface small makes regular upstream rebases practical.

## What works in the first milestone

- A compiled-in, editor-only `godot_agent` module starts automatically for an open project.
- The bridge binds to an ephemeral loopback port and authenticates every JSON-RPC request with a per-session token.
- Agents can inspect a semantic scene tree; create, edit, reparent, delete, validate, open, and save nodes/scenes; read and write project settings; trigger imports; inspect skeleton rest/pose data; run and stop scenes; and capture a real 3D editor viewport.
- An opt-in runtime add-on talks back through Godot's debugger. Agents can inspect the live scene and properties, set bounded properties, send mapped input, pause and advance exact physics-frame counts, capture the running viewport, raycast, and query navigation paths.
- The stdlib-only `agent/` client provides both a Python API and a CLI.
- The Blender companion runs agent-authored Python in an explicitly selected headless Blender, emits GLB and optional `.blend`, and records the Blender version plus hashes for its primary script and emitted files.
- `examples/agent_smoke` is the end-to-end validation project, and `examples/blender_asset` demonstrates the source recipe and asset contract.

The current bridge is an engineering foundation, not yet the whole platform. Transactions, stable IDs, deterministic seed/snapshot/replay control, semantic render passes, asset dependency/provenance enforcement, declarative level constraints, and a text-authorable gameplay-AI stack are tracked in [the roadmap](docs/roadmap.md). The current asset manifest does not capture transitive script imports, add-ons, environment, or every external input, and installing the GLB, optional `.blend`, and manifest is not one multi-file transaction.

Blender is not installed on the current macOS validation host. Its invocation,
staging, and manifest contract are unit-tested with a mocked executable, and the
example recipe is syntax-checked, but a real Blender export/import loop has not
been validated here. Godot can scan a produced GLB through its normal importer;
automated post-import rig, material, collision, animation, and known-pose
acceptance remains roadmap work.

## Build

On Apple Silicon, the native Metal renderer avoids requiring the Vulkan SDK.
Install Xcode Command Line Tools and [`uv`](https://docs.astral.sh/uv/) first;
the wrapper pins SCons and can be invoked from any directory:

```sh
tools/godot-ai/build-macos.sh
```

The editor binary is written under `bin/`. Other platforms use the normal upstream Godot build process; the agent module is editor-only and can be disabled with `module_godot_agent_enabled=no`.

## Drive an editor

Launch the built editor on a project and wait for `.godot/agent/endpoint.json`:

```sh
bin/godot.macos.editor.dev.arm64 --editor --path examples/agent_smoke
cd agent
python3 -m godot_agent --project ../examples/agent_smoke status
python3 -m godot_agent --project ../examples/agent_smoke scene-tree
python3 -m godot_agent --project ../examples/agent_smoke play
python3 -m godot_agent --project ../examples/agent_smoke runtime-status
python3 -m godot_agent --project ../examples/agent_smoke runtime-call runtime.health
```

The endpoint is deleted on an orderly editor exit and overwritten on the next start. It is project-local, ignored with `.godot/`, and contains the host, ephemeral port, protocol version, process ID, and token. A hard crash can leave harmless stale metadata; the client then reports that the recorded loopback server is unreachable.

See [the architecture](docs/architecture.md), [protocol reference](docs/agent-protocol.md), [runtime add-on](runtime/README.md), and [development roadmap](docs/roadmap.md).

The build, static checks, editor-authoring smoke test, and closed-loop runtime smoke test are documented in [tools/godot-ai](tools/godot-ai/README.md).
