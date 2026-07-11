# Pixiball production ballplayer

This is an original, deterministic, rigged character asset for Pixiball. Its
continuous multi-weight anatomy paints every uniform accent -- belt and buckle,
button placket, raglan shoulder yoke, jersey side panels, sleeve cuff piping,
leg piping, knee folds, sock stripes, and bat grip wraps -- directly onto
deforming chain faces. Deltoid/bicep/elbow/forearm and knee/calf/ankle
landmarks are authored into the ring radii, the pants tuck inside the jersey
hem with shared hips weighting so the midriff can never open, and the hands
are sculpted chains with knuckle and finger-scallop profiles: a half-open
glove hand plus a throwing-hand fist that wraps the resting bat handle. A
graphic four-value face, a lobed baseball mitt with a recessed pocket and one
open web bridge, sculpted one-piece cleats with bold laces and chunky studs,
and a curved tapered cap brim complete the premium hybrid pixel-art
silhouette. No
Unreal mesh or sprite geometry is used by this rebuilt character asset, it does
not attempt a real-player likeness, and it contains no third-party character
geometry. The wider game does retain authorized data and reference textures
from the user's original project; see
[Asset provenance](../../../docs/ASSET_PROVENANCE.md).

The GLB is the runtime source of truth. The `.blend` remains beside it under the
ignored `source/` directory so Godot never tries to invoke Blender while a
ready-to-import GLB is present. `ballplayer.glb.agent.json` records the exact
Blender version plus SHA-256 hashes; `ballplayer.asset.json` records the stable
gameplay/art contract.

## Rebuild

Install or select Blender 4.5 LTS, then run from the repository root:

```sh
uv run --project agent godot-agent \
  --project games/pixiball \
  blender-build res://assets/blender/build_ballplayer.py \
  --output res://assets/models/ballplayer/ballplayer.glb \
  --blend res://assets/models/ballplayer/source/ballplayer.blend \
  --blender /path/to/Blender.app
```

The companion stages and validates both binary outputs before replacing them.
Open the project or run the repository editor headlessly after a rebuild so
Godot refreshes the PackedScene:

```sh
bin/godot.macos.editor.dev.arm64 --headless --editor \
  --path games/pixiball --quit
```

## Deterministic visual QA

Render the same rest, field-ready, mound delivery, infield throw, swing, catch,
run, celebration, and slide review poses after any geometry or animation
change:

```sh
/Applications/Blender.app/Contents/MacOS/Blender \
  --background games/pixiball/assets/models/ballplayer/source/ballplayer.blend \
  --python games/pixiball/assets/blender/render_ballplayer_qa.py -- \
  --output-dir /tmp/pixiball-ballplayer-qa --size 512
```

The renderer uses a fixed three-point studio, camera/lens, action frames, color
management, and equipment visibility. It writes individual PNGs plus
`qa_receipt.json`; it never saves changes back to the production `.blend`.

## Instantiate

The facade loads the rigged model first and creates `VoxelBallplayer` only when
the GLB cannot be loaded or lacks its skeleton, meshes, or animations.

```gdscript
const BallplayerScene = preload("res://characters/ballplayer_actor.tscn")

var player := BallplayerScene.instantiate() as BallplayerActor
player.configure({
    "seed": 34,
    "role": "pitcher",
    "number": 34,
    "build": "power",
    "throws": "right",
    "primary_color": Color("173f73"),
    "secondary_color": Color("f1ead9"),
    "accent_color": Color("e2b447"),
})
add_child(player)
player.set_facing(Vector3.FORWARD)
player.play_action("pitch")
```

`configure()` is safe before `add_child()`. World-space socket transforms become
valid once the actor is inside the scene tree. The current game instantiates
this facade as its primary character path; `voxel_ballplayer.gd` remains the
validated emergency fallback when the GLB contract cannot be loaded.

The authored skeleton is right-sided. `BallplayerActor` mirrors the complete
model on X per action: batting side owns `swing`, while throwing hand owns
`pitch`, `catch`, `field_ready`, `field_throw`, and the `throw` alias. A player
configured to bat left and throw right therefore changes orientation correctly
between offense and defense without duplicate GLBs.

## Exact gameplay API

| Member | Contract |
| --- | --- |
| `configure(spec: Dictionary)` | Applies deterministic height/build variation, handed mirroring, skin/hair palette, equipment visibility, and team colors. |
| `play_action(name: String)` | Plays nine native clips: `idle`, `run`, `pitch`, `swing`, `catch`, `field_ready`, `field_throw`, `celebrate`, and `slide`; `throw` is a compatibility alias for `field_throw`. |
| `set_motion(velocity: Vector3)` | Selects idle/run and scales run cadence. |
| `set_facing(direction: Vector3)` | Smoothly rotates the actor toward a world-space direction. |
| `get_socket_position(name: String) -> Vector3` | Returns a stable world-space gameplay point. |
| `get_socket_node(name: String) -> Node3D` | Returns the live `BoneAttachment3D`, or `null` on voxel fallback. |
| `attach_to_socket(node, name, keep_global=false) -> bool` | Parents props/effects to the live rig socket. |
| `set_uniform_colors(primary, secondary, accent, pants)` | Overrides local material copies without mutating the imported scene. |
| `set_team_mark(mark: String)` | Stores the semantic mark; generated/licensed logo meshes should attach to `chest`. |
| `get_team_mark() -> String` | Returns the live one-character identity mark. |
| `get_jersey_number() -> int` | Returns the normalized 0-99 jersey number. |
| `get_equipment_profile() -> Dictionary` | Reports role, mark, number, and installed modular piece names. |
| `get_equipment_piece(name: String) -> Node3D` | Returns a live helmet/mask/protector/identity attachment for QA or presentation. |
| `set_highlighted(enabled: bool)` | Applies a local emissive selection treatment. |
| `get_current_action() -> String` | Returns the requested gameplay action, including compatibility aliases. |
| `get_generation_signature() -> String` | Returns the deterministic actor identity signature. |
| `is_using_fallback() -> bool` | Reports whether the procedural actor was selected. |
| `get_model_kind() -> String` | Returns `rigged_glb` or `voxel_fallback`. |
| `get_available_actions() -> PackedStringArray` | Returns all accepted gameplay action names. |

Signals are `action_started(action_name)`, `action_marker(action_name,
marker_name)`, and `action_finished(action_name)`. Native markers are
`pitch:ball_release`, `swing:bat_contact`, `catch:glove_contact`,
`field_throw:ball_release`, `celebrate:celebration_peak`, and
`slide:base_contact`.

Stable socket names are `head`, `chest`, `left_hand`, `right_hand`, `glove`,
`catch`, `throw_hand`, `ball_release`, `bat_grip`, `bat_tip`, `left_foot`,
`right_foot`, `left_shin`, `right_shin`, and `feet`.

The base asset stays role-neutral. `characters/equipment/ballplayer_equipment.tscn`
adds batting helmets, catcher/umpire protection, team marks, and jersey numbers
as bone-attached, per-instance pieces. This preserves the GLB contract and lets
future agents replace one equipment family without rebuilding the athlete.

## Validation

```sh
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://characters/tests/test_ballplayer_asset.gd

bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://characters/tests/test_ballplayer_equipment.gd
```

The check loads the real imported scene, verifies the 31-bone armature, eight
skinned logical meshes, nine distinct native animations, per-action handedness,
material slots, grounded bounds, facade sockets/recoloring/equipment, action
signals, and the intentional voxel fallback path.
