# THE LANTERN WHARF — Pixiball Greenfield Art Bible

Version 2.0 — the binding visual specification for the greenfield rebuild.
It supersedes the earlier "SALTLIGHT" draft in full and pairs with
`content/pixel/style_contract.json` for native rendering constraints.

The redesign used the [official Celeste screenshot](https://www.celestegame.com/images/screenshots/p00.png)
as a review-only style reference alongside a pre-rebuild Pixiball capture.
The third-party screenshot is not vendored with the project.

The reference teaches *method only*: impressionistic clustering, dramatic
value structure, layered silhouettes, warm/cool focal contrast, and compact
expressive characters. Nothing from it is copied — no characters, scenery,
UI ornament, or exact palette.

---

## 1. Visual thesis

> **Pixiball is a lantern held up against the sea.**
>
> Every screen is a small bowl of warm, human light — the diamond, the
> players, the painted signage — set into a vast, cool harbor evening of
> sky, water, and town. Warmth means *life and play*; coolness means
> *distance and atmosphere*. The eye always lands where the game lives,
> because the game is the warmest thing on screen.

The baseline capture reads as flat vector wedges, a per-pixel confetti crowd,
and debug-grey overlay UI. The Lantern Wharf replaces all of it: the world
becomes a stacked, breathing harbor painted in organic 4px clusters; the
characters become chunky, joyful "pocket giants"; the UI becomes ballpark
furniture — enamel lightboards, painted plank rosters, pennant tabs, a chalk
rail — that belongs to the same wharf as the field.

### 1.1 Named style pillars (binding)

Every implementation decision must be justifiable by at least one pillar.

1. **LANTERN LOGIC** — Exactly one warm focal pool per screen. Anything warm
   (`lantern_gold`, `clay_lit`, `window_lit`, skin tones) is either the focal
   subject or a deliberately quieter secondary beacon at least two value
   rungs below it. If two warm pools compete, one of them is wrong.
2. **FIVE HORIZONS** — Each gameplay screen stacks exactly five atmospheric
   bands (sky → skyline/sea → stands → field wall → playfield), each on its
   own value rung, separated by value, never by outline alone.
3. **CLUSTERS, NOT CONFETTI** — All texture is authored as organic clusters
   of 4px design cells with deliberate silhouettes: drift edges, clumped
   crowd masses, directional wave grain. Uniform per-cell random noise (the
   baseline crowd) is forbidden everywhere, forever.
4. **POCKET GIANTS** — Athletes are compact, big-headed, huge-handed, and
   readable at three fixed LODs. Emotion lives in eyebrows, mouth, and body
   lean; role lives in silhouette and equipment, never in floating labels.
5. **PAINTED SIGNAGE** — UI is physical wharf-and-ballpark furniture with
   material identity, an ink frame, and a hard offset shadow. No panel may
   look like a generic engine overlay.

---

## 2. Technical frame (inherited, restated)

- Native root framebuffer `2560x1440`. No SubViewport, no 320x180 buffer, no
  resized intermediate, no 3D node, and no filtered pixelation.
- Structural world/actor art retains a 320x180 composition vocabulary and is
  expanded 2x onto the true 640x360 design grid. One structural cell is 8x8
  native pixels; a 0.5-cell material mark is one true design cell and exactly
  4x4 native pixels through `PixelScene`.
- One world-only shader (`WorldCompositeLayer/WorldGrade`) is allowed. It uses
  nearest 4 px taps for hard rim, stepped emissive, posterization, and sparse
  atmosphere, then the HUD renders natively above it.
- UI Controls and fonts use direct native coordinates and native font sizes;
  rendered text is never scaled as a texture. UI decoration snaps to a 4px
  rhythm for cohesion.
- Integer coordinates only; opaque authored color clusters only (the two
  veil roles in §3.2 are the sole sanctioned translucent draws); nearest
  filtering for any source texture.
- All five views (`intro`, `pitching`, `batting`, `fielding`, `dugout`) and
  all three moods (`day`, `golden`, `night`) ship. Gameplay behavior, public
  APIs, input, deterministic sim, action timing/markers, socket contracts,
  and save/content schemas are untouched.

---

## 3. Shared palette

Roles are the API; hexes are the values. All world drawing resolves roles
through `presentation/pixel_art_style.gd` `MOOD_PALETTES`; identity roles
live in `ui/pixiball_style.gd`. **No view file may declare a new color
literal.**

### 3.1 Fixed identity roles (mood-invariant)

| Role | Hex | Use |
| --- | --- | --- |
| `ink` | `#0e1220` | The universal darkest: every outline, UI frame, deepest shadow. Nothing may be darker. |
| `ball_white` | `#f8f4e6` | The baseball, plus chalk-critical highlights only. |
| `stitch_red` | `#d94a3d` | Ball stitches, danger/out states, Harbor Foxes trim. |
| `lantern_gold` | `#ffc65a` | THE focal accent: focus ticks, score digits, lit lantern cores, celebration. |
| `signal_teal` | `#55d6c4` | Secondary signal: Pier Lights trim, aim reticle, tunnel/deception readouts. |
| `chalk_paper` | `#efe9d4` | Primary UI text and chalk marks. |
| `steel_text` | `#9db2c4` | Secondary UI text, road uniforms. |
| `slate_text` | `#5f7189` | Tertiary/disabled UI text (decorative only, never critical). |
| `good_green` | `#46bd6e` | Positive gameplay state (fresh stamina, grade A). |
| `warn_amber` | `#f2a13c` | Caution gameplay state (tiring, grades C–D). |

### 3.2 Environment roles (per mood)

| Role | Day | Golden | Night | Use |
| --- | --- | --- | --- | --- |
| `sky_high` | `#3a79b4` | `#5a3a68` | `#0b1330` | Top 40% of the sky band. |
| `sky_low` | `#a3ccd9` | `#ec9a5e` | `#223760` | Horizon glow; warmest sky value. |
| `cloud_lit` | `#ecf4ef` | `#f9cd8a` | `#42537c` | Cloud tops and lit rims. |
| `cloud_shade` | `#b7d3d9` | `#cf8f6f` | `#2b3a62` | Cloud bellies. |
| `sea_far` | `#2e6c95` | `#6b4a69` | `#0e2442` | Distant water plane. |
| `sea_near` | `#57a1b3` | `#c78468` | `#1a3a5e` | Near water plane. |
| `sea_glint` | `#cdeae3` | `#ffdca3` | `#7ea9d2` | Sparse wave catch-lights (moonlit at night). |
| `town_far` | `#4d6c8a` | `#745a7d` | `#1b2a4a` | Far skyline silhouette fill. |
| `town_near` | `#35526d` | `#574261` | `#12203c` | Near skyline/wharf silhouette fill. |
| `roof_accent` | `#ad5346` | `#c2694d` | `#463250` | Sparse roof/chimney warm notes. |
| `window_lit` | `#f4d98d` | `#ffcf7e` | `#ffd98a` | Lit windows; density scales with mood (§7.6). |
| `stand_shell` | `#2b4359` | `#4b3753` | `#16213c` | Grandstand timber/steel structure. |
| `seat_board` | `#3f6278` | `#72576a` | `#263252` | Bench boards, empty seats. |
| `crowd_shadow` | `#203449` | `#392c46` | `#0c152a` | Crowd mass base, under-deck dark. |
| `crowd_warm` | `#d9976b` | `#ea9d63` | `#cd8d51` | Lit crowd faces/shirts, clustered per §7.5. |
| `crowd_cool` | `#6e88a1` | `#8c6f87` | `#3c4e72` | Shaded crowd bodies. |
| `turf_lit` | `#5f9d54` | `#89874b` | `#2d5349` | Mow-band highlight arcs. |
| `turf_main` | `#49834c` | `#6f7142` | `#204139` | Base grass. |
| `turf_shade` | `#346141` | `#4f5536` | `#16312f` | Grass shadow, outfield depth falloff. |
| `clay_main` | `#c17b4f` | `#cb7c51` | `#6d4b45` | Infield dirt, warning track. |
| `clay_lit` | `#dea16c` | `#efa46a` | `#8c6253` | Raked-dirt highlights, mound crown. |
| `chalk_line` | `#f2ead2` | `#ffeac1` | `#cacde0` | Foul lines, batter's boxes, plate. |
| `wall_pad` | `#1e4b45` | `#3e4b3f` | `#102b2d` | Outfield wall padding. |
| `lamp_glow` | `#ffeaae` | `#ffda90` | `#ffe3a2` | Lamp cores and authored stepped halos. |
| `mist_veil` | `#9ec4cc` @ 20% | `#dca47b` @ 26% | `#20365c` @ 34% | Single translucent veil over the far band (§7.8). |
| `vignette_veil` | `#0e1220` @ 10% | `#26182e` @ 16% | `#0b1330` @ 24% | Stepped corner darkening (§7.8). |

Skin, hair, and uniform micro-ramps for characters are defined in §8 and are
mood-invariant by design: characters re-grade only through the world light
around them, so they always read as the constant, human element.

### 3.3 Hue-shift discipline

- Shadow steps shift **cool** (toward the indigo family of `sky_high` night),
  never merely darker.
- Light steps shift **warm** (toward the `lantern_gold` family), never merely
  lighter.
- A material ramp is exactly 3 steps (lit / main / shade) plus `ink` for its
  deepest accent. No 4+ step material ramps in the environment.

### 3.4 Mood statements

- **Day** — brisk maritime morning. High-key, airy, blue-green; crisp cloud
  clusters; lamps unlit (cool metal); crowd bright. The warm pool is clay
  plus the focal player.
- **Golden** — the hero mood. Violet-over-amber sky, amber sea glints, long
  stepped shadows (2:1 horizontal stair) cast from the stands across the
  outfield, lamps warming at half halo.
- **Night** — the Celeste-lesson mood. Indigo world compressed low, a static
  star field, full stepped lamp halos, lit windows across the town, a
  moonlight path on the water. The diamond is a lantern bowl: darkness owns
  most of the frame and every light pool is precious and deliberate.

---

## 4. Value hierarchy and saturation rules

### 4.1 The six-rung value ladder

Every mood maps its bands onto six luminance rungs (approximate relative
luma, 0 = black, 100 = white). Rung assignments are hard: a band may not
straddle rungs.

| Rung | Day | Golden | Night | Owner |
| --- | --- | --- | --- | --- |
| V0 | 5–10 | 5–10 | 3–8 | `ink` accents, silhouettes against light |
| V1 | 15–25 | 12–22 | 6–12 | Stands shell, near skyline, crowd shadow |
| V2 | 28–40 | 22–34 | 10–18 | Field shade, sea far, far skyline |
| V3 | 42–56 | 36–50 | 16–28 | Base turf, clay, sea near |
| V4 | 60–75 | 55–70 | 30–45 | Sky low, clay lit, turf lit, crowd warm |
| V5 | 80–96 | 72–92 | 55–90 | Chalk, lit clouds, ball, lamp glow, UI text |

Rules:

- **The controlled player and the live ball must always contain V5 against a
  V2-or-lower immediate background** — the lantern-against-sea contract.
- Adjacent atmospheric bands sit at least one full rung apart along their
  entire shared seam; depth must survive a grayscale flatten.
- Background bands hold ≤ 2 rungs of internal contrast; midground ≤ 3;
  playfield ≤ 3; characters and the focal system may span the full ladder.
- Night compresses V1–V3 and rations V4–V5 to ≤ 20% of frame area, all of it
  deliberate light (lamps, windows, chalk, ball, focal player).

### 4.2 Saturation rules

- Background bands (sky, sea, skyline): saturation ≤ 45%.
- Midground (stands, wall, crowd masses): ≤ 55%.
- Playfield: ≤ 65%.
- Characters, ball, focal effects, UI accents: up to 100%, and the focal
  subject must be the most saturated warm element on screen.
- Golden raises every cap by +10 points; night lowers background caps by −10
  but raises lamp/window/celebration accents to full.
- Never place two fully saturated complementary hues adjacent at equal
  value — separate them with `ink` or a neutral step.
- Crowd saturation ≤ 45%: the crowd is a texture of people, not confetti.

---

## 5. The 4px cluster grammar

The design grid is 320×180 cells; each cell rasterizes as an exact 4×4
native-pixel block. "Cell" below always means one 4px design cell.

### 5.1 Cluster rules

- **Minimum blob: 2 cells** (2×1 or 1×2). Single isolated cells are allowed
  only on an authored accent list: eye catch-lights, sea glints, stars,
  window lights, ball stitch ticks. Never as texture fill.
- **Organic stamps**: any repeated texture (crowd, wave chop, raked dirt,
  foliage) is built from a hand-authored set of 4–8 cluster stamps placed
  with deterministic jitter (seeded through the existing `pix_rng` patterns),
  never per-cell random color and never a uniform grid repeat.
- **Directional grain**: horizontal drift for sky/sea, vertical stacks for
  masts and towers, diagonal shingles for roofs, contour-following arcs for
  mow bands and clay rakes.
- **Stair discipline**: curves and diagonals use monotonic stair runs with
  lengths from {1, 2, 3}; a run length repeats at most twice before it must
  change.
- **Drip-and-drift seams**: horizontal band seams undulate ±1–2 cells with
  cluster overhangs every 6–14 cells. A mathematically straight seam longer
  than 24 cells is forbidden — except chalk lines, rooflines, and UI frames,
  which are deliberately straight.

### 5.2 Edge rules

- World shapes are **value edges first**: a shape must read against its
  background by ≥ 1 rung before any outline is considered. Environment
  shapes never take black outlines; the only permitted environment edge
  accent is a 1-cell "rim step" of the shape's own ramp, one step lighter on
  the lit side.
- Characters at Marquee and Battery LOD carry a full 1-cell `ink` contour;
  Diamond LOD carries `ink` under the cap and feet only and otherwise reads
  by silhouette value.
- Chalk marks crossing clay take a 1-cell `turf_shade`/`clay_main` seat on
  their shadow side so chalk never halates into the field.
- No 2-cell-thick outlines anywhere in world art.

### 5.3 Dithering rules

- Allowed patterns: **2×1 alternating checker only**, using exactly two
  adjacent ramp colors, maximum 3 cells deep.
- Allowed locations only: sky_high→sky_low seam, sea_far→sea_near seam,
  turf_shade falloff, lamp-halo ring seams, night fog lapping the
  breakwater.
- Forbidden on: characters, UI, chalk, clay, crowd, the ball, any focal
  element, and any surface smaller than 12×6 cells.

### 5.4 Forbidden marks (hard fails in review)

1. Per-cell uniform random noise fields (the baseline crowd).
2. Alpha-gradient fills, radial gradients, soft shadows, engine draw
   antialiasing.
3. Positioning outside the 4-native-pixel dense design grid.
4. Pure `#000000` or `#ffffff` outside the `ink`/`ball_white` definitions.
5. Black outlines around environment shapes; outline-everything cartooning.
6. Exact-tile repetition visible at native zoom (crowd, seats, water).
7. Unbroken single-color regions larger than 40×20 cells (the baseline
   outfield wedge is the canonical example) — break with mow bands, shadow
   drift, or cluster texture.
8. More than one warm focal pool per screen (Pillar 1).
9. Photo/AI raster textures, 3D nodes, filtered shader pixelation, or any
   compositor other than the single authorized world grade (contract).

---

## 6. View-by-view composition

All five views render through `world/pixel_ballpark_canvas.gd` view modes
with `presentation/broadcast_camera.gd` framing. Coordinates are design-grid
(320×180) staging targets, ±4 cells, arranged around the existing functional
anchors; camera and sim mapping contracts are unchanged.

### 6.1 `intro` (title / shell backdrop)

- Wide postcard of the whole wharf park. Horizon at y=58. Five horizons all
  present: sky (0–58), harbor water + skyline (58–86), grandstand ring
  (86–118), field (118–166), and a foreground dugout-roof `ink` band
  (166–180) anchoring the bottom.
- Focal: the central lightbank tower at (208, 44)–(224, 96), lamps lit in
  all moods — the single warm pool. Shell UI floats over the left 45%
  (§10.6); the harbor stays visible on the right.
- A ferry with lit windows crosses `sea_near` on a slow loop; two gulls hold
  station above the stands; the lighthouse at x≈296 sweeps its beam every
  6 s in golden/night. Nothing animates faster than 1 step/second.

### 6.2 `pitching`

- The camera is a tight center-field television angle looking inward toward
  home plate, with the pronounced horizontal offset associated with the
  Citizens Bank Park feed. The plate sits near (160, 92) while the pitcher and
  mound sit camera-left near (138, 141); that diagonal is the core
  pitch-movement stage. The batter remains fully outside the zone to
  camera-left.
- This crop shows only the plate cutout, uninterrupted grass flight corridor,
  and foreground mound. First, second, and third base are outside the frame.
  Never draw a full base-path diamond in the pitching view: it reads as a UI
  diagram and collapses the telephoto depth.
- The Liberty Bell, scoreboard, harbor, and outfield skyline are behind the
  camera and never appear in this view. The upper frame is the plate-facing
  Diamond Club: recessed club glass behind an irregular brick belt, three
  separately raked premium seating rooms, broad masonry wings/piers, stepped
  brick portals, wall padding, and a wide low protective net. Brick is the
  structural shell around openings, never a full-frame repeating wallpaper.
  Club/stands occupy y=0–82 and field y=82–180.
- Focal: the pitcher, rim-lit `clay_lit`→`lantern_gold` against
  `turf_shade`. The strike zone is the secondary beacon in `chalk_line` with
  a `signal_teal` aim reticle — cool, so it never fights the pitcher.
- Field contour: long horizontal mow passes, isolated mound and plate clay
  islands, and uninterrupted grass between them. No checker tiles,
  concentric/radial mowing, base bags, or clay base paths in this view.
- Pitch flight: the ball leaves the visible hand above the mound and crosses
  the open diagonal corridor before the zone. Three authored trail marks
  (spark / dash / tail) are sampled from the real semantic trajectory; no
  enlarged dotted chain or continuous ribbon may substitute for camera depth.
- Batter, catcher, umpire cluster at the zone in Battery LOD at staggered
  depths.

### 6.3 `batting`

- Mirror weight: batter large at lower-left (feet ≈ (96, 150)); pitcher
  small and cool at ≈ (196, 84); strike zone floats center-right (176, 96).
- Horizon at y=42 — this camera faces the sea: breakwater, moored trawler,
  and lighthouse visible above the center-field wall. The lighthouse lamp
  stays quiet (`lamp_glow`); the ball owns the focal warm once in flight;
  before the pitch, the batter's bat highlight is the screen's brightest
  warm mark.
- Crowd frames both upper corners but thins toward center so the pitch
  corridor stays visually quiet (≤ 2 rungs of internal contrast along the
  corridor).
- Catcher and umpire crouch behind the batter as V1 silhouettes with `ink`
  contours and single mask glints.

### 6.4 `fielding`

- High harbor-balcony camera. Field owns y=60–170; sky+sea compress to
  0–60 but the skyline stays visible — never a full-green frame.
- All fielders and runners in Diamond LOD; the controlled fielder carries a
  4-cell `lantern_gold` focus ring (1 cell thick, stepped). Runners carry
  `lantern_gold` cap ticks.
- Focal: the live ball with its stepped trail (§9.2); while the ball is
  live, everything else drops one saturation band.
- Outfield depth: three mow-band arcs plus `turf_shade` falloff toward the
  wall; warning track `clay_main` 3 cells deep; wall `wall_pad` with
  distance signage in `chalk_line`. Bases, foul lines, and cutout arcs must
  be complete and unbroken — the landmark check happens at this view first.

### 6.5 `dugout`

- Interior close shot. Dugout roof beam crosses y=28–36 as an
  `ink`+`stand_shell` frame; bench players at Marquee LOD sit y=96–150;
  through the dugout opening (x=180–300, y=40–92) the field, stands, and
  harbor read as a bright framed postcard — the warm pool is *outside*,
  longing to play.
- Props: bat rack, rosin bags, water pail, hanging pennant of the active
  team, one wall-mounted `lamp_glow` cage lamp at (56, 44).

---

## 7. Environment language

### 7.1 Harbor architecture

Buildings are stacked plank-and-brick wharf structures: narrow (8–16 cells),
tall gabled roofs, chimneys, hoist beams, rope lines with hanging floats.
Authored as 6 reusable silhouette stamps in two depth tints (`town_far`,
`town_near`) with `roof_accent` and `window_lit` notes. Recurring vocabulary:
gabled cannery with roof monitor and steam stack, fish-shed rows, a gantry
crane, stacked lobster traps, an irregular mast forest, a stone breakwater
with a foam seam, and the lighthouse (round, banded, lamp room) at the right
skyline edge.

### 7.2 Skyline

Two overlapping silhouette rows: the far row (V2) is pure shape — cranes,
masts, gable teeth, low hills behind everything; the near row (V1) adds
interior detail only via lit windows and roof accents. Mast rigging is
single-cell lines with 1–3 stair runs. The skyline dips lowest behind the
pitcher in the pitching view so the focal character reads against water, not
roofline clutter.

### 7.3 Seating and stands

A shallow two-deck timber-and-brick ring, not bleacher stripes: `stand_shell`
structure with a visible post rhythm every 10 cells, `seat_board` rows on a
2-cell vertical rhythm, brick base courses (`roof_accent` family) every 3
rows, an `ink` shadow under each deck lip, aisle cuts every 9–13 columns
(irregular), and bunting swags (`stitch_red`/`chalk_paper`/`signal_teal`)
every 24 cells along the facade in all moods. A **harbor bell tower** rises
above the left facade at (72, 88) — the stadium landmark (§9.6) — and the
LED reaction board sits center facade.

### 7.4 Field

- Mow bands: alternating `turf_lit`/`turf_main`; the pitching view uses broad
  horizontal passes while the other field views may use 6–9-cell perspective
  arcs. Checker tiles and radial/ripple patterns are forbidden around the mound.
- Infield: `clay_main` paths with `clay_lit` rake marks (2-cell dash clusters),
  `chalk_line` foul lines, batter's boxes, and a proper 5-sided plate. The
  pitching view may enlarge the plate to an 11×6-cell readability cluster.
- Mound: 10-cell `clay_lit` crown with an `ink` shade crescent and a
  `chalk_line` rubber.
- Bases: 2×2 `ball_white` diamonds with 1-cell `ink` ground-contact shade.
- Golden mood: stepped long shadows from the stands cross the outfield;
  night: the pitching view lifts the same field-wide horizontal mow passes by
  one value rung, never adding a circular or trapezoidal pool over the pitch
  lane. Other views may use authored elliptical lamp pools with 2-cell stairs.

### 7.5 Crowd

Crowd = clustered masses, never noise. Build from 8 authored clump stamps
(3–6 cells each: two heads and shoulders, a standing fan, a flag waver, a
child on shoulders…) in `crowd_cool` bodies with sparse `crowd_warm` face
clusters — at most 1 warm cluster per 5 clumps in day, per 3 at golden, per
8 at night. Occupancy 55–80% with visible empty `seat_board` gaps; clump
row-runs of 2–5 with irregular gaps, deterministic per seed. Density thins
with distance; the top deck is silhouette-only clumps against sky. The
aggregate crowd silhouette undulates per §5.1. Scarves/flags in muted team
hues at ≤ 1 per 40 spectators.

### 7.6 Lighting

Light is authored, stepped, and diegetic: lamp towers (4 heads lit at
golden, 6 at night, unlit cool metal by day), cage lamps, window grids, the
lighthouse. Halos are concentric stepped rings — 2 rings day/golden, 3 at
night — with §5.3 dither permitted at ring seams, never radial gradients.
`window_lit` density across the skyline: ≈ 8 windows day, ≈ 30 golden, ≈ 70
night.

### 7.7 Weather

One sparse deterministic weather note per mood: day — 3 drifting cumulus
clusters, 2 gull pairs, a cannery steam loop; golden — steam re-grades to
`cloud_shade`, stand shadows extend, a slow 1-cell leaf drift (≤ 12
particles); night — static stars (≤ 40 single cells), one blinking buoy
light, fog lapping the breakwater. No rain or snow systems in scope.

### 7.8 Atmospheric layers

Exactly one `mist_veil` rect over the far band (skyline+sea) per mood and
one stepped `vignette_veil` corner treatment per screen are the only authored
translucent geometry. The world grade may add opaque hard-step rim, emissive,
posterization, vignette, and mote results at the native dense grid. Far-layer
colors may alternatively be pre-blended toward the veil at palette-build time;
no smooth alpha ramp is allowed.

---

## 8. Character language ("Pocket Giants")

Implemented in `characters/pixel_actor_sprite.gd` and
`characters/ballplayer_actor.gd`. Three fixed LODs, all on the 4px grid.

### 8.1 Proportions

| LOD | Cell size (w×h) | Head share | Used in |
| --- | --- | --- | --- |
| **Marquee** | 28×40 | head 16 cells (40%) | dugout bench, shell portraits, final-screen heroes |
| **Battery** | 14×22 | head 9 cells | pitcher, batter, catcher, umpire in pitching/batting views |
| **Diamond** | 7×11 | head 5 cells | fielders, runners, base coaches in fielding view |

Heads are round-cornered rectangles; bodies taper; necks do not exist.
Hands, mitts, and shoes are oversized masses (+30% versus naturalistic) so
poses read at distance; limbs are 1–2-cell ribbons.

### 8.2 Face grammar

- **Marquee**: 2×3-cell `ink` eyes with a 1-cell `ball_white` catch-light,
  2-cell brows (the primary emotion channel), 1–3-cell mouth states, an
  optional 1-cell `clay_lit` blush/dirt smudge, and a 1-cell cap-brim shadow
  band across the brow line.
- **Battery**: 2×2 eyes, 1-cell brows, 1–2-cell mouth; the face uses at most
  4 colors (skin, `ink`, `ball_white`, one accent).
- **Diamond**: a single 1-cell eye mark at most — all expression moves to
  posture (§8.5).

Skin tones: a 4-ramp roster set `#8a4b32` / `#b06e44` / `#d29061` /
`#ecb98a`, each with its own cool-shifted shade step, distributed across
generated rosters by the existing content seed. Hair: 6 two-color ramps
(black, brown, auburn, blond, gray, teal-dyed).

### 8.3 Role silhouettes

Every role must be identifiable from silhouette alone, in grayscale, at its
gameplay LOD:

- **Pitcher** — forward-tilted cap, glove held chest-high making an L-notch,
  drive leg one cell thicker.
- **Catcher** — squat trapezoid: chest protector adds 2 cells of torso
  width, helmet+mask grill (2-cell grid), the game's largest mitt (3-cell
  mass) breaking the contour, shin-guard steps on both legs.
