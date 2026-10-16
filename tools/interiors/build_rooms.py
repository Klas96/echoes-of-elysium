#!/usr/bin/env python3
"""Bake Kaela-scale tiled interiors (#62).

Rooms are small top-down maps on a 12x8 grid of 32px tiles (384x256), the
same pixel density as the overworld and as Kaela (32px). One tileset:

  assets/images/interiors/tileset.png   16 columns, 32px, spacing 0 margin 0

Each room JSON is the map: `floor` (opaque ground and walls) and `props`
(transparent furniture, 0 = empty). Collision rects are the wall tiles, the
pool, and solid props — rugs and ferns do not block. NPCs stand on a floor
tile; the game blocks that tile itself.

    python3 tools/interiors/build_rooms.py

Rewrites tileset.png, each room PNG, and each room JSON. Deterministic.
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "images" / "interiors"
T = 32
COLS = 16
W, H = 12, 8

# --- palette (same family as the painted rooms, fewer colours) ---
def rgba(r: int, g: int, b: int, a: int = 255) -> tuple[int, int, int, int]:
    return (r, g, b, a)


INK = rgba(16, 10, 8)
WD = rgba(58, 36, 22)
WM = rgba(96, 62, 38)
WL = rgba(142, 98, 60)
WH = rgba(186, 142, 96)
FD = rgba(78, 50, 30)
FM = rgba(112, 74, 44)
FL = rgba(146, 102, 64)
PD = rgba(86, 54, 78)
PM = rgba(128, 82, 112)
PL = rgba(172, 126, 154)
CREAM = rgba(236, 216, 180)
GOLD = rgba(212, 168, 72)
BRASS = rgba(176, 140, 64)
FIRE = rgba(228, 112, 36)
FLAME = rgba(255, 196, 84)
EMBER = rgba(120, 48, 28)
NEON = rgba(255, 92, 156)
NEON_D = rgba(120, 32, 72)
CD = rgba(14, 28, 40)
CM = rgba(32, 58, 74)
CL = rgba(72, 118, 132)
CYAN = rgba(160, 232, 238)
CYAN_D = rgba(48, 120, 140)
MOSS = rgba(42, 112, 74)
MOSS_L = rgba(86, 156, 96)
SD = rgba(34, 30, 42)
SM = rgba(58, 52, 68)
SL = rgba(98, 90, 112)
PURP = rgba(156, 110, 186)
PAPER = rgba(236, 220, 188)
TEA = rgba(186, 176, 160)
RED = rgba(168, 64, 58)
RED_L = rgba(210, 96, 88)
GREEN = rgba(70, 120, 78)
GREEN_L = rgba(120, 164, 110)
WHITE = rgba(244, 236, 220)
SHADOW = rgba(0, 0, 0, 80)


def blank(alpha: int = 0) -> Image.Image:
    return Image.new("RGBA", (T, T), (0, 0, 0, alpha))


def fill(im: Image.Image, x: int, y: int, w: int, h: int, c: tuple[int, int, int, int]) -> None:
    if w <= 0 or h <= 0:
        return
    ImageDraw.Draw(im).rectangle([x, y, x + w - 1, y + h - 1], fill=c)


def pix(im: Image.Image, x: int, y: int, c: tuple[int, int, int, int]) -> None:
    if 0 <= x < T and 0 <= y < T:
        im.putpixel((x, y), c)


def disc(im: Image.Image, cx: int, cy: int, r: int, c: tuple[int, int, int, int]) -> None:
    r2 = r * r
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r2:
                pix(im, x, y, c)


def wood_floor(alt: int) -> Image.Image:
    im = blank(255)
    cols = (FM, FL, FD, FM) if alt == 0 else (FD, FM, FL, FD)
    for i, y in enumerate((0, 8, 16, 24)):
        c = cols[i]
        fill(im, 0, y, T, 8, c)
        fill(im, 0, y, T, 1, WD)
        fill(im, 0, y + 1, T, 1, WL if alt == 0 else WM)
        end = 6 + ((i * 9 + alt * 5) % 18)
        fill(im, end, y, 1, 8, WD)
        pix(im, end + 4, y + 4, WD)
        pix(im, (end * 2) % 28 + 2, y + 6, WL)
    return im


def noodle_floor(alt: int) -> Image.Image:
    im = blank(255)
    base = rgba(154, 114, 78) if alt == 0 else rgba(138, 100, 68)
    grout = rgba(72, 48, 32)
    fill(im, 0, 0, T, T, base)
    fill(im, 0, 0, T, 1, grout)
    fill(im, 0, 0, 1, T, grout)
    fill(im, 0, 16, T, 1, grout)
    fill(im, 16, 0, 1, T, grout)
    speck = WD if alt else WM
    for x, y in ((6, 6), (22, 8), (10, 24), (24, 22)):
        pix(im, x, y, speck)
    return im


def cabin_floor(alt: int) -> Image.Image:
    im = blank(255)
    a = rgba(96, 78, 48) if alt == 0 else rgba(84, 68, 42)
    b = rgba(112, 90, 54) if alt == 0 else rgba(100, 80, 48)
    fill(im, 0, 0, T, T, a)
    for y in range(0, T, 8):
        fill(im, 0, y, T, 1, rgba(62, 48, 28))
        fill(im, 0, y + 1, T, 1, b)
        fill(im, (y * 3 + alt * 7) % 26, y, 1, 8, rgba(62, 48, 28))
    # moss in the cracks
    if alt:
        pix(im, 4, 18, MOSS)
        pix(im, 5, 18, MOSS_L)
        pix(im, 27, 7, MOSS)
    return im


def stone_floor(alt: int) -> Image.Image:
    im = blank(255)
    fill(im, 0, 0, T, T, SD)
    blocks = ((1, 1, 14, 14), (17, 1, 14, 14), (1, 17, 14, 14), (17, 17, 14, 14))
    for i, (x, y, w, h) in enumerate(blocks):
        c = SM if (i + alt) % 2 == 0 else rgba(68, 60, 80)
        fill(im, x, y, w, h, c)
        fill(im, x, y, w, 1, SL)
    if alt:
        pix(im, 8, 8, PURP)
        pix(im, 24, 22, CYAN_D)
    return im


def cave_floor(alt: int) -> Image.Image:
    im = blank(255)
    fill(im, 0, 0, T, T, CD if alt == 0 else rgba(18, 36, 48))
    # wet rock facets
    fill(im, 2, 4, 10, 6, CM)
    fill(im, 16, 14, 12, 8, rgba(24, 48, 62))
    fill(im, 6, 22, 8, 5, CM)
    pix(im, 8, 6, CL)
    pix(im, 20, 18, CL)
    if alt:
        pix(im, 14, 24, MOSS)
        pix(im, 15, 25, MOSS_L)
    return im


def pool() -> Image.Image:
    im = blank(255)
    fill(im, 0, 0, T, T, rgba(10, 36, 52))
    fill(im, 2, 4, 28, 24, rgba(16, 64, 84))
    fill(im, 6, 8, 12, 3, rgba(48, 110, 130, 220))
    pix(im, 22, 12, CYAN)
    pix(im, 10, 18, CL)
    return im


def moss_floor() -> Image.Image:
    im = cave_floor(1)
    fill(im, 4, 18, 24, 8, MOSS)
    fill(im, 8, 16, 10, 4, MOSS_L)
    pix(im, 12, 20, rgba(180, 220, 140))
    return im


def mat(cave: bool = False) -> Image.Image:
    im = (cave_floor(0) if cave else wood_floor(0)).copy()
    # open night beyond the sill, coir mat on the near side
    fill(im, 0, 22, T, 10, rgba(6, 6, 10) if not cave else rgba(4, 8, 14))
    fill(im, 0, 20, T, 2, WD if not cave else CM)
    fill(im, 6, 8, 20, 12, rgba(120, 86, 48) if not cave else rgba(40, 56, 48))
    fill(im, 6, 8, 20, 1, WH if not cave else MOSS_L)
    for x in range(8, 24, 3):
        pix(im, x, 12, INK)
        pix(im, x + 1, 15, INK)
    return im


def wall_panels(base: tuple[int, int, int, int], trim: tuple[int, int, int, int], beam: tuple[int, int, int, int]) -> Image.Image:
    im = blank(255)
    fill(im, 0, 0, T, T, base)
    fill(im, 0, 0, T, 5, beam)
    fill(im, 0, 5, T, 2, trim)
    for x in (3, 15, 26):
        fill(im, x, 8, 3, 22, trim)
    fill(im, 7, 12, 7, 12, beam)
    fill(im, 19, 12, 6, 12, beam)
    return im


def tea_wall() -> Image.Image:
    return wall_panels(WD, WM, rgba(40, 24, 16))


def tea_window() -> Image.Image:
    im = tea_wall()
    disc(im, 16, 18, 8, rgba(64, 40, 56))
    disc(im, 16, 18, 6, rgba(186, 140, 150))
    disc(im, 16, 18, 3, CREAM)
    # muntins
    fill(im, 15, 11, 1, 14, WD)
    fill(im, 10, 17, 12, 1, WD)
    # lantern under the beam
    fill(im, 23, 7, 4, 5, CREAM)
    pix(im, 24, 8, FLAME)
    return im


def noodle_wall() -> Image.Image:
    im = wall_panels(rgba(72, 40, 28), rgba(110, 64, 42), rgba(48, 26, 18))
    # stripe of awning along the top
    for x in range(0, T, 4):
        fill(im, x, 0, 2, 4, RED_L)
    return im


def neon_wall() -> Image.Image:
    im = noodle_wall()
    fill(im, 7, 14, 18, 8, NEON_D)
    fill(im, 9, 16, 14, 4, NEON)
    pix(im, 12, 17, WHITE)
    pix(im, 18, 17, WHITE)
    return im


def log_wall() -> Image.Image:
    im = blank(255)
    bark = (rgba(72, 48, 28), rgba(96, 64, 36), rgba(64, 42, 24))
    for i, y in enumerate((0, 11, 22)):
        h = 10 if i < 2 else 10
        fill(im, 0, y, T, h, bark[i])
        fill(im, 0, y, T, 1, rgba(140, 100, 60))
        fill(im, 0, y + h - 1, T, 1, rgba(36, 22, 14))
        # knot
        disc(im, 8 + i * 7, y + 5, 2, rgba(48, 30, 18))
    return im


def fire_wall() -> Image.Image:
    im = log_wall()
    fill(im, 6, 6, 20, 22, rgba(40, 26, 22))
    fill(im, 8, 16, 16, 10, rgba(24, 14, 12))
    disc(im, 16, 16, 6, FIRE)
    disc(im, 16, 14, 3, FLAME)
    pix(im, 14, 10, FLAME)
    pix(im, 18, 11, CREAM)
    fill(im, 4, 26, 24, 5, rgba(80, 76, 72))
    return im


def map_wall() -> Image.Image:
    im = log_wall()
    fill(im, 3, 5, 26, 22, rgba(176, 154, 100))
    fill(im, 3, 5, 26, 1, rgba(96, 72, 40))
    fill(im, 6, 10, 12, 2, MOSS)
    fill(im, 16, 12, 2, 10, rgba(120, 80, 48))
    pix(im, 20, 10, RED)
    pix(im, 10, 18, rgba(40, 80, 120))
    pix(im, 22, 18, RED)
    return im


def books_wall() -> Image.Image:
    im = blank(255)
    fill(im, 0, 0, T, T, rgba(28, 22, 32))
    spines = (
        PURP, rgba(120, 70, 60), CYAN_D, rgba(90, 70, 50),
        PL, rgba(70, 90, 80), GOLD, rgba(80, 50, 70),
    )
    for shelf_y in (2, 12, 22):
        fill(im, 0, shelf_y + 8, T, 2, SM)
        x = 1
        for i, c in enumerate(spines):
            fill(im, x, shelf_y, 3, 8, c)
            pix(im, x + 1, shelf_y + 2, CREAM if i % 2 == 0 else WHITE)
            x += 4
    return im


def cave_wall() -> Image.Image:
    im = blank(255)
    fill(im, 0, 0, T, T, rgba(10, 18, 28))
    disc(im, 8, 10, 8, rgba(28, 44, 58))
    disc(im, 22, 16, 10, rgba(20, 36, 48))
    disc(im, 14, 26, 7, rgba(32, 52, 64))
    pix(im, 8, 8, CL)
    pix(im, 24, 14, rgba(20, 24, 32))
    return im


def drip_wall() -> Image.Image:
    im = cave_wall()
    for x, y in ((14, 6), (15, 10), (16, 16), (15, 22), (14, 28)):
        pix(im, x, y, CYAN)
        pix(im, x, y + 1, CL)
    return im


def jamb(base_fn, side: str, post: tuple[int, int, int, int] = WH) -> Image.Image:
    """Door post on the inner edge. side 'l' is the left jamb (post on the right)."""
    im = base_fn().copy()
    if side == "l":
        fill(im, 26, 0, 6, T, INK)
        fill(im, 27, 0, 4, T, post)
        fill(im, 27, 0, 1, T, CREAM)
    else:
        fill(im, 0, 0, 6, T, INK)
        fill(im, 1, 0, 4, T, post)
        fill(im, 4, 0, 1, T, CREAM)
    return im


def _shadow(im: Image.Image, x: int, y: int, w: int, h: int = 3) -> None:
    fill(im, x, y, w, h, SHADOW)


def counter(kind: str = "plain") -> Image.Image:
    """Counter top sits at Kaela's shoulder when she stands on the tile south."""
    im = blank()
    _shadow(im, 3, 29, 26)
    # top
    fill(im, 2, 18, 28, 5, WL)
    fill(im, 2, 18, 28, 1, WH)
    # front face ~ mid torso (short)
    fill(im, 2, 23, 28, 7, WM)
    fill(im, 2, 23, 28, 1, WD)
    fill(im, 6, 25, 6, 4, WD)
    fill(im, 18, 25, 6, 4, WD)
    if kind == "urn":
        fill(im, 3, 11, 6, 7, TEA)
        fill(im, 11, 8, 10, 10, BRASS)
        fill(im, 13, 6, 6, 3, GOLD)
        fill(im, 22, 11, 6, 7, RED)
    elif kind == "pots":
        disc(im, 10, 16, 5, rgba(70, 68, 76))
        disc(im, 22, 16, 5, rgba(86, 82, 90))
        fill(im, 8, 20, 6, 2, FIRE)
        fill(im, 20, 20, 6, 2, EMBER)
        pix(im, 10, 10, WHITE)
        pix(im, 11, 8, rgba(220, 220, 230, 200))
        pix(im, 22, 9, WHITE)
    elif kind == "tin":
        fill(im, 11, 12, 10, 7, RED)
        fill(im, 12, 14, 8, 2, CREAM)
        pix(im, 15, 17, WHITE)
    return im


