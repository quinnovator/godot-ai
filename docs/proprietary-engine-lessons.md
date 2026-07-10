# Lessons from an existing proprietary-engine project

A representative Unreal Engine game served as a requirements probe, not a product target for this fork. The reusable lessons are architectural:

## Patterns worth keeping

- Engine-independent deterministic simulation.
- Seeded fixed-step updates.
- Typed agent input, state, waits, screenshots, and event bridging.
- Golden replays and trace digests.
- Text-driven animation choreography.

## Bottlenecks the platform must remove

- Binary maps can combine geometry, lighting, and camera composition without a useful semantic diff surface.
- Placement, camera, and presentation coordinates can become opaque when they live in compiled code instead of queryable scene data.
- Asset generation cannot be reproduced end to end when source files, import recipes, and provenance are incomplete.
- Gameplay state alone is insufficient; agents also need structured scene trees, transforms, bounds, collision, navigation, rigs, visibility, and dependencies.
- Visual acceptance must cover layout, collision, navigation, lighting, and rendered correctness instead of depending on manual editor inspection.
- Editor automation must converge across restarts and repeated imports without duplicating content.
- Build and test automation should not depend on an interactive proprietary-editor installation.

These observations drive the roadmap toward semantic scene operations, deterministic testing, structured spatial perception, complete provenance, convergent materialization, and a model-neutral Blender companion.
