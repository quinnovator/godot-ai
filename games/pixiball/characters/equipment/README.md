# Ballplayer equipment architecture

`ballplayer_equipment.tscn` is the reusable presentation layer for role gear
and jersey identity. The production athlete GLB remains an invariant base: 31
bones, eight logical skinned meshes, nine native actions, and the same gameplay
sockets. Equipment is assembled from engine-native meshes sized to the
anatomical head, plus jersey identity built as stitched tackle-twill vector
geometry. Runtime text is converted from the OFL-licensed Graduate collegiate
font into real `TextMesh` contours, with a raised team-primary fill over a
secondary border. Every glyph is independently wrapped and tangent-aligned to
the measured torso ellipse, stands a few millimetres proud of the cloth, and
uses the knit fabric normal map. This keeps the team mark, surname, and number
fully programmable without reducing them to flat billboards. Everything is
attached to semantic bones by `BallplayerActor`.

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
| player roles | front team mark, front number, curved back surname, large back number |

All colored meshes share per-actor local materials. `set_uniform_colors()`
updates the base GLB and role gear together, restyling the lettering in the
new palette; `set_team_mark()`, `set_player_name()`, and
`set_jersey_number()` update the live identity. Identity pieces are rebuilt in
place, so bone attachment and handedness-mirroring
correction survive every palette or identity change. The actor's existing
`bat` and `glove` rules remain authoritative. The imported cap is hidden only
when a helmet or role mask replaces it.

Run the focused contract with:

```sh
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://characters/tests/test_ballplayer_equipment.gd
```

The contract covers one- and two-digit numbers, surname extraction, role piece
sets, bone attachment, animated following, palette propagation, live identity
updates, and unchanged bat/glove/cap visibility. `character_gallery.tscn` is the visual QA surface for
pitcher, batter, catcher, umpire, fielder, and sliding runner variants across
the complete native action cycle.
