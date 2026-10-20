#!/usr/bin/env python3
"""Pixelize Cursor-gen cabin sources into 32px tile overrides and patch tileset.

Reads tools/interiors/gen_src/cabin/*.jpg, writes:
  tools/interiors/gen_src/cabin/tiles/<id>.png
then pastes those ids into assets/images/interiors/tileset.png.

Run before (or via) build_rooms.py so cabin art stays Cursor-gen.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
GEN = Path(__file__).resolve().parent / "gen_src" / "cabin"
TILES = GEN / "tiles"
OUT_SHEET = ROOT / "assets" / "images" / "interiors" / "tileset.png"
SYS_TOOLS = ROOT / "tools"
sys.path.insert(0, str(SYS_TOOLS))
from pixelize_gen import pixelize  # noqa: E402

T = 32
COLS = 16

# Cabin tile ids (must match build_rooms.py)
CABIN, CABIN2 = 4, 5
MAT = 12
W_LOG, W_FIRE = 20, 21
W_MAP = 24
J_LOG_L, J_LOG_R = 30, 31
PLANT = 48
CHEST = 50
JOURNAL, NOTE = 52, 53
LOGS = 60
RUG = 63
BED_C_H, BED_C_F = 64, 65


def opaque_tile(im: Image.Image, size: int = T) -> Image.Image:
    im = im.convert("RGBA")
    # Soft fit then nearest snap for chunky pixels.
    tmp = im.resize((size * 4, size * 4), Image.Resampling.LANCZOS)
    out = tmp.resize((size, size), Image.Resampling.NEAREST)
    # Force opaque for floor/wall cells.
    px = out.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            if a < 255:
                px[x, y] = (r, g, b, 255)
    return out


def slice_floor(src: Path) -> dict[int, Image.Image]:
    raw = Image.open(src).convert("RGBA")
    # Use center square, build a 4x2 grid, pick two neighbouring cells.
    side = min(raw.size)
    left = (raw.width - side) // 2
    top = (raw.height - side) // 2
    crop = raw.crop((left, top, left + side, top + side))
    grid = crop.resize((T * 4, T * 2), Image.Resampling.LANCZOS)
    grid = grid.resize((T * 4, T * 2), Image.Resampling.NEAREST)
    a = grid.crop((0, 0, T, T))
    b = grid.crop((T, 0, T * 2, T))
    return {CABIN: opaque_tile(a), CABIN2: opaque_tile(b)}


def find_content_box(im: Image.Image, dark: int = 28) -> tuple[int, int, int, int]:
    """Bounding box of non-near-black pixels (the tile grid on dark canvas)."""
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
    """Split a content box into cols×rows cells (GenerateImage wall sheets)."""
    box = find_content_box(im)
    grid = im.crop(box)
    gw, gh = grid.size
    cw, ch = gw // cols, gh // rows
    # Trim a thin gutter so black grid lines don't dominate.
    pad = max(1, min(cw, ch) // 16)
    cells: list[Image.Image] = []
    for r in range(rows):
        for c in range(cols):
            x0, y0 = c * cw + pad, r * ch + pad
            x1, y1 = (c + 1) * cw - pad, (r + 1) * ch - pad
            cells.append(grid.crop((x0, y0, x1, y1)))
    return cells


def slice_walls(src: Path) -> dict[int, Image.Image]:
    raw = Image.open(src).convert("RGBA")
    # cabin_wall_sheet is a 5×3 log-wall atlas: hearth, map, doorway among plains.
    cells = grid_cells(raw, 5, 3)
    # Indices (row-major): hearth ~6, map ~7, doorway ~12; plains elsewhere.
    log = cells[0]
    fire = cells[6]
    mmap = cells[7]
    door = cells[12]
    # Jambs: left/right halves of the doorway cell, stretched to full tile.
    dw, dh = door.size
    jl = door.crop((0, 0, dw // 2, dh)).resize((dw, dh), Image.Resampling.NEAREST)
    jr = door.crop((dw // 2, 0, dw, dh)).resize((dw, dh), Image.Resampling.NEAREST)
    return {
        W_LOG: opaque_tile(log),
        W_FIRE: opaque_tile(fire),
        W_MAP: opaque_tile(mmap),
        J_LOG_L: opaque_tile(jl),
        J_LOG_R: opaque_tile(jr),
    }


def clear_dark_bg(im: Image.Image) -> Image.Image:
    """Second pass: drop leftover near-black canvas after pixelize_gen."""
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


def assemble_props() -> dict[int, Image.Image]:
    mapping = {
        PLANT: "cabin_plant.jpg",
        CHEST: "cabin_chest.jpg",
        JOURNAL: "cabin_journal.jpg",
        NOTE: "cabin_note.jpg",
        LOGS: "cabin_logs.jpg",
        RUG: "cabin_rug.jpg",
        BED_C_H: "cabin_bed_head.jpg",
        BED_C_F: "cabin_bed_foot.jpg",
        MAT: "cabin_doormat.jpg",
    }
    out: dict[int, Image.Image] = {}
    for tid, name in mapping.items():
        out[tid] = prop_tile(GEN / name, tid)
    return out


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
        # Clear cell then paste (props need alpha).
        blank = Image.new("RGBA", (T, T), (0, 0, 0, 0))
        sheet.paste(blank, (x, y))
        sheet.alpha_composite(tile, (x, y))
    sheet.save(OUT_SHEET)
    print(f"patched {OUT_SHEET} ({len(tiles)} tiles)")


def main() -> int:
    TILES.mkdir(parents=True, exist_ok=True)
    tiles: dict[int, Image.Image] = {}
    tiles.update(slice_floor(GEN / "cabin_floor_sheet.jpg"))
    tiles.update(slice_walls(GEN / "cabin_wall_sheet.jpg"))
    tiles.update(assemble_props())
    for tid, im in tiles.items():
        path = TILES / f"{tid}.png"
        im.save(path)
        print(f"wrote {path}")
    patch_sheet(tiles)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