def table() -> Image.Image:
    im = blank()
    _shadow(im, 6, 28, 20, 2)
    fill(im, 6, 20, 20, 4, WL)
    fill(im, 6, 20, 20, 1, WH)
    fill(im, 6, 24, 20, 4, WM)
    # cups
    disc(im, 12, 21, 2, CREAM)
    disc(im, 20, 21, 2, rgba(120, 150, 110))
    return im


def cushion() -> Image.Image:
    im = blank()
    disc(im, 16, 22, 7, PD)
    disc(im, 16, 22, 5, PM)
    pix(im, 16, 22, PL)
    return im


def bed(head: bool, cabin: bool = False) -> Image.Image:
    im = blank()
    blanket = GREEN if cabin else PM
    blanket_l = GREEN_L if cabin else PL
    wood = rgba(90, 64, 40)
    if head:
        _shadow(im, 4, 29, 24, 2)
        fill(im, 3, 12, 26, 5, rgba(36, 22, 14))  # headboard
        fill(im, 5, 16, 22, 6, CREAM)
        fill(im, 4, 22, 24, 8, blanket)
        fill(im, 8, 24, 5, 3, blanket_l)
    else:
        _shadow(im, 4, 28, 24, 2)
        fill(im, 4, 0, 24, 22, blanket)
        fill(im, 4, 22, 24, 6, wood)  # footboard
        fill(im, 10, 6, 5, 3, blanket_l)
        fill(im, 16, 12, 4, 3, CREAM if not cabin else rgba(200, 190, 140))
    return im