- **Batter** — helmet with an ear-flap bump; the bat diagonal always breaks
  the silhouette (1×8 cells at Battery LOD) with one `lantern_gold`
  highlight cell; elbow-up coil.
- **Infielder** — knees-bent ready diamond, glove low, glove-side arm one
  cell longer.
- **Outfielder** — upright, feet wider, cap not helmet.
- **Umpire** — all-`ink` mass with a `steel_text` chest pad, wide low
  stance, no team trim.
- **Runner** — forward lean ≥ 2 cells off vertical, `lantern_gold` cap tick.

### 8.4 Uniforms and equipment

Uniform = base cloth (`chalk_paper` home, `steel_text` road) + one team trim
family on cap, chest band, and sock: Harbor Foxes = `stitch_red` family,
Pier Lights = `signal_teal` family. Numbers in `ink` at Marquee LOD only.
Team logos are 2×2-cell abstract marks (fox-head notch, pier-light dot) —
never letters at Battery LOD or below. Equipment: bat `#a5713f` wood with a
`#c99457` grain dash and 1-cell sheen; gloves/mitts `clay_main`/`clay_lit`
leather; helmets team trim + `ink`; catcher gear `stand_shell` with
`steel_text` bars.

### 8.5 Action exaggeration

Squash-and-stretch on the 4px grid, 3-pose keys (anticipation / action /
settle), all motion landing on whole cells and whole ticks — no tweened
sub-cell motion:

