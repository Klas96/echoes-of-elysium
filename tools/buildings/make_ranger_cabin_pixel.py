#!/usr/bin/env python3
"""Hard 32×32-grid pixel-art ranger cabin exterior (128×128).

Replaces soft AI-processed magenta-key art with calm nearest-neighbour pixel
painting. Collision / door from ranger_cabin.json stay valid:
  collision x6 y54 w108 h64 ; door (63, 118)
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "images" / "maps" / "buildings" / "ranger_cabin.png"
TOOLS_OUT = Path(__file__).resolve().parent  # keep json sibling only

W = H = 128
T = 32

# Limited woods cabin palette
INK = (16, 10, 8, 255)
BARK_D = (58, 36, 22, 255)
BARK = (86, 56, 32, 255)
BARK_L = (122, 84, 48, 255)
MOSS_D = (36, 72, 34, 255)
MOSS = (58, 108, 48, 255)
MOSS_L = (96, 148, 72, 255)
STONE_D = (64, 64, 68, 255)
STONE = (96, 96, 100, 255)
STONE_L = (132, 132, 136, 255)
WOOD = (110, 74, 42, 255)
WOOD_L = (148, 104, 58, 255)
GLOW = (255, 196, 84, 255)
FIRE = (228, 112, 36, 255)
GRASS = (48, 92, 42, 255)
GRASS_L = (78, 128, 58, 255)
MUSH_D = (72, 40, 96, 255)
MUSH = (120, 72, 160, 255)
MUSH_L = (168, 120, 210, 255)
CLEAR = (0, 0, 0, 0)


def new() -> Image.Image:
    return Image.new("RGBA", (W, H), CLEAR)


def fill(im: Image.Image, x: int, y: int, w: int, h: int, c) -> None:
    px = im.load()
    for yy in range(max(0, y), min(H, y + h)):
        for xx in range(max(0, x), min(W, x + w)):
            px[xx, yy] = c


def pix(im: Image.Image, x: int, y: int, c) -> None:
    if 0 <= x < W and 0 <= y < H:
        im.putpixel((x, y), c)


def disc(im: Image.Image, cx: int, cy: int, r: int, c) -> None:
    rr = r * r
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= rr:
                pix(im, x, y, c)


def paint() -> Image.Image:
    im = new()
    # --- roof A-frame (moss, blocky) ---
    # Peak around y=18, eaves ~y=54; cabin body sits under eaves.
    for row, y0, half in (
        (0, 18, 10),
        (1, 24, 18),
        (2, 30, 28),
        (3, 36, 38),
        (4, 42, 48),
        (5, 48, 54),
    ):
        left = 64 - half
        shade = MOSS_L if row % 2 == 0 else MOSS
        fill(im, left, y0, half * 2, 6, shade)
        fill(im, left, y0, half * 2, 1, MOSS_L)
        fill(im, left, y0 + 5, half * 2, 1, MOSS_D)
        # drip tufts
        if row >= 3:
            for x in range(left + 4, left + half * 2 - 4, 10):
                fill(im, x, y0 + 6, 3, 3, MOSS if (x // 10) % 2 else MOSS_D)

    # chimney (left of peak)
    fill(im, 34, 10, 14, 28, STONE)
    fill(im, 34, 10, 14, 2, STONE_L)
    fill(im, 36, 8, 10, 3, STONE_D)
    fill(im, 38, 6, 6, 3, STONE)
    for y in (16, 24):
        fill(im, 34, y, 14, 1, STONE_D)

    # --- log walls ---
    # Body: x16..112, y54..112 (about 3 tiles tall under roof)
    wall_top = 54
    wall_bot = 112
    fill(im, 16, wall_top, 96, wall_bot - wall_top, BARK)
    for i, y in enumerate(range(wall_top, wall_bot, 8)):
        c = BARK_L if i % 2 == 0 else BARK
        fill(im, 16, y, 96, 7, c)
        fill(im, 16, y, 96, 1, BARK_L)
        fill(im, 16, y + 6, 96, 1, BARK_D)
        # knots
        pix(im, 28 + (i * 11) % 60, y + 3, BARK_D)
        pix(im, 90 - (i * 7) % 50, y + 4, INK)
    # side posts
    fill(im, 16, wall_top, 4, wall_bot - wall_top, BARK_D)
    fill(im, 108, wall_top, 4, wall_bot - wall_top, BARK_D)

    # door (centred ~x63) — threshold near door.y=118 but art lip at ~112
    door_x, door_y, door_w, door_h = 52, 78, 24, 34
    fill(im, door_x, door_y, door_w, door_h, WOOD)
    fill(im, door_x, door_y, door_w, 1, WOOD_L)
    fill(im, door_x, door_y, 1, door_h, BARK_D)
    fill(im, door_x + door_w - 1, door_y, 1, door_h, BARK_D)
    # small barred window
    fill(im, 58, 84, 12, 10, INK)
    fill(im, 59, 85, 10, 8, GLOW)
    fill(im, 63, 85, 1, 8, WOOD)
    fill(im, 59, 89, 10, 1, WOOD)
    pix(im, 70, 100, GOLD := (212, 168, 72, 255))  # handle

    # lit window right of door
    fill(im, 86, 82, 16, 16, INK)
    fill(im, 88, 84, 12, 12, GLOW)
    fill(im, 88, 84, 12, 1, FIRE)
    fill(im, 93, 84, 1, 12, WOOD)
    fill(im, 88, 89, 12, 1, WOOD)
    # lantern left of door
    fill(im, 40, 86, 6, 8, WOOD)
    fill(im, 41, 88, 4, 4, GLOW)
    pix(im, 42, 89, FIRE)

    # stone steps under door (walkable apron below collision bottom)
    fill(im, 48, 112, 32, 10, STONE)
    fill(im, 50, 114, 28, 2, STONE_L)
    fill(im, 52, 118, 24, 4, STONE_D)
    fill(im, 54, 120, 20, 2, STONE)

    # log pile left
    for i, (x, y) in enumerate(((8, 96), (8, 104), (18, 100), (18, 108), (28, 104))):
        fill(im, x, y, 14, 6, BARK if i % 2 == 0 else BARK_L)
        disc(im, x + 2, y + 3, 2, WOOD_L)
        fill(im, x, y, 14, 1, BARK_L)

    # one calm mushroom (left)
    disc(im, 12, 88, 7, MUSH)
    disc(im, 12, 86, 5, MUSH_L)
    pix(im, 10, 85, (220, 200, 240, 255))
    pix(im, 14, 87, (220, 200, 240, 255))
    fill(im, 11, 94, 3, 8, MUSH_D)
    fill(im, 10, 100, 5, 2, MUSH_D)

    # grass / base tufts (bottom row partly opaque — matches README quirk)
    for x in range(10, 118, 6):
        fill(im, x, 122, 4, 4, GRASS if (x // 6) % 2 else GRASS_L)
        pix(im, x + 1, 121, GRASS_L)
    # small rocks
    disc(im, 100, 118, 3, STONE_D)
    disc(im, 108, 120, 2, STONE)

    # navy outline on opaque silhouette (1px, hard)
    outline(im, INK)
    return im


def outline(im: Image.Image, c) -> None:
    px = im.load()
    opaque = [[px[x, y][3] > 0 for x in range(W)] for y in range(H)]
    add: list[tuple[int, int]] = []
    for y in range(H):
        for x in range(W):
            if opaque[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and opaque[ny][nx]:
                    add.append((x, y))
                    break
    for x, y in add:
        px[x, y] = c


def main() -> int:
    im = paint()
    # Binary alpha cleanup
    px = im.load()
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a < 128:
                px[x, y] = CLEAR
            else:
                px[x, y] = (r, g, b, 255)
    colors = im.getcolors(W * H)
    n = len(colors) if colors else -1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    im.save(OUT)
    print(f"wrote {OUT} ({n} colours)")
    if n > 40:
        raise SystemExit(f"too many colours ({n}) for hard pixel cabin")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