def plant() -> Image.Image:
    im = blank()
    fill(im, 12, 22, 8, 7, rgba(140, 90, 54))
    fill(im, 14, 20, 4, 3, rgba(90, 60, 40))
    disc(im, 16, 14, 6, GREEN)
    disc(im, 12, 16, 4, GREEN_L)
    disc(im, 20, 15, 3, rgba(40, 90, 54))
    return im


def screen() -> Image.Image:
    im = blank()
    # person-tall folding screen: three panels
    for i, x in enumerate((4, 12, 20)):
        fill(im, x, 6, 7, 22, PD if i != 1 else PM)
        fill(im, x, 6, 7, 1, PL)
        fill(im, x + 2, 12, 3, 8, rgba(200, 170, 180) if i == 1 else rgba(90, 60, 70))
    return im


def chest() -> Image.Image:
    im = blank()
    _shadow(im, 5, 28, 22, 2)
    fill(im, 5, 16, 22, 12, rgba(110, 72, 40))
    fill(im, 5, 16, 22, 3, rgba(140, 96, 52))
    fill(im, 14, 20, 4, 3, GOLD)
    fill(im, 5, 21, 22, 1, WD)
    return im


def desk(with_draft: bool) -> Image.Image:
    im = blank()
    _shadow(im, 3, 29, 26, 2)
    fill(im, 3, 18, 26, 5, rgba(110, 78, 48))
    fill(im, 3, 23, 26, 6, rgba(72, 50, 34))
    if with_draft:
        # brittle page — the TAKE target (#59 reads it; kept at one tile)
        fill(im, 8, 12, 14, 10, PAPER)
        fill(im, 8, 12, 14, 1, WHITE)
        for y in (15, 17, 19):
            fill(im, 10, y, 8, 1, rgba(90, 70, 60))
        pix(im, 18, 19, PURP)
    else:
        # open journal
        fill(im, 8, 13, 14, 8, PAPER)
        fill(im, 15, 13, 1, 8, rgba(90, 70, 60))
        fill(im, 10, 16, 4, 1, rgba(80, 60, 50))
        fill(im, 17, 15, 4, 1, rgba(80, 60, 50))
    return im