- **Pitch**: wind-up compresses to 90% height (2 ticks); drive stretches to
  115% with a 3-cell stride and a 1-tick 2-cluster arm-arc smear in authored
  opaque colors (1 frame only); release snaps back with a cap-brim pop
  (2 ticks).
- **Swing**: load twists shoulders 2 cells back; the contact frame stretches
  bat + arms into a single 12-cell diagonal with a 3-cluster arc smear
  (1 frame); follow-through wraps the bat behind the head and holds 2 ticks
  longer than anatomically real.
- **Catch**: the mitt doubles (2×2 → 3×3 cells) on the reception frame only.
- **Sprint** (Diamond LOD): 2-frame gallop with a 1-cell vertical bob and a
  lean.

### 8.6 Expression mapping

Drives Marquee/Battery faces and Diamond posture:

| Game state | Brows | Mouth | Body |
| --- | --- | --- | --- |
| Ready/neutral | flat | 1-cell line | square stance |
| Focus (sign/aim) | inner-down 1 cell | dot | 1-cell forward lean |
| Strike thrown / good play | up | 2-cell grin | chest up 1 cell |
| Ball / miss | inner-up | 1-cell frown | head drop 1 cell |
| Strikeout victim / error | inner-up | open 2×1 | shoulders squash 2 cells |
| Home run hero | up | open 2×2 grin | full 115% stretch jump, arms up 2 frames |
| Home run allowed | flat low | 1-cell frown | head drop, shoulders −1 cell |
| Gassed pitcher | flat low | wavy 2-cell | 1-cell slump + one `sea_glint` sweat cell |

