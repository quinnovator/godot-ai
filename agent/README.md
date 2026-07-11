# Godot agent client

This directory contains a standard-library-only Python client for the local
JSON-RPC server exposed by an AI-enabled Godot editor. The editor publishes its
connection details to:

```text
<project>/.godot/agent/endpoint.json
```

The file must contain `host`, `port`, `token`, and `protocol_version`. Requests
use JSON-RPC 2.0 with LSP-style `Content-Length` framing. The client injects the
published token into the `params` object of every call.

Run without installing:

```sh
cd agent
python3 -m godot_agent --project /path/to/project status
python3 -m godot_agent --project /path/to/project scene-tree
python3 -m godot_agent --project /path/to/project open-scene res://levels/arena.tscn
python3 -m godot_agent --project /path/to/project create-node Node3D --parent . --name Arena --properties '{"position":{"@type":"Vector3","args":[0,0,0]}}'
python3 -m godot_agent --project /path/to/project instantiate-scene res://assets/runner.glb --parent Arena --name Runner
python3 -m godot_agent --project /path/to/project set-property Arena position '{"@type":"Vector3","args":[0,1,0]}'
python3 -m godot_agent --project /path/to/project save
python3 -m godot_agent --project /path/to/project play
python3 -m godot_agent --project /path/to/project stop
python3 -m godot_agent --project /path/to/project runtime-status
python3 -m godot_agent --project /path/to/project runtime-call runtime.health
python3 -m godot_agent --project /path/to/project runtime-call scene.get_tree --params '{"max_depth":4}'
python3 -m godot_agent --project /path/to/project scenario-run scenarios/first-pitch.json
python3 -m godot_agent --project /path/to/project call scene.get_tree --params '{}'
```

`raw` is accepted as an alias for `call`.
Parameterless `play` always launches the project's configured main scene, even
when an asset gallery or test scene is open in the editor. Use `play --current`
only when the edited scene is deliberately the launch target, or pass an
explicit `res://.../*.tscn` path for a custom scene.

## Running-game commands

The runtime helpers use Godot's debugger connection to inspect and exercise a
game that is running from the editor. The project must enable the Godot AI
runtime probe, and `runtime-status` reports whether an active debugger session
has completed the probe handshake.

`runtime-call` submits a typed command, polls its bounded asynchronous result,
and consumes the retained terminal record. Parameters must be a JSON object and
may be read from a file with `--params @path`:

```sh
python3 -m godot_agent \
  --project /path/to/project \
  runtime-call physics.raycast \
  --params @raycast.json \
  --session 0 \
  --poll-interval 0.05 \
  --wait-timeout 30
```

The global `--timeout` controls each editor socket request. The runtime-call
`--wait-timeout` is a separate overall deadline covering command enqueue and
polling. If it expires, the CLI reports the command ID when one was assigned;
the retained result can still be inspected with a raw `runtime.result` call.

The Python client offers the same operations directly:

```python
from godot_agent import DomainError, GodotAgentClient, RuntimeTimeoutError

client = GodotAgentClient.for_project("/path/to/project")
instance = client.instantiate_scene(
    "res://assets/runner.glb",
    parent_path="Arena",
    properties={"position": {"@type": "Vector3", "args": [1, 0, 2]}},
)
runtime = client.runtime_status()
queued = client.runtime_command("runtime.health")
record = client.runtime_result(queued["id"])
data = client.runtime_call(
    "scene.get_tree",
    {"max_depth": 4},
    timeout=30.0,
    poll_interval=0.05,
)
```

Unlike the older convenience methods, these four runtime helpers intentionally
unwrap the editor's `{"ok":true,"data":...}` domain envelope. Expected editor
or running-game failures raise `DomainError` with `code`, `message`, `details`,
`method`, and, when available, `command_id`. A local polling deadline raises
`RuntimeTimeoutError`; malformed JSON-RPC or domain/result shapes raise
`ProtocolError`.

## Semantic scenario runner

`scenario-run` executes bounded JSON steps against a game's opt-in semantic
driver. It can send declared intents, advance 1–600 exact physics frames,
observe state, assert or wait on dot-separated state paths, and capture the
runtime viewport. Scenarios pause by default and restore the game's previous
pause state on completion or failure.

