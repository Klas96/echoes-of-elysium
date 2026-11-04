#!/usr/bin/env python3
"""Render a top-down overview PNG of a generated Tiled map (.tmj).

    python3 tools/render_map_overview.py assets/images/maps/world.tmj out.png [--scale 0.5] [--title TEXT]
    python3 tools/render_map_overview.py --compare BEFORE.tmj AFTER.tmj out.png [--scale 0.5]

Draws the ground and props layers from the embedded tilesets, the building
sprites, and a marker + label for every gameplay object (spawn, NPCs,
fragments, exits, checkpoints, enemies, secrets...). The walkable rings
counted by tools/map_rings.py are outlined in yellow and their number is
printed in the header, so the overview doubles as a layout review.
Needs numpy + Pillow.
"""
import json, os, sys
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from map_rings import rings  # noqa: E402

COL = dict(spawn=(0, 255, 0), portal=(0, 255, 255), npc=(255, 255, 0), fragment=(200, 80, 255),
           health=(0, 255, 120), drone=(255, 60, 60), sentinel=(255, 120, 0), checkpoint=(120, 255, 220),
           creature=(255, 170, 255), stump=(200, 140, 60), boulder=(160, 160, 160), stash=(255, 230, 90),
           glyph=(90, 255, 255), hidden=(255, 140, 200), darkzone=(60, 60, 160), pebble=(140, 200, 255),
           moonflower=(240, 240, 255), hiddenpath=(255, 120, 200), examine=(140, 220, 255),
           abilitygate=(255, 140, 0),
           mapexit=(255, 255, 255), entry=(255, 255, 255), storygate=(255, 80, 200), ambient=None, light=None)
LABEL = {"npc": "name", "examine": "id", "checkpoint": "label", "mapexit": "dest", "entry": "side",
         "creature": "species", "drone": "kind", "abilitygate": "gate"}


