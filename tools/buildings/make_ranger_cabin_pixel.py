#!/usr/bin/env python3
"""Pixelize AI-gen ranger cabin exterior to hard 128×128 (4×4 of 32px) sprite.

Source: tools/buildings/gen_src/ranger_cabin_front.jpg
NEAREST-only — no soft 512 intermediate as the gameplay sprite.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SYS_TOOLS = ROOT / "tools"
sys.path.insert(0, str(SYS_TOOLS))
from pixelize_gen import pixelize  # noqa: E402

SRC = Path(__file__).resolve().parent / "gen_src" / "ranger_cabin_front.jpg"
OUT = ROOT / "assets" / "images" / "maps" / "buildings" / "ranger_cabin.png"
SIZE = 128  # 4×4 tiles of 32px


def hard_snap(im: Image.Image, size: int, colours: int = 24) -> Image.Image:
    im = im.convert("RGBA")
    assert im.size == (size, size), im.size
    px = im.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            if a < 128 or (r < 28 and g < 28 and b < 28):
                px[x, y] = (0, 0, 0, 0)
            else:
                px[x, y] = (r, g, b, 255)
    rgb = im.convert("RGB").quantize(colors=colours, method=Image.Quantize.MEDIANCUT).convert("RGBA")
    a = im.split()[-1]
    r, g, b, _ = rgb.split()
    out = Image.merge("RGBA", (r, g, b, a))
    px = out.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            px[x, y] = (0, 0, 0, 0) if a < 128 else (r, g, b, 255)
    return out


def main() -> int:
    if not SRC.exists():
        raise SystemExit(f"missing AI source {SRC}")
    # Straight to gameplay size — NEAREST only.
    pixelize(SRC, OUT, SIZE, SIZE, pad=0.04, soft_fit=False)
    out = hard_snap(Image.open(OUT).convert("RGBA"), SIZE)
    out.save(OUT)
    n = len(out.getcolors(SIZE * SIZE) or [])
    print(f"wrote {OUT} ({SIZE}×{SIZE}, {n} colours, hard NN)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
