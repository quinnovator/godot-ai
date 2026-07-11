# Agent protocol v1

## Discovery and transport

For each open project the editor writes:

```text
<project>/.godot/agent/endpoint.json
```

The file contains `host`, `port`, `token`, `protocol_version`, `pid`, `project_path`, and engine version metadata. The transport is JSON-RPC 2.0 over TCP with LSP framing:

```text
Content-Length: <UTF-8 byte count>\r\n
\r\n
<JSON body>
```

Only individual request objects are accepted in v1. Every request uses an object for `params` and includes `params.token`. The client injects the endpoint token automatically.

Successful domain calls return a JSON-RPC result shaped as `{"ok":true,"data":...}`. Expected domain failures return `{"ok":false,"error":{"code":"...","message":"...","details":...}}`. Malformed, unauthorized, or unknown JSON-RPC calls use standard JSON-RPC error responses.

## Typed values

JSON scalars, arrays, and string-keyed dictionaries use ordinary JSON. Godot-native values use the engine's tagged JSON form:

```json
{"@type":"Vector3","args":[1.0,2.0,3.0]}
```

Other examples include `Vector2`, `Color`, `Quaternion`, `Transform2D`, `Transform3D`, and `AABB`. Project resources use `{"@type":"Resource","path":"res://..."}` and are loaded through Godot's resource pipeline, which lets agents assign scripts, meshes, materials, animations, and other imported assets without exposing arbitrary filesystem paths. Non-resource engine objects are read-only references containing class and instance ID.

## Methods

| Method | Important parameters | Result |
|---|---|---|
| `agent.health` | none | protocol, engine, project, scene, play state, capabilities |
| `scene.create` | `type`, `name`, optional `path` | creates a root scene |
| `scene.open` | `path` | schedules a `.tscn` to open |
| `scene.get_tree` | `max_depth`, `include_internal`, `include_warnings` | semantic tree with transforms, bounds, bones, warnings |
| `scene.create_node` | `parent_path`, `type`, optional `name`, `properties` | creates and owns a node in the edited scene |
| `scene.instantiate` | `path`, `parent_path`, optional `name`, `properties` | instantiates and owns a project-local `PackedScene` or imported scene |
| `scene.set_property` | `node_path`, `property`, `value` | updates a typed property |
| `scene.delete_node` | `node_path` | deletes a non-root node |
| `scene.reparent_node` | `node_path`, `new_parent_path`, `keep_global_transform` | reparents without duplicating |
| `scene.save` | optional `path` | saves current `.tscn` without preview |
| `scene.validate` | none | all node configuration warnings |
| `node.inspect` | `node_path`, optional `properties` | property schema and encoded values |
| `project.get_setting` | `key` | typed project setting |
| `project.set_setting` | `key`, `value`, optional `save` | updates and optionally persists setting |
| `assets.scan` | optional `paths` | scan changes or reimport explicit sources |
| `editor.focus_node` | `node_path`, optional `viewport` | select and frame a 3D node |
| `editor.preview_camera` | `node_path`, optional `viewport` | drive an editor viewport through a scene camera; an empty path restores the editor camera |
| `editor.capture` | optional `viewport`, `path` | GPU-backed editor viewport PNG |
| `rig.inspect` | `node_path` | skeleton hierarchy, rest/global rest, and current pose |
| `game.play` | optional `scene` or `current=true` | runs the project main scene by default, a custom scene by path, or the currently edited scene only when explicitly requested |
| `game.stop` | none | stop the running game |
| `game.status` | none | current play state and scene |
| `runtime.status` | none | active debugger sessions and runtime-probe readiness |
| `runtime.command` | `method`, `command_params`, optional `session_id` | enqueue a typed command for the running game |
| `runtime.result` | `id`, optional `consume` | poll an asynchronous runtime command result |

Node paths are relative to the edited scene root. `.` identifies the root.

`runtime.command` forwards only the fixed command set implemented by the opt-in add-on. Its current commands are `runtime.health`, `scene.get_tree`, `node.get_properties`, `node.set_property`, `input.action_press`, `input.action_release`, `gameplay.describe`, `gameplay.state`, `gameplay.intent`, `time.set_paused`, `time.advance_physics_frames`, `viewport.capture`, `physics.raycast`, and `navigation.map_path`. The gameplay commands target one explicitly grouped game-owned driver through three fixed callbacks; they never accept an arbitrary object method. See [the runtime reference](../runtime/README.md) for their schemas, driver contract, and safety limits. JSON integer parameters are accepted only when finite, integral, and within each command's documented range.

## Deliberate v1 limitations

Operations execute serially on the editor main thread, but multi-call transactions, rollback, precondition hashes, stable agent IDs, deterministic seed control, snapshot/replay, and an action journal are not yet part of v1. Runtime observation and bounded frame stepping are present, but they do not yet make arbitrary projects deterministic. The missing convergence and recovery features should be in place before unattended long-running generation jobs.
