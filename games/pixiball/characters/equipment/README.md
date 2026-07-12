# Ballplayer equipment and jersey identity

`ballplayer_equipment.tscn` is a selector and roster-text controller for the
Blender-authored ballplayer. It never creates 3D character geometry.

The production GLB contains hidden, skinned meshes for the batting helmet,
catcher mask/chest/shins, and umpire mask/chest. The controller toggles those
`Gear_*` objects by role while `BallplayerActor` applies the same per-instance
team material palette used by the uniform.

The jersey contains two Blender-authored, skinned UV surfaces:
`JerseyIdentityFront` and `JerseyIdentityBack`. Two 512x512 transparent
`SubViewport`s render the OFL-licensed Graduate font into those surfaces. This
keeps the team mark, one- or two-digit number, and surname editable at runtime
without `TextMesh`, primitive meshes, or a GLB rebuild. When handedness mirrors
the athlete, the material U transform is flipped so the lettering remains
readable.

| Role/spec | Selected Blender meshes |
| --- | --- |
| `helmet=true` (batter default) | `Gear_BattingHelmet` |
| `role=catcher` | `Gear_CatcherMask`, `Gear_CatcherChest`, both catcher shins |
| `role=umpire` | `Gear_UmpireMask`, `Gear_UmpireChest` |
| player roles | both identity UV surfaces and live roster viewports |

Run the focused contract with:

```sh
bin/godot.windows.editor.dev.x86_64.console.exe --headless --path games/pixiball \
  --script res://characters/tests/test_ballplayer_equipment.gd
```

It verifies that role pieces are imported Blender `ArrayMesh` objects on the
shared skin, the controller creates no 3D geometry, palette changes propagate,
live surname/number changes redraw the viewports, and handedness never mirrors
the visible glyphs.
