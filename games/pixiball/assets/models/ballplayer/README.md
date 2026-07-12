# Pixiball Blender ballplayer

Asset version 14 is an authored Blender character. The editable source of
truth is `source/ballplayer.blend`; `ballplayer.glb` is its checked-in runtime
export. There is no character generator and no primitive/voxel fallback.

The base anatomy comes from Blender Studio's CC0 [Human Base Meshes
bundle](https://download.blender.org/demo/bundles/bundles-3.6/) and is modified
for Pixiball as a slim, naturalistic baseball athlete. The Blender file owns
the complete body and face, fitted jersey/pants/socks, cap, short hair, cleats,
glove, bat, belt, collar, placket, sleeve trim, hidden role gear, skinning, and
nine actions. The runtime GLB contains 35 skinned mesh objects on one 31-bone
armature.

Cloth materials retain embedded knit normal and roughness maps. Named material
slots (`TEAM_Primary`, `TEAM_Secondary`, `TEAM_Accent`, `MAT_Jersey`, and
`MAT_Pants`) let each actor change uniform colors without changing geometry.
The front and back of the jersey contain dedicated skinned UV panels named
`JerseyIdentityFront` and `JerseyIdentityBack`. Godot renders the team mark,
player surname, and number into high-resolution transparent textures for those
surfaces, so roster changes remain programmatic while the lettering deforms
with the authored jersey.

Role gear is also modeled and skinned in Blender. `BallplayerEquipment` only
selects the hidden `Gear_*` meshes for batter, catcher, or umpire roles; it does
not construct character geometry at runtime.

## Editing and export

Open `source/ballplayer.blend` in Blender 5.x and edit the meshes, weights, or
actions directly. Export `ballplayer.glb` with glTF 2.0 settings that include:

- binary GLB format;
- materials, UVs, skins, and all vertex influences;
- all actions as separate animations;
- Y-up conversion and applied mesh modifiers;
- extras enabled so the asset contract metadata is retained.

The source directory contains `.gdignore`, so Godot imports the GLB rather than
trying to import the working Blender file. After export, refresh imports with:

```sh
bin/godot.windows.editor.dev.x86_64.console.exe --headless \
  --path games/pixiball --import
```

## Visual QA

The QA helper renders fixed rest and action views without modifying the source:

```sh
blender --background \
  games/pixiball/assets/models/ballplayer/source/ballplayer.blend \
  --python games/pixiball/assets/blender/render_ballplayer_qa.py -- \
  --output-dir /tmp/pixiball-ballplayer-qa --size 512
```

The pitching receipt currently reports release at frame 28, 25.053 m/s hand
speed, 0.230 m root excursion, full root recovery, and 0.015173 m lead-foot
drift. Delivery changes should be authored as new/revised Blender actions; the
actor API and marker contract do not need to change.

For the Godot material and identity view, run:

```sh
bin/godot.windows.editor.dev.x86_64.console.exe --path games/pixiball \
  --script res://tools/capture_ballplayer_review.gd -- --output-dir /tmp/review
```

## Runtime contract

`BallplayerActor` loads the GLB, duplicates its PBR materials per instance,
selects imported equipment, applies palette/height/handedness settings, and
plays the imported actions. It exposes the existing gameplay sockets and
signals. `get_model_kind()` returns `rigged_glb` when the asset loads and
`missing_model` otherwise. `is_using_fallback()` remains as a compatibility
query and always returns `false`.

Stable actions are `idle`, `run`, `pitch`, `swing`, `catch`, `field_ready`,
`field_throw`, `celebrate`, and `slide`; `throw` aliases `field_throw`. Stable
sockets are `head`, `chest`, `left_hand`, `right_hand`, `glove`, `catch`,
`throw_hand`, `ball_release`, `bat_grip`, `bat_tip`, `left_foot`, `right_foot`,
`left_shin`, `right_shin`, and `feet`.

Validate the imported asset and roster/equipment path with:

```sh
bin/godot.windows.editor.dev.x86_64.console.exe --headless --path games/pixiball \
  --script res://characters/tests/test_ballplayer_asset.gd
bin/godot.windows.editor.dev.x86_64.console.exe --headless --path games/pixiball \
  --script res://characters/tests/test_ballplayer_equipment.gd
```

See [asset provenance](../../../docs/ASSET_PROVENANCE.md) for source and
license details.
