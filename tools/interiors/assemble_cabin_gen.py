#!/usr/bin/env python3
"""Pixelize AI-gen cabin sources into hard 32×32 tile overrides and patch tileset.

AI JPG → NEAREST-only pixelize straight to 32×32 (no soft 128 intermediate).
Gameplay tiles are only tiles/<id>.png at 32×32 — never commit soft _raw_* files.
Continuous bed (`cabin_bed_full.jpg`) → 32×64 hard NN → head/foot split.

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
from pixelize_gen import pixelize, pixelize_stack_pair  # noqa: E402

T = 32
COLS = 16
MAX_COLOURS = 24

CABIN, CABIN2 = 4, 5
MAT_CABIN = 15
W_LOG, W_FIRE = 20, 21
W_MAP = 24
J_LOG_L, J_LOG_R = 30, 31
# AI cutaway companions (also stamped into tileset by build_rooms overrides).
W_LOG_S, W_LOG_C = 72, 77
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
    box = find_content_box(im, dark=20)
    grid = im.crop(box)
    gw, gh = grid.size
    cw, ch = gw // cols, gh // rows
    pad = max(2, min(cw, ch) // 20)
    cells: list[Image.Image] = []
    for r in range(rows):
        for c in range(cols):
            x0, y0 = c * cw + pad, r * ch + pad
            x1, y1 = (c + 1) * cw - pad, (r + 1) * ch - pad
            cells.append(grid.crop((x0, y0, x1, y1)))
    return cells


def _row_mean(px, y: int, w: int) -> tuple[float, float, float]:
    rs = gs = bs = n = 0
    step = max(1, w // 40)
    for x in range(0, w, step):
        r, g, b, a = px[x, y]
        if a < 8:
            continue
        rs += r
        gs += g
        bs += b
        n += 1
    if not n:
        return (0.0, 0.0, 0.0)
    return (rs / n, gs / n, bs / n)


def _is_orange_floor(rgb: tuple[float, float, float]) -> bool:
    r, g, b = rgb
    return r > 115 and b < 95 and r > g + 20 and r > b + 35 and (g + b) < (r + 40)


def strip_atlas_floor(cell: Image.Image) -> Image.Image:
    """Drop orange floor planks baked under AI wall cells; keep ~2px contact shadow.

    Processes the AI atlas only — does not invent wall pixels.
    """
    cell = cell.convert("RGBA")
    px = cell.load()
    w, h = cell.size
    y = h - 1
    floor_run = 0
    while y > int(h * 0.28):
        if _is_orange_floor(_row_mean(px, y, w)):
            floor_run += 1
            y -= 1
            continue
        if floor_run >= 3 and y > 2 and _is_orange_floor(_row_mean(px, y - 1, w)):
            y -= 1
            floor_run += 1
            continue
        break
    if floor_run >= 3:
        cell = cell.crop((0, 0, w, min(h, y + 2)))
    return cell


def nonblack_box(cell: Image.Image, dark: int = 40) -> tuple[int, int, int, int]:
    px = cell.load()
    w, h = cell.size
    min_x, min_y, max_x, max_y = w, h, 0, 0
    found = False
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            if r > dark or g > dark or b > dark:
                found = True
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if not found:
        return (0, 0, w, h)
    return (min_x, min_y, max_x + 1, max_y + 1)


def scrub_floor_bleed(tile: Image.Image) -> Image.Image:
    """If NN still leaves orange floor on the bottom rows, darken toward baseboard."""
    tile = tile.copy()
    px = tile.load()
    for yy in (30, 31):
        for x in range(T):
            r, g, b, a = px[x, yy]
            if r > 115 and r > g + 20 and r > b + 35 and b < 95:
                br, bg, bb, _ = px[x, 26]
                fac = 3 if yy == 31 else 2
                px[x, yy] = (max(0, br // fac), max(0, bg // fac), max(0, bb // fac), a)
    return tile


def trim_void_columns(tile: Image.Image, dark_sum: int = 70, min_keep: int = 12) -> Image.Image:
    """Crop near-black void columns left after NN so cutaway wood fills the tile."""
    px = tile.load()
    w, h = tile.size
    left = 0
    while left < w - min_keep:
        dark = sum(1 for y in range(h) if sum(px[left, y][:3]) < dark_sum)
        if dark < h * 0.7:
            break
        left += 1
    right = w - 1
    while right > left + min_keep:
        dark = sum(1 for y in range(h) if sum(px[right, y][:3]) < dark_sum)
        if dark < h * 0.7:
            break
        right -= 1
    if left == 0 and right == w - 1:
        return tile
    return tile.crop((left, 0, right + 1, h))


def strip_side_top_beam(cell: Image.Image) -> Image.Image:
    """Remove the horizontal top-beam band from E/W cutaway cells.

    Mid-side columns tile vertically; keeping the atlas top beam would stamp a
    false horizontal stripe every 32px. Corners keep the beam via W_LOG_C.
    """
    w, h = cell.size
    # Drop ~18% from the top (beam + join), keep vertical rim/face continuous.
    y0 = max(6, h * 18 // 100)
    if y0 >= h - 8:
        return cell
    return cell.crop((0, y0, w, h))


def wall_tile(cell: Image.Image, *, fill_cutaway: bool = False) -> Image.Image:
    """AI wall cell → hard opaque 32×32 (floor stripped; optional void crop for sides)."""
    cell = strip_atlas_floor(cell)
    if fill_cutaway:
        cell = cell.crop(nonblack_box(cell, dark=35))
        cell = strip_side_top_beam(cell)
    out = scrub_floor_bleed(opaque_tile(cell))
    if fill_cutaway:
        out = opaque_tile(trim_void_columns(out))
    # Re-snap after scrub so side cutaways stay within the hard-pixel budget.
    return opaque_tile(out)


def slice_walls(src: Path) -> dict[int, Image.Image]:
    """Cutaway wall atlas (5×3): quiet face + beam/baseboard, side thickness, corners, jambs.

    Cell map (row-major):
      0 face, 2 fire, 3 map, 5 side cutaway, 6 corner post, 7 left jamb,
      9 door (unused gameplay id), 10 side variant.
    Right jamb is a horizontal flip of the AI left jamb (no new pixels invented).
    """
    raw = Image.open(src).convert("RGBA")
    cells = grid_cells(raw, 5, 3)
    jamb_l = wall_tile(cells[7])
    return {
        W_LOG: wall_tile(cells[0]),
        W_FIRE: wall_tile(cells[2]),
        W_MAP: wall_tile(cells[3]),
        W_LOG_S: wall_tile(cells[5], fill_cutaway=True),
        W_LOG_C: wall_tile(cells[6]),
        J_LOG_L: jamb_l,
        J_LOG_R: jamb_l.transpose(Image.Transpose.FLIP_LEFT_RIGHT),
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


def bed_pair(src: Path) -> tuple[Image.Image, Image.Image]:
    """One continuous AI bed → hard 32×64 NN → head/foot (no mid padding gap)."""
    head, foot = pixelize_stack_pair(src, T, pad=0.02, soft_fit=False)
    head = hard_pixel(clear_dark_bg(head), size=T, colours=12)
    foot = hard_pixel(clear_dark_bg(foot), size=T, colours=12)
    return clear_dark_bg(head), clear_dark_bg(foot)


def assemble_props() -> dict[int, Image.Image]:
    mapping = {
        PLANT: "cabin_plant.jpg",
        CHEST: "cabin_chest.jpg",
        JOURNAL: "cabin_journal.jpg",
        NOTE: "cabin_note.jpg",
        LOGS: "cabin_logs.jpg",
        RUG: "cabin_rug.jpg",
        MAT_CABIN: "cabin_doormat.jpg",
    }
    out = {tid: prop_tile(GEN / name, tid) for tid, name in mapping.items()}
    # #132 continuous bed (hard NN) — avoids mid-seam hole between head/foot.
    bed_src = GEN / "cabin_bed_full.jpg"
    if not bed_src.exists():
        raise FileNotFoundError(f"missing continuous bed source: {bed_src}")
    out[BED_C_H], out[BED_C_F] = bed_pair(bed_src)
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