def note() -> Image.Image:
    im = blank()
    _shadow(im, 8, 26, 16, 2)
    fill(im, 9, 14, 14, 12, PAPER)
    fill(im, 11, 17, 10, 1, rgba(90, 70, 60))
    fill(im, 11, 20, 7, 1, rgba(90, 70, 60))
    pix(im, 12, 22, RED)
    return im


def lamp() -> Image.Image:
    im = blank()
    fill(im, 11, 16, 10, 7, CREAM)
    fill(im, 12, 18, 8, 3, FLAME)
    fill(im, 15, 23, 2, 4, WM)
    fill(im, 11, 27, 10, 3, GOLD)
    return im


def crate() -> Image.Image:
    im = blank()
    _shadow(im, 6, 28, 20, 2)
    fill(im, 6, 14, 20, 14, rgba(120, 82, 46))
    fill(im, 6, 14, 20, 2, rgba(156, 112, 64))
    fill(im, 6, 20, 20, 1, WD)
    fill(im, 15, 16, 1, 10, WD)
    return im


def fridge() -> Image.Image:
    im = blank()
    fill(im, 8, 4, 16, 26, rgba(150, 164, 170))
    fill(im, 8, 4, 16, 2, rgba(190, 200, 206))
    fill(im, 8, 16, 16, 1, rgba(90, 100, 108))
    fill(im, 20, 10, 2, 3, rgba(60, 70, 78))
    fill(im, 20, 20, 2, 3, rgba(60, 70, 78))
    return im


def bowl() -> Image.Image:
    im = blank()
    _shadow(im, 6, 28, 20, 2)
    fill(im, 5, 20, 22, 4, rgba(120, 48, 42))
    fill(im, 5, 20, 22, 1, RED_L)
    disc(im, 16, 20, 6, CREAM)
    disc(im, 16, 20, 3, rgba(220, 200, 140))
    # chopsticks
    fill(im, 22, 16, 1, 8, WM)
    return im


def crystal() -> Image.Image:
    im = blank()
    fill(im, 8, 22, 16, 6, SM)
    fill(im, 10, 22, 12, 1, SL)
    # shard, shorter than Kaela
    fill(im, 14, 8, 4, 14, CYAN)
    fill(im, 12, 12, 8, 8, rgba(190, 245, 248))
    pix(im, 15, 10, WHITE)
    pix(im, 18, 14, CYAN_D)
    return im


def rock() -> Image.Image:
    im = blank()
    disc(im, 16, 22, 8, rgba(36, 48, 58))
    disc(im, 14, 20, 5, rgba(58, 74, 86))
    pix(im, 12, 18, CL)
    return im


def logs() -> Image.Image:
    im = blank()
    fill(im, 4, 18, 24, 6, rgba(96, 64, 36))
    fill(im, 4, 24, 24, 5, rgba(72, 48, 28))
    for x in (8, 14, 20):
        disc(im, x, 20, 2, rgba(140, 100, 64))
    return im


def nightstand() -> Image.Image:
    im = blank()
    _shadow(im, 8, 28, 16, 2)
    fill(im, 8, 18, 16, 4, WL)
    fill(im, 8, 22, 16, 6, WM)
    # candle
    fill(im, 14, 12, 4, 6, CREAM)
    pix(im, 15, 10, FLAME)
    return im


def stool() -> Image.Image:
    im = blank()
    fill(im, 10, 20, 12, 3, WM)
    fill(im, 12, 23, 2, 6, WD)
    fill(im, 18, 23, 2, 6, WD)
    return im


def rug() -> Image.Image:
    # Full-bleed on the sides so neighbouring rug tiles read as one carpet.
    im = blank()
    fill(im, 0, 8, T, 18, PD)
    fill(im, 0, 10, T, 14, PM)
    fill(im, 14, 15, 4, 4, PL)
    return im


def lectern() -> Image.Image:
    im = blank()
    fill(im, 10, 22, 12, 7, rgba(70, 52, 40))
    fill(im, 6, 14, 20, 8, rgba(90, 64, 44))
    fill(im, 8, 15, 16, 5, PAPER)
    fill(im, 10, 17, 8, 1, rgba(80, 60, 50))
    return im