```json
{
  "name": "first result",
  "steps": [
    {"intent": {"name": "start_match", "params": {"seed": 7}}},
    {"advance": 1},
    {"wait": {"path": "presentation.flow", "equals": "result", "max_frames": 300}},
    {"assert": {"path": "pitch_serial", "equals": 1}},
    {"capture": "res://.godot/agent/captures/first-result.png"}
  ]
}
```

Each step contains exactly one operation. Waits are bounded to 100,000 total
frames and advance in chunks of at most 600, matching the runtime probe's
per-command limit. Supported comparisons are `equals`, `not_equals`, `in`,
`contains`, and `exists`. The result includes every step record and final
semantic state; a rejected intent, timeout, malformed response, or failed
assertion exits nonzero with its one-based step number.

## Blender companion builds

An authored Blender Python recipe can be run headlessly without requiring a
running Godot editor:

```sh
python3 -m godot_agent \
  --project /path/to/project \
  blender-build res://tools/build_character.py \
  --output res://assets/characters/runner.glb \
  --blend res://assets/characters/runner.blend
```

`SCRIPT` may be a `res://` path or a filesystem path relative to the project.
Output paths must use `res://`, stay inside the project, and end in `.glb` or
`.blend` as appropriate. Blender is discovered in this order:

1. `--blender PATH`
2. the `BLENDER` environment variable
3. `blender` on `PATH`
4. `Blender.app` in the standard system or user macOS Applications directory

Independent modeling jobs can be validated and fanned out from one reviewable
JSON manifest:

```sh
python3 -m godot_agent \
  --project /path/to/project \
  blender-batch res://tools/player-candidates.batch.json \
  --max-workers 4
```

```json
{
  "schema_version": 1,
  "name": "player candidates",
  "max_workers": 4,
  "result": "res://artifacts/candidates/batch-result.json",
  "defaults": {"timeout_seconds": 600},
  "jobs": [
    {
      "id": "pitcher-a",
      "script": "res://tools/build_player.py",
      "output": "res://artifacts/candidates/pitcher-a.glb",
      "blend": "res://artifacts/candidates/pitcher-a.blend",
      "parameters": {"role": "pitcher", "variant": "power"}
    }
  ]
}
```

Use `--dry-run` to parse the entire manifest, resolve all paths, reject unknown
fields and case-insensitive output collisions, and print the source-ordered
plan without locating Blender or writing files. A real run validates all jobs
before launch and uses at most `max_workers` Blender processes (bounded to
1–32). Each job gets a default `<output>.agent.log` JSON diagnostic file in
addition to its existing `<output>.agent.json` provenance. The persisted batch
result remains in manifest order even when completion order differs. Any
failure makes the command exit nonzero, while successful peer artifacts remain
installed and recorded.

Recipe parameters are normalized, bounded JSON and are available to authored
scripts through the file path in `GODOT_AGENT_BLENDER_PARAMETERS`. The
bootstrap restores that environment value after each script. This preserves
the existing no-parameter `blender-build` behavior while allowing a single
recipe to generate many isolated candidates.

The client does not install Blender and does not invoke a shell. It starts a
fixed Blender command with `--background`, `--factory-startup`, and a packaged
bootstrap. The authored script runs first, then the bootstrap optionally saves
the `.blend` and exports the GLB. Authored scripts are Python and should be
treated as trusted project source.

Files are staged and checked before replacing existing assets. GLB structure
and optional Blender headers are validated. A deterministic sidecar named
`<output>.agent.json` records invocation schema and Blender versions, project-
relative `res://` paths, and SHA-256 hashes for the script, GLB, and optional
`.blend`. It deliberately contains no timestamp or host-specific path.

Replacement is atomic per file, not across the GLB, optional `.blend`, and
manifest as a group. The manifest also does not recursively identify imported
Python modules, Blender add-ons or preferences, environment variables, or
external source assets. Multi-file transactions and transitive provenance are
roadmap work.

When an editor is running, follow the build with `assets.scan` on the emitted
GLB to force Godot's importer to materialize the engine-side mesh, materials,
animations, and skeleton resources. Import completion waits and automatic
post-import rig/collision acceptance remain roadmap work.

Blender is not installed on the current project validation host. The runner's
process, staging, validation, and manifest contract is tested with mocks, and
the example script is syntax-checked, but no real Blender export has been
executed on that host.

Run the tests with:

```sh
python3 -m unittest discover -s tests -v
```
