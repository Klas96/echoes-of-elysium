#!/usr/bin/env python3
"""Pixelize AI-gen cabin sources into hard 32px tile overrides and patch tileset.

Reads tools/interiors/gen_src/cabin/*.jpg (Cursor/AI image gen), writes:
  tools/interiors/gen_src/cabin/tiles/<id>.png
then pastes those ids into assets/images/interiors/tileset.png.

Uses nearest-neighbour only (no LANCZOS soft fit) plus a light palette snap so
tiles stay calm/readable hard pixel art. Does not invent art with Pillow draws.

Run:
  python3 tools/interiors/assemble_cabin_gen.py
  python3 tools/interiors/build_rooms.py
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
# Soft AI leftovers were 400–800 colours; hard pixel target stays under this.
MAX_COLOURS = 48

# Cabin tile ids (must match build_rooms.py)
CABIN, CABIN2 = 4, 5
MAT_CABIN = 15
W_LOG, W_FIRE = 20, 21
W_MAP = 24
J_LOG_L, J_LOG_R = 30, 31
PLANT = 48
CHEST = 50
JOURNAL, NOTE = 52, 53
LOGS = 60
RUG = 63
BED_C_H, BED_C_F = 64, 65


def hard_pixel(im: Image.Image, size: int = T, colours: int = 24) -> Image.Image:
    """NEAREST downscale + adaptive palette snap (process AI art, don't invent)."""
    im = im.convert("RGBA")
    out = im.resize((size, size), Image.Resampling.NEAREST)
    # Binary alpha first so soft fringes don't inflate colour counts.
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255 if a >= 128 else 0)
    rgb = out.convert("RGB").quantize(colors=colours, method=Image.Quantize.MEDIANCUT)
    rgb = rgb.convert("RGBA")
    src_a = out.split()[-1]
    r, g, b, _ = rgb.split()
    return Image.merge("RGBA", (r, g, b, src_a))


def opaque_tile(im: Image.Image, size: int = T) -> Image.Image:
    out = hard_pixel(im, size=size, colours=20)
    px = out.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            if a < 255:
                px[x, y] = (r, g, b, 255)
    return out


def slice_floor(src: Path) -> dict[int, Image.Image]:
    raw = Image.open(src).convert("RGBA")
    side = min(raw.size)
    left = (raw.width - side) // 2
    top = (raw.height - side) // 2
    crop = raw.crop((left, top, left + side, top + side))
    # Snap to a 4×2 cell grid with NEAREST only.
    grid = crop.resize((T * 4, T * 2), Image.Resampling.NEAREST)
    a = grid.crop((0, 0, T, T))
    b = grid.crop((T, 0, T * 2, T))
    return {CABIN: opaque_tile(a), CABIN2: opaque_tile(b)}


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


def slice_walls(src: Path) -> dict[int, Image.Image]:
    raw = Image.open(src).convert("RGBA")
    cells = grid_cells(raw, 5, 3)
    log = cells[0]
    fire = cells[6]
    mmap = cells[7]
    jl = cells[13]
    jr = cells[14]
    return {
        W_LOG: opaque_tile(log),
        W_FIRE: opaque_tile(fire),
        W_MAP: opaque_tile(mmap),
        J_LOG_L: opaque_tile(jl),
        J_LOG_R: opaque_tile(jr),
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
    """AI prop → hard 32px via existing pixelize_gen, then NEAREST palette snap."""
    tmp = TILES / f"_raw_{tid}.png"
    # pixelize_gen still does a soft fit; we re-snap hard below.
    pixelize(src, tmp, T * 4, T * 4, pad=0.06)
    raw = clear_dark_bg(Image.open(tmp).convert("RGBA"))
    out = hard_pixel(raw, size=T, colours=16)
    return clear_dark_bg(out)


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
        MAT_CABIN: "cabin_doormat.jpg",
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
        n = len(tile.getcolors(T * T) or [])
        if n > MAX_COLOURS:
            print(f"warn: tile {tid} still noisy ({n} colours)")
        x, y = (tid % COLS) * T, (tid // COLS) * T
        blank = Image.new("RGBA", (T, T), (0, 0, 0, 0))
        sheet.paste(blank, (x, y))
        sheet.alpha_composite(tile, (x, y))
    sheet.save(OUT_SHEET)
    print(f"patched {OUT_SHEET} ({len(tiles)} tiles)")


def main() -> int:
    TILES.mkdir(parents=True, exist_ok=True)
    for stale in TILES.glob("*.png"):
        # Keep regenerating cleanly from AI jpgs.
        stale.unlink()
    tiles: dict[int, Image.Image] = {}
    tiles.update(slice_floor(GEN / "cabin_floor_sheet.jpg"))
    tiles.update(slice_walls(GEN / "cabin_wall_sheet.jpg"))
    tiles.update(assemble_props())
    for tid, im in tiles.items():
        path = TILES / f"{tid}.png"
        im.save(path)
        n = len(im.getcolors(T * T) or [])
        print(f"wrote {path} ({n} colours)")
    patch_sheet(tiles)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
