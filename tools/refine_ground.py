#!/usr/bin/env python3
"""Soften woods ground and add diagonal trail tiles (#64).

Reads tools/tilesets/woods.png (the pre-refine sheet: 512x544). Rewrites grass,
dirt, water and forest so shared edges wrap, feathers blob borders, and appends
the trail-/hero- tiles from tools/trail_ribbons.py. Updates the tsx/tsj and the
woods map's ground layer. Safe to run only on the original 544px sheet.
"""
import json
import os
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image

from trail_ribbons import ALL_PATH_NAMES, HERO_NAMES, PORT_PX, apply_woods_ribbons, load_tsx

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TSDIR = os.path.join(HERE, "tilesets")
MAPDIR = os.path.join(ROOT, "assets", "images", "maps")
T = 32
COLS = 16
OLD_COUNT = 272
# 108 path tiles, padded to a full row.
NEW_ROWS = 7
NEW_COUNT = OLD_COUNT + NEW_ROWS * COLS  # 384
NEW_H = NEW_COUNT // COLS * T  # 768

BASES = {"grass": 0, "dirt": 8, "water": 12, "forest": 14}
BAYER = np.array([
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
], np.float32)


def tile_box(tid, width_tiles=COLS):
    r, c = divmod(tid, width_tiles)
    return r * T, c * T


def crop(img, tid):
    y, x = tile_box(tid)
    return img[y:y + T, x:x + T]


def paste(img, tid, tile):
    y, x = tile_box(tid)
    img[y:y + T, x:x + T] = tile


def seamless(src, band=6):
    """Pull opposite edges together so the tile wraps without a hard seam."""
    out = src.astype(np.float32).copy()
    left, right = out[:, 0].copy(), out[:, -1].copy()
    avg = 0.5 * (left + right)
    for i in range(band):
        t = (band - i) / float(band)
        t = t * t * (3 - 2 * t)
        out[:, i] = out[:, i] * (1 - t) + avg * t
        out[:, -1 - i] = out[:, -1 - i] * (1 - t) + avg * t
    top, bot = out[0].copy(), out[-1].copy()
    avg = 0.5 * (top + bot)
    for i in range(band):
        t = (band - i) / float(band)
        t = t * t * (3 - 2 * t)
        out[i] = out[i] * (1 - t) + avg * t
        out[-1 - i] = out[-1 - i] * (1 - t) + avg * t
    return np.clip(out, 0, 255)


def palette(tiles):
    cols = np.unique(np.vstack([t.reshape(-1, 3) for t in tiles]), axis=0)
    return cols.astype(np.float32)


def snap(img, pal):
    flat = img.reshape(-1, 3).astype(np.float32)
    # 32*32 x ~30 is small.
    d = ((flat[:, None, :] - pal[None, :, :]) ** 2).sum(2)
    return pal[d.argmin(1)].reshape(img.shape).astype(np.uint8)


def seam_mse(tile):
    t = tile.astype(np.float32)
    h = np.mean((t[:, 0] - t[:, -1]) ** 2)
    v = np.mean((t[0] - t[-1]) ** 2)
    return float(h), float(v)


def port_xy(edge, port):
    p = PORT_PX[port]
    return {"N": (p, 0), "S": (p, 31), "W": (0, p), "E": (31, p)}[edge]


def band_weight(name, radius, feather):
    """Dirt weight 0..1 for a trail-* or hero-* tile name."""
    body = name.split("-", 1)[1]
    a, b = body.split("-")
    e0, p0 = a[0], int(a[1])
    e1, p1 = b[0], int(b[1])
    x0, y0 = port_xy(e0, p0)
    x1, y1 = port_xy(e1, p1)
    ys, xs = np.mgrid[0:T, 0:T]
    if {e0, e1} in ({"N", "S"}, {"E", "W"}):
        dist = _seg_dist(xs, ys, x0, y0, x1, y1)
    else:
        mx, my = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        cx, cy = mx * 0.58 + 15.5 * 0.42, my * 0.58 + 15.5 * 0.42
        pts = []
        for t in np.linspace(0, 1, 20):
            u = 1 - t
            pts.append((u * u * x0 + 2 * u * t * cx + t * t * x1,
                        u * u * y0 + 2 * u * t * cy + t * t * y1))
        dist = np.full((T, T), 1e9, np.float32)
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            dist = np.minimum(dist, _seg_dist(xs, ys, ax, ay, bx, by))
    return np.clip((radius + feather - dist) / feather, 0, 1)


def _seg_dist(xs, ys, x0, y0, x1, y1):
    dx, dy = x1 - x0, y1 - y0
    l2 = dx * dx + dy * dy or 1e-6
    t = np.clip(((xs - x0) * dx + (ys - y0) * dy) / l2, 0, 1)
    return np.hypot(xs - (x0 + t * dx), ys - (y0 + t * dy))


