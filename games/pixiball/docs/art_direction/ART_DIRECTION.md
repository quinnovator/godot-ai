# Pixiball visual direction

Pixiball renders directly into one native `2560x1440` root framebuffer. World,
athletes, ball, effects, and HUD are intentional CanvasItem clusters authored
on a `640x360` dense design grid whose unit is exactly one `4x4` framebuffer
block. Existing `320x180` composition landmarks receive an exact 2x density
transform before `PixelScene` applies its direct 4x CanvasItem transform. No
design grid is an image, texture, viewport, or intermediate framebuffer. One
world-only compositor samples that native grid with nearest taps before the HUD
to add stepped rim light, emissive fringes, posterized values, and atmosphere;
it does not resize or blur the scene.

The target is an original harbor-league world with clear action silhouettes,
expressive color, layered environmental storytelling, and dense material detail
at the full design grid. The renderer takes process cues from the
[Animal Well developer rendering breakdown](https://blog.playstation.com/2022/07/20/how-animal-well-taps-into-ps5-hardware-to-elevate-2d-pixel-art-platforming/):
layered compositing, hard value thresholds, local rim light, reflections/glow,
and dense authored pixels, while retaining Pixiball's own baseball setting and
models. Reference PNGs in `references/` guide
composition and readability; they are not atlas-ready source art and must not
be traced into runtime assets.

## Hard runtime contract

- Capture and review the exact `2560x1440` framebuffer. Author graphics in
  `640x360` design units, with every unit landing on the 4 px framebuffer grid.
  Composition may retain the shared `320x180` landmarks through the exact 2x
  density transform.
- Use the Compatibility renderer only as the CanvasItem backend. Do not add a
  spatial scene, `SubViewport`, offscreen low-resolution texture, dynamic
  surface lighting, anti-aliasing, or framebuffer filter. Exactly one
  `WorldCompositeLayer/WorldGrade` shader is authorized below the native HUD.
  Its taps remain locked to the 4 px design grid.
- Build with flat rectangles, lines, stepped ellipses, and deliberate clusters.
  Avoid smooth gradients, subpixel motion, fractional alpha, and uniform noise
  spread across the frame. Material marks must form deterministic clusters.
- Cap each accepted generated frame at 32 opaque colors. Character ramps use at
  most four tones, including outline and shadow.
- Share the navy-ink, sea-teal, verdigris, coral/brick, mustard, and cream value
  family. Team colors vary inside that hierarchy rather than replacing it.

[`style_contract.json`](../../content/pixel/style_contract.json) is the
machine-readable authority for these limits.

## Simulation-to-pixel seam

Gameplay retains finite `Vector3` baseball positions because lateral movement,
height, and field depth are useful simulation data. `broadcast_camera.gd` is a
deterministic projector: it maps those values to integer `Vector2` pixels,
visibility, depth order, and actor LOD. Simulation coordinates never become
presentation geometry.

There are five fixed compositions: intro, pitching, batting, fielding, and
dugout. Each is authored independently rather than derived from a free camera.
Pitching and batting also own fixed logical strike-zone rectangles. A visual
change must preserve projection determinism and the gameplay geometry beneath
it.

## Character construction

- Design the silhouette at its final size: 34/20/15 design units for
  hero/midground/field actors, producing exactly 136/80/60 native framebuffer
  pixels on the 4 px grid.
- Prefer a broad head/cap cluster, compact torso block, strong foot plant, and
  readable limb direction. Remove fingers, facial modeling, seams, folds, and
  anatomy that cannot survive as a stable two-pixel decision.
- Make the action read before identity. Pitch release, swing path, catch reach,
  throw follow-through, run stride, slide line, and celebration shape must be
  distinguishable in a one-color silhouette.
- Animate as pose-authored stepped frames at 10 fps. The ten runtime actions are
  `idle`, `run`, `pitch`, `swing`, `catch`, `field_ready`, `field_throw`,
  `throw`, `celebrate`, and `slide`.
- Preserve semantic timing markers and simulation sockets even when the visible
  body is simplified. Ball release, bat contact, glove contact, celebration
  peak, and base contact remain gameplay contracts.
- Express role equipment as logical layers with marks at least two design units
  (8 native pixels) wide: helmet and bat for the batter, glove for field roles,
  compact catcher gear, and an umpire mask. Equipment should change the
  silhouette, not add texture.
- Keep team palette, skin/hair variation, mark, number, handedness, and facing
  deterministic. Text and identity marks must remain readable when the action
  faces the opposite direction.

Large, small, and tiny presenters are separately authored reductions. Do not
downsample the hero actor to create field LOD; redraw the minimum silhouette
needed by that view.

## World construction

- Divide the image into four depth bands: sky, harbor skyline/water, stadium
  structure/crowd, and playable field. Each band has a distinct contrast range;
  the playable ball and athletes win every overlap.
- Reserve large quiet color fields around pitch release, the strike zone, ball
  flight, scoreboard text, and selection focus. Environmental density belongs
  at the frame edges and behind low-priority play space.
- Build repeatable detail on an 8x8 design-unit cluster grid, which occupies
  32x32 pixels in the native framebuffer. Break repetition with authored aisles,
  rails, bunting, boats, cranes, piers, signs, and skyline landmarks.
- Crowds are deterministic clusters whose count and motion are authored per
  fixed view. Reactions may vary by outcome and phase, but must remain stepped,
  bounded, and readable as a group.
- Day is clear and buoyant, golden is warm and compressed, and night is cool
  with small motivated lamp pixels. Mood changes swap flat palette decisions;
  they do not introduce continuous illumination.

## Ball, effects, and UI

- The baseball is a one- to three-design-unit focal mark (4-12 native pixels)
  with a compact grid-aligned shadow. Use at most five stored pitch-trail
  samples and two live-play samples.
- Effects are brief geometric events: stepped trails, square contact sparks,
  compact flashes, LED changes, and clustered bursts. They must not obscure the
  ball or strike zone.
- The HUD shares the native root framebuffer. Text, focus rails, strike-zone
  lines, and icons follow the 4 px grid and remain crisp in all three moods.

## Live receipts

Native framebuffer captures for all five views × three moods live under
[`receipts/`](receipts/). Prefer those over older `after/` or `final/` images
when reviewing world art.

## Generated-art acceptance

Generated PNGs must target the native 4 px grid, with complete backgrounds at
exactly `2560x1440`, binary alpha, bounded palettes, explicit pivots, palette
slots, roles, actions, and frame metadata. Do not accept an image that needs
resampling, palette repair, edge cleanup, or runtime filtering to fit the game.

Run the gate from `games/pixiball`:

```powershell
python tools/validate_native_pixel_art.py `
  content/pixel/style_contract.json `
  <candidate.png>
```

## Review and promotion

Capture representative states without `--headless` so the native framebuffer
can be read back directly:

```powershell
bin\godot.windows.editor.dev.x86_64.console.exe `
  --path games/pixiball `
  --script res://tools/capture_visual_rebuild.gd -- `
  --screen=game-batting-golden `
  --output=res://.godot/visual-qa/game-batting-golden.png
```

Review landing, pitcher select, team select, final, and pitching/batting/fielding
in day, golden, and night. Also inspect the intro and dugout fixed views during
live review. Captures must remain exactly `2560x1440`; a `320x180` capture would
prove that an obsolete low-resolution intermediate has returned.

Run the focused contracts after any renderer, projector, actor, ball, or style
change:

```powershell
$godot = "bin\godot.windows.editor.dev.x86_64.console.exe"
& $godot --headless --path games/pixiball --script res://core/tests/test_native_720_pipeline.gd
& $godot --headless --path games/pixiball --script res://core/tests/test_scene_composition.gd
& $godot --headless --path games/pixiball --script res://presentation/tests/test_broadcast_camera.gd
& $godot --headless --path games/pixiball --script res://presentation/tests/test_baseball_visual.gd
& $godot --headless --path games/pixiball --script res://characters/tests/test_ballplayer_asset.gd
& $godot --headless --path games/pixiball --script res://characters/tests/test_ballplayer_equipment.gd
```

A candidate is promotable only when silhouettes read at every LOD, the ball
stays visible, UI remains crisp, all five projections stay integer-aligned,
palette/alpha validation passes, and the full Pixiball test suite remains green.
