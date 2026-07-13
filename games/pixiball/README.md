# Pixiball: Harbor League

Pixiball is a high-fidelity playable replica and Godot 4.7 reference
implementation of the user's original Unreal Engine game in `../pixiball-ue`.
It preserves the authorized source game's baseball data, trained pitch models,
deterministic fixtures, park dimensions, core rules, modes, and presentation
textures while rebuilding the runtime around agent-operable Godot scenes and a
native `2560x1440` direct-CanvasItem presentation pipeline.

This is not a direct conversion of Unreal packages, a byte-exact runtime port,
or a claim of Unreal trace-digest parity. The game consumes selected source data
and textures, translates or reimplements gameplay systems in GDScript, and uses
rebuilt native-pixel presentation code. The exact content and implementation
boundary is recorded in [Asset provenance](docs/ASSET_PROVENANCE.md); the
measured simulation boundary is recorded under [Compatibility boundary](#compatibility-boundary).

## Play

Open the project with this repository's custom editor build:

```sh
bin/godot.macos.editor.dev.arm64 --editor --path games/pixiball
```

Run the project, choose a mode, and play with keyboard or an SDL-standard
controller. The project renders directly into one `2560x1440` root framebuffer.
Composition retains its `320x180` vocabulary, expands it through a 2x density
pass onto a `640x360` design grid, and `PixelScene` uses an exact 4x CanvasItem
transform so every dense design unit becomes a `4x4` native block. There is no
low-resolution texture, intermediate viewport, upscale, or post-process pixel
filter.

### Modes

- **Endless Pitch** — choose one of ten pitchers and keep pitching until three
  runs score. Strikeouts are the score, every pitch is user-thrown, every live
  ball is user-fielded, and three outs clear the bases without changing sides.
  The career-best strikeout total is saved locally.
- **Versus** — choose distinct player and CPU clubs from eight fictional teams,
  then play 3, 6, or 9 innings at Rookie, Pro, or All-Star difficulty. The full
  game includes batting and defense, sides and innings, stamina, five-pitcher
  staffs, bullpen warm-up and substitution, extra innings, and walk-offs. The
  win-loss record is saved locally.

### Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Navigate / aim / move fielder | W A S D or arrows | Left stick or d-pad |
| Pitch / swing / confirm | Space | R2 / right trigger |
| Pitch 1–4 / throw or command runner home–third | 1–4; hold/release when fielding | Cross/A, Circle/B, Triangle/Y, Square/X |
| Pitch 5 | 5 | R1 / RB |
| Cycle assisted fielder / runner | Q | L1 / LB |
| Start / title confirm | Enter | Options/Menu or Cross/A |
| Restart | R | Create/View/Back |
| Lighting mood | M | R3 |
| Back | Escape | Circle/B |

The primary action intentionally uses the right trigger. Pitch selection and
throw are read in the same ready-state tick, so sharing a face button would
select a pitch and immediately release it.

## Current game systems

### Trained pitch model and tunneling feedback

`core/model/pitch_model.gd` packs the original 37-feature contract and evaluates
the four authorized XGBoost-derived XGB1 assets through this fork's bounded
native `AITreeModel` evaluator:

- stage one predicts ball, called strike, swinging strike, foul, or in play;
- stage two predicts out, single, double, triple, or home run after contact;
- two regressors predict launch speed and launch angle.

Sequential pitch state measures tunnel separation, break difference,
break-to-tunnel ratio, pitch-shape distance, and late movement. Model results
drive CPU plate outcomes and launch predictions; human batting combines model
contact information with barrel position and timing. The pitch-intelligence
panel reports probabilities, expected versus actual run value, tunnel metrics,
ranked counterfactual pitch options, and a catcher-view release/tunnel/plate
diagram.

### Live ball and fielding

The batted ball is advanced in the live game, not replaced by a presentation
arc. `core/fielding/batted_ball_physics.gd` is a deterministic 60 Hz integrator
with gravity, quadratic drag, backspin lift, wall collision, bounce, roll, and
stop states. It classifies fair/foul balls, wall caroms, and home runs against
the frozen Citizens Bank Park fence and wall-height geometry.

`gameplay/live_play_controller.gd` predicts the first playable point, selects
and assists a defender, follows wall caroms, and resolves user catches, pickups,
and base throws while the broadcast director projects the real ball state.

For headless simulations that do not tick scene fielders,
`core/fielding/semantic_defense.gd` resolves the same trajectory through the
original coarse fielder-intercept, catch, pickup, and throw-race model.
`PixiballSim.resolve_semantic_live_play()` uses an isolated keyed Play stream;
it returns the normal live-play commit packet without mutating the match.

### Native pixel characters and equipment

`characters/ballplayer_actor.tscn` remains the stable gameplay facade. Its
`BallplayerActor` is a logic node that carries baseball-space `Vector3` data,
team and roster identity, handedness, semantic sockets, role equipment, and
action markers. A detached `PixiballPixelActorSprite` attaches directly to
`PixelScene` and draws the visible athlete with integer-aligned CanvasItem
clusters. `native_pixel_sprite` is the runtime model kind; the character image
is generated entirely by the native pixel presenter.

Characters are designed at 34/20/15 design units for hero, midground, and field
actors, producing exactly 136/80/60 native framebuffer pixels. The presenter
favors a broad head, compact torso, readable limb lines, and two-or-more-unit
equipment marks over anatomy that disappears at gameplay scale. Team palette,
skin and hair variation, jersey mark, number, helmet, bat, glove, catcher gear,
and umpire mask remain deterministic logical layers.

Ten pose-authored actions run at a stepped 10 fps: `idle`, `run`, `pitch`,
`swing`, `catch`, `field_ready`, `field_throw`, `throw`, `celebrate`, and
`slide`. Ball-release, bat-contact, glove-contact, celebration-peak, and
base-contact markers preserve the gameplay timing contract. Mirroring changes
the authored facing direction without filtering the sprite or mirroring text.

See [Native pixel pipeline](docs/art_direction/NATIVE_PIXEL_PIPELINE.md) and
[Visual direction](docs/art_direction/ART_DIRECTION.md) for the generation and
promotion rules.

### Native-1440 pixel presentation

`PixelScene` is a direct `Node2D` stage scaled 4x inside the native `2560x1440`
root. World, actors, ball, effects, and HUD use a `640x360` dense design grid;
legacy composition landmarks remain in `320x180` vocabulary and are expanded
2x before rasterization. Neither grid is ever an intermediate framebuffer.
`PixelBallparkCanvas` draws flat sky, harbor, stadium, field, 8x8-design-unit
tile detail, crowd clusters, and day/golden/night palettes. Crowd, LED, bell,
and burst reactions are deterministic and outcome-driven.

The broadcast director is a projector, not a render camera. Gameplay continues
to own finite `Vector3` baseball positions; the director maps them to integer
`Vector2` pixels, visibility, depth order, and large/small/tiny actor LOD in
five authored views: intro, pitching, batting, fielding, and dugout. The ball
uses the same seam and draws a discrete one- to three-design-unit mark (4-12
native pixels) with bounded five-sample pitch and two-sample play trails. This
keeps simulation data intact without making it presentation geometry.

### DualSense and portable haptics

Pitching emits semantic `release`, `tunnel`, `frontdoor`, `backdoor`,
`corner_paint`, `called_k`, and `swinging_k` cues. The composer uses pitch
location, tunneling, predicted outcome, confidence, and strikeout context to
produce bounded timelines. On ordinary gamepads, Godot rumble encodes the two
semantic sides across strong/low- and weak/high-frequency channels.

This fork also adds native adaptive-trigger effects for official DualSense and
DualSense Edge device IDs. Directional cues can move between physical L2 and R2
while portable body rumble remains active. The current native boundary provides
true left/right trigger locality; it does not claim DualSense voice-coil PCM,
controller-speaker routing, or spatial body-haptic playback. See
[Pitch haptics](presentation/haptics/README.md) for the API, limits, diagnostics,
and hardware boundary.

## Agent control

The project vendors and enables `godot_ai_runtime`. Start the game through a
running Godot AI editor, then inspect its typed semantic contract and state.
Parameterless `play` always starts the project main scene (`main.tscn`), even if
another scene is currently open in the editor. Use `play --current` only when
you explicitly want the currently edited scene:

```sh
uv run --project agent godot-agent --project games/pixiball play
uv run --project agent godot-agent --project games/pixiball play --current
uv run --project agent godot-agent --project games/pixiball \
  runtime-call gameplay.describe
uv run --project agent godot-agent --project games/pixiball \
  runtime-call gameplay.state
```

Declared intents include `start_match`, `start_endless`, `start_versus`,
`rematch`, `exit_to_menu`, `select_pitcher`, `select_pitch`, `aim`, `primary`,
`move_fielder`, `throw_base`, `press_throw`, `release_throw`, `cycle_fielder`,
`cycle_runner`, `command_runner`, `autoplay`, and `set_mood`.
State snapshots include the menu and match mode, phase-correct `legal_actions`,
saved records, live pitcher/batter identity, pitch selection, aim and delivery
progress, live-ball state, and haptic diagnostics.
Intents enter the normal command path on the next physics tick; the bridge
cannot invoke arbitrary game methods.

Four deterministic scenarios exercise pitching, selected-team Versus setup,
agent diagnostics, clean menu teardown, and bounded live-ball fielding:

```sh
uv run --project agent godot-agent --project games/pixiball \
  scenario-run games/pixiball/scenarios/first_pitch.json
uv run --project agent godot-agent --project games/pixiball \
  scenario-run games/pixiball/scenarios/tunnel_sequence.json
uv run --project agent godot-agent --project games/pixiball \
  scenario-run games/pixiball/scenarios/versus_semantic_loop.json
uv run --project agent godot-agent --project games/pixiball \
  scenario-run games/pixiball/scenarios/live_ball_fielding.json
```

## Compatibility boundary

The authorized Unreal `sim_golden.json` and `trace_golden.json` fixtures remain
executable compatibility evidence, not labels applied by inspection. The
`test_sim_golden_compatibility.gd` audit validates both fixture schemas, runs a
deterministic Godot semantic replay twice for each of five canonical seeds, and
reports every currently observed difference. Its neutral controller mixes
strikes, edges, chases, takes, and imperfect swings; balls in play use the
coarse physical defense instead of treating every well-hit grounder as a hit.
Broad per-game and population rate bands catch implausible scoring, hit,
strikeout, walk, batter, and pitch counts without labeling Godot as tick-parity.

The current measured boundary is explicit: 11 of 60 comparable coarse values
match, 49 differ, the five Unreal presentation-tick counts have no equivalent
in the semantic Godot transition loop, and none of the six per-tick trace digest
items are comparable. Thus `parity=false` is the expected passing result. Godot
has its own executable deterministic contracts for models, rules, modes, and
live-ball physics; passing them proves stable Godot behavior, not byte- or
digest-identical execution with Unreal.

```sh
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/tests/test_sim_golden_compatibility.gd
```

## Native pixel production pipeline

[`content/pixel/style_contract.json`](content/pixel/style_contract.json) is the
source of truth for generated and hand-authored additions. It freezes the
`2560x1440` root framebuffer, `640x360` design space, 2x linear density pass,
4 px authoring grid, actor
sizes, 10 fps animation cadence, palette and binary-alpha limits, fixed views,
and direct-CanvasItem runtime rules.

Validate candidate PNGs from `games/pixiball` before importing them:

```powershell
python tools/validate_native_pixel_art.py `
  content/pixel/style_contract.json `
  <candidate.png>
```

The validator rejects art with the wrong native dimensions or grid alignment,
fractional alpha, gradient-heavy output, and unbounded palettes. Runtime art
uses the same declarative rules through `presentation/pixel_art_style.gd`;
resampling is not used to repair source art.

Capture the authored framebuffer without `--headless` so Godot can read a
completed GPU frame:

```powershell
bin\godot.windows.editor.dev.x86_64.console.exe `
  --path games/pixiball `
  --script res://tools/capture_visual_rebuild.gd -- `
  --screen=game-batting-golden `
  --output=res://.godot/visual-qa/game-batting-golden.png
```

The capture tool writes the native `2560x1440` framebuffer. It supports landing,
pitcher/team selection, final, the three moods in pitching, batting, and
fielding views, plus the legacy `game-day`, `game-golden`, and `game-night`
pitching aliases.

For a repeatable pitching-view presentation check, launch Endless Pitch directly
and optionally leave the ready pose on screen before autoplay begins:

```sh
bin/godot.windows.editor.dev.x86_64.console.exe --path games/pixiball -- \
  --autoplay --scenario=endless --autoplay-delay=4.0
```

## Validation

Run every `test_*.gd` contract plus the character construction smoke:

```sh
tools/godot-ai/test-pixiball.sh
```

The most useful focused contracts are:

```sh
# Authorized content, 37-feature model, four model assets, and golden integration
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/tests/test_pitch_model.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/tests/test_replica_integration.gd

# Endless and Versus mode rules
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://gameplay/tests/test_endless_sim.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://gameplay/tests/test_versus_sim.gd

# Live ball physics, semantic defense, and fielding integration
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/fielding/tests/test_batted_ball_physics.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/fielding/tests/test_semantic_defense.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://gameplay/tests/test_live_play_controller.gd

# Native pixel actor actions, equipment layers, and roster identity
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://characters/tests/test_ballplayer_asset.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://characters/tests/test_ballplayer_equipment.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://characters/character_smoke.gd

# Native scene, integer projector, and pixel baseball presentation
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/tests/test_native_720_pipeline.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://core/tests/test_scene_composition.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://presentation/tests/test_broadcast_camera.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://presentation/tests/test_baseball_visual.gd

# Portable/native haptic composition and complete menu/mode wiring
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://presentation/haptics/tests/test_haptics.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://ui/tests/test_shell_integration.gd
```

The engine-side evaluator and DualSense driver contracts are native doctests:

```sh
bin/godot.macos.editor.dev.arm64 --test --test-case='[AITreeModel]*'
bin/godot.macos.editor.dev.arm64 --test --test-case='[SDL][DualSense]*'
```

### Pack export smoke

[`export_presets.cfg`](export_presets.cfg) defines the `macOS` preset and its
bundle metadata. CI performs a pack-only export, which validates resource
selection and serialization without requiring platform export templates or
code signing. Reproduce that smoke locally and verify the output is nonempty:

```sh
pack="${TMPDIR:-/tmp}/pixiball-export-smoke.pck"
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --export-pack macOS "$pack"
test -s "$pack"
```

## Source map

- `main.tscn` / `main.gd` — scene composition, input and agent intent routing,
  simulation-to-presentation choreography, and mode lifecycle.
- `core/content/` — authorized data loading and validation.
- `core/model/` — pitch feature packing, trained model evaluation, and tunneling.
- `core/fielding/` — deterministic batted-ball physics, park geometry, and
  presentation-free semantic defense.
- `gameplay/` — Endless and Versus simulation, bullpens, stamina, live fielding,
  and controller-facing commands.
- `characters/` — logic actors, native pixel presenters, role-equipment
  layers, roster identity, actions, markers, and construction smoke.
- `world/` / `presentation/` — native ballpark canvas, integer world projector,
  pixel ball, shared art style, audio, and haptics.
- `ui/` — landing flow, team/pitcher selection, save data, scoreboard, strike
  zone, results, and pitch-intelligence panel.
- `scenarios/` — deterministic agent-play fixtures.
