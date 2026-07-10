# Blender companion example

This project contains a deterministic, agent-authored Blender recipe for a semantic low-poly beacon. With Blender installed, run from the repository root:

```sh
uv run --project agent godot-agent \
  --project examples/blender_asset \
  blender-build res://build_beacon.py \
  --output res://assets/beacon.glb \
  --blend res://assets/beacon.blend
```

The companion runs Blender in background factory mode, executes the recipe, validates the staged GLB and optional `.blend`, replaces each artifact individually, and writes `assets/beacon.glb.agent.json` with the Blender version and SHA-256 hashes for the primary script and outputs. The files are not installed as one transaction, and the manifest does not capture transitive script imports, add-ons, environment, or external source assets. Opening this project in Godot then imports the GLB through the regular engine pipeline.

With an AI-enabled editor open on the project, an agent can trigger that import explicitly:

```sh
uv run --project agent godot-agent \
  --project examples/blender_asset \
  call assets.scan \
  --params '{"paths":["res://assets/beacon.glb"]}'
```

The recipe uses named parts, a stable root, an attachment socket, semantic custom properties, real-world units, and no random input. It is an example of the asset contract, not a required visual style.

Blender is not installed on the current validation host, so this recipe has
been syntax-checked but not exported with a real Blender process there.
