#!/usr/bin/env python3
"""Pixelize AI-gen cabin sources into hard 32×32 tile overrides and patch tileset.

AI JPG → NEAREST-only pixelize straight to 32×32 (no soft 128 intermediate).
Gameplay tiles are only tiles/<id>.png at 32×32 — never commit soft _raw_* files.

Run:
  python3 tools/interiors/assemble_cabin_gen.py
  python3 tools/interiors/build_rooms.py
"""
from __future__ import annotations

import sys
import tempfile
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
MAX_COLOURS = 24

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


def hard_pixel(im: Image.Image, size: int = T, colours: int = 16) -> Image.Image:
    """NEAREST to size + binary alpha + palette snap (process AI, don't invent)."""
    im = im.convert("RGBA")
    out = im.resize((size, size), Image.Resampling.NEAREST)
    px = out.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255 if a >= 128 else 0)
    rgb = out.convert("RGB").quantize(colors=colours, method=Image.Quantize.MEDIANCUT)
    rgb = rgb.convert("RGBA")
    src_a = out.split()[-1]
    r, g, b, _ = rgb.split()
    return Image.merge("RGBA", (r, g, b, src_a))


def opaque_tile(im: Image.Image, size: int = T) -> Image.Image:
    out = hard_pixel(im, size=size, colours=16)
    px = out.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255)
    return out


def slice_floor(src: Path) -> dict[int, Image.Image]:
    raw = Image.open(src).convert("RGBA")
    side = min(raw.size)
    left = (raw.width - side) // 2
    top = (raw.height - side) // 2
    crop = raw.crop((left, top, left + side, top + side))
    # Straight NEAREST into a 4×2 cell grid — no LANCZOS.
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
    return {
        W_LOG: opaque_tile(cells[0]),
        W_FIRE: opaque_tile(cells[6]),
        W_MAP: opaque_tile(cells[7]),
        J_LOG_L: opaque_tile(cells[13]),
        J_LOG_R: opaque_tile(cells[14]),
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
    """AI prop → hard 32×32 in one step (NEAREST only). No soft _raw intermediate."""
    with tempfile.TemporaryDirectory(prefix=f"cabin_prop_{tid}_") as tmpdir:
        tmp = Path(tmpdir) / f"{tid}.png"
        pixelize(src, tmp, T, T, pad=0.08, soft_fit=False)
        raw = clear_dark_bg(Image.open(tmp).convert("RGBA"))
    assert raw.size == (T, T), (tid, raw.size)
    out = hard_pixel(raw, size=T, colours=12)
    out = clear_dark_bg(out)
    assert out.size == (T, T), (tid, out.size)
    return out


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
    return {tid: prop_tile(GEN / name, tid) for tid, name in mapping.items()}


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
            raise SystemExit(f"tile {tid} too soft/noisy ({n} colours > {MAX_COLOURS})")
        x, y = (tid % COLS) * T, (tid // COLS) * T
        sheet.paste(Image.new("RGBA", (T, T), (0, 0, 0, 0)), (x, y))
        sheet.alpha_composite(tile, (x, y))
    sheet.save(OUT_SHEET)
    print(f"patched {OUT_SHEET} ({len(tiles)} tiles)")


def main() -> int:
    TILES.mkdir(parents=True, exist_ok=True)
    # Drop soft intermediates and prior cells — only 32×32 id PNGs remain.
    for stale in TILES.glob("*.png"):
        stale.unlink()
    tiles: dict[int, Image.Image] = {}
    tiles.update(slice_floor(GEN / "cabin_floor_sheet.jpg"))
    tiles.update(slice_walls(GEN / "cabin_wall_sheet.jpg"))
    tiles.update(assemble_props())
    for tid, im in tiles.items():
        assert im.size == (T, T), (tid, im.size)
        path = TILES / f"{tid}.png"
        im.save(path)
        n = len(im.getcolors(T * T) or [])
        print(f"wrote {path} ({im.size[0]}×{im.size[1]}, {n} colours)")
    # Guard: no soft leftovers in the tiles folder.
    leftovers = [p.name for p in TILES.glob("_raw_*.png")]
    if leftovers:
        raise SystemExit(f"soft _raw_ files must not remain: {leftovers}")
    soft = [p.name for p in TILES.glob("*.png") if Image.open(p).size != (T, T)]
    if soft:
        raise SystemExit(f"non-32×32 tiles: {soft}")
    patch_sheet(tiles)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