---

## 9. Effects language

Owned by `presentation/pixel_ball_sprite.gd`,
`presentation/baseball_visual.gd`, and the reaction system in
`world/pixel_ballpark_canvas.gd`. All effects are opaque authored clusters
on whole cells. "Fade" always means stepping through authored colors toward
the local background color, never alpha ramps.

### 9.1 Baseball

Battery LOD: 2×2-cell `ball_white` core + 1 `ink` lower-right shade cell +
1 `stitch_red` stitch tick alternating sides every 2 ticks (spin read).
Diamond LOD: a single `ball_white` cell with a 1-cell `ink` ground shadow
that separates from the ball with height (always rendered). Night adds a
1-ring `lamp_glow` halo when the ball is above wall height.

### 9.2 Trail

Three opaque afterimage cells at 3/6/9 cells behind the flight path, colored
with pre-mixed steps toward the local background (`sea_glint` family over
sky, `turf_lit` family over grass). Trail length codes effort: 1 ghost soft
toss, 3 ghosts max effort; fast pitches tighten spacing to 2/4/6. Breaking
balls bend the ghost chain along the actual deterministic path. The trail is
the only motion cue — no ribbons, no continuous lines, no blur.

### 9.3 Contact burst

6-tick starburst at bat-ball contact: ticks 1–2 a 3×3 `lantern_gold`
diamond; ticks 3–4 four 2-cell `chalk_paper` rays; ticks 5–6 ray tips only,
stepped to background. Perfect-timing contact upgrades rays to 3 cells and
adds a 1-tick full-`ball_white` ball flash. Weak contact drops the ray
phase. Never a screen flash.

