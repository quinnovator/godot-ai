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
| `content/legacy/sprites/` | `Content/RawAssets/sprites/` | The 54 production PNG/JSON files currently compare byte-for-byte after excluding Unreal-side `_preview.png` files and Godot `.import` sidecars. The 3D game still uses the rebuilt ballplayer; the landing screen now uses one authorized frame from the pitcher and batter sheets as small pixel-art accents. |
| `assets/fonts/unreal_ui/` | `Content/Fonts/` | Pixelify Sans, DotGothic16, and VT323 are unchanged copies of the reference UI font set and restore the exact display/body/score roles. The SIL OFL 1.1 text is included beside them. |

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
  shader, broadcast cameras, synthesized audio, particles, and pitch-intel
  presentation. The UI remains a native Godot implementation but now ports the
  Unreal Slate layout, typography, palette, and interaction states directly.
- `assets/models/ballplayer/ballplayer.glb`, its Blender 5.1.2 `.blend` source,
  deterministic Python recipe, animations, build receipt, and QA renderer.
  The head and layered eye meshes come from the CC0 (public domain) Blender
  Studio "Human Base Meshes" bundle (realistic animation head), vendored as
  `assets/models/ballplayer/source/cc0_head_base.blend` and fitted/re-weighted
  by the recipe; the asset does not attempt a real-player likeness. All other
  geometry is procedurally sculpted inside the recipe.
- `assets/textures/surface/` holds CC0 Poly Haven photogrammetry detail maps
  (cotton jersey knit, brown leather, fine-grained wood; see its
  `LICENSES.md`), sampled triplanar as runtime micro-surface detail.
- `assets/textures/uniform/double_knit_albedo.png` is a Codex built-in
  image-generation output authored as a neutral, seamless, tintable runtime
  textile tile. It contains no logo, lettering, player likeness, or source-game
  artwork.
- `assets/fonts/graduate/Graduate-Regular.ttf` comes from the official Google
  Fonts repository under SIL Open Font License 1.1; its license text is vendored
  beside the font. Godot converts its vector contours into the runtime uniform
  identity meshes.
- `characters/ballplayer_actor.tscn` and the modular helmet, catcher, umpire,
  team-mark, surname, and jersey-number equipment layer. These assets do not
  use Unreal mesh or sprite geometry.
- Semantic haptic composition, portable Godot rumble, and the fork's bounded
  native DualSense/DualSense Edge adaptive-trigger API.
- `docs/art_direction/references/pixiball-pitcher-delivery-sheet-v2.png` is a
  Codex built-in image-generation output used only as production art direction.
  It is not a runtime texture, sprite atlas, third-party mesh, or player likeness.

## Not imported or consumed

- Unreal `.uasset`, `.umap`, project configuration, build products, and editor
  plugins are not loaded by the Godot project.
- Unreal sprite sheets are preserved under `content/legacy/sprites/`; only two
  landing-screen mascot frames are loaded. Gameplay ballplayers remain 3D.
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
