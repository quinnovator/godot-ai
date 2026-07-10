# Roadmap

The platform grows by closing autonomous feedback loops, not by adding a chat panel.

The repository currently delivers M0 plus an intentionally narrow runtime/spatial vertical slice from M2 and M3. Later milestone headings describe the remaining acceptance target, not claims that nothing in those areas exists.

## M0: live semantic editor bridge

- Buildable Godot 4.7 fork.
- Authenticated, versioned local JSON-RPC.
- Scene CRUD, semantic tree/properties/transforms/bounds, validation, settings, imports, rig inspection, run/stop, and GPU viewport capture.
- Dependency-free client/CLI and a real-scene smoke workflow.
- Headless Blender runner with GLB/source/provenance contract.

## M1: safe unattended authoring

- Stable agent IDs stored in scenes and resources.
- Atomic transactions with dry-run, preconditions, commit, rollback, and editor undo integration, including multi-artifact asset installation.
- Idempotent upserts and convergent materialization.
- Append-only action journal with artifact hashes and bounded responses.
- Resource CRUD, UID-aware dependency graph, import completion waits, cook/export validation, and one-command reimport recipes.
- Transitive asset provenance covering imported scripts, add-ons, environment, external inputs, and pinned toolchain identity.
- Structured diagnostics from editor, importer, parser, build, debugger, and export pipelines.

## M2: deterministic runtime laboratory

- Expand the delivered opt-in editor-debugger runtime probe.
- Add fixed seed and fixed timestep control around the delivered explicit physics-frame stepping and input intents.
- Typed events and state predicates; snapshot/restore; trace and replay.
- Scenario files, JSON/JUnit output, golden-state tests, performance budgets, and export-and-launch smoke tests.
- Gameplay-model inference as a pluggable resource rather than engine-coupled policy.

## M3: spatial and visual perception

- Expand delivered semantic bounds, runtime raycasts, and navigation path queries into collision shapes, overlaps, clearance, contacts, connectivity, reachability, cover, traversal metrics, and physics assertions.
- Camera projection/world-to-pixel mapping and occlusion queries.
- Labeled multi-camera captures plus object-ID, depth, normal, albedo, motion, and lighting passes.
- Deterministic capture manifests and tolerant image comparisons.
- Rig validation: hierarchy, weights, retarget maps, IK/constraints, root motion, sockets, collision, foot contact, pose sweeps, self-intersection, and turntables.

## M4: declarative game construction

- Text schemas for zones, affordances, encounters, pacing, connectivity, sightlines, traversal, lighting, and performance targets.
- Constraint-based blockout and level materialization that converges on desired state.
- Text-authorable statecharts, behavior trees, utility systems, GOAP/planners, and schema-checked blackboards.
- Decision traces, explanation APIs, deterministic batch simulation, and scenario-driven AI acceptance tests.
- Voxel and pixel/voxel asset pipelines as optional extensions, not engine-wide assumptions.

## M5: game factory

- Durable planner/reviewer loops with crash recovery and resumable task state.
- Cross-platform hermetic CI, export templates, packaging, signing hooks, and release evidence.
- Reusable genre kits and evaluation suites without coupling the engine to any one game.
- Start-to-finish benchmark games measuring autonomy, quality, reproducibility, time, and human intervention.

## Acceptance principle

A milestone is complete only when an agent can exercise it against a real project, observe structured results from the deciding engine/runtime surface, and reproduce the artifacts from versioned inputs. A method existing in the API is not sufficient evidence by itself.