def glyph() -> Image.Image:
    im = blank()
    disc(im, 16, 20, 8, SM)
    disc(im, 16, 20, 5, rgba(40, 80, 96))
    disc(im, 16, 18, 3, CYAN)
    pix(im, 16, 18, WHITE)
    return im


def barrel() -> Image.Image:
    im = blank()
    fill(im, 10, 12, 12, 16, rgba(110, 72, 40))
    fill(im, 10, 16, 12, 2, WM)
    fill(im, 10, 22, 12, 2, WM)
    return im


def fern() -> Image.Image:
    im = blank()
    disc(im, 16, 22, 6, MOSS)
    disc(im, 12, 20, 3, MOSS_L)
    disc(im, 20, 18, 3, rgba(30, 80, 54))
    return im


# ids
WOOD, WOOD2 = 0, 1
NOODLE, NOODLE2 = 2, 3
CABIN, CABIN2 = 4, 5
STONE, STONE2 = 6, 7
CAVE, CAVE2 = 8, 9
POOL, MOSS_F = 10, 11
MAT, MAT_CAVE = 12, 13
W_TEA, W_TEA_WIN = 16, 17
W_NOODLE, W_NEON = 18, 19
W_LOG, W_FIRE = 20, 21
W_BOOKS, W_CAVE = 22, 23
W_MAP, W_DRIP = 24, 25
J_TEA_L, J_TEA_R = 26, 27
J_NOODLE_L, J_NOODLE_R = 28, 29
J_LOG_L, J_LOG_R = 30, 31
J_CAVE_L, J_CAVE_R = 32, 33
J_BOOK_L, J_BOOK_R = 34, 35
COUNTER, URN, POTS, TIN = 40, 41, 42, 43
TABLE, CUSHION = 44, 45
BED_H, BED_F = 46, 47
PLANT, SCREEN = 48, 49
CHEST, DESK, JOURNAL, NOTE = 50, 51, 52, 53
LAMP, CRATE, FRIDGE, BOWL = 54, 55, 56, 57
CRYSTAL, ROCK, LOGS, NIGHT = 58, 59, 60, 61
STOOL, RUG = 62, 63
BED_C_H, BED_C_F = 64, 65
LECTERN, GLYPH = 66, 67
BARREL, FERN = 68, 69

WALLS = set(range(16, 36))
SOLID_FLOOR = WALLS | {POOL}
SOLID_PROPS = {
    COUNTER, URN, POTS, TIN, TABLE, CUSHION, BED_H, BED_F, PLANT, SCREEN,
    CHEST, DESK, JOURNAL, NOTE, LAMP, CRATE, FRIDGE, BOWL, CRYSTAL, ROCK,
    LOGS, NIGHT, STOOL, BED_C_H, BED_C_F, LECTERN, GLYPH, BARREL,
}


