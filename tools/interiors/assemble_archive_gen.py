#!/usr/bin/env python3
"""Pixelize Cursor-gen archive sources into 32px tile overrides.

Reads tools/interiors/gen_src/archive/*.jpg, writes:
  tools/interiors/gen_src/archive/tiles/<id>.png
then pastes those ids into assets/images/interiors/tileset.png.

Run before build_rooms.py (with cabin/grotto assemble) so archive art stays.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
GEN = Path(__file__).resolve().parent / "gen_src" / "archive"
TILES = GEN / "tiles"
OUT_SHEET = ROOT / "assets" / "images" / "interiors" / "tileset.png"
sys.path.insert(0, str(ROOT / "tools"))
from pixelize_gen import pixelize  # noqa: E402

T = 32
COLS = 16

# Archive tile ids (must match build_rooms.py)
STONE, STONE2 = 6, 7
MAT_ARCHIVE = 14
W_BOOKS = 22
J_BOOK_L, J_BOOK_R = 34, 35
ARCHIVE_RUG = 36
W_BOOKS_S, W_BOOKS_C = 73, 78


def opaque_tile(im: Image.Image, size: int = T) -> Image.Image:
    im = im.convert("RGBA")
    tmp = im.resize((size * 4, size * 4), Image.Resampling.LANCZOS)
    out = tmp.resize((size, size), Image.Resampling.NEAREST)
    px = out.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            if a < 255:
                px[x, y] = (r, g, b, 255)
    return out


def find_content_box(im: Image.Image, dark: int = 28) -> tuple[int, int, int, int]:
    px = im.load()
    w, h = im.size
    min_x, min_y, max_x, max_y = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            if r > dark or g > dark or b > dark:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if max_x <= min_x:
        return (0, 0, w, h)
    return (min_x, min_y, max_x + 1, max_y + 1)


def grid_cells(im: Image.Image, cols: int, rows: int) -> list[Image.Image]:
    box = find_content_box(im)
    grid = im.crop(box)
    gw, gh = grid.size
    cw, ch = gw // cols, gh // rows
    pad = max(1, min(cw, ch) // 16)
    cells: list[Image.Image] = []
    for r in range(rows):
        for c in range(cols):
            x0, y0 = c * cw + pad, r * ch + pad
            x1, y1 = (c + 1) * cw - pad, (r + 1) * ch - pad
            cells.append(grid.crop((x0, y0, x1, y1)))
    return cells


def slice_floor(src: Path) -> dict[int, Image.Image]:
    raw = Image.open(src).convert("RGBA")
    side = min(raw.size)
    left = (raw.width - side) // 2
    top = (raw.height - side) // 2
    crop = raw.crop((left, top, left + side, top + side))
    grid = crop.resize((T * 4, T * 2), Image.Resampling.LANCZOS)
    grid = grid.resize((T * 4, T * 2), Image.Resampling.NEAREST)
    a = grid.crop((0, 0, T, T))
    b = grid.crop((T, 0, T * 2, T))
    return {STONE: opaque_tile(a), STONE2: opaque_tile(b)}


def slice_walls(src: Path) -> dict[int, Image.Image]:
    """archive_wall_sheet is a 4×3 atlas: books, pillars, jambs/door/corner."""
    raw = Image.open(src).convert("RGBA")
    cells = grid_cells(raw, 4, 3)
    # Row0: books×4 — Row1: books×2, pillar sides×2 — Row2: jamb L, door, jamb R, corner
    return {
        W_BOOKS: opaque_tile(cells[0]),
        W_BOOKS_S: opaque_tile(cells[6]),
        J_BOOK_L: opaque_tile(cells[8]),
        J_BOOK_R: opaque_tile(cells[10]),
        W_BOOKS_C: opaque_tile(cells[11]),
    }


def clear_dark_bg(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if r < 28 and g < 28 and b < 28:
                px[x, y] = (0, 0, 0, 0)
            elif r < 40 and g < 40 and b < 40 and max(r, g, b) - min(r, g, b) < 8:
                px[x, y] = (0, 0, 0, 0)
    return im


def prop_tile(src: Path, tid: int) -> Image.Image:
    tmp = TILES / f"_raw_{tid}.png"
    pixelize(src, tmp, T, T, pad=0.08)
    return clear_dark_bg(Image.open(tmp).convert("RGBA"))


def mat_tile(src: Path) -> Image.Image:
    """Full-bleed floor mat — keep opaque (door threshold is a floor cell)."""
    raw = Image.open(src).convert("RGBA")
    side = min(raw.size)
    left = (raw.width - side) // 2
    top = (raw.height - side) // 2
    crop = raw.crop((left, top, left + side, top + side))
    return opaque_tile(crop)


def rug_tile(src: Path) -> Image.Image:
    """Inset crop so neighbouring rug cells join as one runner (no frame)."""
    raw = Image.open(src).convert("RGBA")
    side = min(raw.size)
    left = (raw.width - side) // 2
    top = (raw.height - side) // 2
    crop = raw.crop((left, top, left + side, top + side))
    pad = max(1, int(side * 0.12))
    inner = crop.crop((pad, pad, side - pad, side - pad))
    return opaque_tile(inner)


def assemble_props() -> dict[int, Image.Image]:
    return {
        MAT_ARCHIVE: mat_tile(GEN / "archive_doormat.jpg"),
        ARCHIVE_RUG: rug_tile(GEN / "archive_rug.jpg"),
    }


def patch_sheet(tiles: dict[int, Image.Image]) -> None:
    sheet = Image.open(OUT_SHEET).convert("RGBA")
    rows_needed = max(tiles) // COLS + 1
    need_h = rows_needed * T
    if sheet.height < need_h:
        bigger = Image.new("RGBA", (COLS * T, need_h), (0, 0, 0, 0))
        bigger.paste(sheet, (0, 0))
        sheet = bigger
    for tid, tile in tiles.items():
        assert tile.size == (T, T), (tid, tile.size)
        x, y = (tid % COLS) * T, (tid // COLS) * T
        sheet.paste(Image.new("RGBA", (T, T), (0, 0, 0, 0)), (x, y))
        sheet.alpha_composite(tile, (x, y))
    sheet.save(OUT_SHEET)
    print(f"patched {OUT_SHEET} ({len(tiles)} archive tiles)")


def main() -> int:
    TILES.mkdir(parents=True, exist_ok=True)
    tiles: dict[int, Image.Image] = {}
    tiles.update(slice_floor(GEN / "archive_floor_sheet.jpg"))
    tiles.update(slice_walls(GEN / "archive_wall_sheet.jpg"))
    tiles.update(assemble_props())
    for tid, im in tiles.items():
        path = TILES / f"{tid}.png"
        im.save(path)
        print(f"wrote {path}")
    patch_sheet(tiles)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