### 9.4 Dust

Slide/landing dust: 3 clay-family cluster puffs (2–4 cells each) that hop
1 cell up-and-out over 4 ticks, then step to `turf_shade` and vanish. Mound
rosin puff: a single 2-cell `chalk_line` puff on release, 3 ticks. Mound
scuffs persist for the half-inning as 1–2-cell `clay_main`-shade marks
(max 5).

### 9.5 Crowd reactions

The existing `CROWD_REACTIONS` timing table is preserved. Strength maps to
cluster motion, never color noise: clump stamps swap to 1-cell-raised
"arms up" variants in a traveling wave (strength = wave count), amplitude
≤ 1 cell, ≤ 8 Hz; sparse `lantern_gold` phone-light cells at night (≤ 12);
team-trim flag clusters extend 2 cells on big plays; at strength ≥ 0.7,
2×1-cell cap-toss clusters arc overhead (≤ 8 alive). The LED board shows the
reaction word in `lantern_gold` on `ink`.

### 9.6 Harbor bell

The home-run bell is diegetic: the bell tower at (72, 88) rocks 1 cell
left/right per 4 ticks with stepped `lamp_glow` arc rings radiating (one
ring per rock, max 3 alive), and gulls scatter from the roofline once. At
night the floodlights pulse +1 value step for 2 ticks.

