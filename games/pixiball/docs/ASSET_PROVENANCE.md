# Pixiball asset and source provenance

This document records the content boundary for the Godot replica. The user has
identified `../pixiball-ue` as their original Unreal Engine game and authorized
it as a reference and content source for this implementation.

The adjacent checkout is the comparison source used below. Its configured Git
remote is `git@github.com:quinnovator/pixiball-ue.git`; the remote name is
informational and is not required at runtime.

## Ported unchanged

| Godot path | Unreal reference path | Current evidence and runtime use |
| --- | --- | --- |
| `content/data/` | `Content/Data/` | All 17 files currently compare byte-for-byte, including pitchers, batters, names, teams, choreography, metadata, jersey stamp, sprite manifest, four XGB model binaries, and golden fixtures. The Godot content catalog and pitch model consume these files. |
| `content/legacy/field/` | `Content/RawAssets/field/` | All 58 source PNGs currently compare byte-for-byte after excluding Godot `.import` sidecars. They are retained for provenance and visual comparison; the native ballpark does not load them, and the export preset excludes `content/legacy/`. |
| `content/legacy/sprites/` | `Content/RawAssets/sprites/` | The 54 production PNG/JSON files currently compare byte-for-byte after excluding Unreal `_preview.png` files and Godot `.import` sidecars. They are archival references, not gameplay or menu sprites, and are excluded from exports. |
| `assets/fonts/unreal_ui/` | `Content/Fonts/` | Pixelify Sans, DotGothic16, and VT323 are unchanged copies of the reference UI font set and provide the display, body, and score roles. The SIL OFL 1.1 text is included beside them. |

The authorized pitcher dataset includes real pitcher names and pitch arsenals.
The eight club identities in `teams.json` are fictional. Native pixel athletes
are generic project-authored designs and do not attempt a real player's
likeness.

## Translated or reimplemented

These systems preserve contracts and behavior from the original source or its
golden fixtures, but are GDScript/native-Godot implementations rather than
Unreal package imports:

- `core/content/content_catalog.gd` loads and validates the ported JSON/binary
  content.
- `core/model/pitch_model.gd` reproduces the 37-feature model input contract,
  sequential-pitch state, tunneling analysis, and four-model evaluation through
  the fork's native `AITreeModel` class.
- `gameplay/pixiball_endless_sim.gd`, `gameplay/pixiball_sim.gd`,
  `gameplay/teams.gd`, `gameplay/bullpen.gd`, `gameplay/pitcher_condition.gd`,
  and `gameplay/stamina_config.gd` implement the game and mode rules.
- `core/fielding/park_geometry.gd` freezes the original Citizens Bank Park
  dimensions; `core/fielding/batted_ball_physics.gd` and
  `gameplay/live_play_controller.gd` provide the deterministic live ball and
  fielding loop.

Source comments and tests identify faithful ports where behavior is intended to
match exactly. GDScript files remain normal source code and should not be
described as byte-identical copies of Unreal C++.

## Rebuilt for Godot AI

The following visible assets and systems are original to this repository:

- `main.tscn`, the native `PixelScene`, semantic driver, scenario surface,
  save/menu flow, and agent-readable state.
- `presentation/pixel_art_style.gd` and `world/pixel_ballpark_canvas.gd`, which
  draw the fixed-view harbor ballpark, crowds, field, props, moods, and reactions
  as deterministic integer-aligned CanvasItem clusters.
- `presentation/broadcast_camera.gd`, which projects simulation `Vector3` data
  into integer pixels for intro, pitching, batting, fielding, and dugout views.
  The spatial values remain a gameplay-data seam and are not visual geometry.
- `characters/ballplayer_actor.tscn`, `characters/ballplayer_actor.gd`, and
  `characters/pixel_actor_sprite.gd`, which provide the native pixel athlete,
  ten stepped actions, roster palette and identity, semantic sockets, and
  logical helmet, bat, glove, catcher, and umpire layers.
- `presentation/baseball_visual.gd` and `presentation/pixel_ball_sprite.gd`,
  which draw the projected ball, shadow, and bounded discrete trails.
- `content/pixel/style_contract.json` and
  `tools/validate_native_pixel_art.py`, the declarative generation contract and
  PNG acceptance gate.
- The native UI, synthesized audio, semantic haptic composition, portable Godot
  rumble, and bounded DualSense/DualSense Edge adaptive-trigger integration.

The PNGs under `docs/art_direction/references/` are review inputs only. The
pitcher-delivery sheet is an original built-in image-generation output; it is
not a runtime texture, sprite atlas, or player likeness. Documentation and
reference images are excluded from exported packs.

## Not imported or consumed

- Unreal `.uasset`, `.umap`, project configuration, build products, and editor
  plugins are not loaded by the Godot project.
- The archived Unreal field and sprite PNGs are not loaded by runtime code.
- No external spatial asset stack, generated panorama, or resize/pixelation
  filter participates in the current image. World and character structures use
  the `320x180` composition vocabulary, material marks use the true `640x360`
  dense grid, and one original world-only shader adds hard native-grid light.
- The additional licensed font directories under `assets/fonts/` remain
  available for development, but the current UI loads only the three authorized
  fonts listed in the table above.

## Reproduce the current comparison

Run from the Godot AI repository root with the authorized Unreal checkout still
at `../pixiball-ue`:

```sh
# Silent exit 0 means every data file is identical.
diff -qr \
  ../pixiball-ue/Content/Data \
  games/pixiball/content/data

# Godot adds import sidecars; the 58 source images should otherwise match.
diff -qr -x '*.import' \
  ../pixiball-ue/Content/RawAssets/field \
  games/pixiball/content/legacy/field

# Unreal-only previews and Godot-only sidecars are outside the 54 source files.
diff -qr -x '*.import' -x '*_preview.png' \
  ../pixiball-ue/Content/RawAssets/sprites \
  games/pixiball/content/legacy/sprites
```

Validate the consuming data/trained-model boundary and native presentation
boundary with:

```sh
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/tests/test_content_and_rng.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/tests/test_pitch_model.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/tests/test_replica_integration.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/tests/test_scene_composition.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://characters/tests/test_ballplayer_asset.gd
```

When adding content, update this document in the same change. Record whether a
file is an unchanged authorized port, a translated implementation, or a rebuilt
asset; do not relabel ported files as generated content.
