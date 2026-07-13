# Pixiball native pixel pipeline

Pixiball renders directly into one `2560x1440` root framebuffer. Composition
retains a `320x180` coordinate vocabulary, a 2x density pass expands it onto a
`640x360` design grid, and `PixelScene.scale = Vector2(4, 4)` makes each dense
unit a deliberate `4x4` block in that framebuffer. `PixelScene` is an ordinary
`Node2D`, not a texture or viewport: neither design grid is a framebuffer to
enlarge, sample, or filter.

The runtime keeps baseball positions as `Vector3` data because height, lateral
movement, and field depth remain useful simulation concepts. The view director
maps those values into five fixed integer-pixel compositions. No `Camera3D`,
mesh, light, environment, spatial shader, skeletal rig, or composite pixel
filter participates in the image. No `SubViewport`, offscreen low-resolution
texture, or framebuffer post-process participates either.

## Generative contract

[`style_contract.json`](../../content/pixel/style_contract.json) is the stable
target for AI-authored additions. New sprite or tile generators must emit:

- 4 px-aligned clusters or a complete `2560x1440` background;
- binary alpha with no antialiased fringe;
- no more than 32 simultaneous opaque colors;
- explicit pivots, palette slots, roles, actions, and frame metadata;
- pose-authored animation intended for ten visible frames per second.

Run the asset gate before importing generated PNGs:

```powershell
python tools/validate_native_pixel_art.py `
  content/pixel/style_contract.json `
  content/pixel/generated/actors.png
```

The validator rejects art with the wrong native dimensions or grid alignment,
gradient-heavy generation, fractional alpha, and unbounded palettes. It never
silently repairs an asset with resampling or a pixel filter.

## Runtime layers

1. The root window owns the only framebuffer, exactly `2560x1440`.
2. `PixelScene` is a direct CanvasItem stage scaled 4x from `640x360` dense
   design coordinates. Legacy `320x180` composition landmarks receive an exact
   2x coordinate transform; no intermediate image is allocated or sampled.
3. `PixelBallparkCanvas` draws flat sky, harbor, stadium, field, tile detail,
   crowd clusters, and semantic reactions.
4. `BallplayerActor` retains deterministic baseball state while its detached
   `PixiballPixelActorSprite` draws role equipment and stepped poses.
5. `BaseballVisual` retains the ball's simulation position while its pixel
   presenter draws a one- to three-design-unit ball, shadow, and discrete trail.
6. The HUD renders into the same native root and follows the same 4 px design
   grid with integer bounds.

This split leaves gameplay deterministic and inspectable while allowing the AI
fork to regenerate any visible layer without reconstructing a spatial asset
stack or a low-resolution composite pipeline.