def draw_path_tile(name, grass, dirt):
    hero = name.startswith("hero-")
    radius, feather = (8.4, 3.6) if hero else (4.8, 3.4)
    w = band_weight(name, radius, feather)
    thr = (BAYER + 0.5) / 16.0
    ys, xs = np.mgrid[0:T, 0:T]
    pick = w > thr[ys % 4, xs % 4]
    out = np.where(pick[:, :, None], dirt, grass)
    rgba = np.zeros((T, T, 4), np.uint8)
    rgba[:, :, :3] = out
    rgba[:, :, 3] = 255
    return rgba


def refine_woods(img):
    """img is RGBA uint8, height 544. Returns a 768px sheet."""
    assert img.shape == (544, 512, 4), img.shape
    rgb = img[:, :, :3]
    bases = {name: crop(rgb, tid).astype(np.float32) for name, tid in BASES.items()}
    pals = {}
    groups = {
        "grass": list(range(0, 8)),
        "dirt": list(range(8, 12)),
        "water": [12, 13],
        "forest": [14, 15],
    }
    for name, ids in groups.items():
        pals[name] = palette([crop(rgb, i) for i in ids])
    soft = {name: snap(seamless(bases[name], band=7 if name in ("forest", "water", "dirt") else 6), pals[name])
            for name in bases}
    print("seam before/after (h, v mse):")
    for name, tid in BASES.items():
        print(f"  {name:7} {seam_mse(bases[name])} -> {seam_mse(soft[name])}")

    out = np.zeros((NEW_H, 512, 4), np.uint8)
    out[:544] = img
    names = list(bases)
    for tid in range(0, 160):
        tile = crop(img, tid)
        if tile[:, :, 3].mean() < 10:
            continue
        src = tile[:, :, :3].astype(np.float32)
        dist = np.stack([np.linalg.norm(src - bases[n], axis=2) for n in names], 0)
        best_i = dist.argmin(0)
        best_d = dist.min(0)
        # second best
        dist2 = dist.copy()
        dist2[best_i, np.arange(T)[:, None], np.arange(T)[None, :]] = 1e9
        second_i = dist2.argmin(0)
        second_d = dist2.min(0)
        painted = src.copy()
        solid = best_d < 24
        band = (best_d >= 24) & (best_d < 42) & ((second_d - best_d) < 16)
        for i, name in enumerate(names):
            m = solid & (best_i == i)
            painted[m] = soft[name][m]
        thr = (BAYER + 0.5) / 16.0
        ys, xs = np.mgrid[0:T, 0:T]
        take_best = thr[ys % 4, xs % 4] > 0.5
        # In the blend band, dither between the two neighbouring terrains.
        for i, name in enumerate(names):
            m = band & (best_i == i) & take_best
            painted[m] = soft[name][m]
            m2 = band & (second_i == i) & ~take_best
            painted[m2] = soft[name][m2]
        # Keep designer flecks (flowers, pebbles) that are not the base texture.
        if tid in range(1, 8):
            orig = crop(rgb, tid).astype(np.float32)
            fleck = np.linalg.norm(orig - bases["grass"], axis=2) > 30
            fleck[:3, :] = fleck[-3:, :] = fleck[:, :3] = fleck[:, -3:] = False
            painted[fleck] = orig[fleck]
        if tid in range(9, 12):
            orig = crop(rgb, tid).astype(np.float32)
            fleck = np.linalg.norm(orig - bases["dirt"], axis=2) > 30
            fleck[:3, :] = fleck[-3:, :] = fleck[:, :3] = fleck[:, -3:] = False
            painted[fleck] = orig[fleck]
        rgba = np.zeros((T, T, 4), np.uint8)
        rgba[:, :, :3] = np.clip(painted, 0, 255).astype(np.uint8)
        rgba[:, :, 3] = 255
        paste(out, tid, rgba)

    grass, dirt = soft["grass"], soft["dirt"]
    for i, name in enumerate(ALL_PATH_NAMES):
        paste(out, OLD_COUNT + i, draw_path_tile(name, grass, dirt))
    return out


def _xml_tile(tid, name):
    return (
        f' <tile id="{tid}">\n'
        f'  <properties>\n'
        f'   <property name="ground" value="trail" />\n'
        f'   <property name="path" value="{name}" />\n'
        f'  </properties>\n'
        f' </tile>\n'
    )


