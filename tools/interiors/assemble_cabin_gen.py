#!/usr/bin/env python3
"""Export hard 32×32 pixel-art cabin tiles (NEAREST, limited palette).

Soft AI `gen_src/cabin/*.jpg` sources are intentionally unused — preference is
calm readable pixel art, not detail-rich downscales. This script writes the
Pillow cabin builders from build_rooms.py into gen_src/cabin/tiles/ and patches
the shared interiors tilesheet so re-runs stay true pixel art.

Run:
  python3 tools/interiors/assemble_cabin_gen.py
  python3 tools/interiors/build_rooms.py
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
GEN = Path(__file__).resolve().parent / "gen_src" / "cabin"
TILES = GEN / "tiles"
OUT_SHEET = ROOT / "assets" / "images" / "interiors" / "tileset.png"
T = 32
COLS = 16

# Cabin-owned tile ids (must match build_rooms.py). Shared plant/rug (48/63)
# stay on Pillow via build_rooms — do not reintroduce soft AI overrides for them.
CABIN_IDS = {
    4: "cabin_floor",
    5: "cabin_floor_alt",
    15: "mat_cabin",
    20: "log_wall",
    21: "fire_wall",
    24: "map_wall",
    30: "jamb_log_l",
    31: "jamb_log_r",
    50: "chest",
    52: "journal",
    53: "note",
    60: "logs",
    64: "bed_cabin_head",
    65: "bed_cabin_foot",
}


def _load_build_rooms():
    path = Path(__file__).resolve().parent / "build_rooms.py"
    spec = importlib.util.spec_from_file_location("build_rooms_cabin", path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def hard_cabin_tiles(br) -> dict[int, Image.Image]:
    """True pixel art: opaque floors/walls, binary-alpha props."""
    return {
        4: br.cabin_floor(0),
        5: br.cabin_floor(1),
        15: br.mat(False),
        20: br.log_wall(),
        21: br.fire_wall(),
        24: br.map_wall(),
        30: br.jamb(br.log_wall, "l", br.rgba(140, 100, 60)),
        31: br.jamb(br.log_wall, "r", br.rgba(140, 100, 60)),
        50: br.chest(),
        52: br.desk(False),
        53: br.note(),
        60: br.logs(),
        64: br.bed(True, cabin=True),
        65: br.bed(False, cabin=True),
    }


def assert_hard_pixel(im: Image.Image, tid: int) -> None:
    assert im.size == (T, T), (tid, im.size)
    colors = im.getcolors(T * T)
    assert colors is not None
    # Soft AI downscales land 400–800 colours; hard pixel stays tiny.
    if len(colors) > 48:
        raise SystemExit(f"tile {tid} too noisy ({len(colors)} colours) — not hard pixel art")


def patch_sheet(tiles: dict[int, Image.Image]) -> None:
    sheet = Image.open(OUT_SHEET).convert("RGBA")
    rows_needed = max(tiles) // COLS + 1
    need_h = rows_needed * T
    if sheet.height < need_h:
        bigger = Image.new("RGBA", (COLS * T, need_h), (0, 0, 0, 0))
        bigger.paste(sheet, (0, 0))
        sheet = bigger
    for tid, tile in tiles.items():
        x, y = (tid % COLS) * T, (tid // COLS) * T
        blank = Image.new("RGBA", (T, T), (0, 0, 0, 0))
        sheet.paste(blank, (x, y))
        sheet.alpha_composite(tile, (x, y))
    sheet.save(OUT_SHEET)
    print(f"patched {OUT_SHEET} ({len(tiles)} tiles)")


def main() -> int:
    br = _load_build_rooms()
    TILES.mkdir(parents=True, exist_ok=True)
    # Drop leftover soft AI cell PNGs (including old plant/rug) from this folder.
    for stale in TILES.glob("*.png"):
        stale.unlink()
    tiles = hard_cabin_tiles(br)
    for tid, im in tiles.items():
        assert_hard_pixel(im, tid)
        path = TILES / f"{tid}.png"
        im.save(path)
        print(f"wrote {path} ({CABIN_IDS[tid]}, {len(im.getcolors(T * T))} colours)")
    patch_sheet(tiles)
    print("note: soft gen_src/cabin/*.jpg unused — hard pixel only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