### 9.7 Celebration

Home-run/walk-off sequence inside the reaction table's 3.2 s budget: bell
(§9.6) + full-strength crowd wave + two streamer clusters (team-trim
authored 6-cell ribbons, ≤ 8 alive) drifting from the upper deck + every
`window_lit` cell in the skyline pulsing one value step on a 12-tick cycle.
Walk-off/final adds stepped 8-spoke firework clusters above the skyline
(team trim + `lamp_glow`, 4 ticks each, ≤ 2 simultaneous). No confetti rain,
no particle spam, no full-screen tint.

---

## 10. UI language ("Painted Signage")

Owned by `ui/pixiball_hud.gd`, `ui/pixiball_style.gd`,
`ui/pixiball_pixel_overlay.gd`, `ui/strike_zone.gd`, and `ui/pitch_intel/*`.
All Controls in native 1440p coordinates; all fonts render at native size.

### 10.1 Materials

Every panel declares exactly one material identity:

- **Enamel lightboard** (scoreline, count, outs, LED): `ink` face, `#1b2138`
  raised bezel, `lantern_gold` numerals, rivet cells in the corners.
- **Painted plank** (matchup cards, roster/select cards, dugout menus):
  `#2c3a55` board fill with 1-cell wood-grain dashes `#374763`,
  `chalk_paper` lettering, a team-trim edge stripe.
- **Pennant tab** (pitch selector, tabs): triangle-tail flags in team trim
  with `ink` outline; the focused pennant hoists 4 native px.
- **Chalk rail** (help line, hints): an `ink` rail strip with hand-chalk
  `chalk_paper` text and a chalk-dust tick before each verb.
- **Slate board** (Pitch Intel, stats): `#1a2233` slate, `chalk_paper` chalk
  diagrams, `signal_teal`/`lantern_gold` chalk accents, an eraser-smudge
  corner.

The baseline's cyan debug border is dead everywhere.

### 10.2 Typography (native sizes only)

