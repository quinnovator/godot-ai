#!/usr/bin/env python3
"""Validate generated Pixiball raster assets before Godot imports them.

The AI-native pipeline is allowed to generate or edit source imagery, but this
gate makes the shipped result obey the same authored-pixel contract as the
runtime canvas: native-sized cells, a bounded palette, binary alpha, and no
half-pixel dimensions. It intentionally performs no smoothing or quantization;
failed generation must be corrected at the source instead of hidden by a
post-process filter.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

try:
    from PIL import Image
except ImportError as exc:  # pragma: no cover - environment guidance
    raise SystemExit("Pillow is required: python -m pip install pillow") from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("contract", type=Path)
    parser.add_argument("images", nargs="+", type=Path)
    parser.add_argument(
        "--kind",
        choices=("frame", "sheet", "tilemap", "background"),
        default="sheet",
    )
    return parser.parse_args()


def validate_image(path: Path, contract: dict, kind: str) -> list[str]:
    errors: list[str] = []
    if not path.is_file():
        return [f"{path}: file does not exist"]

    with Image.open(path) as source:
        image = source.convert("RGBA")
        width, height = image.size
        canvas_width, canvas_height = contract["logical_canvas"]
        tile_width, tile_height = contract["tile_grid"]

        if kind == "background" and (width, height) != (canvas_width, canvas_height):
            errors.append(
                f"{path}: background must be {canvas_width}x{canvas_height}, got {width}x{height}"
            )
        if kind in {"sheet", "tilemap"} and (
            width % tile_width != 0 or height % tile_height != 0
        ):
            errors.append(
                f"{path}: {width}x{height} does not align to {tile_width}x{tile_height} cells"
            )

        colors = image.getcolors(maxcolors=width * height)
        if colors is None:
            errors.append(f"{path}: color count could not be bounded")
            return errors

        opaque_colors = {rgba[:3] for _, rgba in colors if rgba[3] > 0}
        maximum = int(contract["palette"]["maximum_colors_per_frame"])
        if len(opaque_colors) > maximum:
            errors.append(
                f"{path}: uses {len(opaque_colors)} opaque colors; maximum is {maximum}"
            )

        allowed_alpha = set(contract["palette"]["transparent_alpha_values"])
        used_alpha = {rgba[3] for _, rgba in colors}
        invalid_alpha = sorted(used_alpha - allowed_alpha)
        if invalid_alpha:
            preview = ", ".join(str(value) for value in invalid_alpha[:12])
            errors.append(
                f"{path}: contains antialiased alpha values ({preview}); only {sorted(allowed_alpha)} allowed"
            )

        if len(opaque_colors) <= 1:
            errors.append(f"{path}: contains no meaningful authored pixel clusters")

    return errors


def main() -> int:
    args = parse_args()
    contract = json.loads(args.contract.read_text(encoding="utf-8"))
    errors: list[str] = []
    for image in args.images:
        errors.extend(validate_image(image, contract, args.kind))
    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1
    print(
        "PIXIBALL_NATIVE_PIXEL_ART_OK "
        f"images={len(args.images)} canvas={contract['logical_canvas'][0]}x{contract['logical_canvas'][1]}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
