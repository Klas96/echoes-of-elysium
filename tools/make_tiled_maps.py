#!/usr/bin/env python3
"""Generate the three Bonfire/Tiled levels for Echoes of Elysium.

    python3 tools/make_tiled_maps.py [out_dir] [--preview DIR]
    (needs numpy + Pillow: pip install numpy pillow)

Defaults: tilesets from tools/tilesets/ (or ../tilesets/, or $TILESETS),
output to assets/images/maps/ next to tools/ (or ./build-maps if absent).
Output is deterministic (fixed seeds), so re-running reproduces the maps.

Reads the Designer tilesets (<name>.tsx + .png), embeds them in the
.tmj files (Bonfire 3.15.1 / tiledjsonreader 1.4.1 can't read external .tsx;
only .json/.tsj), and writes:

  <out>/world.tmj   woods / starter   (tileset woods)
  <out>/world2.tmj  city              (tileset city)
  <out>/world3.tmj  cyberpunk ruins   (tileset cyberpunk)
  <out>/tilesets/<name>.png
  <preview>/preview_world*.png        (only with --preview: render + walkability)

Layers per map: "ground" (blob/wang terrain incl. walls), "props" (decor,
some collide via per-tile collision rects) and an object layer "gameplay"
with objects named spawn, portal, npc (property name), fragment, health,
drone (property startAngle), sentinel, checkpoint (property label). Object x/y = component top-left in
world px, width/height = component size (same coords the code used before).

The script checks that every gameplay object sits on fully walkable tiles and
that all of them are reachable from the spawn; it fails loudly otherwise.
Checkpoints (respawn points; one at the spawn plus one per area entrance) must
also stay clear of every enemy's reach, so respawning never lands in a fight.
"""
import json, math, os, shutil, sys
import xml.etree.ElementTree as ET
from collections import deque
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TSDIR = os.environ.get("TILESETS") or next(
    (d for d in (os.path.join(HERE, "tilesets"), os.path.join(ROOT, "tilesets")) if os.path.isdir(d)),
    os.path.join(HERE, "tilesets"))
_args = sys.argv[1:]
PREVIEW = None
if "--preview" in _args:
    i = _args.index("--preview"); PREVIEW = _args[i + 1]; del _args[i:i + 2]
_default_out = os.path.join(ROOT, "assets", "images", "maps")
OUT = _args[0] if _args else (_default_out if os.path.isdir(_default_out) else os.path.join(ROOT, "build-maps"))
T = 32
COLS = 16