| Tier | Font file | Sizes (px) | Usage |
| --- | --- | --- | --- |
| Display | `assets/fonts/geist_pixel/GeistPixel-Square.ttf` | 48 | Title sign, final score |
| Header | `assets/fonts/unreal_ui/PixelifySans-Regular.ttf` | 32 / 24 | Panel titles, team names, buttons, situation text |
| Numerals | `assets/fonts/unreal_ui/VT323-Regular.ttf` | 40 / 28 | Score, count, speed — every lightboard digit |
| Body | `assets/fonts/unreal_ui/DotGothic16-Regular.ttf` | 20 / 16 | Help, Pitch Intel copy, stat lines |

16 px is the absolute text floor, and 16-px text is never gameplay-critical.
Tracking via `PixiballStyle.tracked(+8)` at 48/40 sizes only. No scaled text
textures, no faux bold/italic. Text colors: `chalk_paper` primary,
`steel_text` secondary, team trim for identity, `lantern_gold` reserved for
the focused/live element and score digits, `stitch_red` for outs/danger.

### 10.3 Framing and spacing

- Chrome widths keep the `ui/pixiball_style.gd` constants: panel border 12,
  thin frame 8, hard offset shadows 8/16/24 down-right in `ink`. Square
  corners, no antialiasing.
- Global rhythm: all margins, paddings, and gaps are multiples of **8 native
  px** (16 default gutter, 24 between sibling panels); every UI x/y/size is
  a multiple of 4.
- Safe frame: 24 px from every screen edge. The top lightboard strip is
  exactly 56 px tall and the bottom chalk rail 40 px; these two strips are
  the only full-bleed elements.
- Panels never touch each other: minimum 8 px of world visible between
  siblings — the world is the hero (Pillar 1).
- Passive panels may use 12-px corner-tick L-marks instead of a full frame;
  a full frame means interactive.

### 10.4 State and focus language

| State | Treatment |
| --- | --- |
| Rest | material base, `chalk_paper`/`steel_text` text |
| Focused | `lantern_gold` 4-px corner ticks (not a full border), panel raises 4 px (shadow grows 4 px), text steps to `chalk_paper` |
| Active/confirmed | `lantern_gold` full frame for 6 ticks, then rest with a badge |
| Disabled | fill steps toward `ink`, text `slate_text`, no shadow |
| Danger/out | `stitch_red` frame + chalk-rail verb; never a full red fill |

Exactly one focused element per screen. Focus moves are instant (≤ 100 ms,
no easing curves) with a 1-tick `lantern_gold` tick flash at the
destination. Every state change pairs a hue change with a value or shape
change (grayscale-safe).

### 10.5 Gameplay HUD specifics

- **Scoreline** (top lightboard): away/home abbreviations + VT323 runs,
  inning ordinal with an up/down chevron cell, count as pips — balls are
  round `ball_white` filled / `slate_text` hollow, strikes are square —
  outs as three lamp cells lighting `stitch_red`, situation text
  right-aligned in Header 24 team trim. Baserunner diamond: a 28-px rotated
  square cluster; occupied bases fill `lantern_gold`.
- **Strike zone** (`ui/strike_zone.gd`): a thin continuous `chalk_paper` rail
  in an `ink` seat + a persistent 3×3 dashed `steel_text` interior grid,
  `signal_teal` aim reticle, and called-strike cells flashing
  `lantern_gold`. Plate actors stay outside or below its perimeter so the
  guide never becomes a cage over the batter. The pitch-trajectory preview is
  stepped `chalk_line` segments — the baseline's opaque brown ribbons are dead.
- **Pitch selector**: five pennant tabs keyed to the existing `PITCH_SLOTS`
  hues, number + pitch code in Numerals 28; the focused pennant hoists,
  unfocused tabs dim to `steel_text`.
- **Chalk rail** (bottom): verbs in Body 20 with chalk-dust ticks
  (`1–5 SELECT · WASD AIM · SPACE THROW`).

### 10.6 Menus (landing, pitcher/team select, final)

Shell screens sit over the `intro` world view (§6.1), re-graded per mood.
Cards are painted planks on the left 45% of the screen; the harbor stays
visible right. Portraits use Marquee-LOD character heads on plank chips with
team-trim rims. The title logotype is a built sign: Display 48 on an enamel
board with two cage lamps and rope suspension from the top frame. The final
screen sets Display-tier score over the night panorama with §9.7
celebration if the player won.

### 10.7 Pitch Intel

A slate board (§10.1) with a Header 24 title, Body 20 copy, and a diagram
pane: zone grid in 2-px `steel_text` chalk lines, pitch locations as 8-px
cluster dots in the pitch-slot accents, break paths as stepped cells along
the deterministic break (never smooth curves), grip dots, tunnel overlay in
`signal_teal`, and confidence as chalk tally marks. The recommended target
carries the `lantern_gold` focal treatment — and therefore the Intel panel
may only be open when it is the screen's focal system.

---

## 11. Legibility and accessibility constraints

1. Text contrast ≥ 4.5:1 against its own panel fill in all three moods;
   `chalk_paper` on every §10.1 material must pass; `slate_text` is
   decorative only. Gameplay-critical text never renders over unpaneled
   world art.
2. Ball, strike zone, controlled player, bases, plate, foul lines: each ≥ 2
   value rungs off its immediate background in all moods (the night lamp
   pools guarantee this at night).
3. Meaning is never hue-only: balls/strikes differ by pip shape
   (round/square), outs by lamp position, grades pair letter + color, pitch
   slots pair number + color, and every UI state change carries a value or
   shape change.
4. Red/green pairs (`stitch_red`/`good_green`) never appear as adjacent
   same-value fills; separate by rung or `ink`.
5. Motion caps: crowd shimmer ≤ 1 cell displacement at ≤ 8 Hz; no
   full-screen flashes; nothing blinks faster than 3 Hz; light pulses are
   ≤ +1 value step for ≤ 2 ticks.
