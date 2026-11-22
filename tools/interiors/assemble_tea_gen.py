#!/usr/bin/env python3
"""Pixelize AI-gen tea house sources into hard 32×32 tile overrides.

Walls: continuous wood/paper face strip (`tea_wall_strip.jpg`) → NEAREST to a
16×3 grid → slice (aligned rows); glowing windows re-seated into one mid cell.
Side cutaway from `tea_side_strip.jpg` keeps AI black void + thin wood rim.
Props: AI JPG → hard NN 32×32. Continuous bed → 32×64 hard NN. Opaque doormat.
No soft `_raw_*`, no Pillow invent. Does not touch the exterior building prop.

Run:
  python3 tools/interiors/assemble_tea_gen.py
  python3 tools/interiors/build_rooms.py
"""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
GEN = Path(__file__).resolve().parent / "gen_src" / "tea"
TILES = GEN / "tiles"
OUT_SHEET = ROOT / "assets" / "images" / "interiors" / "tileset.png"
SYS_TOOLS = ROOT / "tools"
sys.path.insert(0, str(SYS_TOOLS))
from pixelize_gen import pixelize, pixelize_stack_pair  # noqa: E402

T = 32
COLS = 16
MAX_COLOURS = 28

WOOD, WOOD2 = 0, 1
MAT = 12
W_TEA, W_TEA_WIN = 16, 17
J_TEA_L, J_TEA_R = 26, 27
COUNTER, URN = 40, 41
TABLE, CUSHION = 44, 45
BED_H, BED_F = 46, 47
SCREEN = 49
NIGHT = 61
RUG = 63
W_TEA_S, W_TEA_C = 70, 75
# Tall cutaway companions + continuous N-wall strip (16 cols).
W_TEA_S_MID, W_TEA_S_BASE = 176, 177
W_TEA_S_E, W_TEA_S_MID_E, W_TEA_S_BASE_E, W_TEA_C_E = 178, 179, 180, 181
TEA_STRIP_TOP0, TEA_STRIP_MID0, TEA_STRIP_BASE0 = 128, 144, 160
TEA_STRIP_COLS = 16


def hard_pixel(im: Image.Image, size: int = T, colours: int = 16) -> Image.Image:
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