def build_sheet() -> Image.Image:
    tiles: dict[int, Image.Image] = {
        WOOD: wood_floor(0), WOOD2: wood_floor(1),
        NOODLE: noodle_floor(0), NOODLE2: noodle_floor(1),
        CABIN: cabin_floor(0), CABIN2: cabin_floor(1),
        STONE: stone_floor(0), STONE2: stone_floor(1),
        CAVE: cave_floor(0), CAVE2: cave_floor(1),
        POOL: pool(), MOSS_F: moss_floor(),
        MAT: mat(False), MAT_CAVE: mat(True),
        W_TEA: tea_wall(), W_TEA_WIN: tea_window(),
        W_NOODLE: noodle_wall(), W_NEON: neon_wall(),
        W_LOG: log_wall(), W_FIRE: fire_wall(),
        W_BOOKS: books_wall(), W_CAVE: cave_wall(),
        W_MAP: map_wall(), W_DRIP: drip_wall(),
        J_TEA_L: jamb(tea_wall, "l", WH), J_TEA_R: jamb(tea_wall, "r", WH),
        J_NOODLE_L: jamb(noodle_wall, "l", WH), J_NOODLE_R: jamb(noodle_wall, "r", WH),
        J_LOG_L: jamb(log_wall, "l", rgba(140, 100, 60)), J_LOG_R: jamb(log_wall, "r", rgba(140, 100, 60)),
        J_CAVE_L: jamb(cave_wall, "l", CL), J_CAVE_R: jamb(cave_wall, "r", CL),
        J_BOOK_L: jamb(books_wall, "l", SL), J_BOOK_R: jamb(books_wall, "r", SL),
        COUNTER: counter(), URN: counter("urn"), POTS: counter("pots"), TIN: counter("tin"),
        TABLE: table(), CUSHION: cushion(),
        BED_H: bed(True), BED_F: bed(False),
        PLANT: plant(), SCREEN: screen(),
        CHEST: chest(), DESK: desk(True), JOURNAL: desk(False), NOTE: note(),
        LAMP: lamp(), CRATE: crate(), FRIDGE: fridge(), BOWL: bowl(),
        CRYSTAL: crystal(), ROCK: rock(), LOGS: logs(), NIGHT: nightstand(),
        STOOL: stool(), RUG: rug(),
        BED_C_H: bed(True, cabin=True), BED_C_F: bed(False, cabin=True),
        LECTERN: lectern(), GLYPH: glyph(),
        BARREL: barrel(), FERN: fern(),
    }
    rows = max(tiles) // COLS + 1
    sheet = Image.new("RGBA", (COLS * T, rows * T), (0, 0, 0, 0))
    for i, tile in tiles.items():
        sheet.alpha_composite(tile, ((i % COLS) * T, (i // COLS) * T))
    return sheet


SHEET: Image.Image | None = None


def blit_tile(dst: Image.Image, tid: int, x: int, y: int) -> None:
    assert SHEET is not None
    src = SHEET.crop(((tid % COLS) * T, (tid // COLS) * T, (tid % COLS) * T + T, (tid // COLS) * T + T))
    dst.alpha_composite(src, (x * T, y * T))


def shell(wall: int, floor: int, mat_id: int, jamb_l: int, jamb_r: int) -> tuple[list[list[int]], list[list[int]]]:
    F = [[floor for _ in range(W)] for _ in range(H)]
    for y in range(H):
        for x in range(W):
            edge = x == 0 or x == W - 1 or y == 0 or y >= H - 2
            if edge:
                F[y][x] = wall
    # Door gap is two tiles (Kaela is one). Mat is the leave trigger.
    # One-tile-tall frame: Kaela (32px) fills the doorway. The mat row is the
    # leave trigger; the tile north of it is still inside.
    F[H - 2][5] = floor
    F[H - 2][6] = floor
    F[H - 1][5] = mat_id
    F[H - 1][6] = mat_id
    F[H - 1][4] = jamb_l
    F[H - 1][7] = jamb_r
    P = [[0 for _ in range(W)] for _ in range(H)]
    return F, P


def vary(F: list[list[int]], base: int, alt: int) -> None:
    for y in range(H):
        for x in range(W):
            if F[y][x] == base and (x * 3 + y * 5) % 4 == 0:
                F[y][x] = alt


def solid_map(F: list[list[int]], P: list[list[int]]) -> list[list[bool]]:
    return [
        [F[y][x] in SOLID_FLOOR or P[y][x] in SOLID_PROPS for x in range(W)]
        for y in range(H)
    ]


def merge_rects(mask: list[list[bool]]) -> list[list[int]]:
    seen = [[False] * W for _ in range(H)]
    out: list[list[int]] = []
    for y in range(H):
        for x in range(W):
            if not mask[y][x] or seen[y][x]:
                continue
            w = 1
            while x + w < W and mask[y][x + w] and not seen[y][x + w]:
                w += 1
            h = 1
            while y + h < H and all(mask[y + h][x + dx] and not seen[y + h][x + dx] for dx in range(w)):
                h += 1
            for dy in range(h):
                for dx in range(w):
                    seen[y + dy][x + dx] = True
            out.append([x, y, w, h])
    return out


def reachable(mask: list[list[bool]], spawn: tuple[int, int]) -> set[tuple[int, int]]:
    if mask[spawn[1]][spawn[0]]:
        return set()
    seen = {spawn}
    q = [spawn]
    while q:
        x, y = q.pop(0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n in seen:
                continue
            if not (0 <= n[0] < W and 0 <= n[1] < H) or mask[n[1]][n[0]]:
                continue
            seen.add(n)
            q.append(n)
    return seen


def approaches(mask: list[list[bool]], rect: list[int]) -> set[tuple[int, int]]:
    x, y, w, h = rect
    cells = {(x + dx, y + dy) for dy in range(h) for dx in range(w)}
    out: set[tuple[int, int]] = set()
    for cx, cy in cells:
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (cx + dx, cy + dy)
            if (dx or dy) and n in cells:
                continue
            if 0 <= n[0] < W and 0 <= n[1] < H and not mask[n[1]][n[0]]:
                out.add(n)
    return out


def check(room: dict) -> None:
    F, P = room["floor"], room["props"]
    mask = solid_map(F, P)
    for n in room["npcs"]:
        tx, ty = n["tile"]
        if mask[ty][tx]:
            raise SystemExit(f"{room['id']}: NPC {n['name']} stands inside a solid tile {tx},{ty}")
        mask[ty][tx] = True
    spawn = tuple(room["spawn"])
    door = room["door"]
    door_cells = {(door[0] + dx, door[1] + dy) for dy in range(door[3]) for dx in range(door[2])}
    floor = reachable(mask, spawn)  # type: ignore[arg-type]
    if spawn not in floor:
        raise SystemExit(f"{room['id']}: spawn {spawn} sealed")
    if not door_cells & floor:
        raise SystemExit(f"{room['id']}: door unreachable")
    x, y = spawn
    steps = 0
    while (x, y) not in door_cells:
        if (x, y) not in floor:
            raise SystemExit(f"{room['id']}: blocked on the way to the mat at {x},{y}")
        y += 1
        steps += 1
        if steps > 4:
            raise SystemExit(f"{room['id']}: mat is not just south of spawn")
    if len(floor) < 20:
        raise SystemExit(f"{room['id']}: only {len(floor)} walkable tiles")
    for s in room["interact"]:
        if not approaches(mask, s["rect"]) & floor:
            raise SystemExit(f"{room['id']}: spot {s['id']} unreachable {s['rect']}")
    room["walkable_tiles"] = len(floor)


def render(F: list[list[int]], P: list[list[int]]) -> Image.Image:
    img = Image.new("RGBA", (W * T, H * T), (0, 0, 0, 255))
    for y in range(H):
        for x in range(W):
            blit_tile(img, F[y][x], x, y)
            if P[y][x]:
                blit_tile(img, P[y][x], x, y)
    return img


def room(rid: str, title: str, F, P, spots, npcs, lights) -> dict:
    mask = solid_map(F, P)
    data = {
        "id": rid,
        "title": title,
        "image": f"{rid}.png",
        "tileset": "tileset.png",
        "sheetCols": COLS,
        "size": [W, H],
        "tile": T,
        "floor": F,
        "props": P,
        "collision": merge_rects(mask),
        "door": [5, 7, 2, 1],
        "spawn": [5, 5],
        "npcs": npcs,
        "interact": spots,
        "lights": lights,
    }
    check(data)
    return data


def tea() -> dict:
    F, P = shell(W_TEA, WOOD, MAT, J_TEA_L, J_TEA_R)
    for x in (4, 5, 6):
        F[0][x] = W_TEA_WIN
    vary(F, WOOD, WOOD2)
    P[1][1], P[1][2], P[1][3] = URN, COUNTER, COUNTER
    P[1][8] = TABLE
    P[1][10] = BED_H
    P[2][6] = CUSHION
    P[2][10] = BED_F
    P[3][1] = PLANT
    P[3][3] = SCREEN
    P[4][9] = NIGHT
    P[4][10] = PLANT
    P[4][5], P[4][6] = RUG, RUG
    return room(
        "tea_house",
        "Tea house: the inn at Lantern Gate",
        F, P,
        [
            {"id": "rest_bed", "rect": [10, 1, 1, 2], "kind": "rest",
             "note": "Wen: sleep here -> save + well_rested"},
            {"id": "ferro", "rect": [5, 1, 1, 1], "kind": "npc",
             "note": "Old Ferro: riddle / rumour"},
            {"id": "wen", "rect": [2, 2, 1, 1], "kind": "npc", "note": "Wen, host"},
            {"id": "window_seat", "rect": [4, 0, 3, 1], "kind": "flavour",
             "note": "'Lantern Road runs east from here. The lamps were lit by hand, every one.'"},
            {"id": "tea_counter", "rect": [1, 1, 3, 1], "kind": "flavour",
             "note": "The brass urn and tea tins"},
        ],
        [
            {"name": "wen", "sprite": "wen", "tile": [2, 2], "role": "host",
             "note": "Serves tea from the brass urn on the counter; first-visit / later lines in interiors-text.md"},
            {"name": "ferro", "sprite": "ferro", "tile": [5, 1], "role": "regular",
             "note": "By the round window: one riddle or rumour per in-game day"},
        ],
        [
            {"tile": [5, 0], "kind": "warm"},
            {"tile": [2, 1], "kind": "warm"},
            {"tile": [8, 1], "kind": "warm"},
            {"tile": [10, 1], "kind": "warm"},
        ],
    )


def noodle() -> dict:
    F, P = shell(W_NOODLE, NOODLE, MAT, J_NOODLE_L, J_NOODLE_R)
    F[0][1] = W_NEON
    F[0][10] = W_NEON
    vary(F, NOODLE, NOODLE2)
    P[1][1], P[1][2], P[1][3] = COUNTER, COUNTER, COUNTER
    P[1][4], P[1][5], P[1][7] = POTS, POTS, POTS
    P[1][8] = TIN
    P[1][9] = FRIDGE
    P[1][10] = CRATE
    P[2][1] = CRATE
    P[3][1] = CRATE
    P[3][3] = BOWL
    P[3][8] = BOWL
    P[3][10] = CRATE
    P[4][2] = STOOL
    P[4][9] = STOOL
    P[4][10] = BARREL
    return room(
        "noodle_shop",
        "Noodle shop on Market Row",
        F, P,
        [
            {"id": "dao", "rect": [4, 1, 4, 1], "kind": "shop",
             "note": "Dao's menu for glimmer: ember_broth (faster regen), moss_noodles (faster run), night_bowl (see creatures further at night)"},
            {"id": "dao_errand", "rect": [4, 1, 4, 1], "kind": "errand",
             "note": "Daily: bring one moonflower_bloom from the Woods -> tomorrow's bowl free"},
            {"id": "counter_tin", "rect": [8, 1, 1, 1], "kind": "flavour",
             "note": "'A tin of chopsticks. One pair is carved with a vine fox.'"},
            {"id": "tables", "rect": [3, 3, 1, 1], "kind": "flavour",
             "note": "Steaming bowls (also the right table)"},
            {"id": "tables_right", "rect": [8, 3, 1, 1], "kind": "flavour",
             "note": "Steaming bowls"},
        ],
        [
            {"name": "dao", "sprite": "dao", "tile": [6, 1], "role": "cook",
             "note": "At the pass between the pots"},
        ],
        [
            {"tile": [4, 1], "kind": "fire"},
            {"tile": [1, 0], "kind": "neon"},
            {"tile": [10, 0], "kind": "neon"},
            {"tile": [6, 2], "kind": "warm"},
        ],
    )


def ranger() -> dict:
    F, P = shell(W_LOG, CABIN, MAT, J_LOG_L, J_LOG_R)
    for x in (2, 3, 4):
        F[0][x] = W_FIRE
    for x in (5, 6, 7):
        F[0][x] = W_MAP
    vary(F, CABIN, CABIN2)
    P[1][1] = LOGS
    P[2][1] = CHEST
    P[1][8] = JOURNAL
    P[1][9] = NOTE
    P[2][10] = BED_C_H
    P[3][10] = BED_C_F
    P[4][1] = PLANT
    P[4][8] = PLANT
    P[3][5], P[3][6] = RUG, RUG
    return room(
        "ranger_cabin",
        "Ranger cabin in the Woods: Asha's place",
        F, P,
        [
            {"id": "stash_chest", "rect": [1, 2, 1, 1], "kind": "stash",
             "note": "Stash between trips (#32)"},
            {"id": "desk_journal", "rect": [8, 1, 1, 1], "kind": "journal",
             "note": "Creature journal: 'N of 24 creatures befriended'"},
            {"id": "asha_note", "rect": [9, 1, 1, 1], "kind": "note",
             "note": "'Kaela, use what you need. The chest is yours now. A.'"},
            {"id": "wall_map", "rect": [5, 0, 3, 1], "kind": "map",
             "note": "Region map: 'Asha has pinned every trail she's walked. A few are still blank.'"},
            {"id": "stove", "rect": [2, 0, 3, 1], "kind": "flavour",
             "note": "'Cold ashes and a kettle. It smells of pine.'"},
        ],
        [],
        [
            {"tile": [3, 0], "kind": "fire"},
            {"tile": [8, 1], "kind": "warm"},
            {"tile": [1, 2], "kind": "warm"},
        ],
    )


def archive() -> dict:
    F, P = shell(W_BOOKS, STONE, MAT, J_BOOK_L, J_BOOK_R)
    vary(F, STONE, STONE2)
    P[1][9] = LECTERN
    P[2][2] = GLYPH
    P[2][5] = DESK
    P[2][6] = LAMP
    P[4][4], P[4][5], P[4][6], P[4][7] = RUG, RUG, RUG, RUG
    return room(
        "archive_library",
        "Archive library (Archive Square, opened by the Archivist's seal)",
        F, P,
        [
            {"id": "book_choosing", "rect": [1, 0, 10, 1], "kind": "lore",
             "note": "Shelves: The Choosing. 'The Aetherians did not lose a war. They declined one.'"},
            {"id": "book_lattice_keys", "rect": [9, 1, 1, 1], "kind": "lore",
             "note": "Lectern tome: Lattice Keys. 'A keystone fits only a gate that remembers it.' (Ruins gate hint)"},
            {"id": "book_field_notes", "rect": [2, 2, 1, 1], "kind": "clue",
             "note": "Glyph pedestal: Field Notes, author unknown -> clue for the optional City fragment in the West Yard"},
            {"id": "merge_draft", "rect": [5, 2, 1, 1], "kind": "clue",
             "note": "First Memory Draft on the reading desk — the whisper-vote. TAKE triggers archive_ash."},
            {"id": "reading_lamp", "rect": [6, 2, 1, 1], "kind": "flavour",
             "note": "'A lamp still lit. Someone was here not long ago.'"},
            {"id": "archivist", "rect": [10, 3, 1, 1], "kind": "npc",
             "note": "The Archivist"},
        ],
        [
            {"name": "archivist", "sprite": "archivist", "tile": [10, 3], "role": "keeper",
             "note": "'Few walk in here who aren't already dust. Read gently.'"},
        ],
        [
            {"tile": [6, 2], "kind": "warm"},
            {"tile": [2, 2], "kind": "cyan"},
        ],
    )


def grotto() -> dict:
    F, P = shell(W_CAVE, CAVE, MAT_CAVE, J_CAVE_L, J_CAVE_R)
    F[0][2] = W_DRIP
    F[0][3] = W_DRIP
    vary(F, CAVE, CAVE2)
    for x in range(5, 9):
        F[4][x] = POOL
    F[3][3] = MOSS_F
    F[3][4] = MOSS_F
    P[1][6] = CRYSTAL
    P[2][2] = ROCK
    P[2][9] = ROCK
    P[3][1] = FERN
    P[3][10] = FERN
    P[5][1] = ROCK
    P[5][10] = ROCK
    return room(
        "pond_grotto",
        "Pond grotto: a lit cave by the water",
        F, P,
        [
            {"id": "pond_fragment", "rect": [6, 1, 1, 1], "kind": "clue",
             "note": "A memory fragment rests in the crystal alcove."},
            {"id": "drip_wall", "rect": [2, 0, 2, 1], "kind": "flavour",
             "note": "Water ticks from the stone. The Light still hums in the moss."},
            {"id": "pool_edge", "rect": [5, 4, 4, 1], "kind": "flavour",
             "note": "A shallow pool mirrors the mouth you came through."},
        ],
        [],
        [
            {"tile": [6, 1], "kind": "cyan"},
            {"tile": [3, 3], "kind": "cyan"},
            {"tile": [9, 2], "kind": "warm"},
        ],
    )


def dump(obj, indent: int = 0) -> str:
    sp = " " * indent
    if isinstance(obj, dict):
        parts = []
        for k, v in obj.items():
            if k in ("floor", "props"):
                rows = ",\n".join(
                    " " * (indent + 2) + "[" + ", ".join(str(n) for n in row) + "]" for row in v
                )
                parts.append(f'{sp}"{k}": [\n{rows}\n{sp}]')
            else:
                parts.append(f'{sp}"{k}": {dump(v, indent + 1).strip()}')
        return "{\n" + ",\n".join(parts) + "\n" + sp + "}"
    if isinstance(obj, list):
        if obj and all(isinstance(x, int) for x in obj):
            return "[" + ", ".join(str(x) for x in obj) + "]"
        if not obj:
            return "[]"
        inner = ",\n".join(dump(x, indent + 1) for x in obj)
        return "[\n" + inner + "\n" + sp + "]"
    if isinstance(obj, str):
        return json.dumps(obj, ensure_ascii=False)
    if isinstance(obj, bool):
        return "true" if obj else "false"
    return str(obj)


def main() -> None:
    global SHEET
    SHEET = build_sheet()
    OUT.mkdir(parents=True, exist_ok=True)
    SHEET.save(OUT / "tileset.png")
    rooms = [tea(), noodle(), ranger(), archive(), grotto()]
    for data in rooms:
        img = render(data["floor"], data["props"])
        img.convert("RGB").save(OUT / data["image"])
        text = dump(data) + "\n"
        (OUT / f"{data['id']}.json").write_text(text)
        # round-trip
        json.loads(text)
        print(f"{data['id']}: walkable {data['walkable_tiles']}, collision {len(data['collision'])}")
    print(f"tileset {SHEET.size}")


if __name__ == "__main__":
    main()
