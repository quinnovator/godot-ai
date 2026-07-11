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
| `content/legacy/field/` | `Content/RawAssets/field/` | All 58 source PNGs currently compare byte-for-byte. Godot-generated `.import` sidecars exist only in the Godot tree. The stadium uses the authorized day, golden-hour, and night surface/prop textures. |
| `content/legacy/sprites/` | `Content/RawAssets/sprites/` | The 54 production PNG/JSON files currently compare byte-for-byte after excluding Unreal-side `_preview.png` files and Godot `.import` sidecars. They are retained as authorized reference/compatibility assets, not used as the production ballplayer renderer. |

The authorized pitcher dataset includes real pitcher names and pitch arsenals.
The eight club identities in `teams.json` are fictional. The rebuilt production
athlete is a generic art asset and does not attempt a real player's likeness.

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
  `gameplay/live_play_controller.gd` provide the deterministic live Godot ball
  and fielding loop.

Source comments and tests identify faithful ports where behavior is intended to
match exactly. GDScript files remain normal source code and should not be
described as byte-identical copies of Unreal C++.

## Rebuilt for Godot AI

The following are new or rebuilt assets and systems for this repository:

- `main.tscn`, the Godot node architecture, typed semantic driver, scenario
  surface, save/menu flow, and agent-readable state.
- The authored stadium geometry, rebuilt harbor backdrop, pixel-composite
  shader, broadcast cameras, synthesized audio, particles, UI, and pitch-intel
  presentation. The stadium intentionally combines rebuilt geometry with the
  ported field texture set above.
- `assets/models/ballplayer/ballplayer.glb`, its Blender 4.5 LTS `.blend` source,
  deterministic Python recipe, animations, build receipt, and QA renderer.
- `characters/ballplayer_actor.tscn` and the modular helmet, catcher, umpire,
  team-mark, and jersey-number equipment layer. These assets do not use Unreal
  mesh or sprite geometry.
- Semantic haptic composition, portable Godot rumble, and the fork's bounded
  native DualSense/DualSense Edge adaptive-trigger API.

## Not imported or consumed

- Unreal `.uasset`, `.umap`, project configuration, build products, and editor
  plugins are not loaded by the Godot project.
- Unreal sprite sheets are preserved under `content/legacy/sprites/`, but no
  production GDScript or scene loads them for the current ballplayer.
- The Blender athlete does not derive geometry from an Unreal mesh or sprite
  sheet. Its fallback is the repository's procedural `VoxelBallplayer`.

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

Validate the consuming content/model boundary with:

```sh
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/tests/test_content_and_rng.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/tests/test_pitch_model.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/tests/test_replica_integration.gd
```

When adding content, update this document in the same change. Record whether a
file is an unchanged authorized port, a translated implementation, or a rebuilt
asset; do not relabel ported files as generated content.
