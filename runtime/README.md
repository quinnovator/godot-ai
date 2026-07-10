# Godot AI runtime probe

This add-on gives a debugger-connected editor bridge a deliberately bounded view of a running Godot 4.7 game. It is designed for observation, placement checks, input-driven tests, and deterministic-ish paused iteration without exposing general code execution.

## Install

Copy `addons/godot_ai_runtime` into the target project's `addons` directory, then enable **Godot AI Runtime** under **Project Settings > Plugins**. Enabling the plug-in installs `GodotAIRuntime` as an autoload. If that autoload name is already assigned to another resource, the plug-in reports the collision and leaves the existing configuration untouched. Disabling the plug-in removes only an autoload with the exact bundled name and resource path, including after an editor restart. Run the game with the editor debugger attached; the runtime API is intentionally unavailable in a standalone release run without an active debugger.

The add-on is source-only GDScript and does not require a custom engine module.

## Debugger messages

The runtime registers the `godot_ai` capture with `EngineDebugger.register_message_capture`. Every payload is a one-element debugger data array whose element is a Dictionary.

- Runtime to editor: `godot_ai:hello`, containing `protocol_version`, engine and add-on versions, current scene, and capabilities.
- Editor to runtime: `godot_ai:command`, containing `{id, method, params}`. An optional `protocol_version` must equal `1`.
- Runtime to editor: `godot_ai:response`, containing `{id, ok, data}` or `{id, ok, error}`.

Commands execute serially, with at most 256 commands pending. Serialized commands are limited to 1 MiB and responses to 2 MiB before they cross the debugger channel. Paths for nodes are relative to the running scene root; `.` selects that root. Absolute paths, parent traversal, subresource paths, and unique-name shortcuts are rejected. Integer fields also accept finite, integral JSON numbers because JSON-RPC decoders commonly represent numbers as floating-point values.

## Commands

| Method | Parameters | Result |
| --- | --- | --- |
| `runtime.health` | none | Engine, scene, pause, frame, viewport, and capability state. |
| `scene.get_tree` | optional `max_depth` (0-32), `include_internal` | Semantic tree of at most 4096 nodes with paths, classes, local/global transforms, visibility, `VisualInstance3D` local/global AABBs, UI rects, groups, and skeleton bone counts. |
| `node.get_properties` | `node_path`, optional `properties` | Inspector-visible property schemas and safely encoded values. |
| `node.set_property` | `node_path`, `property`, `value` | Sets one inspector-visible, non-read-only property with strict type checking. Object, RID, callable, signal, oversized, internal, secret, script, ownership, and scene-path mutations are rejected. |
| `input.action_press` | `action`, optional `strength` (0-1) | Presses an action already present in the project Input Map. |
| `input.action_release` | `action` | Releases an Input Map action. |
| `time.set_paused` | `paused` | Sets and reports `SceneTree.paused`; the probe itself keeps processing while paused. |
| `time.advance_physics_frames` | `frames` (1-600) | Temporarily releases pause and advances through the fork's post-server `physics_frame_finished` signal for every requested tick, then restores an initially paused tree. |
| `viewport.capture` | optional `viewport_path`, `path` | Waits boundedly for `RenderingServer.frame_post_draw` and writes a PNG of at most 33,554,432 pixels. A custom path must be directly under `res://.godot/agent/captures/`; symbolic links below the project root are rejected, and headless or disabled render loops return `capture_unavailable`. |
| `physics.raycast` | native `Vector3` `from`/`to`; optional `collision_mask`, `exclude`, `collide_with_areas`, `collide_with_bodies` | Performs one 3D world ray query on a physics frame. `exclude` is at most 128 current-scene-relative paths to `CollisionObject3D` nodes. Collider objects and RIDs are never returned. |
| `navigation.map_path` | native `Vector3` `origin`/`target`; optional `optimize`, `navigation_layers` | Queries the current `World3D` navigation map and returns at most 4096 path points. |

The probe has no arbitrary method call, expression evaluation, resource load, scene mutation, configuration edit, socket, shell, or general filesystem API. The only write is a validated viewport PNG inside the project-local capture directory.
