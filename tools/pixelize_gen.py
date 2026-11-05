#!/usr/bin/env python3
"""Downscale Cursor GenerateImage output to game-ready PNGs with alpha.

Usage:
  python3 tools/pixelize_gen.py SRC DST WIDTH HEIGHT [--hard]
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


def pixelize_rgba(
    src: Path,
    width: int,
    height: int,
    pad: float = 0.06,
    *,
    cover: bool = False,
    soft_fit: bool = True,
) -> Image.Image:
    """AI gen → sized RGBA.

    cover=True fills the box (aspect-preserving crop) — used for continuous beds.
    soft_fit=True (legacy): LANCZOS upsample then NEAREST.
    soft_fit=False: NEAREST only — hard pixel gameplay tiles.
    """
    raw = Image.open(src).convert("RGBA")
    cut = remove_bg(raw)
    box = content_bbox(cut)
    subject = cut.crop(box)
    max_w = max(1, int(width * (1 - 2 * pad)))
    max_h = max(1, int(height * (1 - 2 * pad)))
    sw, sh = subject.size
    if cover:
        scale = max(max_w / sw, max_h / sh)
        if soft_fit:
            nw = max(1, int(sw * scale * 4))
            nh = max(1, int(sh * scale * 4))
            subject = subject.resize((nw, nh), Image.Resampling.LANCZOS)
            fw, fh = max(1, nw // 4), max(1, nh // 4)
            subject = subject.resize((fw, fh), Image.Resampling.NEAREST)
        else:
            nw = max(1, int(round(sw * scale)))
            nh = max(1, int(round(sh * scale)))
            subject = subject.resize((nw, nh), Image.Resampling.NEAREST)
        if subject.width > width or subject.height > height:
            cx = max(0, (subject.width - width) // 2)
            cy = max(0, (subject.height - height) // 2)
            subject = subject.crop(
                (cx, cy, cx + min(width, subject.width), cy + min(height, subject.height))
            )
    elif soft_fit:
        subject = subject.resize((max_w * 4, max_h * 4), Image.Resampling.LANCZOS)
        subject = subject.resize((max_w, max_h), Image.Resampling.NEAREST)
    else:
        # Preserve aspect; NEAREST only — no soft intermediate.
        scale = min(max_w / sw, max_h / sh)
        nw = max(1, int(round(sw * scale)))
        nh = max(1, int(round(sh * scale)))
        subject = subject.resize((nw, nh), Image.Resampling.NEAREST)
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ox = (width - subject.width) // 2
    oy = (height - subject.height) // 2
    out.paste(subject, (ox, oy), subject)
    return out


def pixelize(
    src: Path,
    dst: Path,
    width: int,
    height: int,
    pad: float = 0.06,
    *,
    soft_fit: bool = True,
    cover: bool = False,
) -> None:
    out = pixelize_rgba(src, width, height, pad=pad, cover=cover, soft_fit=soft_fit)
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst, "PNG")
    print(f"Wrote {dst} ({width}x{height}, soft_fit={soft_fit})")


def pixelize_stack_pair(
    src: Path,
    tile: int = 32,
    pad: float = 0.02,
    *,
    soft_fit: bool = True,
) -> tuple[Image.Image, Image.Image]:
    """Pixelize one continuous tall prop to tile×(2*tile), then split head/foot.

    Beds and other 1×2 props must go through this path so the mid join has no
    independent padding gap between halves. Pass soft_fit=False for hard NN
    (cabin); default True keeps legacy tea/other soft cover path.
    """
    full = pixelize_rgba(src, tile, tile * 2, pad=pad, cover=True, soft_fit=soft_fit)
    head = full.crop((0, 0, tile, tile))
    foot = full.crop((0, tile, tile, tile * 2))
    return head, foot


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("width", type=int)
    ap.add_argument("height", type=int)
    ap.add_argument(
        "--hard",
        action="store_true",
        help="NEAREST-only (no LANCZOS soft fit) for hard pixel gameplay tiles",
    )
    args = ap.parse_args()
    pixelize(Path(args.src), Path(args.dst), args.width, args.height, soft_fit=not args.hard)
    return 0


if __name__ == "__main__":
    sys.exit(main())