def update_tsx(path):
    text = open(path, encoding="utf-8").read()
    old_head = 'tilecount="272"'
    if old_head not in text:
        raise SystemExit(f"{path} is not the original 272-tile woods sheet")
    text = text.replace('tilecount="272"', f'tilecount="{NEW_COUNT}"', 1)
    text = text.replace('height="544"', f'height="{NEW_H}"', 1)
    block = "".join(_xml_tile(OLD_COUNT + i, name) for i, name in enumerate(ALL_PATH_NAMES))
    needle = "<wangsets>"
    if needle not in text:
        raise SystemExit("woods.tsx has no wangsets")
    text = text.replace(needle, block + needle, 1)
    open(path, "w", encoding="utf-8").write(text)


def update_tsj(path):
    data = json.loads(open(path, encoding="utf-8").read())
    if data.get("tilecount") != OLD_COUNT:
        raise SystemExit(f"{path} tilecount is {data.get('tilecount')}, expected {OLD_COUNT}")
    data["tilecount"] = NEW_COUNT
    data["imageheight"] = NEW_H
    existing = {t["id"] for t in data["tiles"]}
    for i, name in enumerate(ALL_PATH_NAMES):
        tid = OLD_COUNT + i
        if tid in existing:
            continue
        data["tiles"].append({
            "id": tid,
            "properties": [
                {"name": "ground", "type": "string", "value": "trail"},
                {"name": "path", "type": "string", "value": name},
            ],
        })
    data["tiles"].sort(key=lambda t: t["id"])
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps(data, indent=1) + "\n")


def update_world(tmj_path, tsx_path):
    ts = load_tsx(tsx_path)
    tmj = json.loads(open(tmj_path, encoding="utf-8").read())
    woods = tmj["tilesets"][0]
    if woods["name"] != "woods" or woods["tilecount"] != OLD_COUNT:
        raise SystemExit(f"unexpected woods tileset in {tmj_path}")
    ground_layer = next(l for l in tmj["layers"] if l["name"] == "ground")
    h, w = tmj["height"], tmj["width"]
    gids = np.array(ground_layer["data"], np.int32).reshape(h, w)
    first = int(woods["firstgid"])
    local = gids - first
    stats = apply_woods_ribbons(local, ts)
    ground_layer["data"] = (local + first).reshape(-1).astype(int).tolist()
    delta = NEW_COUNT - OLD_COUNT
    old_buildings = None
    for tsj in tmj["tilesets"]:
        if tsj["name"] == "woods":
            tsj["tilecount"] = NEW_COUNT
            tsj["imageheight"] = NEW_H
            have = {t["id"] for t in tsj.get("tiles", [])}
            for i, name in enumerate(ALL_PATH_NAMES):
                tid = OLD_COUNT + i
                if tid in have:
                    continue
                tsj["tiles"].append({
                    "id": tid,
                    "properties": [
                        {"name": "ground", "type": "string", "value": "trail"},
                        {"name": "path", "type": "string", "value": name},
                    ],
                })
            tsj["tiles"].sort(key=lambda t: t["id"])
        elif tsj["firstgid"] > first:
            old_buildings = tsj["firstgid"]
            tsj["firstgid"] = old_buildings + delta
    if old_buildings is not None:
        for layer in tmj["layers"]:
            for obj in layer.get("objects") or []:
                if obj.get("gid", 0) >= old_buildings:
                    obj["gid"] = obj["gid"] + delta
    with open(tmj_path, "w", encoding="utf-8") as f:
        f.write(json.dumps(tmj, indent=1) + "\n")
    return stats


def main():
    src = os.path.join(TSDIR, "woods.png")
    img = np.array(Image.open(src).convert("RGBA"))
    if img.shape[0] != 544:
        raise SystemExit(f"{src} is {img.shape}, expected the original 512x544 sheet")
    out = refine_woods(img)
    assert out.shape == (NEW_H, 512, 4)
    # Props (tile >= 160) stay pixel-identical.
    props = img[10 * T:17 * T]
    if not np.array_equal(out[10 * T:17 * T], props):
        raise SystemExit("refine changed prop rows")
    for dest in (src, os.path.join(MAPDIR, "tilesets", "woods.png")):
        Image.fromarray(out).save(dest)
        print("wrote", dest)
    update_tsx(os.path.join(TSDIR, "woods.tsx"))
    update_tsj(os.path.join(TSDIR, "woods.tsj"))
    stats = update_world(os.path.join(MAPDIR, "world.tmj"), os.path.join(TSDIR, "woods.tsx"))
    if stats["ribbons"] < 40:
        raise SystemExit(f"expected a woods full of diagonal tracks, got {stats}")
    print("hero tiles", len(HERO_NAMES), "trail tiles", len(ALL_PATH_NAMES) - len(HERO_NAMES))


if __name__ == "__main__":
    main()
