# Parallel Pixiball modeling example

`player_equipment_candidates.batch.json` is a text-first queue for independent
player and equipment explorations. Each job has a stable ID, unique artifact
paths, bounded runtime, and explicit recipe parameters. This is the intended
handoff when several visual/modeling agents generate candidates at once: each
agent can own a job or recipe without sharing a mutable Blender scene.

Validate the complete plan without locating Blender or writing artifacts:

```sh
uv run --locked --project agent python -m godot_agent \
  --project games/pixiball \
  blender-batch res://tools/blender/player_equipment_candidates.batch.json \
  --dry-run
```

Build with up to four Blender processes:

```sh
uv run --locked --project agent python -m godot_agent \
  --project games/pixiball \
  blender-batch res://tools/blender/player_equipment_candidates.batch.json \
  --max-workers 4
```

Outputs intentionally live under
`res://artifacts/blender_candidates/pixiball_parallel_example/`; they do not
replace the production ballplayer or any other agent's character paths. Each
job writes a GLB, optional editable `.blend`, deterministic `.agent.json`
provenance, and JSON `.agent.log`. The batch result remains source-ordered even
when jobs finish out of order. A failed job makes the command exit nonzero but
does not delete or roll back successful peers.

The shared recipe reads its normalized parameter object from the file named by
`GODOT_AGENT_BLENDER_PARAMETERS`. That variable is supplied only for the
recipe process by the packaged bootstrap; recipes should treat it as input and
must not mutate output paths themselves. Once a candidate is selected, scan its
GLB with the editor's `assets.scan` method and run scene-level skeleton,
silhouette, material, and animation acceptance before promoting it.
