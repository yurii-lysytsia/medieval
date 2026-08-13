#!/usr/bin/env python3
"""Split the legacy Europe map into transparent pointy-top hex PNG assets."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw


COLUMNS = 40
ROWS = 30
HORIZONTAL_STEP = 36.5
VERTICAL_STEP = 30
FIRST_CENTER_X = 18.25
FIRST_CENTER_Y = 19
ODD_ROW_OFFSET = 18.25
TILE_WIDTH = 39
TILE_HEIGHT = 43
HEX_RADIUS_X = 18.25
HEX_RADIUS_Y = 20


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    return parser.parse_args()


def alpha_mask(center_x: float, center_y: float, left: int, top: int) -> Image.Image:
    scale = 4
    vertices = [
        (center_x, center_y - HEX_RADIUS_Y),
        (center_x + HEX_RADIUS_X, center_y - HEX_RADIUS_Y / 2),
        (center_x + HEX_RADIUS_X, center_y + HEX_RADIUS_Y / 2),
        (center_x, center_y + HEX_RADIUS_Y),
        (center_x - HEX_RADIUS_X, center_y + HEX_RADIUS_Y / 2),
        (center_x - HEX_RADIUS_X, center_y - HEX_RADIUS_Y / 2),
    ]
    local = [((x - left) * scale, (y - top) * scale) for x, y in vertices]
    mask = Image.new("L", (TILE_WIDTH * scale, TILE_HEIGHT * scale), 0)
    ImageDraw.Draw(mask).polygon(local, fill=255)
    return mask.resize((TILE_WIDTH, TILE_HEIGHT), Image.Resampling.LANCZOS)


def crop_with_padding(source: Image.Image, left: int, top: int) -> Image.Image:
    target = Image.new("RGBA", (TILE_WIDTH, TILE_HEIGHT), (0, 0, 0, 0))
    source_left = max(0, left)
    source_top = max(0, top)
    source_right = min(source.width, left + TILE_WIDTH)
    source_bottom = min(source.height, top + TILE_HEIGHT)
    if source_left < source_right and source_top < source_bottom:
        region = source.crop((source_left, source_top, source_right, source_bottom)).convert("RGBA")
        target.alpha_composite(region, (source_left - left, source_top - top))
    return target


def classify(tile: Image.Image) -> str:
    pixels = []
    for y in range(7, TILE_HEIGHT - 7):
        for x in range(6, TILE_WIDTH - 6):
            red, green, blue, alpha = tile.getpixel((x, y))
            if alpha > 240:
                pixels.append((red, green, blue))
    if not pixels:
        return "unknown"

    total = len(pixels)
    ratio = lambda predicate: sum(1 for pixel in pixels if predicate(*pixel)) / total
    if ratio(lambda r, g, b: r < 45 and g > 115 and b > 175) > 0.34:
        return "water"
    if ratio(lambda r, g, b: r > 225 and g > 225 and b > 190) > 0.025:
        return "mountains"
    if ratio(lambda r, g, b: r > 215 and g > 215 and b < 100) > 0.30:
        return "desert"
    if ratio(lambda r, g, b: r < 105 and 65 < g < 200 and b < 75) > 0.13:
        return "forest"
    if ratio(lambda r, g, b: 70 < r < 165 and 125 < g < 215 and b < 70) > 0.28:
        return "hills"
    return "plains"


def main() -> None:
    args = arguments()
    source = Image.open(args.source).convert("RGBA")
    output = args.output
    tiles_directory = output / "tiles"
    terrain_directory = output / "terrain"
    tiles_directory.mkdir(parents=True, exist_ok=True)
    terrain_directory.mkdir(parents=True, exist_ok=True)

    entries = []
    terrain_counts: Counter[str] = Counter()

    for row in range(ROWS):
        center_y = FIRST_CENTER_Y + row * VERTICAL_STEP
        for column in range(COLUMNS):
            center_x = FIRST_CENTER_X + (ODD_ROW_OFFSET if row % 2 else 0) + column * HORIZONTAL_STEP
            left = round(center_x - TILE_WIDTH / 2)
            top = round(center_y - TILE_HEIGHT / 2)
            tile = crop_with_padding(source, left, top)
            mask = alpha_mask(center_x, center_y, left, top)
            original_alpha = tile.getchannel("A")
            tile.putalpha(Image.new("L", tile.size, 0))
            tile.putalpha(Image.frombytes("L", tile.size, bytes(min(a, m) for a, m in zip(original_alpha.get_flattened_data(), mask.get_flattened_data()))))

            filename = f"hex-r{row:02d}-c{column:02d}.png"
            path = tiles_directory / filename
            tile.save(path, optimize=True)
            terrain = classify(tile)
            terrain_counts[terrain] += 1
            clipped = left < 0 or top < 0 or left + TILE_WIDTH > source.width or top + TILE_HEIGHT > source.height
            visible_pixels = sum(1 for alpha in tile.getchannel("A").get_flattened_data() if alpha > 8)
            axial_q = column - (row - (row & 1)) // 2
            entries.append(
                {
                    "id": f"r{row:02d}-c{column:02d}",
                    "row": row,
                    "column": column,
                    "q": axial_q,
                    "r": row,
                    "terrain": terrain,
                    "image": f"tiles/{filename}",
                    "center": {"x": round(center_x, 2), "y": center_y},
                    "sourceBounds": {"x": left, "y": top, "width": TILE_WIDTH, "height": TILE_HEIGHT},
                    "isClippedBySource": clipped,
                    "visiblePixels": visible_pixels,
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                }
            )

    by_position = {(entry["row"], entry["column"]): entry for entry in entries}
    terrain_candidates: dict[str, tuple[int, Path]] = {}
    for entry in entries:
        row, column = entry["row"], entry["column"]
        diagonal = 1 if row % 2 else -1
        neighbors = [
            (row, column - 1),
            (row, column + 1),
            (row - 1, column),
            (row + 1, column),
            (row - 1, column + diagonal),
            (row + 1, column + diagonal),
        ]
        same_neighbors = sum(
            1 for position in neighbors if by_position.get(position, {}).get("terrain") == entry["terrain"]
        )
        score = 0 if entry["isClippedBySource"] else same_neighbors * 10_000 + entry["visiblePixels"]
        candidate_path = output / entry["image"]
        if score > terrain_candidates.get(entry["terrain"], (-1, candidate_path))[0]:
            terrain_candidates[entry["terrain"]] = (score, candidate_path)

    for terrain, (_, source_path) in terrain_candidates.items():
        shutil.copy2(source_path, terrain_directory / f"{terrain}.png")

    manifest = {
        "formatVersion": 1,
        "source": args.source.name,
        "sourceSize": {"width": source.width, "height": source.height},
        "layout": "odd-r-pointy-top",
        "rows": ROWS,
        "columns": COLUMNS,
        "tileSize": {"width": TILE_WIDTH, "height": TILE_HEIGHT},
        "spacing": {"horizontal": HORIZONTAL_STEP, "vertical": VERTICAL_STEP},
        "terrainCounts": dict(sorted(terrain_counts.items())),
        "tiles": entries,
    }
    (output / "hex-map.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Exported {len(entries)} hexes to {output}")
    print("Terrain counts:", dict(sorted(terrain_counts.items())))


if __name__ == "__main__":
    main()
