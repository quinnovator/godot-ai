# Pixiball visual direction

Pixiball uses a hybrid 3D/high-density pixel-art presentation. Geometry,
animation, lighting, and materials are authored at full quality first; the
screen composite then unifies them into a stable pixel language. The composite
is a finish, not a substitute for modeled or painted detail.

## Reference targets

- `references/pixiball-target-gameplay-v1.png` is the composition, lighting,
  density, and final in-game readability target.
- `references/pixiball-character-sheet-v1.png` is the anatomy, silhouette,
  uniform, equipment, and action-pose target.
- `references/pixiball-environment-sheet-v1.png` is the stadium density,
  harbor depth, material, wear, and prop target.
- `baseline/` preserves the pre-pass title, day/night gameplay views, and the
  fixed ballplayer QA poses used for visual comparisons.

The references are direction, not atlas-ready source art. Production assets
must remain original, deterministic, and compatible with the documented rig,
socket, gameplay geometry, and mood contracts.

## Non-negotiable style rules

1. Silhouette before surface detail. Athletes must read by role and action at
   gameplay size; the stadium must retain a clear field/stands/harbor depth
   hierarchy.
2. Use deliberate 2-4 pixel clusters at 1280 x 720. Avoid single-pixel noise,
   full-frame dithering, blurry upscaling, and smooth vector-like gradients.
3. Keep geometry faceted enough to create graphic planes, but never reduce a
   model to disconnected capsules, cubes, or voxel blocks. Curvature belongs
   where anatomy, equipment, and silhouette need it.
4. Share one palette family: navy ink shadows, sea teal, verdigris green,
   coral/brick warmth, mustard gold, and cream highlights. Team colors may
   vary inside that value structure.
5. Separate materials by value response and microstructure: cloth is broad and
   matte; leather has tight warm highlights and stitching; rubber is dark and
   soft; painted steel has chipped hard edges; dirt is granular and warm;
   grass has clustered blades and mowing direction.
6. Preserve stable warm-key/cool-fill lighting. Contact shadows and ambient
   occlusion ground every character and prop. Bloom is reserved for lamps,
   windows, signage, and the brightest specular accents.
7. World anti-aliasing stabilizes moving geometry before pixel quantization.
   UI is composited after the world pass and remains native-resolution sharp.

## Character bar

- Athletic, stylized proportions with readable shoulders, ribcage, pelvis,
  elbows, knees, calves, hands, and feet.
- Expressive brow, eye, nose, jaw, ear, hair, and mouth planes that survive the
  gameplay camera; no generic sphere head.
- Continuous deformation at every major joint with enough topology to hold
  pitching, batting, catching, sliding, and running silhouettes.
- Authored jersey collar, placket, piping, sleeve cuffs, cloth folds, belt
  loops, socks, cleat laces/studs, cap seams, glove webbing/stitching, and bat
  grip. Details should form readable clusters rather than texture noise.
- Keep the 31-bone armature, nine native actions, marker frames, semantic
  sockets, eight logical mesh categories, team material slots, handedness, and
  grounded bounds intact unless a contract and its tests are deliberately
  versioned together.

## Environment bar

- Gameplay fence, bases, mound, foul lines, and camera anchors remain driven by
  the simulation geometry. Visual dressing may add thickness, bevels, wear,
  railings, netting, doors, posts, caps, and backing structures without moving
  the contract surface.
- Layer foreground field detail, midground wall/stands, and background harbor
  silhouettes. Each depth band gets a distinct contrast and saturation range.
- Replace repeated block crowds and skyline boxes with clustered silhouettes,
  stepped seating, aisles, rails, canopies, bunting, pennants, dugout detail,
  boats, cranes, pier furniture, and landmark shapes.
- Day is clear and buoyant, golden is warm and cinematic, and night uses cool
  ambient fill plus motivated floodlights. Mood changes must affect sky,
  environment, fixtures, emissive props, and character grounding together.

## Rendering bar

- Render the 3D world at the native 1280 x 720 reference resolution.
- Prefer MSAA for geometric stability in the Compatibility renderer. Avoid a
  post-process AA pass that washes out the final pixel clusters.
- Quantize in a perceptual color space or luminance-aware palette transform;
  never independently crush RGB channels into noisy color ramps.
- Dither only where it resolves visible banding, using a stable screen-space
  pattern with materially lower strength on faces, UI-adjacent edges, and dark
  scenes.
- Use a restrained outline/rim treatment based on lighting and material planes,
  not a uniform black contour around every object.
- Judge every change in title, gameplay day, gameplay golden, gameplay night,
  and the fixed ballplayer QA poses. A source-file change is incomplete until
  fresh images have been inspected.

## Quality checks

- Character silhouette reads at gameplay scale and in every fixed action pose.
- Hands, feet, face, glove, bat, uniform, and catcher gear are not fused or
  visibly intersecting at their contract frames.
- Grass, dirt, chalk, wall, brick, steel, cloth, leather, and rubber are
  distinguishable without relying only on hue.
- Pixel grid remains stable during camera and character motion.
- UI text and thin strike-zone lines remain crisp.
- No mood clips highlights, buries faces, or detaches players from the field.
- Visual changes preserve the full Pixiball automated test suite.