def font(sz):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def load(path):
    with open(path) as f:
        tmj = json.load(f)
    base = os.path.dirname(os.path.abspath(path))
    W, H, T = tmj["width"], tmj["height"], tmj["tilewidth"]
    gids = {}      # gid -> (image, collides)
    for ts in tmj["tilesets"]:
        first = ts["firstgid"]
        if "image" in ts:
            img = Image.open(os.path.join(base, ts["image"])).convert("RGBA")
            cols = ts["columns"]
            coll = {t["id"] for t in ts.get("tiles", []) if t.get("objectgroup", {}).get("objects")}
            for i in range(ts["tilecount"]):
                gids[first + i] = (img.crop(((i % cols) * T, (i // cols) * T, (i % cols + 1) * T, (i // cols + 1) * T)),
                                   i in coll)
        else:          # collection of images (buildings)
            for t in ts["tiles"]:
                col = [o for o in t.get("objectgroup", {}).get("objects", []) if o.get("type") == "collision"]
                gids[first + t["id"]] = (os.path.join(base, t["image"]), col[0] if col else None)
    layers = {l["name"]: l for l in tmj["layers"]}
    return tmj, W, H, T, gids, layers


def walkable(W, H, T, gids, layers, objs):
    ok = np.ones((H, W), bool)
    for name in ("ground", "props"):
        data = layers[name]["data"]
        for i, g in enumerate(data):
            if g and gids.get(g, (None, False))[1] is True:
                ok[i // W, i % W] = False
    for o in objs:
        if o.get("gid"):
            path, col = gids[o["gid"]]
            if col:
                x, y = o["x"] + col["x"], o["y"] - o["height"] + col["y"]
                for cy in range(int(y // T), int((y + col["height"] - 0.01) // T) + 1):
                    for cx in range(int(x // T), int((x + col["width"] - 0.01) // T) + 1):
                        ok[cy, cx] = False
        elif o["name"] in ("boulder", "hiddenpath", "storygate"):     # gates closed
            for cy in range(int(o["y"] // T), int((o["y"] + o["height"] - 0.01) // T) + 1):
                for cx in range(int(o["x"] // T), int((o["x"] + o["width"] - 0.01) // T) + 1):
                    ok[cy, cx] = False
    return ok


def flood(ok, sx, sy):
    H, W = ok.shape
    seen = np.zeros_like(ok); seen[sy, sx] = True; q = deque([(sx, sy)])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H and ok[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True; q.append((nx, ny))
    return seen


def prop(o, k):
    for p in o.get("properties", []):
        if p["name"] == k:
            return p["value"]
    return None


def render(path, scale=0.5, title=None):
    tmj, W, H, T, gids, layers = load(path)
    objs = next(l for l in tmj["layers"] if l["type"] == "objectgroup")["objects"]
    im = Image.new("RGBA", (W * T, H * T), (0, 0, 0, 255))
    for name in ("ground", "props"):
        data = layers[name]["data"]
        for i, g in enumerate(data):
            if g and isinstance(gids[g][0], Image.Image):
                im.alpha_composite(gids[g][0], ((i % W) * T, (i // W) * T))
    for o in sorted((o for o in objs if o.get("gid")), key=lambda o: o["y"]):
        spr = Image.open(gids[o["gid"]][0]).convert("RGBA")
        im.alpha_composite(spr, (int(o["x"]), int(o["y"] - o["height"])))
    ok = walkable(W, H, T, gids, layers, objs)
    sp = next(o for o in objs if o["name"] == "spawn")
    reach = flood(ok, int((sp["x"] + 1) // T), int((sp["y"] + 1) // T))
    rs = rings(reach)
    small = im.resize((int(W * T * scale), int(H * T * scale)), Image.LANCZOS)
    d = ImageDraw.Draw(small)
    s = T * scale
    for r in rs:     # ring = outline of the block the loop goes around
        d.rectangle([r["x0"] * s, r["y0"] * s, (r["x1"] + 1) * s, (r["y1"] + 1) * s], outline=(255, 220, 0), width=3)
    f = font(max(10, int(13 * scale / 0.5)))
    for o in objs:
        if o.get("gid") or COL.get(o["name"]) is None:
            continue
        c = COL[o["name"]]
        x0, y0 = o["x"] * scale, o["y"] * scale
        x1, y1 = x0 + max(o["width"] * scale, 4), y0 + max(o["height"] * scale, 4)
        if o["name"] in ("darkzone",):
            d.rectangle([x0, y0, x1, y1], outline=c, width=2); continue
        d.rectangle([x0, y0, x1, y1], outline=c, width=2)
        lab = LABEL.get(o["name"])
        if o["name"] in ("npc", "checkpoint", "mapexit", "fragment", "spawn", "storygate", "portal", "sentinel"):
            txt = o["name"] if not lab else f"{prop(o, lab)}"
            if o["name"] == "mapexit": txt = f"EXIT→{prop(o, 'dest')}"
            if o["name"] == "checkpoint": txt = f"CP {prop(o, 'label')}"
            d.text((x1 + 2, y0 - 2), txt, fill=c, font=f, stroke_width=2, stroke_fill=(0, 0, 0))
    head = 34
    out = Image.new("RGB", (small.width, small.height + head), (16, 16, 24))
    out.paste(small.convert("RGB"), (0, head))
    dd = ImageDraw.Draw(out)
    name = title or os.path.basename(path)
    dd.text((8, 8), f"{name}  {W}x{H} tiles  rings: {len(rs)}  reachable floor: {int(reach.sum())}",
            fill=(255, 255, 255), font=font(16))
    return out, len(rs)


def main(argv):
    scale = 0.5
    if "--scale" in argv:
        i = argv.index("--scale"); scale = float(argv[i + 1]); del argv[i:i + 2]
    title = None
    if "--title" in argv:
        i = argv.index("--title"); title = argv[i + 1]; del argv[i:i + 2]
    if argv and argv[0] == "--compare":
        before, after, out = argv[1:4]
        a, na = render(before, scale, "BEFORE " + (title or os.path.basename(before)))
        b, nb = render(after, scale, "AFTER " + (title or os.path.basename(after)))
        im = Image.new("RGB", (a.width + b.width + 16, max(a.height, b.height)), (0, 0, 0))
        im.paste(a, (0, 0)); im.paste(b, (a.width + 16, 0))
        im.save(out)
        print(f"{out}: rings before {na}, after {nb}")
    else:
        src, out = argv[0], argv[1]
        im, n = render(src, scale, title)
        im.save(out)
        print(f"{out}: rings {n}")


if __name__ == "__main__":
    main(sys.argv[1:])
