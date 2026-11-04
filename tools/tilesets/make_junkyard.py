#!/usr/bin/env python3
"""Assemble the Canal Works junkyard tileset as true 32×32 pixel art.

Default: recolor cyberpunk.png (same wang/collision footprints) into a rusty
scrapyard palette with hard nearest-neighbour pixels — no blur, no LANCZOS
downscale on terrain. Optional --sheet still accepts an AI pixel-art sheet.

    python3 tools/tilesets/make_junkyard.py
    python3 tools/tilesets/make_junkyard.py --sheet /path/to/pixel-tilesheet.png
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import xml.etree.ElementTree as ET

from PIL import Image
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "gen_src", "junkyard")
T = 32
COLS = 16
ROWS = 16
TILECOUNT = COLS * ROWS
PROP_START = 176  # cyberpunk prop region

PROP_RENAME = {
    "rubble_small": "scrap_pile",
    "rubble_large": "scrap_heap",
    "wrecked_car_v": "wreck_car_v",
    "wrecked_car_h": "wreck_car_h",
    "barrel_purple": "drum_sealed",
    "barrel_toxic": "drum_leaking",
    "neon_kiosk": "parts_stall",
    "vending_broken": "broken_vendor",
    "terminal": "weigh_console",
    "holo_billboard": "salvage_board",
    "neon_sign": "yard_sign",
    "crate": "scrap_crate",
    "dumpster": "skip_bin",
    "steam_vent": "vent_stack",
    "broken_pillar": "concrete_stub",
    "neon_streetlight": "yard_lamp",
    "satellite_dish": "radar_dish",
    "drone_wreck": "drone_hulk",
    "barricade": "tire_wall",
    "portal_hexpad": "crane_pad",
    "generator": "arc_welder",
    "loose_cables": "cable_tangle",
}

WANG_RENAME = {
    "asphalt-ruin": "dirt-heap",
    "asphalt-sludge": "dirt-oil",
    "asphalt-metal": "dirt-metal",
}

COLOR_RENAME = {
    "asphalt": ("dirt", "#8a7048"),
    "ruin": ("heap", "#c06030"),
    "sludge": ("oil", "#2a6058"),
    "metal": ("plate", "#708090"),
}

# Hard junkyard palettes (RGB) — few steps, game-like pixel shading.
DIRT = [(58, 42, 28), (86, 64, 40), (110, 84, 52), (138, 108, 68), (162, 130, 82)]
HEAP = [(28, 18, 14), (48, 28, 18), (72, 40, 22), (104, 56, 28), (138, 72, 34), (168, 92, 42)]
OIL = [(18, 28, 30), (28, 48, 46), (36, 68, 62), (48, 92, 78), (64, 118, 96)]
METAL = [(32, 34, 40), (52, 56, 64), (78, 84, 94), (108, 116, 126), (140, 148, 158)]
# Prop accent push: cool neon → warm rust/amber
PROP_NEON_TO_RUST = True


def nn_sheet(path: str) -> Image.Image:
    """Load a sheet and snap to exact 512×512 with NEAREST (keeps pixels crisp)."""
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    im = im.crop((left, top, left + side, top + side))
    return im.resize((COLS * T, ROWS * T), Image.Resampling.NEAREST)


def _nearest_palette(rgb: np.ndarray, palette: list[tuple[int, int, int]]) -> np.ndarray:
    """Map each pixel to nearest palette colour (Euclidean)."""
    p = np.array(palette, dtype=np.float32)  # (K,3)
    flat = rgb.reshape(-1, 3).astype(np.float32)
    # (N,1,3) - (1,K,3) → (N,K)
    d = ((flat[:, None, :] - p[None, :, :]) ** 2).sum(axis=2)
    idx = d.argmin(axis=1)
    return p[idx].astype(np.uint8).reshape(rgb.shape)


def _luma(rgb: np.ndarray) -> np.ndarray:
    return (0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]).astype(np.float32)


def _ramp_by_luma(rgb: np.ndarray, palette: list[tuple[int, int, int]]) -> np.ndarray:
    """Assign palette steps by source luminance (preserves pixel shading structure)."""
    lum = _luma(rgb)
    # Ignore near-black void for props later; terrain is opaque.
    lo, hi = np.percentile(lum[lum > 8], [5, 95]) if (lum > 8).any() else (0, 255)
    t = np.clip((lum - lo) / max(1.0, hi - lo), 0, 1)
    n = len(palette) - 1
    idx = np.clip(np.round(t * n).astype(np.int32), 0, n)
    out = np.zeros_like(rgb)
    p = np.array(palette, dtype=np.uint8)
    out[...] = p[idx]
    return out


def pixel_junkyard_from_cyberpunk() -> Image.Image:
    """Recolor cyberpunk terrain into rusty dirt/heap/oil/metal — keep every pixel edge."""
    cyber = Image.open(os.path.join(HERE, "cyberpunk.png")).convert("RGBA")
    cyber = cyber.resize((COLS * T, ROWS * T), Image.Resampling.NEAREST)
    arr = np.array(cyber)
    rgb = arr[..., :3].copy()
    a = arr[..., 3]

    for tid in range(0, PROP_START):
        ox, oy = (tid % COLS) * T, (tid // COLS) * T
        tile = rgb[oy : oy + T, ox : ox + T]
        if 16 <= tid <= 17 or 32 <= tid <= 78:
            # Scrap-heap walls — darker rust
            remapped = _ramp_by_luma(tile, HEAP)
            # Extra darken full-collision wall tiles for contact-shadow readability
            remapped = (remapped.astype(np.float32) * 0.88).astype(np.uint8)
        elif 18 <= tid <= 19 or 80 <= tid <= 126:
            remapped = _ramp_by_luma(tile, OIL)
        elif tid in (12, 13, 14, 20) or 128 <= tid <= 174:
            remapped = _ramp_by_luma(tile, METAL)
        else:
            remapped = _ramp_by_luma(tile, DIRT)
            # Light checker dither on flat dirt so floors read pixel-y, not flat fill
            for j in range(T):
                for i in range(T):
                    if (i + j) % 4 == 0 and remapped[j, i, 0] > 90:
                        remapped[j, i] = np.clip(remapped[j, i].astype(int) - 10, 0, 255).astype(np.uint8)
        rgb[oy : oy + T, ox : ox + T] = remapped

    # Props: keep cyberpunk silhouettes; warm-shift cool neon toward rust/amber.
    if PROP_NEON_TO_RUST:
        prop = rgb[(PROP_START // COLS) * T :, :, :].astype(np.float32)
        r, g, b = prop[..., 0], prop[..., 1], prop[..., 2]
        # Magenta / cyan neon → amber / copper
        magenta = (r > 140) & (b > 140) & (g < 120)
        cyan = (g > 140) & (b > 140) & (r < 100)
        cool = (b > r + 20) & (b > 80)
        r2, g2, b2 = r.copy(), g.copy(), b.copy()
        r2[magenta] = np.clip(r[magenta] * 0.95 + 40, 0, 255)
        g2[magenta] = np.clip(g[magenta] * 0.7 + 30, 0, 255)
        b2[magenta] = np.clip(b[magenta] * 0.35, 0, 255)
        r2[cyan] = np.clip(r[cyan] + 50, 0, 255)
        g2[cyan] = np.clip(g[cyan] * 0.85, 0, 255)
        b2[cyan] = np.clip(b[cyan] * 0.45, 0, 255)
        r2[cool & ~magenta & ~cyan] = np.clip(r[cool & ~magenta & ~cyan] + 25, 0, 255)
        b2[cool & ~magenta & ~cyan] = np.clip(b[cool & ~magenta & ~cyan] * 0.7, 0, 255)
        # Grey metal props → slightly rustier
        grey = (np.abs(r - g) < 12) & (np.abs(g - b) < 12) & (r > 40) & (r < 180)
        r2[grey] = np.clip(r[grey] * 1.08 + 8, 0, 255)
        g2[grey] = np.clip(g[grey] * 0.95, 0, 255)
        b2[grey] = np.clip(b[grey] * 0.82, 0, 255)
        rgb[(PROP_START // COLS) * T :, :, 0] = r2.astype(np.uint8)
        rgb[(PROP_START // COLS) * T :, :, 1] = g2.astype(np.uint8)
        rgb[(PROP_START // COLS) * T :, :, 2] = b2.astype(np.uint8)

    out = np.dstack([rgb, a])
    return Image.fromarray(out, "RGBA")


def punch_prop_alpha(sheet: Image.Image) -> Image.Image:
    """Make near-black / empty prop cells transparent."""
    sheet = sheet.copy()
    px = sheet.load()
    for tid in range(PROP_START, TILECOUNT):
        ox, oy = (tid % COLS) * T, (tid // COLS) * T
        for j in range(T):
            for i in range(T):
                r, g, b, a = px[ox + i, oy + j]
                if r < 28 and g < 28 and b < 36:
                    px[ox + i, oy + j] = (0, 0, 0, 0)
                elif r > 200 and g < 40 and b > 200:
                    px[ox + i, oy + j] = (0, 0, 0, 0)
    return sheet


def quantize_sheet_to_pixel(sheet: Image.Image, colors: int = 48) -> Image.Image:
    """Force a limited palette on an AI sheet (NEAREST already applied)."""
    # Preserve alpha: quantize RGB only where opaque.
    arr = np.array(sheet)
    rgb = arr[..., :3]
    a = arr[..., 3]
    opaque = a > 8
    if not opaque.any():
        return sheet
    # PIL adaptive palette on opaque bbox
    tmp = Image.fromarray(rgb, "RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT)
    pal = tmp.convert("RGB")
    q = np.array(pal)
    out = arr.copy()
    out[opaque, :3] = q[opaque]
    return Image.fromarray(out, "RGBA")


def rewrite_tsx(cyber_path: str, out_path: str):
    tree = ET.parse(cyber_path)
    root = tree.getroot()
    root.set("name", "junkyard")
    img = root.find("image")
    img.set("source", "junkyard.png")
    for t in root.findall("tile"):
        for p in t.findall("properties/property"):
            if p.get("name") == "prop" and p.get("value") in PROP_RENAME:
                p.set("value", PROP_RENAME[p.get("value")])
    for ws in root.findall("wangsets/wangset"):
        old = ws.get("name")
        if old in WANG_RENAME:
            ws.set("name", WANG_RENAME[old])
        for c in ws.findall("wangcolor"):
            n = c.get("name")
            if n in COLOR_RENAME:
                nn, col = COLOR_RENAME[n]
                c.set("name", nn)
                c.set("color", col)
    ET.indent(tree, space=" ")
    tree.write(out_path, encoding="utf-8", xml_declaration=True)


def tsx_to_tsj(tsx_path: str, tsj_path: str):
    root = ET.parse(tsx_path).getroot()
    tiles = []
    for t in root.findall("tile"):
        d: dict = {"id": int(t.get("id"))}
        if t.get("probability"):
            d["probability"] = float(t.get("probability"))
        props = []
        for p in t.findall("properties/property"):
            entry = {"name": p.get("name"), "type": p.get("type", "string"), "value": p.get("value")}
            if entry["type"] == "bool":
                entry["value"] = entry["value"] == "true"
            elif entry["type"] == "int":
                entry["value"] = int(entry["value"])
            elif entry["type"] == "float":
                entry["value"] = float(entry["value"])
            props.append(entry)
        if props:
            d["properties"] = props
        objs = []
        for o in t.findall("objectgroup/object"):
            objs.append({
                "id": int(o.get("id", 1)),
                "x": float(o.get("x", 0)),
                "y": float(o.get("y", 0)),
                "width": float(o.get("width", 0)),
                "height": float(o.get("height", 0)),
                "rotation": 0,
            })
        if objs:
            d["objectgroup"] = {"draworder": "index", "id": 1, "name": "", "objects": objs, "x": 0, "y": 0}
        tiles.append(d)
    wangsets = []
    for ws in root.findall("wangsets/wangset"):
        wangsets.append({
            "name": ws.get("name"),
            "type": ws.get("type", "mixed"),
            "colors": [{
                "color": c.get("color"),
                "name": c.get("name"),
                "probability": float(c.get("probability", 1)),
                "tile": int(c.get("tile", 0)),
            } for c in ws.findall("wangcolor")],
            "wangtiles": [{
                "tileid": int(w.get("tileid")),
                "wangid": [int(v) for v in w.get("wangid").split(",")],
            } for w in ws.findall("wangtile")],
        })
    doc = {
        "columns": COLS,
        "image": "junkyard.png",
        "imageheight": ROWS * T,
        "imagewidth": COLS * T,
        "margin": 0,
        "name": "junkyard",
        "spacing": 0,
        "tilecount": TILECOUNT,
        "tiledversion": "1.10.2",
        "tileheight": T,
        "tilewidth": T,
        "type": "tileset",
        "version": "1.10",
        "tiles": tiles,
        "wangsets": wangsets,
    }
    with open(tsj_path, "w") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", default="",
                    help="Optional AI pixel-art tilesheet (NEAREST snap + palette quantize)")
    ap.add_argument("--from-cyberpunk", action="store_true", default=False,
                    help="Force cyberpunk recolor path (default when no --sheet)")
    args = ap.parse_args()

    os.makedirs(GEN, exist_ok=True)

    if args.sheet:
        sheet_path = args.sheet
        if not os.path.isfile(sheet_path):
            raise SystemExit(f"Sheet not found: {sheet_path}")
        staged = os.path.join(GEN, os.path.basename(sheet_path))
        if os.path.abspath(sheet_path) != os.path.abspath(staged):
            shutil.copy2(sheet_path, staged)
            sheet_path = staged
        sheet = nn_sheet(sheet_path)
        sheet = quantize_sheet_to_pixel(sheet, colors=40)
        sheet = punch_prop_alpha(sheet)
        # Darken colliding heap wall tiles for wall/floor contrast
        wall_ids = _colliding_heap_ids()
        px = sheet.load()
        for tid in wall_ids:
            ox, oy = (tid % COLS) * T, (tid // COLS) * T
            for j in range(T):
                for i in range(T):
                    r, g, b, a = px[ox + i, oy + j]
                    if a < 8:
                        continue
                    px[ox + i, oy + j] = (
                        max(0, int(r * 0.75)),
                        max(0, int(g * 0.72)),
                        max(0, int(b * 0.78)),
                        a,
                    )
    else:
        # Default: true pixel art via cyberpunk structure + junkyard palette
        sheet = pixel_junkyard_from_cyberpunk()
        sheet = punch_prop_alpha(sheet)

    png = os.path.join(HERE, "junkyard.png")
    sheet.save(png)
    print(f"wrote {png}")
    tsx = os.path.join(HERE, "junkyard.tsx")
    rewrite_tsx(os.path.join(HERE, "cyberpunk.tsx"), tsx)
    print(f"wrote {tsx}")
    tsj = os.path.join(HERE, "junkyard.tsj")
    tsx_to_tsj(tsx, tsj)
    print(f"wrote {tsj}")


def _colliding_heap_ids() -> set[int]:
    root = ET.parse(os.path.join(HERE, "cyberpunk.tsx")).getroot()
    ids = set()
    for t in root.findall("tile"):
        tid = int(t.get("id"))
        if not (16 <= tid <= 17 or 32 <= tid <= 78):
            continue
        for p in t.findall("properties/property"):
            if p.get("name") == "collides" and p.get("value") == "true":
                ids.add(tid)
                break
        if t.find("objectgroup/object") is not None and (16 <= tid <= 17 or 32 <= tid <= 78):
            ids.add(tid)
    return ids or set(range(16, 18)) | {78}


if __name__ == "__main__":
    main()
