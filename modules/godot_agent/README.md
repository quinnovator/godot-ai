# Godot Agent editor module

This editor-only module provides the always-on semantic control plane for Godot AI. It listens only on an ephemeral localhost TCP port and writes connection metadata to `.godot/agent/endpoint.json` inside the open project. Requests use JSON-RPC 2.0 with LSP-style `Content-Length` framing and must include the per-session token in `params.token`.

While the bridge is active, externally modified open scenes and `project.godot`
are reloaded automatically only when every affected editor document is saved
and every replacement parses successfully. The editor shows an informational
toast after a safe reload. Unsaved conflicts, incomplete writes, and malformed
files keep the standard reload-or-resave dialog, so agent edits cannot silently
overwrite in-editor work.

The module intentionally exposes domain operations, not arbitrary code or shell execution. Model calls, credentials, Blender, Git, builds, and long-running orchestration belong in the external `agent/` sidecar.

Initial methods:

- `agent.health`
- `scene.create`, `scene.open`, `scene.get_tree`, `scene.create_node`, `scene.instantiate`, `scene.set_property`, `scene.delete_node`, `scene.reparent_node`, `scene.save`, `scene.validate`
- `node.inspect`
- `project.get_setting`, `project.set_setting`
- `assets.scan`
- `editor.focus_node`, `editor.preview_camera`, `editor.capture`
- `rig.inspect`
- `game.play`, `game.stop`, `game.status`
- `runtime.status`, `runtime.command`, `runtime.result`

Complex Godot values use the engine's tagged JSON-native form, for example `{"@type":"Vector3","args":[1,2,3]}`.

`game.play` starts the project's configured main scene when called without
parameters. Pass a project-local `scene` for a custom scene, or `current=true`
to deliberately run the currently edited scene. This keeps an agent's gameplay
launch stable even when an asset gallery or test scene is open in the editor.
