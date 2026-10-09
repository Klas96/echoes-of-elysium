#!/usr/bin/env python3
"""Generate the Bonfire/Tiled levels for Echoes of Elysium.

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
  <out>/world4.tmj  Gaia Core         (tileset core)
  <out>/world5.tmj  Lantern Town hub  (tileset city)
  <out>/tilesets/<name>.png
  <preview>/preview_world*.png        (only with --preview: render + walkability)

Layers per map: "ground" (blob/wang terrain incl. walls), "props" (decor,
some collide via per-tile collision rects) and an object layer "gameplay"
with objects named spawn, portal, npc (property name), fragment, health,
drone (properties startAngle, kind=scout|sniper|shield|swarm), sentinel, checkpoint (property label). Object x/y = component top-left in
world px, width/height = component size (same coords the code used before).

M2 (woods only): creature (species, radius in tiles, netted, gated), stump
(the vine fox's sweetroot), pebble (the brookling's river pebble), stash
(glimmer), moonflower (decor), glyph (glyph id), hidden (glimmer; only found with the vine fox's
SCENT), hiddenpath (brambles the vine fox's SCENT opens), boulder (2x2 tiles,
pushX/pushY in tiles; needs the stone turtle's PUSH) and darkzone (a rect of
darkness; the glowmoth's LIGHT reveals the glyph inside). Ability gates only
guard secrets (glyph, stash, hidden, creatures marked gated).

Buildings (tools/buildings/buildings.tsj, art in assets/images/maps/buildings/)
are Tiled tile objects named "building" with a string property building=<id>.
The buildings tileset (collection of images) is embedded after the terrain
tileset. Tile objects are anchored bottom-left, so their x/y is the sprite's
bottom-left corner (the game subtracts the height). Each building sits in a
"lot" carved out of the walls after the terrain/props pass; only the cells
around a lot are re-tiled (separate RNG), so the rest of the map is unchanged.

The script checks that every gameplay object sits on fully walkable tiles and
that all of them are reachable from the spawn; it fails loudly otherwise.
Checkpoints (respawn points; one at the spawn plus one per area entrance) must
also stay clear of every enemy's reach, so respawning never lands in a fight.
Buildings must stand on clear floor, must not overlap gameplay objects or each
other, their door must be reachable, and their collision box must not cut off
any floor that was reachable without them.
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
BLDIR = os.path.join(HERE, "buildings")
BLIMG = os.path.join(ROOT, "assets", "images", "maps", "buildings")

# --------------------------------------------------------------- buildings
class Buildings:
    """tools/buildings/buildings.tsj: Tiled collection-of-images tileset, one
    tile per building with its collision rect (px from the sprite top-left)
    and door point as tile properties."""
    def __init__(self):
        with open(os.path.join(BLDIR, "buildings.tsj")) as f:
            self.tsj = json.load(f)
        self.defs = {}
        for i, t in enumerate(self.tsj["tiles"]):
            assert t["id"] == i, "buildings.tsj ids must be contiguous from 0 (Bonfire indexes by list position)"
            props = {p["name"]: p["value"] for p in t.get("properties", [])}
            cols = [o for o in t["objectgroup"]["objects"] if o.get("type") == "collision"]
            assert len(cols) == 1
            c = cols[0]
            assert c["height"] >= 2 * T and c["width"] >= 2 * T, "building collision must be >= 2 tiles"
            assert t["imagewidth"] % T == 0 and t["imageheight"] % T == 0
            self.defs[props["building"]] = dict(id=i, w=t["imagewidth"], h=t["imageheight"], image=t["image"],
                                                col=(c["x"], c["y"], c["width"], c["height"]),
                                                door=(props["door_x"], props["door_y"]))

    def to_json(self, firstgid):
        d = {k: v for k, v in self.tsj.items() if k not in ("type", "version", "tiledversion")}
        d["firstgid"] = firstgid
        d["tiles"] = [dict(t, image="buildings/" + t["image"]) for t in self.tsj["tiles"]]
        return d

BUILDINGS = Buildings()

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
        self.instances = []         # (prop name, x, y) stamped on the props layer
        self.buildings = []         # dicts: name, tx, ty (sprite top-left in tiles)
        self.seed = seed

    def obj(self, obj, x, y, w, h, **props):
        self.objects.append(dict(name=obj, x=float(x), y=float(y), w=float(w), h=float(h), props=props))

    def stamp(self, name, x, y, layer=None):
        w, h, grid = self.ts.props[name]
        L = self.props if layer is None else layer
        if layer is None: self.instances.append((name, x, y))
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

    def dilate(self, mask, r=1):
        out = mask.copy()
        for _ in range(r):
            m = out.copy()
            m[1:, :] |= out[:-1, :]; m[:-1, :] |= out[1:, :]
            m[:, 1:] |= out[:, :-1]; m[:, :-1] |= out[:, 1:]
            out = m
        return out

    def fringe(self, wall=None):
        """Walkable floor tiles that touch a wall (or non-floor) — good for trees/rubble."""
        w = (~self.floor) if wall is None else wall
        touch = np.zeros_like(self.floor)
        touch[1:, :] |= w[:-1, :]; touch[:-1, :] |= w[1:, :]
        touch[:, 1:] |= w[:, :-1]; touch[:, :-1] |= w[:, 1:]
        return self.floor & touch

    def path_edge(self):
        """Floor beside a keepout corridor but not on keepout_hard — lanterns, flowers."""
        near = self.dilate(self.keepout, 1) & ~self.keepout & self.floor
        return near & ~self.keepout_hard

    def cells_of(self, mask):
        ys, xs = np.nonzero(mask)
        return list(zip(xs.tolist(), ys.tolist()))

    def scatter_on(self, names, n, mask, tries=None, need_floor=True):
        """Place up to n props randomly among tiles where mask is True."""
        cells = self.cells_of(mask)
        if not cells or n <= 0: return 0
        tries = tries or max(n * 40, 800)
        placed = 0
        for _ in range(tries):
            if placed >= n: break
            name = names[self.rng.integers(len(names))]
            x, y = cells[self.rng.integers(len(cells))]
            if self.prop_fits(name, x, y, need_floor):
                self.stamp(name, x, y); placed += 1
        return placed

    def cluster(self, names, cx, cy, n, radius=2, need_floor=True):
        """A small composed group around (cx, cy) tile."""
        placed = 0
        for _ in range(n * 12):
            if placed >= n: break
            name = names[self.rng.integers(len(names))]
            x = int(cx + self.rng.integers(-radius, radius + 1))
            y = int(cy + self.rng.integers(-radius, radius + 1))
            if self.prop_fits(name, x, y, need_floor):
                self.stamp(name, x, y); placed += 1
        return placed

    def line_props(self, name, points, step=3, need_floor=True):
        """Stamp the same prop along a polyline of tile centres (e.g. lamps)."""
        placed = 0
        for a, b in zip(points, points[1:]):
            ax, ay = a; bx, by = b
            dist = max(abs(bx - ax), abs(by - ay), 1)
            for t in range(0, int(dist) + 1, step):
                u = t / dist
                x, y = int(round(ax + (bx - ax) * u)), int(round(ay + (by - ay) * u))
                if self.prop_fits(name, x, y, need_floor):
                    self.stamp(name, x, y); placed += 1
        return placed

    def building(self, name, tx, ty):
        """place building <name> with its sprite's top-left at tile (tx, ty)"""
        assert name in BUILDINGS.defs, name
        self.buildings.append(dict(name=name, tx=tx, ty=ty))

    def carve_lots(self, wall, lots, reground):
        """Open building lots (x0, y0, x1, y1 inclusive tile rects) in the
        walls after the terrain and props are done. Only cells next to a
        changed wall cell are re-tiled, with their own RNG, and props that
        touch a lot or a building sprite are removed, so the rest of the map
        (and the main RNG stream) stays exactly as before. reground(x, y,
        wall, rng) returns the ground tile for a re-tiled cell, or None to
        keep it. Returns the new wall mask."""
        new = wall.copy()
        for (x0, y0, x1, y1) in lots:
            assert x0 >= 2 and y0 >= 2 and x1 < self.W - 2 and y1 < self.H - 2, "lot touches the map border"
            new[y0:y1 + 1, x0:x1 + 1] = False
        new = clean_walls(new)
        changed = new != wall
        region = changed.copy()
        region[1:, :] |= changed[:-1, :]; region[:-1, :] |= changed[1:, :]
        r2 = region.copy()
        r2[:, 1:] |= region[:, :-1]; r2[:, :-1] |= region[:, 1:]
        rng = np.random.default_rng(self.seed + 1000)
        for y in range(self.H):
            for x in range(self.W):
                if r2[y, x]:
                    g = reground(x, y, new, rng)
                    if g is not None: self.ground[y, x] = g
        clear = np.zeros_like(wall)
        for (x0, y0, x1, y1) in lots: clear[y0:y1 + 1, x0:x1 + 1] = True
        for b in self.buildings:
            d = BUILDINGS.defs[b["name"]]
            clear[b["ty"]:b["ty"] + d["h"] // T, b["tx"]:b["tx"] + d["w"] // T] = True
        keep = []
        for (name, x, y) in self.instances:
            w, h, grid = self.ts.props[name]
            cells = [(x + i, y + j) for j in range(h) for i in range(w) if grid[j][i] >= 0]
            # gone: props in a lot / under a building, and roof props whose
            # wall cell opened up or got re-tiled as an edge
            if any(clear[cy, cx] or (r2[cy, cx] and wall[cy, cx]) for (cx, cy) in cells):
                for (cx, cy) in cells: self.props[cy, cx] = -1
            else:
                keep.append((name, x, y))
        self.instances = keep
        self.floor = ~new
        return new

    def building_rects(self, b):
        """(sprite rect, collision rect, door point) in world px"""
        d = BUILDINGS.defs[b["name"]]
        X, Y = b["tx"] * T, b["ty"] * T
        cx, cy, cw, ch = d["col"]
        return (X, Y, d["w"], d["h"]), (X + cx, Y + cy, cw, ch), (X + d["door"][0], Y + d["door"][1])

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
        def px_cells(x, y, w, h):     # tiles a px rect overlaps (any area)
            return [(cx, cy) for cy in range(int(y // T), int((y + h - 0.01) // T) + 1)
                    for cx in range(int(x // T), int((x + w - 0.01) // T) + 1)]
        def overlap(a, b):
            return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]
        def floorless(o):
            return o["name"] == "darkzone" or (o["name"] == "creature" and o["props"]["species"] in FLYING)
        for o in self.objects:
            if floorless(o): continue
            for (x, y) in cells(o):
                if not ok[y, x]:
                    raise SystemExit(f"{o['name']} {o['props']} at tile {x},{y} is not on walkable floor")
        sx, sy = cells(spawn[0])[0]
        def flood(mask):
            seen = np.zeros_like(mask); q = deque([(sx, sy)]); seen[sy, sx] = True
            while q:
                x, y = q.popleft()
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.W and 0 <= ny < self.H and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True; q.append((nx, ny))
            return seen
        # buildings: clear floor under the whole sprite, no overlaps with
        # objects or other buildings, collision box blocks its tiles
        bblock = np.zeros_like(ok)
        sprites = []
        for b in self.buildings:
            spr, col, door = self.building_rects(b)
            for (x, y) in px_cells(*spr):
                if not ok[y, x] or self.props[y, x] >= 0:
                    raise SystemExit(f"building {b['name']} sprite covers wall/prop at tile {x},{y}")
            for o in self.objects:
                if overlap(spr, (o["x"], o["y"], o["w"], o["h"])):
                    raise SystemExit(f"building {b['name']} overlaps {o['name']} {o['props']}")
            for (n2, s2) in sprites:
                if overlap(spr, s2): raise SystemExit(f"building {b['name']} overlaps building {n2}")
            sprites.append((b["name"], spr))
            for (x, y) in px_cells(*col): bblock[y, x] = True
            # enemies patrol a 70 px circle; keep them well away from walls
            for o in self.objects:
                if o["name"] in ("drone", "sentinel"):
                    ox, oy = o["x"] + o["w"] / 2, o["y"] + o["h"] / 2
                    dx = max(col[0] - ox, 0, ox - col[0] - col[2]); dy = max(col[1] - oy, 0, oy - col[1] - col[3])
                    if (dx * dx + dy * dy) ** 0.5 < 128:
                        raise SystemExit(f"building {b['name']} is too close to {o['name']} {o['props']}")
        before = flood(ok)
        ok = ok & ~bblock
        seen = flood(ok)
        lost = before & ~bblock & ~seen
        if lost.any():
            ys, xs = np.nonzero(lost)
            raise SystemExit(f"building collision cuts off {len(xs)} floor tiles, e.g. {xs[0]},{ys[0]}")
        for b in self.buildings:
            spr, col, door = self.building_rects(b)
            dx, dy = int(door[0] // T), int((col[1] + col[3] - 0.01) // T) + 1   # first tile in front of the door
            if not seen[dy, dx]:
                raise SystemExit(f"building {b['name']} door (tile {dx},{dy}) is not reachable")
        for o in self.objects:
            if o["name"] in ("drone", "sentinel"): continue   # they fly; just need floor
            if floorless(o): continue
            if not all(seen[y, x] for (x, y) in cells(o)):
                raise SystemExit(f"{o['name']} {o['props']} not reachable from spawn")
        self.validate_secrets(ok, seen, cells, flood)
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

    def validate_secrets(self, ok, seen, cells, flood):
        """Ability gates (M2): a boulder must block something optional and be
        pushable into open floor; nothing but secrets may sit behind it; ground
        creatures' habitats must be floor; dark zones must cover a glyph."""
        objs = self.objects
        gates = [o for o in objs if o["name"] in ("boulder", "hiddenpath")]
        blocked = ok.copy()
        for g in gates:
            for (x, y) in cells(g): blocked[y, x] = False
        with_all = flood(blocked)
        def secret(o):
            return o["name"] in SECRET_KINDS or (o["name"] == "creature" and o["props"].get("gated"))
        for g in gates:
            opened = blocked.copy()
            for (x, y) in cells(g): opened[y, x] = True
            if g["name"] == "boulder":
                px, py = g["props"]["pushX"], g["props"]["pushY"]
                moved = dict(g, x=g["x"] + px * T, y=g["y"] + py * T)
                for (x, y) in cells(moved):
                    if not ok[y, x]:
                        raise SystemExit(f"boulder at {g['x']},{g['y']} would be pushed onto wall at tile {x},{y}")
                for (x, y) in cells(moved): opened[y, x] = False
            gained = flood(opened) & ~with_all
            inside = [o for o in objs if any(gained[y, x] for (x, y) in cells(o))]
            if not any(secret(o) for o in inside):
                raise SystemExit(f"{g['name']} at {g['x']},{g['y']} guards no secret")
        for o in objs:
            if o["name"] in ("drone", "sentinel", "darkzone", "boulder", "hiddenpath"): continue
            if o["name"] == "creature" and o["props"]["species"] in FLYING: continue
            if secret(o): continue
            if not all(with_all[y, x] for (x, y) in cells(o)):
                raise SystemExit(f"{o['name']} {o['props']} is behind an ability gate (only secrets may be)")
        for o in objs:
            if o["name"] != "creature" or o["props"]["species"] in FLYING: continue
            cx, cy = (o["x"] + o["w"] / 2) / T, (o["y"] + o["h"] / 2) / T
            r = o["props"]["radius"]
            for y in range(int(cy - r - 1), int(cy + r + 2)):
                for x in range(int(cx - r - 1), int(cx + r + 2)):
                    if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r and not ok[y, x]:
                        raise SystemExit(f"creature {o['props']['species']} habitat covers blocked tile {x},{y}")
        for z in (o for o in objs if o["name"] == "darkzone"):
            if not any(g["name"] == "glyph" and z["x"] <= g["x"] and g["x"] + g["w"] <= z["x"] + z["w"]
                       and z["y"] <= g["y"] and g["y"] + g["h"] <= z["y"] + z["h"] for g in objs):
                raise SystemExit(f"dark zone at {z['x']},{z['y']} hides no glyph")

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
        bfirst = ts.tilecount + 1
        for b in self.buildings:
            bd = BUILDINGS.defs[b["name"]]
            # tile object: x/y is the bottom-left of the sprite
            objs.append({"id": len(objs) + 1, "name": "building", "type": "", "gid": bfirst + bd["id"],
                         "rotation": 0, "visible": True, "x": float(b["tx"] * T), "y": float((b["ty"] * T) + bd["h"]),
                         "width": float(bd["w"]), "height": float(bd["h"]),
                         "properties": [{"name": "building", "type": "string", "value": b["name"]}]})
        tmj = {"compressionlevel": -1, "type": "map", "version": "1.10", "tiledversion": "1.10.2",
               "orientation": "orthogonal", "renderorder": "right-down", "infinite": False,
               "width": self.W, "height": self.H, "tilewidth": T, "tileheight": T,
               "nextlayerid": 4, "nextobjectid": len(objs) + 1,
               "properties": [{"name": "generator", "type": "string", "value": "tools/make_tiled_maps.py"}],
               "tilesets": [ts.to_json(1, image_rel), BUILDINGS.to_json(ts.tilecount + 1)],
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
                   checkpoint=(120, 255, 220), creature=(255, 170, 255), stump=(200, 140, 60),
                   boulder=(160, 160, 160), stash=(255, 230, 90), glyph=(90, 255, 255), hidden=(255, 140, 200),
                   darkzone=(40, 40, 120), pebble=(140, 200, 255), moonflower=(240, 240, 255),
                   hiddenpath=(255, 120, 200), examine=(140, 220, 255))
        for b in sorted(self.buildings, key=lambda b: b["ty"]):
            spr, bc, door = self.building_rects(b)
            bim = Image.open(os.path.join(BLIMG, BUILDINGS.defs[b["name"]]["image"])).convert("RGBA")
            im.alpha_composite(bim, (int(spr[0]), int(spr[1])))
            d.rectangle([bc[0], bc[1], bc[0] + bc[2], bc[1] + bc[3]], outline=(255, 60, 160), width=2)
            d.ellipse([door[0] - 3, door[1] - 3, door[0] + 3, door[1] + 3], fill=(255, 230, 0))
        for o in self.objects:
            d.rectangle([o["x"], o["y"], o["x"] + o["w"], o["y"] + o["h"]], outline=col[o["name"]], width=2)
        os.makedirs(PREVIEW, exist_ok=True)
        im.convert("RGB").resize((self.W * 16, self.H * 16)).save(os.path.join(PREVIEW, "preview_" + fname.replace(".tmj", ".png")))
        n_col = int((~ok).sum())
        if os.environ.get("PREVIEW_FULL"):
            im.convert("RGB").save(os.path.join(PREVIEW, "full_" + fname.replace(".tmj", ".png")))
        print(f"{fname}: {self.W}x{self.H} tiles ({self.W*T}x{self.H*T}px), {len(objs)} objects, "
              f"{n_col} blocking tiles, reachable floor {int(seen.sum())}")

# --------------------------------------------------------------- sizes used by the code
SZ = dict(spawn=32, portal=56, npc=30, fragment=18, health=16, drone=24, sentinel=48, checkpoint=32,
          creature=32, stump=64, stash=32, glyph=24, hidden=24, pebble=16, moonflower=16, examine=20)
# creatures that fly (no floor needed under their habitat)
FLYING = {"glowmoth"}
# objects an ability gate may hide; anything else behind a boulder is an error
SECRET_KINDS = {"glyph", "stash", "hidden", "moonflower"}
# min centre distance from a checkpoint to each enemy kind (see validate)
CP_CLEAR = dict(drone=260, sentinel=300)

def place(lv, obj, tx, ty, **props):
    """place an object whose CENTRE is at tile coords (tx, ty) (floats).
    Extra kwargs become Tiled properties (e.g. kind='sniper', name='gaia')."""
    s = SZ[obj]
    lv.obj(obj, round(tx * T - s / 2), round(ty * T - s / 2), s, s, **props)

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
    # Reserve tiles that later get creatures / moonflowers / secrets
    for (fx, fy) in ((28.5, 21.5), (24.5, 24.5), (18.5, 40.5), (11.5, 21.5), (24.5, 21.5), (30.0, 33.0),
                     (24.5, 26.5), (22.5, 27.5), (25.5, 28.5), (27.5, 29.5), (28.5, 32.5),
                     (31.5, 32.5), (28.5, 33.5), (31.5, 33.5), (12.5, 12.5), (14.5, 46.5),
                     (26.5, 6.5), (30.5, 41.5), (29.5, 25.5), (21.5, 55.5)):
        disk_carve(lv.keepout, fx, fy, 1.4); disk_carve(lv.keepout_hard, fx, fy, 1.0)
    # Scenery: ship + camp as anchors; trees on forest fringe; soft flora on path edge
    lv.stamp("crashed_ship", 2, 2) if lv.prop_fits("crashed_ship", 2, 2) else None
    lv.stamp("campfire", 7, 4) if lv.prop_fits("campfire", 7, 4) else None
    fringe = lv.fringe(wall)
    edge = lv.path_edge()
    mid = lv.floor & ~lv.keepout_hard & ~fringe
    trees = ["tree_green", "tree_teal", "tree_blue", "tree_purple", "tree_pine"]
    big = ["boulder", "log", "stump"]
    bush = ["bush_green", "bush_glow", "rock_small", "rock_moss"]
    soft = ["mushrooms", "flowers", "lantern"]
    lv.scatter_on(trees, 16, fringe)
    lv.scatter_on(big, 6, fringe)
    lv.scatter_on(bush, 8, fringe | (edge & mid))
    lv.scatter_on(soft, 14, edge)
    lv.scatter_on(soft, 4, mid)                       # a few deep-glade accents
    lv.cluster(["flowers", "mushrooms", "lantern"], *P["h2"], 4, radius=2)
    lv.cluster(["flowers", "bush_glow"], *P["asha"], 3, radius=2)
    lv.cluster(["rock_moss", "flowers"], *P["portal"], 3, radius=3)
    # ranger cabin in a small clearing east of the crash site, off the trail
    lv.building("ranger_cabin", 16, 2)
    reground1 = lambda x, y, w, rng: None if (water[y, x] or path[y, x]) else blob(ts, "grass-forest", w, x, y, rng)
    wall = lv.carve_lots(wall, [(15, 2, 21, 7)], reground1)
    # M2 secret nooks behind a 2-tile tunnel through a 2-thick wall, each
    # plugged by a boulder just inside the nook (PUSH shoves it one tile
    # east, freeing the nook's west column). A separate pass so the rest of
    # the map stays as it was.
    wall = lv.carve_lots(wall, [(24, 2, 27, 7), (22, 4, 23, 5),      # beside the ranger cabin
                                (29, 36, 31, 42), (27, 38, 28, 39),   # east of the fourth fragment
                                (26, 29, 30, 29), (29, 30, 30, 31),   # hushdeer: trail, bramble gap,
                                (28, 32, 31, 33),                     # and the hidden glade below
                                (25, 27, 25, 28)],                    # (clears the pines in its way)
                         reground1)
    # gameplay objects
    place(lv, "spawn", *P["spawn"])
    place(lv, "npc", *P["gaia"], name="gaia")
    place(lv, "npc", *P["asha"], name="asha")
    # memory fragments 1-2 (dialogue-flashbacks-and-finale.md): both open the
    # portal. One on the eastern side branch, one past Asha. The old f1/f3/f5
    # clearings stay so the terrain is unchanged.
    for k in ("f2", "f4"): place(lv, "fragment", *P[k])
    for k in ("h1", "h2", "h3"): place(lv, "health", *P[k])
    # calm pass: d3 (between the second health pickup and Asha) is gone; its
    # clearing stays so the terrain is unchanged.
    # Variety: early scout, then a sniper on the side branch.
    place(lv, "drone", *P["d1"], startAngle=0.0, kind="scout")
    place(lv, "drone", *P["d2"], startAngle=2.1, kind="sniper")
    place(lv, "portal", *P["portal"])
    # checkpoints: spawn + mid trail + gate (fewer, ~15+ tiles apart)
    place(lv, "checkpoint", *P["spawn"], label="Crash Site")
    place(lv, "checkpoint", P["asha"][0] + 1.5, P["asha"][1] + 1.0, label="Asha's Trail")
    place(lv, "checkpoint", P["portal"][0] - 2.5, P["portal"][1] - 2.0, label="Aetherian Gate")
    # Adventure: examine hotspots (clue board)
    place(lv, "examine", P["spawn"][0] + 1.8, P["spawn"][1] - 0.6,
          id="woods_plaque", title="WEATHERED PLAQUE",
          text="\"We asked to stay.\" A second line: \"Bodies to soil. Minds to Gaia.\"",
          clue="gaia_plaque")
    place(lv, "examine", P["asha"][0] - 1.4, P["asha"][1] + 0.8,
          id="woods_boot", title="UEC BOOT PRINT",
          text="Fresh composite sole marks in the moss after rain.", clue="boot_print")
    woods_creatures_and_secrets(lv)
    lv.write("world.tmj", "tilesets/woods.png")
    return ts

def woods_creatures_and_secrets(lv):
    """M2: creatures (journal + companions) and ability-gated optional secrets.
    Nothing on the main route needs an ability; validate() checks that."""
    # creatures: species, centre (tiles), habitat radius (tiles)
    creature(lv, "glowmoth", 28.5, 21.5, 1.4)       # pond glade, only out at night
    creature(lv, "stoneturtle", 24.5, 24.5, 0.6, netted=True)   # caught in a UEC drone net by the pond
    creature(lv, "vinefox", 18.5, 40.5, 1.2)        # old grove clearing
    creature(lv, "puffcap", 11.5, 21.5, 0.0)        # hides in its cap in the mossy hollow
    creature(lv, "brookling", 24.5, 21.5, 0.6)      # otter on the pond bank
    creature(lv, "hushdeer", 30.0, 33.0, 0.8, gated=True)       # hidden glade, night only
    # the brookling's river pebble, in the shallows at the pond's south bank
    place(lv, "pebble", 24.5, 26.5)
    # SCENT: a 2x2 bramble (Designer's bramble_closed/open) plugging the gap
    # south from the trail into the hushdeer's glade; once open, its middle
    # (x 16-48 px) is a north-south passage between the side clumps
    lv.obj("hiddenpath", 29 * T, 30 * T, 2 * T, 2 * T)
    # moonflowers: a trail of hints up to the brambles, more inside the glade
    for (fx, fy) in ((22.5, 27.5), (25.5, 28.5), (27.5, 29.5), (28.5, 32.5), (31.5, 32.5), (28.5, 33.5), (31.5, 33.5)):
        place(lv, "moonflower", fx, fy)
    # the vine fox's sweetroot, under a 2x2 stump in the west hollow (trunk
    # base collides; pick it standing just below the trunk)
    lv.obj("stump", 11 * T, 25 * T, 2 * T, 2 * T)
    # PUSH: boulders in the nook mouths, pushed one tile east
    boulder(lv, 24, 4, 1, 0)
    place(lv, "stash", 26.5, 6.5, glimmer=25)
    boulder(lv, 29, 38, 1, 0)
    place(lv, "glyph", 30.5, 41.5, glyph="woods_nook")
    # LIGHT: dark zones with a glyph inside
    darkzone(lv, 29, 22, 29, 26)                    # the strip behind the pond
    place(lv, "glyph", 29.5, 25.5, glyph="woods_pond")
    darkzone(lv, 17, 55, 22, 56)                    # the hollow behind the gate
    place(lv, "glyph", 21.5, 55.5, glyph="woods_gate")
    # SCENT: buried glimmer, invisible until the vine fox sniffs it out
    place(lv, "hidden", 12.5, 12.5, glimmer=15)
    place(lv, "hidden", 14.5, 46.5, glimmer=20)

def creature(lv, species, tx, ty, radius, **props):
    place(lv, "creature", tx, ty, species=species, radius=float(radius), **props)

def boulder(lv, tx, ty, push_x, push_y):
    """2x2-tile boulder with its top-left at tile (tx, ty); PUSH moves it by
    (push_x, push_y) tiles"""
    lv.obj("boulder", tx * T, ty * T, 2 * T, 2 * T, pushX=int(push_x), pushY=int(push_y))

def darkzone(lv, x0, y0, x1, y1):
    """darkness over tiles x0..x1, y0..y1 (inclusive), with a half-tile fringe"""
    lv.obj("darkzone", x0 * T - T // 2, y0 * T - T // 2, (x1 - x0 + 2) * T, (y1 - y0 + 2) * T)

# =============================================================== MAP 2: city
def map2():
    ts = Tileset("city")
    lv = Level(ts, 34, 46, seed=22)
    P = dict(spawn=(16.5, 4.5), echo7=(12.5, 7.5), h1=(17.5, 12.5), d1=(6.5, 17.5), arch=(17.5, 20.5),
             h2=(14.5, 21.5), d2=(25.5, 27), sentinel=(16.5, 29), h3=(17.5, 33), voss=(11.5, 37.5),
             portal=(16.5, 41), town=(30.5, 4.5))
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
    rect_carve(floor, 9, 2, 32, 7)             # top street + Lantern Town gate
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
    # plaza tiles in the arena interior (plain variants, by hand); the
    # emblem (13) goes on 1 in 13 cells (~7.7 %), in line with its 0.08 tsx weight
    for y in range(27, 33):
        for x in range(9, 15):
            if not road[y, x]: lv.ground[y, x] = 12 if (x * 7 + y * 3) % 13 else 13
    for y in range(27, 33):
        for x in range(20, 27):
            if not road[y, x] and not wall[y, x]: lv.ground[y, x] = 12 if (x * 7 + y * 3) % 13 else 13
    lv.keepout = road.copy()
    lv.keepout_hard = np.zeros_like(wall)
    for k, (x, y) in P.items():
        disk_carve(lv.keepout, x, y, 2.8); disk_carve(lv.keepout_hard, x, y, 1.6)
    rect_carve(lv.keepout, 7, 25, 29, 35)      # keep the boss arena open
    # crosswalks on the avenue
    for x in range(15, 19):
        lv.ground[16, x] = 6; lv.ground[19, x] = 6
    # Scenery: lamps along the avenue, street furniture on sidewalk fringe, roofs on interiors
    sidewalk = lv.floor & ~road
    curb = sidewalk & lv.dilate(road, 1)                # sidewalk tiles next to asphalt
    near_wall = sidewalk & lv.fringe(wall)
    furniture = curb | near_wall
    # Lamps on sidewalk flanks (avenue asphalt is x 15-18) — every ~4 tiles, not a solid column
    lv.line_props("street_lamp", [(14, 4), (14, 11), (14, 18), (14, 26), (14, 34), (14, 40)], step=4)
    lv.line_props("street_lamp", [(19, 5), (19, 13), (19, 22), (19, 32), (19, 38)], step=4)
    lv.scatter_on(["planter_small", "bench", "bollard"], 12, furniture)
    lv.scatter_on(["trash_bin", "hydrant", "vending_machine"], 8, near_wall)
    lv.scatter_on(["planter_tree", "kiosk", "bus_stop"], 5, near_wall)
    lv.cluster(["bench", "planter_small"], 17, 12, 3, radius=2)   # by Avenue health
    lv.cluster(["bollard", "planter_small"], *P["town"], 3, radius=2)
    lv.cluster(["bench", "trash_bin"], *P["voss"], 2, radius=2)
    interior = np.zeros_like(wall)
    interior[1:-1, 1:-1] = (wall[1:-1, 1:-1] & wall[:-2, 1:-1] & wall[2:, 1:-1] & wall[1:-1, :-2] & wall[1:-1, 2:])
    lv.scatter_on(["rooftop_ac", "rooftop_vent", "solar_panel"], 22, interior, need_floor=False)
    # buildings in courtyards off the avenue: two shops flanking the top
    # street, the archive library across from the Archivist, the apartments
    # on the plaza's west side and the greenhouse by Voss's alcove
    for name, tx, ty in (("noodle_shop", 6, 6), ("tea_house", 24, 6), ("archive_library", 24, 14),
                         ("apartment_block", 2, 26), ("greenhouse", 3, 35)):
        lv.building(name, tx, ty)
    def reground2(x, y, w, rng):
        if w[y, x]: return blob(ts, "sidewalk-building", w, x, y, rng)
        return blob(ts, "road-sidewalk", ~road, x, y, rng, exclude={4, 5, 6, 7, 8})
    lv.carve_lots(wall, [(5, 5, 10, 11), (23, 5, 28, 11), (23, 14, 29, 20), (2, 25, 6, 32), (2, 35, 7, 41)], reground2)
    place(lv, "spawn", *P["spawn"])
    place(lv, "npc", *P["echo7"], name="echo7")
    place(lv, "npc", *P["arch"], name="archivist")
    place(lv, "npc", *P["voss"], name="voss")
    for k in ("h1", "h2", "h3"): place(lv, "health", *P[k])
    place(lv, "sentinel", *P["sentinel"])
    place(lv, "drone", *P["d1"], startAngle=1.0, kind="shield")
    place(lv, "drone", *P["d2"], startAngle=3.3, kind="scout")
    # memory fragment 3 (optional): at the far end of the west yard side
    # street, guarded by d1 and a second drone
    place(lv, "fragment", 3.5, 17.5)
    place(lv, "drone", 5.0, 15.5, startAngle=0.4, kind="swarm")
    place(lv, "portal", *P["portal"])
    place(lv, "portal", *P["town"], dest="town")
    place(lv, "checkpoint", *P["spawn"], label="Upper Street")
    place(lv, "checkpoint", P["echo7"][0], P["echo7"][1] + 2.0, label="Echo District")
    place(lv, "checkpoint", P["portal"][0], P["portal"][1] - 2.0, label="Portal Square")
    # Adventure: plaque + UEC terminal + west-yard side find
    place(lv, "examine", 22.5, 19.5,
          id="city_archive_plaque", title="ARCHIVE PLAQUE",
          text="Sealed by the Archivist. First memory drafts keep here — not the Core itself.",
          clue="city_archive_hint")
    place(lv, "examine", P["voss"][0] + 2.2, P["voss"][1] - 0.5,
          id="city_uec_terminal", title="UEC FIELD TERMINAL",
          text="Override accepted. Field orders scroll past.",
          clue="uec_orders", item="uec_override", consume=True, flag="read_uec_orders")
    place(lv, "examine", 4.5, 18.5,
          id="city_yard_memo", title="DROPPED SLATE",
          text="A scout's note: \"Archive walls hum. Stay clear.\"",
          clue="city_yard_memo")
    place(lv, "stash", 4.0, 19.5, glimmer=18)
    place(lv, "examine", P["town"][0] - 1.2, P["town"][1] + 0.5,
          id="city_lantern_sign", title="LANTERN GATE SIGN",
          text="Side path to Lantern Town — market, rest, no UEC banners.")
    lv.write("world2.tmj", "tilesets/city.png")
    return ts

# =============================================================== MAP 5: Lantern Town
def map5():
    """Peaceful colony hub off the City — vendor, rest, return travel."""
    ts = Tileset("city")
    lv = Level(ts, 28, 28, seed=55)
    P = dict(spawn=(14, 5.5), mira=(10.5, 13.5), h1=(17.5, 12.5), portal=(14, 22.5),
             stash=(20.5, 16.5))
    road = np.zeros((lv.H, lv.W), bool)
    rect_carve(road, 12, 3, 16, 25)            # market lane N-S
    rect_carve(road, 6, 12, 22, 15)            # cross street
    floor = np.zeros_like(road)
    rect_carve(floor, 8, 3, 20, 25)            # main plaza
    rect_carve(floor, 4, 10, 24, 17)           # market square
    rect_carve(floor, 11, 20, 17, 26)          # portal court
    lv.floor = floor | road
    wall = clean_walls(~lv.floor)
    lv.floor = ~wall
    road &= lv.floor
    road = clean_walls(road, border=0) & road
    sidewalk = ~road
    for y in range(lv.H):
        for x in range(lv.W):
            if wall[y, x]:
                lv.ground[y, x] = blob(ts, "sidewalk-building", wall, x, y, lv.rng)
            else:
                lv.ground[y, x] = blob(ts, "road-sidewalk", sidewalk, x, y, lv.rng, exclude={4, 5, 6, 7, 8})
    # warm plaza tiles in the market square
    for y in range(11, 16):
        for x in range(8, 20):
            if not road[y, x] and not wall[y, x]:
                lv.ground[y, x] = 12 if (x * 5 + y * 3) % 11 else 13
    lv.keepout = road.copy()
    lv.keepout_hard = np.zeros_like(wall)
    for k, (x, y) in P.items():
        disk_carve(lv.keepout, x, y, 2.6); disk_carve(lv.keepout_hard, x, y, 1.5)
    sidewalk = lv.floor & ~road
    curb = sidewalk & lv.dilate(road, 1)
    near_wall = sidewalk & lv.fringe(wall)
    # Market lane asphalt is x 12-15; lamps on the flanks, spaced like posts
    lv.line_props("street_lamp", [(11, 5), (11, 11), (11, 17), (11, 21)], step=4)
    lv.line_props("street_lamp", [(16, 6), (16, 12), (16, 18)], step=4)
    lv.scatter_on(["planter_small", "bench", "bollard"], 8, curb | near_wall)
    lv.scatter_on(["trash_bin", "vending_machine", "planter_tree"], 5, near_wall)
    lv.cluster(["bench", "planter_small", "planter_tree"], *P["mira"], 4, radius=2)
    lv.cluster(["bollard", "planter_small"], *P["portal"], 3, radius=2)
    for name, tx, ty in (("tea_house", 4, 8), ("noodle_shop", 19, 8), ("greenhouse", 4, 18)):
        lv.building(name, tx, ty)
    def reground5(x, y, w, rng):
        if w[y, x]: return blob(ts, "sidewalk-building", w, x, y, rng)
        return blob(ts, "road-sidewalk", ~road, x, y, rng, exclude={4, 5, 6, 7, 8})
    lv.carve_lots(wall, [(3, 7, 9, 13), (18, 7, 24, 13), (3, 17, 9, 23)], reground5)
    place(lv, "spawn", *P["spawn"])
    place(lv, "npc", *P["mira"], name="mira", sprite="asha")
    place(lv, "health", *P["h1"])
    place(lv, "stash", *P["stash"], glimmer=15)
    place(lv, "portal", *P["portal"])
    place(lv, "checkpoint", *P["spawn"], label="Lantern Gate")
    place(lv, "checkpoint", *P["portal"], label="Return Portal")
    place(lv, "examine", P["mira"][0] + 1.6, P["mira"][1] + 0.4,
          id="town_stall_note", title="STALL NOTE",
          text="A chalk scribble: 'Archive walls still hum. Drones won't go near.'",
          clue="mira_rumour")
    lv.write("world5.tmj", "tilesets/city.png")
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
    # Scenery: heavy wreckage against ruin walls; clutter in pockets; lights on path edge
    fringe = lv.fringe(wall)
    edge = lv.path_edge()
    pocket = lv.floor & ~lv.keepout & ~lv.keepout_hard
    heavy = ["rubble_large", "wrecked_car_v", "wrecked_car_h", "dumpster", "broken_pillar", "barricade"]
    clutter = ["rubble_small", "barrel_purple", "barrel_toxic", "crate", "drone_wreck", "vending_broken"]
    tech = ["terminal", "steam_vent", "loose_cables"]
    lv.scatter_on(heavy, 10, fringe)
    lv.scatter_on(clutter, 10, fringe | pocket)
    lv.scatter_on(tech, 8, edge | fringe)
    lv.scatter_on(["neon_streetlight"], 6, edge)
    lv.cluster(["barrel_purple", "crate", "rubble_small"], *P["h2"], 4, radius=2)
    lv.cluster(["barricade", "rubble_small"], *P["spawn"], 3, radius=3)
    lv.cluster(["drone_wreck", "barrel_toxic"], *P["portal"], 3, radius=3)
    # Aetherian shrine (stand-in for the Core) in the quiet south-west dead end
    lv.building("ruin_shrine", 10, 31)
    lv.carve_lots(wall, [(9, 30, 14, 37)],
                  lambda x, y, w, rng: None if (metal[y, x] or sludge[y, x]) else blob(ts, "asphalt-ruin", w, x, y, rng))
    place(lv, "spawn", *P["spawn"])
    for k in ("h1", "h2", "h3", "h4"): place(lv, "health", *P[k])
    # calm pass: 6 -> 4 drones (d2 next to the central clearing and d6 in the
    # south-west dead end are gone; their clearings stay)
    place(lv, "drone", *P["d1"], startAngle=0.5, kind="sniper")
    place(lv, "drone", *P["d3"], startAngle=3.1, kind="shield")
    place(lv, "drone", *P["d4"], startAngle=4.5, kind="scout")
    place(lv, "drone", *P["d5"], startAngle=2.3, kind="swarm")
    # memory fragment 5 (optional): off the main path by the collapsed shrine
    # tower in the south-west dead end (before the Core), guarded by a pair
    place(lv, "fragment", 14.5, 34.5)
    place(lv, "drone", 17.5, 33.0, startAngle=1.2, kind="swarm")
    place(lv, "drone", 18.5, 30.5, startAngle=4.0, kind="swarm")
    place(lv, "portal", *P["portal"])
    place(lv, "checkpoint", *P["spawn"], label="Ruined Landing")
    place(lv, "checkpoint", P["h2"][0], P["h2"][1], label="Central Clearing")
    place(lv, "checkpoint", P["portal"][0] - 2.5, P["portal"][1] - 2.5, label="Extraction Approach")
    # Stretch: quiet reads along the road + shrine side reward
    place(lv, "examine", P["spawn"][0] + 1.5, P["spawn"][1] + 1.0,
          id="ruins_landing_mark", title="LANDING MARK",
          text="UEC paint over Aetherian stone: \"Wipe authorized.\" Someone scratched it out.",
          clue="ruins_landing")
    place(lv, "examine", P["h2"][0] - 1.0, P["h2"][1] + 0.8,
          id="ruins_clearing_ring", title="BROKEN RING",
          text="A memory circle, cracked. South-west feels warmer — the shrine path.",
          clue="ruins_ring")
    # Side nudge toward the shrine (d6 clearing sits under the shrine sprite)
    place(lv, "stash", P["d5"][0] - 1.5, P["d5"][1] + 1.0, glimmer=20)
    place(lv, "health", P["d5"][0] + 1.5, P["d5"][1] + 0.5)
    place(lv, "examine", P["d5"][0], P["d5"][1] - 1.2,
          id="ruins_dead_end", title="WAYMARKER",
          text="Offline UEC pad: \"Shrine sector SW — possible civilian anomaly. Do not engage alone.\"",
          clue="ruins_dead_end")
    lv.write("world3.tmj", "tilesets/cyberpunk.png")
    return ts

# =============================================================== MAP 4: Gaia Core
def map4():
    """Sacred chamber under the ruins — activate the Core Record."""
    ts = Tileset("core")
    lv = Level(ts, 30, 36, seed=44)
    P = dict(
        spawn=(15, 4.5),
        h1=(15, 11),
        d1=(6.5, 17),
        d2=(23.5, 17),
        gaia=(15, 20),
        h2=(15, 24),
        d3=(23.5, 25),
        portal=(15, 30),
    )
    edges = [
        ("spawn", "h1"), ("h1", "gaia"), ("gaia", "portal"),
        ("h1", "d1"), ("h1", "d2"), ("gaia", "h2"), ("gaia", "d3"),
    ]
    for a, b in edges:
        seg_carve(lv.floor, P[a], P[b], 2.1)
    for k, (x, y) in P.items():
        r = 4.5 if k in ("spawn", "portal", "gaia") else 3.2
        disk_carve(lv.floor, x, y, r)
    # Slightly wider processional hall
    rect_carve(lv.floor, 12, 6, 17, 30)
    wall = clean_walls(~lv.floor)
    lv.floor = ~wall
    dais = np.zeros_like(wall)
    disk_carve(dais, *P["portal"], 3.8)
    disk_carve(dais, *P["gaia"], 2.8)
    dais &= lv.floor
    for y in range(lv.H):
        for x in range(lv.W):
            if dais[y, x]:
                lv.ground[y, x] = blob(ts, "floor-dais", dais, x, y, lv.rng)
            else:
                lv.ground[y, x] = blob(ts, "floor-void", wall, x, y, lv.rng)
    lv.keepout = np.zeros_like(wall)
    lv.keepout_hard = np.zeros_like(wall)
    for a, b in edges:
        seg_carve(lv.keepout, P[a], P[b], 2.5)
    for k, (x, y) in P.items():
        disk_carve(lv.keepout, x, y, 2.8)
        disk_carve(lv.keepout_hard, x, y, 1.6)
    # Scenery: pylons/braziers frame the processional hall; soft markers near dais
    fringe = lv.fringe(wall)
    edge = lv.path_edge()
    dais_edge = lv.floor & lv.dilate(dais, 1) & ~dais
    solemn = ["orb_pylon", "orb_pylon_large", "energy_brazier", "broken_pillar"]
    soft = ["data_crystals", "gold_glyph_stone", "memory_pedestal", "root_bulb", "floor_ring_marker"]
    gear = ["core_terminal", "core_console", "lattice_panel"]
    lv.scatter_on(solemn, 8, fringe | edge)
    lv.scatter_on(soft, 8, dais_edge | edge)
    lv.scatter_on(gear, 4, fringe)
    lv.cluster(["floor_ring_marker", "gold_glyph_stone"], *P["gaia"], 4, radius=3)
    lv.cluster(["energy_brazier", "orb_pylon"], *P["portal"], 3, radius=3)
    place(lv, "spawn", *P["spawn"])
    place(lv, "npc", *P["gaia"], name="gaia")
    place(lv, "health", *P["h1"])
    place(lv, "health", *P["h2"])
    place(lv, "drone", *P["d1"], startAngle=1.2, kind="sniper")
    place(lv, "drone", *P["d2"], startAngle=4.0, kind="swarm")
    place(lv, "drone", *P["d3"], startAngle=2.5, kind="shield")
    place(lv, "portal", *P["portal"])
    place(lv, "checkpoint", *P["spawn"], label="Core Threshold")
    place(lv, "checkpoint", *P["gaia"], label="Core Record")
    place(lv, "examine", P["spawn"][0] + 1.5, P["spawn"][1] + 1.2,
          id="core_console", title="CORE CONSOLE",
          text="Activation waits on a living neural match. A remote wipe is already queued.",
          clue="core_console")
    lv.write("world4.tmj", "tilesets/core.png")
    return ts

if __name__ == "__main__":
    os.makedirs(os.path.join(OUT, "tilesets"), exist_ok=True)
    for n in ("woods", "city", "cyberpunk", "core"):
        shutil.copy(os.path.join(TSDIR, f"{n}.png"), os.path.join(OUT, "tilesets", f"{n}.png"))
    map1(); map2(); map3(); map4(); map5()
