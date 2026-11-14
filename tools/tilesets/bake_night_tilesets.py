#!/usr/bin/env python3
"""Bake night variants of overworld tilesheets + building props (EOE-99).

Night sheets are the day art with [DayCycle.tint] at full night (colour
0x0A1236, alpha 0.46) source-over blended onto opaque pixels. Light-fixture
tiles stay day-bright so lanterns/lamps still read as lit without a HUD
redraw over Kaela.

  python3 tools/tilesets/bake_night_tilesets.py
"""

from __future__ import annotations

import os
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets" / "images" / "maps"
TILESETS = ASSETS / "tilesets"
BUILDINGS = ASSETS / "buildings"

# Matches DayCycle.tint at darkness=1, strength=1.
NIGHT_RGB = np.array([0x0A, 0x12, 0x36], dtype=np.float64)
NIGHT_A = 0.46

# Local tile ids that stay day-bright (fixtureTileAtlas + junkyard yard_lamp).
BRIGHT_TILES = {
    "woods": {197, 204},  # campfire, lantern
    "city": {224},  # street_lamp
    "cyberpunk": {200},  # neon_streetlight
    "core": {207},  # energy_brazier
    "junkyard": {200},  # yard_lamp
}

SHEETS = ("woods", "city", "cyberpunk", "core", "junkyard")
TILE = 32


def bake_rgba(src: np.ndarray) -> np.ndarray:
    """Source-over night wash; preserve fully transparent pixels."""
    out = src.astype(np.float64)
    a = src[:, :, 3:4] / 255.0
    rgb = out[:, :, :3]
    washed = rgb * (1.0 - NIGHT_A) + NIGHT_RGB * NIGHT_A
    # Only blend where there is coverage; keep clear texels clear.
    out[:, :, :3] = np.where(a > 0, washed, rgb)
    return np.clip(out, 0, 255).astype(np.uint8)


def restore_bright_tiles(day: np.ndarray, night: np.ndarray, name: str) -> np.ndarray:
    ids = BRIGHT_TILES.get(name, set())
    if not ids:
        return night
    cols = day.shape[1] // TILE
    out = night.copy()
    for tid in ids:
        col = tid % cols
        row = tid // cols
        y0, x0 = row * TILE, col * TILE
        out[y0 : y0 + TILE, x0 : x0 + TILE] = day[y0 : y0 + TILE, x0 : x0 + TILE]
    return out


def bake_sheet(name: str) -> Path:
    src_path = TILESETS / f"{name}.png"
    day = np.array(Image.open(src_path).convert("RGBA"))
    night = bake_rgba(day)
    night = restore_bright_tiles(day, night, name)
    out_path = TILESETS / f"{name}_night.png"
    Image.fromarray(night, "RGBA").save(out_path, optimize=True)
    return out_path


def bake_building(path: Path) -> Path | None:
    if path.name.endswith("_night.png"):
        return None
    day = np.array(Image.open(path).convert("RGBA"))
    night = bake_rgba(day)
    out_path = path.with_name(f"{path.stem}_night.png")
    Image.fromarray(night, "RGBA").save(out_path, optimize=True)
    return out_path


def main() -> None:
    os.chdir(ROOT)
    written: list[Path] = []
    for name in SHEETS:
        written.append(bake_sheet(name))
    for path in sorted(BUILDINGS.glob("*.png")):
        out = bake_building(path)
        if out is not None:
            written.append(out)
    for p in written:
        rel = p.relative_to(ROOT)
        print(f"wrote {rel} ({p.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
