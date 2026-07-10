# Architecture

## Design rules

1. **The engine owns game truth.** Scene state, transforms, bounds, animation, imports, physics, navigation, rendering, and export results are queried from the running engine rather than inferred from source text or screenshots.
2. **Stored artifacts stay text-first where possible.** `.tscn`, `.tres`, `project.godot`, scripts, scenario definitions, Blender scripts, and generation manifests remain reviewable and reproducible.
3. **Editor operations are semantic and bounded.** The bridge exposes typed operations on game concepts. It does not expose a shell, raw memory, model credentials, or unrestricted filesystem access.
4. **Visual feedback complements structured perception.** Screenshots are needed for composition and aesthetics, but transforms, bounds, collision, navigation, bones, resources, and diagnostics should never require vision to recover.
5. **Headless and GPU loops are separate.** Logic, import, parsing, simulation, geometry, and export checks should run headlessly. Pixel, lighting, animation, camera, and rig acceptance uses a GPU-backed session.
6. **Generated work must converge.** Stable IDs, preconditions, transactions, and complete provenance will make retries safe. A repeated materialization must not duplicate a level; these guarantees are roadmap work rather than properties of the first milestone.

## Layers

```text
AI agent / planner
        |
        v
agent sidecar ---------------> Blender (headless asset compiler)
  models, Git, builds,              |  .blend + .glb + manifest
  task journal, policies            v
        |                      Godot import pipeline
        | JSON-RPC                   |
        v                            v
editor-only godot_agent module -> edited scene/resources
        |
        | bounded debugger messages
        v
running game -> deterministic state/events/captures/assertions
```

### Sidecar

`agent/` is deliberately outside the engine. It discovers a running editor through the project-local endpoint, speaks the versioned protocol, and will own durable workflows that must survive an editor crash. Model providers, secrets, Git, subprocess policy, builds, Blender, artifact storage, and multi-step recovery belong here.

### Editor bridge

`modules/godot_agent` is compiled only into editor builds. It runs on the editor main thread and uses Godot's own `EditorInterface`, `ProjectSettings`, `EditorFileSystem`, node/resource APIs, renderer viewports, and skeleton APIs. The module is small and isolated so upstream 4.x rebases remain tractable.

### Runtime probe

The opt-in `runtime/addons/godot_ai_runtime` project add-on exchanges typed messages with an `EditorDebuggerPlugin`. The delivered vertical slice provides live semantic trees and properties, bounded property mutation, mapped input, pause and physics-frame advancement, GPU capture, 3D raycasts, and navigation path queries. It registers only while the editor debugger is active and exposes no arbitrary calls, resource loading, script changes, socket, or shell surface. Seed control, state predicates, event traces, snapshot/restore, replay, contacts/overlaps, and performance counters remain roadmap work.

### Blender companion

Blender is not embedded in the editor. The sidecar invokes an explicitly located Blender binary in background mode (which deployments can pin by path or image), runs versioned agent-authored Python, saves source `.blend` when requested, exports GLB, hashes the primary script and outputs, records the Blender version, and writes a sidecar manifest. Godot can then scan the GLB through its normal importer. Automated post-import acceptance of skeletons, animations, materials, bounds, collision, and known poses remains roadmap work.

The current manifest is useful but not complete reproducibility evidence: it
does not recursively hash imported Python modules, Blender add-ons or
preferences, environment variables, external source assets, or every toolchain
input. Each staged artifact is replaced atomically on its own, but the GLB,
optional `.blend`, and manifest are not committed as one transaction. A failure
between replacements can therefore leave a mixed generation. Transitive
provenance and transactional multi-artifact installation belong in M1.

### Optional GDExtensions

Performance-sensitive, public-API-sufficient features such as voxel meshing, geometry analysis, or native inference libraries should use GDExtension. Only missing editor/runtime hooks should become narrow fork patches.

## Trust boundary

- The server binds only to `127.0.0.1` on an OS-selected port.
- Every request includes a 256-bit per-session token stored in `.godot/agent/endpoint.json`.
- Unix builds restrict the endpoint directory to `0700` and the token file to `0600` before writing it; the client refuses non-loopback endpoint hosts.
- Messages are capped at 8 MiB.
- Runtime commands and retained results are bounded; pending commands time out, and captures have path, wait, and pixel limits.
- Scene, capture, and run paths are restricted to `res://` and expected extensions.
- The bridge has no arbitrary evaluation or shell method.
- The sidecar, not the engine, is responsible for workspace authorization and subprocess allow-lists.

The token prevents accidental cross-project control and opportunistic localhost callers; it is not a sandbox against another process already running as the same OS user. Windows currently relies on the project directory's inherited ACL rather than installing a dedicated private DACL, so the M0 bridge should not be used from a project writable by other local OS users.

## Why this is a fork

Most orchestration can and should remain an addon or sidecar. The fork exists for a small always-on bridge, missing low-level editor/debugger hooks, distribution defaults, and deep perception/testing features that public extension APIs cannot reliably supply. Features stay modular and are upstreamable when they are broadly useful.
