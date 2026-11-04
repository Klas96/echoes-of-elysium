#!/usr/bin/env python3
"""Assemble the Canal Works junkyard tileset from AI-generated sources.

Art comes from Cursor image gen under gen_src/junkyard/ (or --sheet).
Wangsets / collision / prop footprints are cloned from cyberpunk.tsx so
make_tiled_maps keeps working — this script only places AI pixels.

    python3 tools/tilesets/make_junkyard.py
    python3 tools/tilesets/make_junkyard.py --sheet /path/to/ai-tilesheet.jpg
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import xml.etree.ElementTree as ET

from PIL import Image

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


def nn_sheet(path: str) -> Image.Image:
    """Load AI sheet and snap to exact 512×512 tile grid."""
    im = Image.open(path).convert("RGBA")
    # Crop to largest centered square, then nearest to 512.
    w, h = im.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    im = im.crop((left, top, left + side, top + side))
    return im.resize((COLS * T, ROWS * T), Image.Resampling.NEAREST)


def punch_prop_alpha(sheet: Image.Image) -> Image.Image:
    """Make near-black / empty prop cells transparent (AI sheets often paint void)."""
    px = sheet.load()
    for tid in range(PROP_START, TILECOUNT):
        ox, oy = (tid % COLS) * T, (tid // COLS) * T
        # Sample corners — if mostly void, clear the whole tile's dark pixels.
        for j in range(T):
            for i in range(T):
                r, g, b, a = px[ox + i, oy + j]
                # Dark navy / black void → transparent
                if r < 28 and g < 28 and b < 36:
                    px[ox + i, oy + j] = (0, 0, 0, 0)
                    continue
                # Magenta key if present
                if r > 200 and g < 40 and b > 200:
                    px[ox + i, oy + j] = (0, 0, 0, 0)
                    continue
                # Soft checkerboard greys sometimes used as void
                if abs(r - g) < 8 and abs(g - b) < 8 and 40 <= r <= 70:
                    # only clear if neighbours are also void-ish (keep metal props)
                    pass
    return sheet


def fill_from_textures(sheet: Image.Image, dirt: Image.Image, heap: Image.Image,
                       oil: Image.Image, metal: Image.Image) -> Image.Image:
    """Optional: re-stamp ground/blob tiles from seamless AI textures using
    cyberpunk luminance as a mix mask so wang edges stay coherent."""
    cyber = Image.open(os.path.join(HERE, "cyberpunk.png")).convert("RGBA")
    cyber = cyber.resize((COLS * T, ROWS * T), Image.Resampling.NEAREST)
    dirt_t = _tileable(dirt)
    heap_t = _tileable(heap)
    oil_t = _tileable(oil)
    metal_t = _tileable(metal)
    out = sheet.copy()
    cpx = cyber.load()
    opx = out.load()
    # For terrain tiles 0–175, blend AI textures guided by cyberpunk brightness.
    for tid in range(0, PROP_START):
        ox, oy = (tid % COLS) * T, (tid // COLS) * T
        # Classify roughly by cyberpunk tile role
        if 16 <= tid <= 17:
            tex = heap_t
        elif 18 <= tid <= 19:
            tex = oil_t
        elif tid in (12, 13, 14, 20) or 128 <= tid <= 174:
            # metal blob block + metal ground — still mix with dirt via mask
            tex_a, tex_b = dirt_t, metal_t
            _stamp_masked(opx, cpx, ox, oy, tex_a, tex_b)
            continue
        elif 80 <= tid <= 126:
            tex_a, tex_b = dirt_t, oil_t
            _stamp_masked(opx, cpx, ox, oy, tex_a, tex_b)
            continue
        elif 32 <= tid <= 78:
            tex_a, tex_b = dirt_t, heap_t
            _stamp_masked(opx, cpx, ox, oy, tex_a, tex_b)
            continue
        else:
            tex = dirt_t
        tpx = tex.load()
        tw, th = tex.size
        for j in range(T):
            for i in range(T):
                opx[ox + i, oy + j] = tpx[(ox + i) % tw, (oy + j) % th]
    return out


def _tileable(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    side = min(w, h)
    im = im.crop(((w - side) // 2, (h - side) // 2, (w - side) // 2 + side, (h - side) // 2 + side))
    return im.resize((128, 128), Image.Resampling.LANCZOS)


def _stamp_masked(opx, cpx, ox, oy, tex_a: Image.Image, tex_b: Image.Image):
    """Use cyberpunk luminance: dark→base dirt, bright/coloured→overlay texture."""
    ap = tex_a.load()
    bp = tex_b.load()
    aw, ah = tex_a.size
    for j in range(T):
        for i in range(T):
            cr, cg, cb, ca = cpx[ox + i, oy + j]
            lum = (cr + cg + cb) / (3 * 255.0)
            # cyberpunk overlay terrains tend brighter / more saturated
            sat = (max(cr, cg, cb) - min(cr, cg, cb)) / 255.0
            t = min(1.0, max(0.0, (lum - 0.25) * 1.6 + sat * 0.5))
            ar, ag, ab, aa = ap[(ox + i) % aw, (oy + j) % ah]
            br, bg, bb, ba = bp[(ox + i) % aw, (oy + j) % ah]
            opx[ox + i, oy + j] = (
                int(ar + (br - ar) * t),
                int(ag + (bg - ag) * t),
                int(ab + (bb - ab) * t),
                255,
            )


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
    ap.add_argument("--sheet", default="", help="AI full tilesheet (jpg/png)")
    ap.add_argument("--restamp-textures", action="store_true",
                    help="Optional: restamp terrain from gen_src ground_*.jpg (can flatten contrast)")
    args = ap.parse_args()

    os.makedirs(GEN, exist_ok=True)
    sheet_path = args.sheet
    if not sheet_path:
        # Prefer artifacts copy staged into gen_src
        for cand in (
            os.path.join(GEN, "junkyard-tilesheet.jpg"),
            os.path.join(GEN, "junkyard-tilesheet.png"),
            "/opt/cursor/artifacts/assets/junkyard-tilesheet.jpg",
        ):
            if os.path.isfile(cand):
                sheet_path = cand
                break
    if not sheet_path or not os.path.isfile(sheet_path):
        raise SystemExit("No AI tilesheet found. Pass --sheet or place junkyard-tilesheet.jpg in gen_src/junkyard/")

    # Stage sources into gen_src for the repo
    staged = os.path.join(GEN, os.path.basename(sheet_path))
    if os.path.abspath(sheet_path) != os.path.abspath(staged):
        shutil.copy2(sheet_path, staged)
        sheet_path = staged
    for name in ("junkyard-ground-dirt.jpg", "junkyard-ground-heap.jpg",
                 "junkyard-ground-oil.jpg", "junkyard-ground-metal.jpg"):
        src = f"/opt/cursor/artifacts/assets/{name}"
        if os.path.isfile(src):
            shutil.copy2(src, os.path.join(GEN, name))

    sheet = nn_sheet(sheet_path)
    if args.restamp_textures:
        dirt = os.path.join(GEN, "junkyard-ground-dirt.jpg")
        heap = os.path.join(GEN, "junkyard-ground-heap.jpg")
        oil = os.path.join(GEN, "junkyard-ground-oil.jpg")
        metal = os.path.join(GEN, "junkyard-ground-metal.jpg")
        if all(os.path.isfile(p) for p in (dirt, heap, oil, metal)):
            sheet = fill_from_textures(
                sheet,
                Image.open(dirt), Image.open(heap),
                Image.open(oil), Image.open(metal),
            )
            # Keep AI sheet props (bottom rows) — restore from nn sheet
            props_only = nn_sheet(sheet_path)
            sheet.paste(props_only.crop((0, (PROP_START // COLS) * T, COLS * T, ROWS * T)),
                        (0, (PROP_START // COLS) * T))
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


if __name__ == "__main__":
    main()