6. Focus is always visible: `lantern_gold` corner ticks must survive the
   night mood (verify on night captures).
7. Minimum interactive/readable element: 32 native px; minimum text 16 px.
8. All animation is tick-quantized: the game must be fully readable in any
   single paused frame. Every acceptance test below is a still image.
9. First-time-viewer rule: plate, mound, bases, foul lines, zone, ball,
   controlled player, and score/count/outs each locatable within one second
   in every mood — reviewed against captures.

---

## 12. Screenshot acceptance checklists

Every implementation pass captures receipts with
`tools/capture_visual_rebuild.gd` (GPU-backed, no `--headless`) and reviews
them with the `Read` tool at 100% zoom **and** mentally flattened to
grayscale. A pass is not done until its checklist passes in all three moods
for its owned screens.

### 12.1 Palette and mood core

- [ ] All world colors resolve through `MOOD_PALETTES` roles and the §3.1
      identity roles; zero stray hex literals in view files.
- [ ] Grayscale key per mood matches §3.4: day high-key, golden mid-key,
      night low-key with rationed light.
- [ ] Exactly one warm focal pool per capture (Pillar 1 audit).

### 12.2 Sky / sea / skyline

- [ ] Five horizon bands present, each on its own value rung; seams undulate
      with cluster overhangs; no straight seam > 24 cells.
- [ ] ≥ 2 cloud masses with lit/shade structure; water shows directional
      cluster grain and sparse glints; no visible tiling.
- [ ] Far/mid skyline separates in grayscale; lighthouse at the right edge;
      mist veil deepens with distance.
- [ ] Night: ≤ 40 single-cell stars, moon path on water, ≈ 70 lit windows.
- [ ] Dithering only at permitted seams, ≤ 3 cells deep.

### 12.3 Stands / crowd / architecture

- [ ] Crowd is clump-stamped with visible empty seats; zero per-cell
      confetti noise at 100% zoom.
- [ ] Warm face clusters obey mood density ratios (§7.5).
- [ ] Decks show post rhythm, brick courses, aisles, deck-lip ink shadow,
      and bunting; the stands never form one unbroken wall.
- [ ] Bell tower and LED board present and legible; lamp states correct per
      mood.

### 12.4 Field

- [ ] Concentric mow bands centered on home plate; no unbroken single-color
      region > 40×20 cells.
- [ ] Plate, foul lines, batter's boxes, bases, mound rubber, warning track
      all present and ≥ 2 rungs off backdrop in all moods.
- [ ] Rake-mark clusters follow the infield arc; chalk takes its shadow-side
      seat.
- [ ] Golden: stepped stand shadows across the outfield. Night: authored
      elliptical lamp pools with stair edges.

### 12.5 Characters

- [ ] Every role identifiable from silhouette alone, in grayscale, at its
      gameplay LOD (§8.3).
- [ ] Marquee/Battery carry full 1-cell ink contours; controlled player
      contains V5 against ≤ V2 backdrop.
- [ ] Faces follow LOD grammar; Diamond LOD carries no facial features.
- [ ] Captured expression matches the game state per §8.6.
- [ ] Team trim on cap + chest + sock; home/road cloth correct; smears are
      1-frame authored clusters, never blur.

### 12.6 Ball and effects

- [ ] Ball contains `ball_white` V5 and reads in all moods; night halo only
      above wall height; ground shadow separates with height.
- [ ] Trail is ≤ 3 opaque stepped afterimages, speed-coded; no continuous
      line.
- [ ] Contact burst ≤ 6 ticks with no screen flash; dust steps to
      background; scuffs cap at 5.
- [ ] Celebration: bell rocks with ≤ 3 rings, ≤ 8 streamers, ≤ 12 phone
      lights, ≤ 2 fireworks; no confetti rain.

### 12.7 Gameplay HUD

- [ ] Every panel has a §10.1 material identity; the cyan debug border is
      gone; nothing reads as an engine overlay.
- [ ] Count pips shaped round/square, outs as lamps, VT323 digits
      `lantern_gold`; baserunner diamond fills correctly.
- [ ] One focused element; gold corner ticks visible on the night capture.
- [ ] All spacing on the 8-px rhythm; safe frame respected; ≥ 8 px of world
      between sibling panels.
- [ ] All text ≥ 16 px at ≥ 4.5:1 contrast; trajectory preview is stepped
      chalk, not ribbons.

### 12.8 Menus / shell

- [ ] Intro composition per §6.1 with the lit lightbank as the sole warm
      focal; ferry, gulls, lighthouse present.
- [ ] Title reads as a rope-hung enamel sign with cage lamps.
- [ ] Cards are painted planks left; harbor visible right; Marquee portraits
      on plank chips.
- [ ] Focus/active/disabled states match §10.4 and survive grayscale.

### 12.9 Pitch Intel

- [ ] Slate material with chalk-diagram language; break paths stepped, not
      smooth; grip dots and tally marks legible.
- [ ] Tunnel overlay `signal_teal`; recommended target is the screen's only
      `lantern_gold` focal while open.
- [ ] Panel fits the safe frame and does not cover the pitcher.

### 12.10 Mood unification (final gate)

- [ ] All 5 views × 3 moods captured at native 2560×1440.
- [ ] Night captures: V4–V5 area ≤ 20% of frame, all deliberate light.
- [ ] Side-by-side with the baseline
      (`.godot/visual-qa/native-1440/game-pitching-day.png`) shows a
      transformed, original game; side-by-side with
      the [official Celeste reference](https://www.celestegame.com/images/screenshots/p00.png) shows kinship in
      method and zero copied content.
- [ ] `core/tests/test_native_720_pipeline.gd`,
      `core/tests/test_scene_composition.gd`,
      `core/tests/test_display_pipeline.gd`, and
      `ui/tests/test_native_2d_layout.gd` all pass.
