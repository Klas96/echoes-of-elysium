#!/usr/bin/env python3
"""Pixelize AI-gen ranger cabin exterior to hard 128×128 sprite.

Source: tools/buildings/gen_src/ranger_cabin_front.jpg (Cursor/AI image gen).
Uses tools/pixelize_gen.py then NEAREST + palette snap — does not invent art.
Collision / door from ranger_cabin.json stay valid.
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
SIZE = 128


def hard_snap(im: Image.Image, size: int, colours: int = 28) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a and r < 28 and g < 28 and b < 28:
                px[x, y] = (0, 0, 0, 0)
    im = im.resize((size, size), Image.Resampling.NEAREST)
    rgb = im.convert("RGB").quantize(colors=colours, method=Image.Quantize.MEDIANCUT).convert("RGBA")
    a = im.split()[-1]
    r, g, b, _ = rgb.split()
    out = Image.merge("RGBA", (r, g, b, a))
    px = out.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            if a < 128:
                px[x, y] = (0, 0, 0, 0)
            else:
                px[x, y] = (r, g, b, 255)
    return out


def main() -> int:
    if not SRC.exists():
        raise SystemExit(f"missing AI source {SRC}")
    raw = SRC.with_suffix(".raw.png")
    pixelize(SRC, raw, SIZE * 4, SIZE * 4, pad=0.04)
    out = hard_snap(Image.open(raw).convert("RGBA"), SIZE)
    raw.unlink(missing_ok=True)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT)
    n = len(out.getcolors(SIZE * SIZE) or [])
    print(f"wrote {OUT} ({n} colours)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