# --------------------------------------------------------------- tileset io
class Tileset:
    def __init__(self, name):
        self.name = name
        root = ET.parse(os.path.join(TSDIR, f"{name}.tsx")).getroot()
        self.root = root
        img = root.find("image")
        self.image_w, self.image_h = int(img.get("width")), int(img.get("height"))
        self.tilecount = int(root.get("tilecount"))
        self.columns = int(root.get("columns"))
        assert self.columns == COLS and int(root.get("tilewidth")) == T
        self.tiles = {}        # id -> dict(prob, props, rects)
        for t in root.findall("tile"):
            tid = int(t.get("id"))
            props = {}
            for p in t.findall("properties/property"):
                v = p.get("value")
                ty = p.get("type", "string")
                if ty == "bool": v = (v == "true")
                elif ty == "int": v = int(v)
                elif ty == "float": v = float(v)
                props[p.get("name")] = (ty, v)
            rects = [(float(o.get("x", 0)), float(o.get("y", 0)), float(o.get("width", 0)), float(o.get("height", 0)),
                      o.get("type") or o.get("class") or "")
                     for o in t.findall("objectgroup/object")]
            self.tiles[tid] = dict(prob=float(t.get("probability", 1)), props=props, rects=rects,
                                   type=t.get("type") or t.get("class"))
        # wangsets: name -> {wangid tuple(0/1 overlay) -> [(tid, prob)]}
        self.wang = {}
        self.wang_xml = []
        for ws in root.findall("wangsets/wangset"):
            m = {}
            for wt in ws.findall("wangtile"):
                wid = tuple(int(v) for v in wt.get("wangid").split(","))
                key = tuple(1 if v == 2 else 0 for v in wid)
                tid = int(wt.get("tileid"))
                m.setdefault(key, []).append((tid, self.tiles.get(tid, {}).get("prob", 1.0)))
            self.wang[ws.get("name")] = m
            self.wang_xml.append(ws)
        # props: name -> (w, h, ids row-major)
        groups = {}
        for tid, t in self.tiles.items():
            if "prop" in t["props"]:
                groups.setdefault(t["props"]["prop"][1], []).append(tid)
        self.props = {}
        for n, ids in groups.items():
            xs = [i % COLS for i in ids]; ys = [i // COLS for i in ids]
            w, h = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
            grid = [[(min(ys) + j) * COLS + min(xs) + i for i in range(w)] for j in range(h)]
            # irregular shapes (e.g. monolith 209,225): keep only real ids, -1 elsewhere
            grid = [[g if g in ids else -1 for g in row] for row in grid]
            self.props[n] = (w, h, grid)
        self.problems = []

    def collides(self, tid):
        return tid >= 0 and bool(self.tiles.get(tid, {}).get("rects"))

    def to_json(self, firstgid, image_path):
        tiles = []
        for tid in sorted(self.tiles):
            t = self.tiles[tid]
            d = {"id": tid}
            if t["prob"] != 1: d["probability"] = t["prob"]
            if t["type"]: d["type"] = t["type"]
            if t["props"]:
                d["properties"] = [{"name": k, "type": ty, "value": v} for k, (ty, v) in sorted(t["props"].items())]
            if t["rects"]:
                d["objectgroup"] = {"draworder": "index", "id": 2, "name": "", "opacity": 1, "type": "objectgroup",
                                    "visible": True, "x": 0, "y": 0,
                                    "objects": [{"id": i + 1, "name": "", "type": ty, "rotation": 0, "visible": True,
                                                 "x": x, "y": y, "width": w, "height": h}
                                                for i, (x, y, w, h, ty) in enumerate(t["rects"])]}
            tiles.append(d)
        wangsets = []
        for ws in self.wang_xml:
            wangsets.append({
                "name": ws.get("name"), "type": ws.get("type"), "tile": int(ws.get("tile", -1)),
                "colors": [{"name": c.get("name"), "color": c.get("color"), "tile": int(c.get("tile", -1)),
                            "probability": float(c.get("probability", 1))} for c in ws.findall("wangcolor")],
                "wangtiles": [{"tileid": int(w.get("tileid")),
                               "wangid": [int(v) for v in w.get("wangid").split(",")]} for w in ws.findall("wangtile")],
            })
        return {"firstgid": firstgid, "name": self.name, "image": image_path,
                "imagewidth": self.image_w, "imageheight": self.image_h, "tilewidth": T, "tileheight": T,
                "tilecount": self.tilecount, "columns": self.columns, "margin": 0, "spacing": 0,
                "tiles": tiles, "wangsets": wangsets}

    def sheet(self):
        im = Image.open(os.path.join(TSDIR, f"{self.name}.png")).convert("RGBA")
        return {tid: im.crop(((tid % COLS) * T, (tid // COLS) * T, (tid % COLS + 1) * T, (tid // COLS + 1) * T))
                for tid in range(self.tilecount)}

# --------------------------------------------------------------- terrain helpers
def blob(ts, wangset, grid, x, y, rng, exclude=()):
    """Tile for cell (x,y) of a boolean overlay grid using the 47-tile blob rule
    (corner counts only when both neighbouring edges are overlay). Out of
    bounds clamps to the edge cell."""
    H, W = grid.shape
    def B(xx, yy): return bool(grid[min(max(yy, 0), H - 1), min(max(xx, 0), W - 1)])
    if not grid[y, x]:
        key = (0,) * 8
    else:
        t, r, b, l = B(x, y - 1), B(x + 1, y), B(x, y + 1), B(x - 1, y)
        tr = t and r and B(x + 1, y - 1); br = b and r and B(x + 1, y + 1)
        bl = b and l and B(x - 1, y + 1); tl = t and l and B(x - 1, y - 1)
        key = tuple(int(v) for v in (t, tr, r, br, b, bl, l, tl))
    cands = [c for c in ts.wang[wangset].get(key, []) if c[0] not in exclude]
    if not cands:
        raise SystemExit(f"{ts.name}/{wangset}: no tile for wangid {key} at {x},{y}")
    if len(cands) == 1: return cands[0][0]
    p = np.array([c[1] for c in cands], float); p /= p.sum()
    return int(cands[rng.choice(len(cands), p=p)][0])

def disk_carve(mask, cx, cy, r):
    H, W = mask.shape
    Y, X = np.mgrid[0:H, 0:W]
    mask |= (X + 0.5 - cx) ** 2 + (Y + 0.5 - cy) ** 2 <= r * r

def seg_carve(mask, a, b, r):
    H, W = mask.shape
    Y, X = np.mgrid[0:H, 0:W]
    px, py = X + 0.5, Y + 0.5
    ax, ay = a; bx, by = b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy or 1e-9
    t = np.clip(((px - ax) * dx + (py - ay) * dy) / L2, 0, 1)
    mask |= (px - ax - t * dx) ** 2 + (py - ay - t * dy) ** 2 <= r * r

def rect_carve(mask, x0, y0, x1, y1):
    mask[y0:y1, x0:x1] = True

def clean_walls(wall, border=2):
    """Every wall cell must be part of a 2x2 wall block (blob tiles need it;
    thinner bits would render as floor and have no collision)."""
    H, W = wall.shape
    wall = wall.copy()
    wall[:border, :] = wall[-border:, :] = True
    wall[:, :border] = wall[:, -border:] = True
    for _ in range(4):
        keep = np.zeros_like(wall)
        b = wall[:-1, :-1] & wall[1:, :-1] & wall[:-1, 1:] & wall[1:, 1:]
        keep[:-1, :-1] |= b; keep[1:, :-1] |= b; keep[:-1, 1:] |= b; keep[1:, 1:] |= b
        if (keep == wall).all(): break
        wall = keep
    return wall

# --------------------------------------------------------------- map assembly
class Level:
    def __init__(self, ts, W, H, seed):
        self.ts, self.W, self.H = ts, W, H
        self.rng = np.random.default_rng(seed)
        self.floor = np.zeros((H, W), bool)
        self.ground = np.full((H, W), -1, int)
        self.props = np.full((H, W), -1, int)
        self.objects = []           # dicts
        self.keepout = np.zeros((H, W), bool)   # no colliding props here (paths, clearings)

    def obj(self, kind, x, y, w, h, **props):
        self.objects.append(dict(name=kind, x=float(x), y=float(y), w=float(w), h=float(h), props=props))

    def stamp(self, name, x, y, layer=None):
        w, h, grid = self.ts.props[name]
        L = self.props if layer is None else layer
        for j in range(h):
            for i in range(w):
                if grid[j][i] >= 0: L[y + j, x + i] = grid[j][i]

    def prop_fits(self, name, x, y, need_floor=True):
        w, h, grid = self.ts.props[name]
        if x < 0 or y < 0 or x + w > self.W or y + h > self.H: return False
        col = any(self.ts.collides(g) for row in grid for g in row if g >= 0)
        for j in range(h):
            for i in range(w):
                if grid[j][i] < 0: continue
                if self.props[y + j, x + i] >= 0: return False
                if need_floor and (not self.floor[y + j, x + i] or self.ts.collides(self.ground[y + j, x + i])): return False
                if col and self.keepout[y + j, x + i]: return False
                if not col and self.keepout_hard[y + j, x + i]: return False
        return True

    def scatter(self, names, n, tries=4000, need_floor=True, only=None):
        placed = 0
        for _ in range(tries):
            if placed >= n: break
            name = names[self.rng.integers(len(names))]
            x, y = int(self.rng.integers(self.W)), int(self.rng.integers(self.H))
            if only is not None and not only[y, x]: continue
            if self.prop_fits(name, x, y, need_floor):
                self.stamp(name, x, y); placed += 1
        return placed

    def walkable(self):
        ok = np.ones((self.H, self.W), bool)
        for y in range(self.H):
            for x in range(self.W):
                if self.ts.collides(self.ground[y, x]) or self.ts.collides(self.props[y, x]):
                    ok[y, x] = False
        return ok

    def validate(self):
        ok = self.walkable()
        spawn = [o for o in self.objects if o["name"] == "spawn"]
        assert len(spawn) == 1, "need exactly one spawn"
        def cells(o):
            x0, y0 = int(o["x"] // T), int(o["y"] // T)
            x1, y1 = int((o["x"] + o["w"] - 0.01) // T), int((o["y"] + o["h"] - 0.01) // T)
            return [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]
        for o in self.objects:
            for (x, y) in cells(o):
                if not ok[y, x]:
                    raise SystemExit(f"{o['name']} {o['props']} at tile {x},{y} is not on walkable floor")
        sx, sy = cells(spawn[0])[0]
        seen = np.zeros_like(ok); q = deque([(sx, sy)]); seen[sy, sx] = True
        while q:
            x, y = q.popleft()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < self.W and 0 <= ny < self.H and ok[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True; q.append((nx, ny))
        for o in self.objects:
            if o["name"] in ("drone", "sentinel"): continue   # they fly; just need floor
            if not all(seen[y, x] for (x, y) in cells(o)):
                raise SystemExit(f"{o['name']} {o['props']} not reachable from spawn")
        # UECDrone detection radius is 160 px (220 before the calm pass; centre
        # to centre) and it patrols a 70 px circle around its origin; keep
        # enemies outside that reach so the player isn't attacked at the spawn.
        scx, scy = spawn[0]["x"] + spawn[0]["w"] / 2, spawn[0]["y"] + spawn[0]["h"] / 2
        for o in self.objects:
            if o["name"] in ("drone", "sentinel"):
                d = ((o["x"] + o["w"] / 2 - scx) ** 2 + (o["y"] + o["h"] / 2 - scy) ** 2) ** 0.5
                if d < 320:
                    raise SystemExit(f"{o['name']} {o['props']} is {d:.0f}px from spawn (< 320)")
        # Checkpoints: the player respawns here, so no enemy may reach them.
        # UECDrone: 160 px detection + 70 px patrol circle (+30 margin);
        # SentinelDrone: 260 px detection (+40 margin).
        cps = [o for o in self.objects if o["name"] == "checkpoint"]
        if not cps or not any(c["x"] == spawn[0]["x"] and c["y"] == spawn[0]["y"] for c in cps):
            raise SystemExit("need a checkpoint at the spawn")
        for c in cps:
            ccx, ccy = c["x"] + c["w"] / 2, c["y"] + c["h"] / 2
            for o in self.objects:
                lim = CP_CLEAR.get(o["name"])
                if lim is None: continue
                d = ((o["x"] + o["w"] / 2 - ccx) ** 2 + (o["y"] + o["h"] / 2 - ccy) ** 2) ** 0.5
                if d < lim:
                    raise SystemExit(f"checkpoint {c['props']} is {d:.0f}px from {o['name']} (< {lim})")
        return ok, seen

    def write(self, fname, image_rel):
        ok, seen = self.validate()
        ts = self.ts
        def lay(i, name, arr):
            return {"id": i, "name": name, "type": "tilelayer", "x": 0, "y": 0, "width": self.W, "height": self.H,
                    "opacity": 1, "visible": True, "data": [int(v) + 1 if v >= 0 else 0 for v in arr.flatten()]}
        objs = []
        for i, o in enumerate(self.objects):
            d = {"id": i + 1, "name": o["name"], "type": "", "rotation": 0, "visible": True,
                 "x": o["x"], "y": o["y"], "width": o["w"], "height": o["h"]}
            if o["props"]:
                d["properties"] = [{"name": k, "type": ("float" if isinstance(v, float) else
                                                         "bool" if isinstance(v, bool) else
                                                         "int" if isinstance(v, int) else "string"), "value": v}
                                   for k, v in o["props"].items()]
            objs.append(d)
        tmj = {"compressionlevel": -1, "type": "map", "version": "1.10", "tiledversion": "1.10.2",
               "orientation": "orthogonal", "renderorder": "right-down", "infinite": False,
               "width": self.W, "height": self.H, "tilewidth": T, "tileheight": T,
               "nextlayerid": 4, "nextobjectid": len(objs) + 1,
               "properties": [{"name": "generator", "type": "string", "value": "tools/make_tiled_maps.py"}],
               "tilesets": [ts.to_json(1, image_rel)],
               "layers": [lay(1, "ground", self.ground), lay(2, "props", self.props),
                          {"id": 3, "name": "gameplay", "type": "objectgroup", "draworder": "topdown",
                           "x": 0, "y": 0, "opacity": 1, "visible": True, "objects": objs}]}
        with open(os.path.join(OUT, fname), "w") as f:
            json.dump(tmj, f, separators=(",", ":"))
        if not PREVIEW:
            return
        # preview: map + red tint on blocked tiles + object boxes
        tiles = ts.sheet()
        im = Image.new("RGBA", (self.W * T, self.H * T), (0, 0, 0, 255))
        for L in (self.ground, self.props):
            for y in range(self.H):
                for x in range(self.W):
                    if L[y, x] >= 0: im.alpha_composite(tiles[int(L[y, x])], (x * T, y * T))
        from PIL import ImageDraw
        d = ImageDraw.Draw(im)
        col = dict(spawn=(0, 255, 0), portal=(0, 255, 255), npc=(255, 255, 0), fragment=(200, 80, 255),
                   health=(0, 255, 120), drone=(255, 60, 60), sentinel=(255, 120, 0),
                   checkpoint=(120, 255, 220))
        for o in self.objects:
            d.rectangle([o["x"], o["y"], o["x"] + o["w"], o["y"] + o["h"]], outline=col[o["name"]], width=2)
        os.makedirs(PREVIEW, exist_ok=True)
        im.convert("RGB").resize((self.W * 16, self.H * 16)).save(os.path.join(PREVIEW, "preview_" + fname.replace(".tmj", ".png")))
        n_col = int((~ok).sum())
        print(f"{fname}: {self.W}x{self.H} tiles ({self.W*T}x{self.H*T}px), {len(objs)} objects, "
              f"{n_col} blocking tiles, reachable floor {int(seen.sum())}")

# --------------------------------------------------------------- sizes used by the code
SZ = dict(spawn=32, portal=56, npc=30, fragment=18, health=16, drone=24, sentinel=48, checkpoint=32)
# min centre distance from a checkpoint to each enemy kind (see validate)
CP_CLEAR = dict(drone=260, sentinel=300)

def place(lv, kind, tx, ty, **props):
    """place an object whose CENTRE is at tile coords (tx, ty) (floats)"""
    s = SZ[kind]
    lv.obj(kind, round(tx * T - s / 2), round(ty * T - s / 2), s, s, **props)

def carve_route(lv, pts, half, mask=None):
    m = lv.floor if mask is None else mask
    for a, b in zip(pts, pts[1:]):
        seg_carve(m, a, b, half)

# =============================================================== MAP 1: woods
def map1():
    ts = Tileset("woods")
    lv = Level(ts, 34, 60, seed=11)
    # gameplay points in tile coords (centres), derived from the old painted map
    P = dict(spawn=(10, 6.5), gaia=(13, 5.5), f1=(6.5, 10.5), d1=(5, 15.5), h1=(12.5, 15),
             f2=(19.5, 16.5), d2=(22, 13), h2=(8, 23), d3=(12, 25.5), f3=(9.5, 27.5),
             asha=(16, 30.5), h3=(20, 33.5), f4=(24, 38.5), f5=(13.5, 43), portal=(20, 53))
    route = ["spawn", "f1", "d1", "h1", "f2", "h2", "f3", "asha", "h3", "f4", "f5", "portal"]
    carve_route(lv, [P[k] for k in route], 1.9)
    for k, (x, y) in P.items():
        disk_carve(lv.floor, x, y, 3.2 if k not in ("portal", "spawn") else 4.2)
    seg_carve(lv.floor, P["f2"], P["d2"], 1.9); seg_carve(lv.floor, P["spawn"], P["gaia"], 1.9)
    seg_carve(lv.floor, P["h2"], P["d3"], 1.9)
    # a side glade with a pond east of the trail (optional exploring, more room for drones)
    glade = np.zeros_like(lv.floor); disk_carve(glade, 26, 24, 4.5); disk_carve(glade, 24, 27, 3.5)
    seg_carve(glade, P["f2"], (25, 22), 1.9); lv.floor |= glade
    wall = clean_walls(~lv.floor)
    lv.floor = ~wall
    water = np.zeros_like(wall); rect_carve(water, 26, 23, 29, 26); water &= lv.floor
    # dirt path: 2 wide along the route
    path = np.zeros_like(wall); carve_route(lv, [P[k] for k in route], 1.05, path)
    path &= lv.floor & ~water
    # keep the dirt path 2x2-clean too
    path = clean_walls(path, border=0) & path
    for y in range(lv.H):
        for x in range(lv.W):
            if wall[y, x] or not (water[y, x] or path[y, x]):
                lv.ground[y, x] = blob(ts, "grass-forest", wall, x, y, lv.rng)
            if water[y, x]: lv.ground[y, x] = blob(ts, "grass-water", water, x, y, lv.rng)
            if path[y, x]: lv.ground[y, x] = blob(ts, "grass-path", path, x, y, lv.rng)
    # keep-out: route corridor + point clearings
    carve_route(lv, [P[k] for k in route], 2.4, lv.keepout)
    lv.keepout_hard = np.zeros_like(wall)
    for k, (x, y) in P.items():
        disk_carve(lv.keepout, x, y, 2.6); disk_carve(lv.keepout_hard, x, y, 1.6)
    # props
    lv.stamp("crashed_ship", 2, 2) if lv.prop_fits("crashed_ship", 2, 2) else None
    lv.scatter(["tree_green", "tree_teal", "tree_blue", "tree_purple", "tree_pine", "boulder", "bush_green",
                "bush_glow", "rock_small", "rock_moss", "log", "stump"], 26)
    lv.scatter(["mushrooms", "flowers", "lantern"], 22)
    lv.stamp("campfire", 7, 4) if lv.prop_fits("campfire", 7, 4) else None
    # gameplay objects
    place(lv, "spawn", *P["spawn"])
    place(lv, "npc", *P["gaia"], name="gaia")
    place(lv, "npc", *P["asha"], name="asha")
    for k in ("f1", "f2", "f3", "f4", "f5"): place(lv, "fragment", *P[k])
    for k in ("h1", "h2", "h3"): place(lv, "health", *P[k])
    # calm pass: d3 (between the second health pickup and Asha) is gone; its
    # clearing stays so the terrain is unchanged.
    for k, a in (("d1", 0.0), ("d2", 2.1)): place(lv, "drone", *P[k], startAngle=a)
    place(lv, "portal", *P["portal"])
    # checkpoints (respawn points): spawn + area entrances, beside the points
    # so they sit in already-clear spots
    place(lv, "checkpoint", *P["spawn"], label="Crash Site")
    place(lv, "checkpoint", P["h2"][0] + 1.0, P["h2"][1] + 1.2, label="Mossy Hollow")
    place(lv, "checkpoint", P["asha"][0] + 1.5, P["asha"][1] + 1.0, label="Asha's Trail")
    place(lv, "checkpoint", P["f5"][0] + 1.2, P["f5"][1] + 1.2, label="Old Grove")
    place(lv, "checkpoint", P["portal"][0] - 2.5, P["portal"][1] - 2.0, label="Aetherian Gate")
    lv.write("world.tmj", "tilesets/woods.png")
    return ts

# =============================================================== MAP 2: city
def map2():
    ts = Tileset("city")
    lv = Level(ts, 34, 46, seed=22)
    P = dict(spawn=(16.5, 4.5), echo7=(12.5, 7.5), h1=(17.5, 12.5), d1=(6.5, 17.5), arch=(17.5, 20.5),
             h2=(14.5, 21.5), d2=(25.5, 27), sentinel=(16.5, 29), h3=(17.5, 33), voss=(11.5, 37.5),
             portal=(16.5, 41))
    road = np.zeros((lv.H, lv.W), bool)
    rect_carve(road, 15, 2, 19, 44)            # main avenue (asphalt) N-S
    rect_carve(road, 4, 16, 15, 19)            # west street to the drone yard
    floor = np.zeros_like(road)
    rect_carve(floor, 11, 2, 23, 44)           # avenue incl. sidewalks
    rect_carve(floor, 3, 14, 11, 21)           # west yard
    rect_carve(floor, 2, 15, 11, 20)
    rect_carve(floor, 7, 25, 29, 35)           # Sentinel plaza (boss arena)
    rect_carve(floor, 22, 23, 30, 31)          # east lot (drone 2)
    rect_carve(floor, 8, 35, 13, 40)           # Voss alcove
    rect_carve(floor, 9, 2, 25, 6)             # top street at the spawn
    rect_carve(floor, 12, 39, 22, 44)          # portal square
    lv.floor = floor | road
    wall = clean_walls(~lv.floor)
    lv.floor = ~wall
    road &= lv.floor
    road = clean_walls(road, border=0) & road
    sidewalk = ~road           # building cells count as sidewalk for the road blob
    for y in range(lv.H):
        for x in range(lv.W):
            if wall[y, x]:
                lv.ground[y, x] = blob(ts, "sidewalk-building", wall, x, y, lv.rng)
            else:
                # 4-8 are hand-placed decals (lanes, crosswalks, arrow) but the
                # tsx lists them as random all-asphalt variants; skip them here.
                lv.ground[y, x] = blob(ts, "road-sidewalk", sidewalk, x, y, lv.rng, exclude={4, 5, 6, 7, 8})
    # plaza tiles in the arena interior (plain variants, by hand)
    for y in range(27, 33):
        for x in range(9, 15):
            if not road[y, x]: lv.ground[y, x] = 12 if (x * 7 + y * 3) % 5 else 13
    for y in range(27, 33):
        for x in range(20, 27):
            if not road[y, x] and not wall[y, x]: lv.ground[y, x] = 12 if (x * 7 + y * 3) % 5 else 13
    lv.keepout = road.copy()
    lv.keepout_hard = np.zeros_like(wall)
    for k, (x, y) in P.items():
        disk_carve(lv.keepout, x, y, 2.8); disk_carve(lv.keepout_hard, x, y, 1.6)
    rect_carve(lv.keepout, 7, 25, 29, 35)      # keep the boss arena open
    # crosswalks on the avenue
    for x in range(15, 19):
        lv.ground[16, x] = 6; lv.ground[19, x] = 6
    # props on sidewalks (never on the asphalt), roof props on building interiors
    lv.scatter(["street_lamp", "planter_small", "bench", "trash_bin", "hydrant", "bollard", "vending_machine"], 26)
    lv.scatter(["planter_tree", "kiosk", "bus_stop"], 5)
    interior = np.zeros_like(wall)
    interior[1:-1, 1:-1] = (wall[1:-1, 1:-1] & wall[:-2, 1:-1] & wall[2:, 1:-1] & wall[1:-1, :-2] & wall[1:-1, 2:])
    lv.scatter(["rooftop_ac", "rooftop_vent", "solar_panel"], 30, need_floor=False, only=interior)
    place(lv, "spawn", *P["spawn"])
    place(lv, "npc", *P["echo7"], name="echo7")
    place(lv, "npc", *P["arch"], name="archivist")
    place(lv, "npc", *P["voss"], name="voss")
    for k in ("h1", "h2", "h3"): place(lv, "health", *P[k])
    place(lv, "sentinel", *P["sentinel"])
    place(lv, "drone", *P["d1"], startAngle=1.0)
    place(lv, "drone", *P["d2"], startAngle=3.3)
    place(lv, "portal", *P["portal"])
    place(lv, "checkpoint", *P["spawn"], label="Upper Street")
    place(lv, "checkpoint", P["h1"][0] - 1.5, P["h1"][1] + 1.0, label="Avenue")
    place(lv, "checkpoint", P["voss"][0] + 2.0, P["voss"][1] + 2.5, label="Portal Square")
    lv.write("world2.tmj", "tilesets/city.png")
    return ts

# =============================================================== MAP 3: cyberpunk ruins
def map3():
    ts = Tileset("cyberpunk")
    lv = Level(ts, 46, 46, seed=33)
    P = dict(spawn=(5.5, 5.5), h1=(6, 13), d1=(16, 6), d2=(18, 12), h2=(17, 18), d3=(26, 5),
             h3=(31, 7), d4=(33, 19), h4=(35, 27), d5=(23, 29), d6=(12, 36), portal=(39.5, 39.5))
    edges = [("spawn", "d1"), ("spawn", "h1"), ("d1", "d2"), ("d2", "h2"), ("h1", "h2"), ("d1", "d3"),
             ("d3", "h3"), ("h3", "d4"), ("h2", "d4"), ("d4", "h4"), ("h4", "portal"), ("h2", "d5"),
             ("d5", "d6"), ("d5", "portal")]
    for a, b in edges: seg_carve(lv.floor, P[a], P[b], 1.9)
    for k, (x, y) in P.items(): disk_carve(lv.floor, x, y, 3.3 if k not in ("spawn", "portal") else 4.2)
    wall = clean_walls(~lv.floor)
    lv.floor = ~wall
    metal = np.zeros_like(wall)
    disk_carve(metal, *P["spawn"], 2.6); disk_carve(metal, *P["portal"], 3.2)
    metal &= lv.floor; metal = clean_walls(metal, border=0) & metal
    sludge = np.zeros_like(wall)
    rect_carve(sludge, 20, 15, 23, 18)          # pool beside the central clearing
    rect_carve(sludge, 27, 30, 30, 33)
    sludge &= lv.floor
    for y in range(lv.H):
        for x in range(lv.W):
            if wall[y, x] or not (metal[y, x] or sludge[y, x]):
                lv.ground[y, x] = blob(ts, "asphalt-ruin", wall, x, y, lv.rng)
            if metal[y, x]: lv.ground[y, x] = blob(ts, "asphalt-metal", metal, x, y, lv.rng)
            if sludge[y, x]: lv.ground[y, x] = blob(ts, "asphalt-sludge", sludge, x, y, lv.rng)
    lv.keepout = np.zeros_like(wall); lv.keepout_hard = np.zeros_like(wall)
    for a, b in edges: seg_carve(lv.keepout, P[a], P[b], 2.3)
    for k, (x, y) in P.items():
        disk_carve(lv.keepout, x, y, 2.8); disk_carve(lv.keepout_hard, x, y, 1.6)
    lv.scatter(["rubble_small", "rubble_large", "wrecked_car_v", "wrecked_car_h", "barrel_purple", "barrel_toxic",
                "dumpster", "crate", "broken_pillar", "barricade", "neon_streetlight", "drone_wreck",
                "vending_broken", "terminal"], 30)
    lv.scatter(["steam_vent", "loose_cables"], 14)
    place(lv, "spawn", *P["spawn"])
    for k in ("h1", "h2", "h3", "h4"): place(lv, "health", *P[k])
    # calm pass: 6 -> 4 drones (d2 next to the central clearing and d6 in the
    # south-west dead end are gone; their clearings stay)
    for k, a in (("d1", 0.5), ("d3", 3.1), ("d4", 4.5), ("d5", 2.3)):
        place(lv, "drone", *P[k], startAngle=a)
    place(lv, "portal", *P["portal"])
    place(lv, "checkpoint", *P["spawn"], label="Ruined Landing")
    place(lv, "checkpoint", P["h2"][0] - 1.2, P["h2"][1] + 1.2, label="Central Clearing")
    place(lv, "checkpoint", P["h4"][0] + 1.2, P["h4"][1] + 1.2, label="East Ruins")
    place(lv, "checkpoint", P["portal"][0] - 2.5, P["portal"][1] - 2.5, label="Extraction Approach")
    lv.write("world3.tmj", "tilesets/cyberpunk.png")
    return ts

if __name__ == "__main__":
    os.makedirs(os.path.join(OUT, "tilesets"), exist_ok=True)
    for n in ("woods", "city", "cyberpunk", "core"):
        shutil.copy(os.path.join(TSDIR, f"{n}.png"), os.path.join(OUT, "tilesets", f"{n}.png"))
    map1(); map2(); map3()
