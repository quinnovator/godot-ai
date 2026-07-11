# Ballplayer equipment architecture

`ballplayer_equipment.tscn` is the reusable presentation layer for role gear
and jersey identity. The production athlete GLB remains an invariant base: 31
bones, eight logical skinned meshes, nine native actions, and the same gameplay
sockets. Equipment is assembled from inexpensive engine-native meshes and
`Label3D` identity glyphs, then attached to semantic bones by
`BallplayerActor`.

Top-level pieces are first positioned in the actor's neutral coordinate space
and reparented to `BoneAttachment3D` nodes with their world transform
preserved. This keeps their authoring coordinates readable while masks follow
the head, protectors follow the chest, and shin guards follow each shin through
all imported clips.

| Role/spec | Modular pieces |
| --- | --- |
| `helmet=true` (batter by default) | team-colored helmet, brim, ear flap, padding, stripe |
| `role=catcher` | mask, plated chest protector, left/right shin guards |
| `role=umpire` | neutral cage mask and padded protector |
| player roles | front team mark, front number, large back number |

All colored meshes share per-actor local materials. `set_uniform_colors()`
updates the base GLB and role gear together; `set_team_mark()` updates the live
front glyph. The actor's existing `bat` and `glove` rules remain authoritative.
The imported cap is hidden only when a helmet or role mask replaces it.

Run the focused contract with:

```sh
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://characters/tests/test_ballplayer_equipment.gd
```

The contract covers one- and two-digit numbers, role piece sets, bone
attachment, animated following, palette propagation, live marks, and unchanged
bat/glove/cap visibility. `character_gallery.tscn` is the visual QA surface for
pitcher, batter, catcher, umpire, fielder, and sliding runner variants across
the complete native action cycle.
