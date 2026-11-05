#!/usr/bin/env python3
"""Pixelize AI-gen cabin sources into hard 32×32 tile overrides and patch tileset.

Walls: continuous masonry strip (`cabin_wall_strip.jpg`) → NEAREST to a
12×3 tile grid → slice (aligned horizontal rows). Side cutaway from
`cabin_side_strip.jpg`. Props: AI JPG → NEAREST 32×32. Continuous bed →
32×64 hard NN → head/foot. No soft `_raw_*`, no Pillow invent.

Run:
  python3 tools/interiors/assemble_cabin_gen.py
  python3 tools/interiors/build_rooms.py
"""
from __future__ import annotations

import json
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
W_LOG_TOP, W_LOG_BASE = 37, 38  # generic south / fallback face bands
# AI cutaway companions (also stamped into tileset by build_rooms overrides).
W_LOG_S, W_LOG_C = 72, 77
W_LOG_S_MID, W_LOG_S_BASE = 116, 117
# Continuous N-wall strip slices: top 80–91, mid 92–103, base 104–115.
STRIP_TOP0, STRIP_MID0, STRIP_BASE0 = 80, 92, 104
STRIP_COLS = 12
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


def scale_strip(src: Path, cols: int, rows: int) -> Image.Image:
    """AI wall strip → hard NN grid so masonry rows stay aligned across tiles."""
    raw = Image.open(src).convert("RGBA")
    box = find_content_box(raw, dark=18)
    grid = raw.crop(box)
    return grid.resize((cols * T, rows * T), Image.Resampling.NEAREST)


def slice_strip_cells(grid: Image.Image, cols: int, rows: int) -> list[list[Image.Image]]:
    out: list[list[Image.Image]] = []
    for r in range(rows):
        row: list[Image.Image] = []
        for c in range(cols):
            row.append(opaque_tile(grid.crop((c * T, r * T, c * T + T, r * T + T))))
        out.append(row)
    return out


def _cell_dark_hole_score(cell: Image.Image) -> float:
    """Higher when a cell has a dark hearth mouth / deep inset void."""
    px = cell.load()
    score = 0.0
    n = 0
    for y in range(T):
        for x in range(T):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            n += 1
            if r < 55 and g < 50 and b < 50:
                score += 1.0
    return score / max(1, n)


def _cell_inset_frame_score(cell: Image.Image) -> float:
    """Higher when a cell has a dark wood frame around a lighter inset (map/window)."""
    px = cell.load()
    dark = light = 0
    n = 0
    for y in range(T):
        for x in range(T):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            n += 1
            if r < 90 and g < 70 and b < 55 and max(r, g, b) - min(r, g, b) < 35:
                dark += 1
            elif r > 150 and g > 120 and b > 70:
                light += 1
    if n == 0:
        return 0.0
    # Framed insets mix a dark border with a lighter interior patch.
    return min(dark, light) / n


def slice_walls_from_strips(face_src: Path, side_src: Path) -> dict[int, Image.Image]:
    """Full masonry face strip + side thickness strip → hard 32×32 wall ids."""
    face = scale_strip(face_src, STRIP_COLS, 3)
    cells = slice_strip_cells(face, STRIP_COLS, 3)
    out: dict[int, Image.Image] = {}
    for c in range(STRIP_COLS):
        out[STRIP_TOP0 + c] = cells[0][c]
        out[STRIP_MID0 + c] = cells[1][c]
        out[STRIP_BASE0 + c] = cells[2][c]

    # Keep insets off the cutaway end-caps so interact spots stay approachable.
    inner = list(range(1, STRIP_COLS - 1))
    fire_c = max(inner, key=lambda c: _cell_dark_hole_score(cells[1][c]) + _cell_dark_hole_score(cells[2][c]))
    # Prefer the right half for the map (hearth is usually left-of-center on the strip).
    right_inner = [c for c in inner if c >= STRIP_COLS // 2 and abs(c - fire_c) > 1]
    map_c = max(right_inner or [c for c in inner if abs(c - fire_c) > 1], key=lambda c: _cell_inset_frame_score(cells[1][c]))
    plain = min(
        (c for c in inner if c not in (fire_c, map_c)),
        key=lambda c: _cell_dark_hole_score(cells[1][c]) + _cell_inset_frame_score(cells[1][c]),
    )
    out[W_LOG_TOP] = cells[0][plain]
    out[W_LOG] = cells[1][plain]
    out[W_LOG_BASE] = cells[2][plain]
    # Hearth sits on the baseboard band; map on the mid face.
    out[W_FIRE] = cells[2][fire_c]
    out[W_MAP] = cells[1][map_c]
    meta = {"fire_col": fire_c, "map_col": map_c, "plain_col": plain, "cols": STRIP_COLS}
    (GEN / "wall_strip_meta.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"strip insets: fire_col={fire_c} map_col={map_c} plain_col={plain}")

    side = scale_strip(side_src, 1, 3)
    side_cells = slice_strip_cells(side, 1, 3)
    out[W_LOG_S] = side_cells[0][0]
    out[W_LOG_S_MID] = side_cells[1][0]
    out[W_LOG_S_BASE] = side_cells[2][0]
    out[W_LOG_C] = side_cells[0][0]

    # Door jambs: reuse AI side-thickness (flip for the right jamb — no invent).
    out[J_LOG_L] = side_cells[1][0]
    out[J_LOG_R] = side_cells[1][0].transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return out


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
    face_strip = GEN / "cabin_wall_strip.jpg"
    side_strip = GEN / "cabin_side_strip.jpg"
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
