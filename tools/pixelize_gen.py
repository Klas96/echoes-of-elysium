#!/usr/bin/env python3
"""Downscale Cursor GenerateImage output to game-ready PNGs with alpha.

Usage:
  python3 tools/pixelize_gen.py SRC DST WIDTH HEIGHT
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image


def _is_bg(r: int, g: int, b: int) -> bool:
    if r < 18 and g < 18 and b < 18:
        return True
    if abs(r - g) < 12 and abs(g - b) < 12:
        if 90 <= r <= 210:
            return True
        if r > 235:
            return True
    return False


def remove_bg(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if _is_bg(r, g, b):
                px[x, y] = (0, 0, 0, 0)
    for cx, cy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        _flood_clear(im, cx, cy)
    return im


def _flood_clear(im: Image.Image, sx: int, sy: int) -> None:
    px = im.load()
    w, h = im.size
    r0, g0, b0, a0 = px[sx, sy]
    if a0 == 0:
        return
    if not _is_bg(r0, g0, b0) and a0 > 200:
        return
    stack = [(sx, sy)]
    seen: set[tuple[int, int]] = set()
    while stack:
        x, y = stack.pop()
        if (x, y) in seen or x < 0 or y < 0 or x >= w or y >= h:
            continue
        seen.add((x, y))
        r, g, b, a = px[x, y]
        if a == 0:
            continue
        if not _is_bg(r, g, b) and a > 40 and (abs(r - r0) + abs(g - g0) + abs(b - b0) > 48):
            continue
        px[x, y] = (0, 0, 0, 0)
        stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))


def content_bbox(im: Image.Image) -> tuple[int, int, int, int]:
    alpha = im.split()[-1]
    return alpha.getbbox() or (0, 0, im.width, im.height)


def pixelize(src: Path, dst: Path, width: int, height: int, pad: float = 0.06) -> None:
    raw = Image.open(src).convert("RGBA")
    cut = remove_bg(raw)
    box = content_bbox(cut)
    subject = cut.crop(box)
    max_w = max(1, int(width * (1 - 2 * pad)))
    max_h = max(1, int(height * (1 - 2 * pad)))
    # Soft fit then nearest snap for chunky pixels.
    subject = subject.resize((max_w * 4, max_h * 4), Image.Resampling.LANCZOS)
    subject = subject.resize((max_w, max_h), Image.Resampling.NEAREST)
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ox = (width - subject.width) // 2
    oy = (height - subject.height) // 2
    out.paste(subject, (ox, oy), subject)
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst, "PNG")
    print(f"Wrote {dst} ({width}x{height})")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("width", type=int)
    ap.add_argument("height", type=int)
    args = ap.parse_args()
    pixelize(Path(args.src), Path(args.dst), args.width, args.height)
    return 0


if __name__ == "__main__":
    sys.exit(main())
