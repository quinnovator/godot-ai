# Native visual receipts

GPU captures of the live native `2560×1440` framebuffer after the Lantern Wharf
world-art cutover. These are the review source of truth for world presentation;
older `after/` and `final/` folders may lag the runtime.

## Matrix

| File | View | Mood |
| --- | --- | --- |
| `landing.png` | intro | day |
| `game-pitching-{day,golden,night}.png` | pitching | ×3 |
| `game-batting-{day,golden,night}.png` | batting | ×3 |
| `game-fielding-{day,golden,night}.png` | fielding | ×3 |
| `game-dugout-{day,golden,night}.png` | dugout | ×3 |

## Regenerate

From the repository root (requires a GPU window; do not use `--headless`):

```sh
for screen in landing game-pitching-day game-pitching-golden game-pitching-night \
  game-batting-day game-batting-golden game-batting-night \
  game-fielding-day game-fielding-golden game-fielding-night \
  game-dugout-day game-dugout-golden game-dugout-night; do
  bin/godot.macos.editor.dev.arm64 --path games/pixiball \
    --script res://tools/capture_visual_rebuild.gd \
    -- --screen="$screen" \
    --output="res://docs/art_direction/receipts/${screen}.png"
done
```
