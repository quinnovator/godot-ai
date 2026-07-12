# Pixiball: Harbor League

Pixiball is a high-fidelity playable replica and Godot 4.7 reference
implementation of the user's original Unreal Engine game in `../pixiball-ue`.
It preserves the authorized source game's baseball data, trained pitch models,
deterministic fixtures, park dimensions, core rules, modes, and presentation
textures while rebuilding the runtime around agent-operable Godot scenes and a
production Blender character pipeline.

This is not a direct conversion of Unreal packages, a byte-exact runtime port,
or a claim of Unreal trace-digest parity. The game consumes selected source data
and textures, translates or reimplements gameplay systems in GDScript, and uses
rebuilt Godot/Blender presentation assets. The exact content and implementation
boundary is recorded in [Asset provenance](docs/ASSET_PROVENANCE.md); the
measured simulation boundary is recorded under [Compatibility boundary](#compatibility-boundary).

## Play

Open the project with this repository's custom editor build:

```sh
bin/godot.macos.editor.dev.arm64 --editor --path games/pixiball
```

Run the project, choose a mode, and play with keyboard or an SDL-standard
controller. The project renders at a 1280 x 720 reference viewport through the
Godot Compatibility renderer with a final pixel-composite pass.

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
and base throws while the broadcast camera tracks the real ball state.

For headless simulations that do not tick scene fielders,
`core/fielding/semantic_defense.gd` resolves the same trajectory through the
original coarse fielder-intercept, catch, pickup, and throw-race model.
`PixiballSim.resolve_semantic_live_play()` uses an isolated keyed Play stream;
it returns the normal live-play commit packet without mutating the match.

### Production characters and equipment

The primary athlete is `assets/models/ballplayer/ballplayer.glb`, built with
Blender 5.1.2. Asset version 12 combines the procedurally sculpted athlete
body with the professionally sculpted CC0 head (and layered eyes) from
Blender Studio's Human Base Meshes bundle, fitted onto the rig by the
deterministic recipe: a 31-bone armature, eight continuously skinned logical
meshes, roughly 84k exported vertices and 157k triangles, naturalistic
7.7-heads proportions at a ~1.88 m nominal height, and nine native clips:
`idle`, `run`, `pitch`, `swing`, `catch`, `field_ready`, `field_throw`,
`celebrate`, and `slide`. Ball-release, bat-contact, glove-contact,
celebration-peak, and base-contact markers are part of the animation
contract. In-engine, the surface shader layers CC0 Poly Haven
photogrammetry micro-detail (jersey knit, leather grain, wood figure,
sampled triplanar) over Burley/GGX response, and the world composite now
renders at 1920x1080 with near-lossless color so the realistic character
survives presentation.

The mound delivery is a frame-reviewed, right-handed 45-frame sequence with
hemisphere-corrected quaternion tracks: set, lift, hand break, stride, plant,
late cock, release, extension, deceleration, and balanced recovery. The release
is the authored hand-speed peak, the planted foot remains stable, and the root
returns to its idle origin before the runtime blend. The head is an anatomical
loft with sculpted bone structure and fully modeled features -- layered wet
eyeballs under skin lids, brows, nose with nostrils, lips, and ears -- so the
expression remains calm and lifelike through the delivery.

`characters/ballplayer_actor.tscn` is the stable gameplay facade. It adds
per-instance body variation, handedness, team palettes, a physically based
surface shader layering procedural pore/weave/grain/strand micro-detail and
a warm skin-scatter approximation over Burley/GGX response, sockets,
animation aliases, and a procedural voxel fallback used only when the
imported production asset fails validation. Modular bone-attached equipment
supplies batting helmets; catcher and umpire protection; team marks; and
one- or two-digit jersey numbers without rebuilding the base athlete. Front
and back numbers are stitched tackle-twill geometry: authored varsity block
glyphs extruded as a raised fill layer over a contrasting border layer,
wrapped to the torso's measured curvature and shaded with the knit fabric
normal map, with a handedness correction so they remain sharp and readable
instead of mirroring when the model changes batting or throwing side.

See [Ballplayer asset](assets/models/ballplayer/README.md) and
[Equipment architecture](characters/equipment/README.md) for the exact runtime
contract.

### High-density pixel presentation

The presentation combines a real rigged 3D cast with an authored Godot stadium,
the authorized day/golden/night field texture set, a rebuilt harbor backdrop,
toon materials, broadcast cameras, particles, synthesized audio, and a
screen-space pixel-composite shader. Legacy Unreal sprite sheets are retained as
authorized reference assets, but the production ballplayers do not render from
those sheets.

The stadium seats 1,184 deterministic articulated spectators across both side
stands and the plate section. Individuals vary in height, build, skin, hair,
shirt, head direction, arm pose, and cap choice, then receive staggered sway,
breathing, cheer timing, and reaction affinity. The plate crowd is divided into
real seating blocks around an open harbor overlook rather than doubled with a
sprite wall. Semantic play outcomes drive individual crowd, LED, and bell
responses with a bounded decay instead of synchronizing every fan.

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

## Blender 5 production pipeline

The editable `.blend`, deterministic Python recipe, exported GLB, asset
contract, and SHA-256 build manifest live together under
`assets/models/ballplayer/`. Rebuild from the repository root:

```sh
uv run --project agent godot-agent \
  --project games/pixiball \
  blender-build res://assets/blender/build_ballplayer.py \
  --output res://assets/models/ballplayer/ballplayer.glb \
  --blend res://assets/models/ballplayer/source/ballplayer.blend \
  --blender /Applications/Blender.app

bin/godot.macos.editor.dev.arm64 --headless --editor \
  --path games/pixiball --quit
```

Render the fixed rest, pitching, batting, catching, and running QA poses without
modifying the production `.blend`:

```sh
/Applications/Blender.app/Contents/MacOS/Blender \
  --background games/pixiball/assets/models/ballplayer/source/ballplayer.blend \
  --python games/pixiball/assets/blender/render_ballplayer_qa.py -- \
  --output-dir /tmp/pixiball-ballplayer-qa --size 512
```

For independent VLM/modeling-agent candidates, the batch example assigns each
job unique GLB, `.blend`, receipt, and log paths and can run four Blender workers
in parallel. See [Parallel modeling](tools/blender/README.md). Candidates remain
isolated until an agent explicitly validates and promotes one.

For a repeatable rear-camera presentation check, launch Endless Pitch directly
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

# Imported production rig, equipment, and facade/fallback construction
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://characters/tests/test_ballplayer_asset.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://characters/tests/test_ballplayer_equipment.gd
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://characters/character_smoke.gd

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
- `characters/` — production rig facade, modular equipment, gallery, and
  emergency procedural fallback.
- `world/` / `presentation/` — stadium, camera, ball, audio, shader, and haptics.
- `ui/` — landing flow, team/pitcher selection, save data, scoreboard, strike
  zone, results, and pitch-intelligence panel.
- `scenarios/` — deterministic agent-play fixtures.