def trim_floor_below_baseboard(im: Image.Image) -> Image.Image:
    """Drop floor-plank rows under the wall so the baseboard sits on the tile bottom."""
    px = im.load()
    w, h = im.size
    last_wall = 0
    for y in range(h):
        wallish = 0
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            # Cream paper panels or mid wood — not dark floor-only rows.
            if (r > 150 and g > 130 and b > 90) or (90 < r < 170 and 50 < g < 120 and b < 90):
                wallish += 1
        if wallish > w // 25:
            last_wall = y
    if last_wall < h // 3:
        return im
    baseboard_pad = max(4, h // 16)
    cut = min(h, last_wall + baseboard_pad)
    return im.crop((0, 0, w, cut))


def scale_strip(src: Path, cols: int, rows: int) -> Image.Image:
    raw = Image.open(src).convert("RGBA")
    box = find_content_box(raw, dark=18)
    grid = trim_floor_below_baseboard(raw.crop(box))
    return grid.resize((cols * T, rows * T), Image.Resampling.NEAREST)


def scale_side_cutaway(src: Path) -> Image.Image:
    """AI side strip → 1×3 hard NN while keeping outside as black void."""
    raw = Image.open(src).convert("RGBA")
    x0, y0, x1, y1 = find_content_box(raw, dark=18)
    rim_w = max(1, x1 - x0)
    rim_h = max(1, y1 - y0)
    target_rim_px = 3
    total_w = max(rim_w * T // target_rim_px, rim_w + 8)
    left_void = x0
    right_void = raw.width - x1
    if left_void >= right_void:
        nx1 = min(raw.width, x1)
        nx0 = max(0, nx1 - total_w)
    else:
        nx0 = max(0, x0)
        nx1 = min(raw.width, nx0 + total_w)
    pad_y = max(2, rim_h // 40)
    ny0 = max(0, y0 - pad_y)
    ny1 = min(raw.height, y1 + pad_y)
    crop = raw.crop((nx0, ny0, nx1, ny1))
    return crop.resize((T, 3 * T), Image.Resampling.NEAREST)


def slice_strip_cells(grid: Image.Image, cols: int, rows: int) -> list[list[Image.Image]]:
    out: list[list[Image.Image]] = []
    for r in range(rows):
        row: list[Image.Image] = []
        for c in range(cols):
            row.append(opaque_tile(grid.crop((c * T, r * T, c * T + T, r * T + T))))
        out.append(row)
    return out


def _cell_window_score(cell: Image.Image) -> float:
    px = cell.load()
    warm = dark = n = 0
    for y in range(T):
        for x in range(T):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            n += 1
            if r > 170 and g > 110 and b < 120 and r >= g > b:
                warm += 1
            elif r < 100 and g < 80 and b < 60:
                dark += 1
    if n == 0 or warm < 8:
        return 0.0
    return (warm / n) * (1.0 + min(1.0, dark / max(1, warm)))


def slice_walls_from_strips(face_src: Path, side_src: Path) -> dict[int, Image.Image]:
    face = scale_strip(face_src, TEA_STRIP_COLS, 3)
    probe = slice_strip_cells(face, TEA_STRIP_COLS, 3)
    inner = list(range(1, TEA_STRIP_COLS - 1))
    # Rank mid cells by warm window glow.
    ranked = sorted(inner, key=lambda c: _cell_window_score(probe[1][c]), reverse=True)
    win_cols = [c for c in ranked if _cell_window_score(probe[1][c]) > 0.02][:3]
    if not win_cols:
        win_cols = [TEA_STRIP_COLS // 2]
    primary = win_cols[0]
    plain_candidates = [
        c for c in inner if all(abs(c - w) > 1 for w in win_cols)
    ] or [c for c in inner if c not in win_cols]
    plain = min(plain_candidates, key=lambda c: _cell_window_score(probe[1][c]))
    cells = slice_strip_cells(face, TEA_STRIP_COLS, 3)
    out: dict[int, Image.Image] = {}
    for c in range(TEA_STRIP_COLS):
        out[TEA_STRIP_TOP0 + c] = cells[0][c]
        out[TEA_STRIP_MID0 + c] = cells[1][c]
        out[TEA_STRIP_BASE0 + c] = cells[2][c]

    out[W_TEA] = cells[1][plain]
    # Keep the continuous mid row as sliced — tea windows often span 2 cols;
    # scrubbing neighbors cuts them into cream blocks.
    out[W_TEA_WIN] = cells[1][primary]

    meta = {
        "window_cols": win_cols,
        "primary_window": primary,
        "plain_col": plain,
        "cols": TEA_STRIP_COLS,
        "inset": "window",
    }
    (GEN / "wall_strip_meta.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(
        f"tea strip windows={win_cols} primary={primary} plain={plain} "
        f"win_score={_cell_window_score(out[W_TEA_WIN]):.3f}"
    )

    side = scale_side_cutaway(side_src)
    side_cells = slice_strip_cells(side, 1, 3)
    west = [side_cells[0][0], side_cells[1][0], side_cells[2][0]]
    east = [t.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for t in west]
    out[W_TEA_S] = west[0]
    out[W_TEA_S_MID] = west[1]
    out[W_TEA_S_BASE] = west[2]
    out[W_TEA_C] = west[0]
    out[W_TEA_S_E] = east[0]
    out[W_TEA_S_MID_E] = east[1]
    out[W_TEA_S_BASE_E] = east[2]
    out[W_TEA_C_E] = east[0]

    jamb_src = GEN / "tea_door_jamb.jpg"
    if jamb_src.exists():
        jamb_raw = Image.open(jamb_src).convert("RGBA")
        jamb = opaque_tile(jamb_raw.crop(find_content_box(jamb_raw, dark=18)))
    else:
        jamb = cells[1][1]
    out[J_TEA_L] = jamb
    out[J_TEA_R] = jamb.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return out


def slice_floor(src: Path) -> dict[int, Image.Image]:
    """Warm plank variants that fully fill each 32×32 (no black gutter strips)."""
    raw = Image.open(src).convert("RGBA")
    crop = raw.crop(find_content_box(raw, dark=18))
    # Force a filled plank grid — content-box may be wide; square-crop center.
    side = min(crop.size)
    left = (crop.width - side) // 2
    top = (crop.height - side) // 2
    crop = crop.crop((left, top, left + side, top + side))
    grid = crop.resize((T * 4, T * 2), Image.Resampling.NEAREST)
    a = opaque_tile(grid.crop((0, 0, T, T)))
    b = opaque_tile(grid.crop((T, 0, T * 2, T)))
    # Guarantee every pixel opaque (AI sheets sometimes leave black gutters).
    for tile in (a, b):
        px = tile.load()
        for y in range(T):
            for x in range(T):
                r, g, b_, al = px[x, y]
                if al < 255 or (r < 20 and g < 20 and b_ < 20):
                    # Sample nearest non-void neighbor.
                    fill = (120, 80, 45, 255)
                    for yy in range(max(0, y - 2), min(T, y + 3)):
                        for xx in range(max(0, x - 2), min(T, x + 3)):
                            rr, gg, bb, aa = px[xx, yy]
                            if aa >= 255 and not (rr < 20 and gg < 20 and bb < 20):
                                fill = (rr, gg, bb, 255)
                                break
                    px[x, y] = fill
    return {WOOD: a, WOOD2: b}


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
    with tempfile.TemporaryDirectory(prefix=f"tea_prop_{tid}_") as tmpdir:
        tmp = Path(tmpdir) / f"{tid}.png"
        pixelize(src, tmp, T, T, pad=0.08, soft_fit=False)
        raw = clear_dark_bg(Image.open(tmp).convert("RGBA"))
    out = hard_pixel(raw, size=T, colours=12)
    return clear_dark_bg(out)


def bed_pair(src: Path) -> tuple[Image.Image, Image.Image]:
    head, foot = pixelize_stack_pair(src, T, pad=0.02, soft_fit=False)
    head = hard_pixel(clear_dark_bg(head), size=T, colours=12)
    foot = hard_pixel(clear_dark_bg(foot), size=T, colours=12)
    return clear_dark_bg(head), clear_dark_bg(foot)


def mat_tile(src: Path) -> Image.Image:
    raw = Image.open(src).convert("RGBA")
    box = find_content_box(raw, dark=18)
    return opaque_tile(raw.crop(box), size=T)


def assemble_props() -> dict[int, Image.Image]:
    # Keep bed sources unchanged when only redesigning floor/props.
    # Plant (48) stays cabin's (tea does not emit 48). Rug (63) is tea's —
    # build_rooms loads tea after cabin so the hub rug wins without touching plants.
    mapping = {
        COUNTER: "tea_counter.jpg",
        URN: "tea_urn.jpg",
        TABLE: "tea_table.jpg",
        CUSHION: "tea_cushion.jpg",
        SCREEN: "tea_screen.jpg",
        NIGHT: "tea_nightstand.jpg",
        RUG: "tea_rug.jpg",
    }
    out = {tid: prop_tile(GEN / name, tid) for tid, name in mapping.items()}
    bed_src = GEN / "tea_bed_full.jpg"
    if not bed_src.exists():
        raise FileNotFoundError(f"missing continuous bed source: {bed_src}")
    out[BED_H], out[BED_F] = bed_pair(bed_src)
    out[MAT] = mat_tile(GEN / "tea_doormat.jpg")
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
    print(f"patched {OUT_SHEET} ({len(tiles)} tea tiles)")


def main() -> int:
    TILES.mkdir(parents=True, exist_ok=True)
    for stale in TILES.glob("*.png"):
        stale.unlink()
    tiles: dict[int, Image.Image] = {}
    tiles.update(slice_floor(GEN / "tea_floor_sheet.jpg"))
    face_strip = GEN / "tea_wall_strip.jpg"
    side_strip = GEN / "tea_side_strip.jpg"
    if not face_strip.exists() or not side_strip.exists():
        raise FileNotFoundError(
            f"need {face_strip.name} + {side_strip.name} (continuous wall strips)"
        )
    tiles.update(slice_walls_from_strips(face_strip, side_strip))
    tiles.update(assemble_props())
    for tid, im in tiles.items():
        assert im.size == (T, T), (tid, im.size)
        path = TILES / f"{tid}.png"
        im.save(path)
        n = len(im.getcolors(T * T) or [])
        print(f"wrote {path} ({im.size[0]}×{im.size[1]}, {n} colours)")
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
