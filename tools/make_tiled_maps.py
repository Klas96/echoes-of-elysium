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

Layout (#26): Woods and City are graphs of places joined by paths that close
into rings, not north→south corridors (see the map1/map2 docstrings). The
validator counts the walkable rings around solid blocks (tools/map_rings.py,
ability/story gates closed) and fails if a map has fewer than its
rings_min (2 for Woods and City). Objects the layout pass moved keep their
old pickup id in a "pid" property, so existing saves stay valid.

Regenerate and review:
    python3 tools/make_tiled_maps.py                      # writes assets/images/maps/*.tmj, validates
    python3 tools/render_map_overview.py assets/images/maps/world2.tmj /tmp/city.png
    python3 tools/render_map_overview.py --compare OLD.tmj NEW.tmj /tmp/diff.png
    MAPS_DRAFT=1 python3 tools/make_tiled_maps.py /tmp/out   # sketching: write even if invalid

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
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from map_rings import rings  # noqa: E402

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
        self.rings_min = 0          # validate(): minimum walkable rings (#26)
        self.mist = []              # (tx, ty) tile centres for ambient mist over water
        self.rings = []

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
            # mapexit / entry sit on border openings punched after clean_walls
            return o["name"] in ("darkzone", "ambient", "light", "mapexit") or (
                o["name"] == "creature" and o["props"].get("species") in FLYING)
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
                if o["name"] in ("ambient", "light"): continue    # overlays (chimney smoke, lamp glow)
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
        self.validate_rings(ok, cells, flood)
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

    def validate_rings(self, ok, cells, flood):
        """Layout check (#26): count the independent walkable loops (rings
        around solid blocks, see tools/map_rings.py) with every ability gate
        and story gate closed, and require at least self.rings_min."""
        closed = ok.copy()
        for o in self.objects:
            if o["name"] in ("boulder", "hiddenpath", "storygate"):
                for (x, y) in cells(o): closed[y, x] = False
        self.rings = rings(flood(closed))
        if len(self.rings) < self.rings_min:
            raise SystemExit(f"only {len(self.rings)} walkable ring(s); this map needs >= {self.rings_min}")

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
            if o["name"] in ("drone", "sentinel", "darkzone", "boulder", "hiddenpath", "ambient", "light"):
                continue
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

    def emit_ambient_fx(self):
        """Gameplay overlays for static props that should feel alive (steam, embers)."""
        kinds = {
            "steam_vent": "steam",
            "rooftop_vent": "steam",
            "crashed_ship": "smoke",       # the wreck still smoulders
            "campfire": "ember",
            "energy_brazier": "ember",
            "fountain": "mist",
        }
        for name, x, y in self.instances:
            kind = kinds.get(name)
            if not kind:
                continue
            w, h, _ = self.ts.props[name]
            cx = (x + w / 2) * T
            cy = (y + h / 2) * T
            # Top of the prop (vents vent upward; campfire/brazier glow above)
            if kind in ("steam", "smoke"):
                cy = (y + 0.15 * h) * T
            elif kind == "ember":
                cy = (y + 0.25 * h) * T
            self.obj("ambient", cx - 12, cy - 12, 24, 24, kind=kind)
        # chimney / kitchen smoke over buildings (px from the sprite top-left)
        for bd in self.buildings:
            for (px, py) in self.CHIMNEYS.get(bd["name"], ()):
                self.obj("ambient", bd["tx"] * T + px - 12, bd["ty"] * T + py - 12, 24, 24, kind="smoke")
        # mist drifting over open water (ponds), set per map in tile coords
        for (tx, ty) in self.mist:
            self.obj("ambient", tx * T - 12, ty * T - 12, 24, 24, kind="mist")

    CHIMNEYS = {
        "ranger_cabin": ((31, 12),),
        "apartment_block": ((19, 4),),
        "noodle_shop": ((36, 12),),
    }

    # Night light pools (#35): prop -> (kind, glow radius px, pool centre as a
    # fraction of the prop height). The game draws a cached cookie per light.
    LIGHTS = {
        "street_lamp": ("lamp", 76, 0.75),
        "lantern": ("lantern", 64, 0.7),
        "campfire": ("fire", 88, 0.5),
        "energy_brazier": ("energy", 72, 0.5),
        "neon_streetlight": ("neon", 72, 0.75),
    }

    # Maps whose street lamps use the cyan neon cookie (the City); elsewhere
    # lamps are warm amber.
    NEON_LAMP_MAPS = ("world2.tmj",)

    def emit_lights(self, fname):
        """A small `light` object (kind, radius[, style]) centred under each lamp-like prop."""
        for name, x, y in self.instances:
            spec = self.LIGHTS.get(name)
            if not spec:
                continue
            kind, radius, fy = spec
            w, h, _ = self.ts.props[name]
            cx, cy = (x + w / 2) * T, (y + h * fy) * T
            extra = {"style": "neon"} if kind == "lamp" and fname in self.NEON_LAMP_MAPS else {}
            self.obj("light", cx - 8, cy - 8, 16, 16, kind=kind, radius=float(radius), **extra)

    def write(self, fname, image_rel):
        self.emit_ambient_fx()
        self.emit_lights(fname)
        try:
            ok, seen = self.validate()
        except SystemExit as e:
            # MAPS_DRAFT=1: still write the map (for render_map_overview.py
            # while sketching a layout); never commit maps written that way
            if not os.environ.get("MAPS_DRAFT"): raise
            print(f"{fname}: INVALID (draft written anyway): {e}")
            ok = seen = self.walkable()
        print(f"{fname}: {len(self.rings)} ring(s) (min {self.rings_min})")
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
            d.rectangle([o["x"], o["y"], o["x"] + o["w"], o["y"] + o["h"]], outline=col.get(o["name"], (255, 255, 255)), width=2)
        os.makedirs(PREVIEW, exist_ok=True)
        im.convert("RGB").resize((self.W * 16, self.H * 16)).save(os.path.join(PREVIEW, "preview_" + fname.replace(".tmj", ".png")))
        n_col = int((~ok).sum())
        if os.environ.get("PREVIEW_FULL"):
            im.convert("RGB").save(os.path.join(PREVIEW, "full_" + fname.replace(".tmj", ".png")))
        print(f"{fname}: {self.W}x{self.H} tiles ({self.W*T}x{self.H*T}px), {len(objs)} objects, "
              f"{n_col} blocking tiles, reachable floor {int(seen.sum())}")

# --------------------------------------------------------------- sizes used by the code
SZ = dict(spawn=32, portal=56, npc=30, fragment=18, health=16, drone=24, sentinel=48, checkpoint=32,
          creature=32, stump=64, stash=32, glyph=24, hidden=24, pebble=16, moonflower=16, examine=20,
          storygate=64, entry=32)

def open_map_edge(lv, side, cx, half=2):
    """Punch a walkable corridor through the sealed map border (after clean_walls).
    [side] is north/south/east/west; [cx] is the centre tile along that edge."""
    W, H = lv.W, lv.H
    # Sample a nearby walkable ground tile to paint into the opening.
    sample = 1
    if side == "south":
        x0, x1 = max(0, cx - half), min(W, cx + half + 1)
        sy = min(H - 4, H - 1)
        for x in range(x0, x1):
            if lv.floor[sy, x]:
                sample = int(lv.ground[sy, x]); break
        for y in range(H - 3, H):
            for x in range(x0, x1):
                lv.floor[y, x] = True
                if lv.ground[y, x] < 0 or y >= H - 2:
                    lv.ground[y, x] = sample
    elif side == "north":
        x0, x1 = max(0, cx - half), min(W, cx + half + 1)
        sy = max(3, 0)
        for x in range(x0, x1):
            if lv.floor[min(3, H - 1), x]:
                sample = int(lv.ground[min(3, H - 1), x]); break
        for y in range(0, 3):
            for x in range(x0, x1):
                lv.floor[y, x] = True
                lv.ground[y, x] = sample
    elif side == "east":
        y0, y1 = max(0, cx - half), min(H, cx + half + 1)
        sx = min(W - 4, W - 1)
        for y in range(y0, y1):
            if lv.floor[y, sx]:
                sample = int(lv.ground[y, sx]); break
        for x in range(W - 3, W):
            for y in range(y0, y1):
                lv.floor[y, x] = True
                if lv.ground[y, x] < 0 or x >= W - 2:
                    lv.ground[y, x] = sample
    elif side == "west":
        y0, y1 = max(0, cx - half), min(H, cx + half + 1)
        sx = max(3, 0)
        for y in range(y0, y1):
            if lv.floor[y, min(3, W - 1)]:
                sample = int(lv.ground[y, min(3, W - 1)]); break
        for x in range(0, 3):
            for y in range(y0, y1):
                lv.floor[y, x] = True
                lv.ground[y, x] = sample

def place_mapexit(lv, side, cx, dest, entry, half=2, unlock=False, **extra):
    """Trigger strip just inside the opened edge. [entry] = spawn side on dest map."""
    W, H, Tloc = lv.W, lv.H, T
    props = dict(dest=dest, entry=entry, **extra)
    if unlock:
        props["unlock"] = "portal"
    if side == "south":
        x0 = max(0, (cx - half) * Tloc)
        lv.obj("mapexit", x0, (H - 2) * Tloc, (half * 2 + 1) * Tloc, 2 * Tloc, **props)
    elif side == "north":
        x0 = max(0, (cx - half) * Tloc)
        lv.obj("mapexit", x0, 0, (half * 2 + 1) * Tloc, 2 * Tloc, **props)
    elif side == "east":
        y0 = max(0, (cx - half) * Tloc)
        lv.obj("mapexit", (W - 2) * Tloc, y0, 2 * Tloc, (half * 2 + 1) * Tloc, **props)
    elif side == "west":
        y0 = max(0, (cx - half) * Tloc)
        lv.obj("mapexit", 0, y0, 2 * Tloc, (half * 2 + 1) * Tloc, **props)

def place_entry(lv, side, tx, ty):
    """Arrival pad when walking in from [side]."""
    place(lv, "entry", tx, ty, side=side)
# creatures that fly (no floor needed under their habitat)
FLYING = {"glowmoth"}
# objects an ability gate may hide; anything else behind a boulder is an error
SECRET_KINDS = {"glyph", "stash", "hidden", "moonflower"}
# min centre distance from a checkpoint to each enemy kind (see validate)
CP_CLEAR = dict(drone=260, sentinel=300)

def place(lv, obj, tx, ty, was=None, **props):
    """place an object whose CENTRE is at tile coords (tx, ty) (floats).
    Extra kwargs become Tiled properties (e.g. kind='sniper', name='gaia').
    was=(tx, ty): where the object sat before the #26 layout pass; its
    old pickup id is kept as property pid so existing saves still know it
    was collected / solved (the game ids pickups by map position)."""
    s = SZ[obj]
    if was is not None:
        props["pid"] = f"{round(was[0] * T - s / 2)}_{round(was[1] * T - s / 2)}"
    lv.obj(obj, round(tx * T - s / 2), round(ty * T - s / 2), s, s, **props)

def carve_route(lv, pts, half, mask=None):
    m = lv.floor if mask is None else mask
    for a, b in zip(pts, pts[1:]):
        seg_carve(m, a, b, half)

# =============================================================== MAP 1: woods
def map1():
    """Woods: a wilderness wider than tall, laid out as a graph of clearings.

    Story beats are nodes, trails are edges, and the edges close into rings
    around solid forest blocks (validated: >= 2 rings, see RINGS_MIN):

        crash ── h1 ── cabin ─── ridge ─── pond (frag)
          │        \\                  /      │
        west       CROSSROADS ── east bend ──┤
        hollow    /     │              \\     east grove (frag)
          │      /      │               \\    │
        sw bend ── ASHA'S CAMP ──── brook ── south meadow ── exit S → City

    Gaia waits at the crash (NW), Asha at her camp in the middle south, the
    two portal fragments sit on opposite sides (pond NE, east grove E), and
    the road to the City leaves the south meadow (SE). Every beat can be
    reached two ways, so the trip reads as crossing a forest, not walking a
    hallway south. The south exit keeps Woods↔City travel unchanged."""
    ts = Tileset("woods")
    lv = Level(ts, 56, 44, seed=11)
    lv.rings_min = 2
    P = dict(spawn=(8, 9), gaia=(11, 8), h1=(17, 12), cabin=(19.5, 7.5), ridge=(31, 6),
             pond=(42, 10), f2=(37.5, 12.5), cross=(27, 20), d2=(34, 15.5), ebend=(36, 24),
             egrove=(48.5, 23), f4=(50.5, 23.5), whollow=(6, 23), f1=(5.5, 21.5), hollow=(13, 19),
             swbend=(9, 34), nest=(4.5, 39), asha=(24, 33), h2=(23, 26), brook=(32, 35),
             meadow=(42, 36), h3=(44.5, 30.5), exit=(42, 40), f3=(15, 36), d1=(16, 33.5))
    trails = [
        ["spawn", "h1", "cross"],                   # crash → crossroads
        ["h1", "cabin"],
        ["cabin", "ridge", "pond"],                 # north ridge to the pond
        ["pond", "d2", "cross"],                    # ring 1: crossroads ↔ pond
        ["pond", "egrove"],                         # east bank down to the grove
        ["cross", "ebend", "egrove"],               # ring 2: crossroads ↔ grove
        ["egrove", "meadow"],
        ["cross", "h2", "asha"],
        ["asha", "brook", "meadow"],                # ring 3: camp ↔ meadow
        ["ebend", "brook"],
        ["spawn", "whollow", "swbend", "asha"],     # ring 4: the west loop
        ["whollow", "hollow"],                      # mossy hollow (puffcap)
        ["swbend", "nest"],                         # nest spur (town job)
        ["meadow", "exit"],
    ]
    def route_pts(r):
        return [P[k] for k in r]
    for r in trails:
        carve_route(lv, route_pts(r), 2.0)
    big = dict(cross=5.5, asha=4.6, pond=5.2, meadow=4.6, spawn=4.6, egrove=4.4, whollow=3.8)
    for k in ("spawn", "h1", "cabin", "ridge", "pond", "cross", "d2", "ebend", "egrove", "whollow",
              "hollow", "swbend", "nest", "asha", "h2", "brook", "meadow", "f3"):
        disk_carve(lv.floor, *P[k], big.get(k, 3.2))
    rect_carve(lv.floor, 16, 2, 24, 9)                # ranger cabin clearing
    seg_carve(lv.floor, P["exit"], (P["exit"][0], 43.5), 2.0)
    # secret pockets (walls >= 2 thick around them; see the gates below)
    disk_carve(lv.floor, 4.5, 6.5, 3.4)                # crash scar under the wreck
    disk_carve(lv.floor, 3.5, 30.5, 2.2)              # LIGHT pocket off the west loop
    seg_carve(lv.floor, (6, 29.5), (3.5, 30.5), 1.4)
    wall = clean_walls(~lv.floor)
    lv.floor = ~wall
    # ---- ability-gated nooks, carved through solid forest after clean_walls
    nooks = [(50, 8), (12, 26)]                       # boulder top-left; tunnel enters from the west
    gated = np.zeros_like(wall)
    for (bx, by) in nooks:
        gated[by:by + 2, bx - 4:bx] = True            # tunnel from the trail (+ its mouth)
        gated[by - 2:by + 4, bx:bx + 4] = True        # 4x6 nook
    # SCENT bramble: ridge trail → 2x2 bramble → hushdeer glade below,
    # hidden inside the forest block between the ridge and the crossroads
    gated[8:11, 27:29] = True                         # bramble cells (+ the trail row above)
    gated[11:14, 26:30] = True                        # hidden glade
    wall &= ~gated
    lv.floor = ~wall
    water = np.zeros_like(wall); rect_carve(water, 41, 7, 46, 10); water &= lv.floor
    lv.mist = [(42.5, 8.0), (44.5, 8.6)]
    path = np.zeros_like(wall)
    for r in trails:
        carve_route(lv, route_pts(r), 1.1, path)
    seg_carve(path, P["exit"], (P["exit"][0], 43.5), 1.1)
    disk_carve(path, *P["cross"], 2.6)               # the crossroads reads as a plaza
    path &= lv.floor & ~water
    path = clean_walls(path, border=0) & path
    for y in range(lv.H):
        for x in range(lv.W):
            if wall[y, x] or not (water[y, x] or path[y, x]):
                lv.ground[y, x] = blob(ts, "grass-forest", wall, x, y, lv.rng)
            if water[y, x]: lv.ground[y, x] = blob(ts, "grass-water", water, x, y, lv.rng)
            if path[y, x]: lv.ground[y, x] = blob(ts, "grass-path", path, x, y, lv.rng)
    # keep-out: trails, clearings, gated pockets, the cabin
    for r in trails:
        carve_route(lv, route_pts(r), 2.5, lv.keepout)
    lv.keepout_hard = np.zeros_like(wall)
    for k, (x, y) in P.items():
        disk_carve(lv.keepout, x, y, 2.8); disk_carve(lv.keepout_hard, x, y, 1.6)
    lv.keepout |= gated; lv.keepout_hard |= gated
    rect_carve(lv.keepout, 16, 2, 24, 9); rect_carve(lv.keepout_hard, 16, 2, 24, 9)
    disk_carve(lv.keepout, 3.5, 30.5, 2.5); disk_carve(lv.keepout_hard, 3.5, 30.5, 2.5)
    disk_carve(lv.keepout, 44, 12.5, 3.0); disk_carve(lv.keepout_hard, 44, 12.5, 2.2)   # pond bank
    for (fx, fy) in WOODS_RESERVED:
        disk_carve(lv.keepout, fx, fy, 1.4); disk_carve(lv.keepout_hard, fx, fy, 1.0)
    # landmarks: the wreck at the crash, a standing-stone circle at the
    # crossroads (seen from every trail into it), Asha's tent, a radio dish
    # on the ridge, a signpost at each fork
    for name, x, y in (("crashed_ship", 2, 4), ("campfire", 5, 11), ("monolith", 27, 19),
                       ("standing_stone", 24, 17), ("standing_stone", 30, 17),
                       ("standing_stone", 24, 22), ("standing_stone", 30, 22),
                       ("tent", 26, 30), ("campfire", 21, 31), ("radio_dish", 30, 3),
                       ("signpost", 14, 10), ("signpost", 37, 21), ("signpost", 7, 31),
                       ("signpost", 33, 33), ("signpost", 45, 15), ("portal_platform", 41, 37)):
        landmark(lv, name, x, y)
    fringe = lv.fringe(wall)
    edge = lv.path_edge()
    mid = lv.floor & ~lv.keepout_hard & ~fringe
    trees = ["tree_green", "tree_teal", "tree_blue", "tree_purple", "tree_pine", "tree_big"]
    bigp = ["boulder", "log", "stump"]
    bush = ["bush_green", "bush_glow", "rock_small", "rock_moss"]
    soft = ["mushrooms", "flowers", "lantern"]
    lv.scatter_on(trees, 34, fringe)
    lv.scatter_on(bigp, 10, fringe)
    lv.scatter_on(bush, 14, fringe | (edge & mid))
    lv.scatter_on(soft, 24, edge)
    lv.scatter_on(soft, 8, mid)
    lv.cluster(["flowers", "mushrooms", "lantern"], *P["cross"], 4, radius=3)
    lv.cluster(["flowers", "bush_glow"], *P["asha"], 3, radius=2)
    lv.cluster(["rock_moss", "flowers"], *P["meadow"], 3, radius=3)
    lv.cluster(["mushrooms", "flowers"], *P["hollow"], 3, radius=2)
    lv.building("ranger_cabin", 18, 2)
    # gameplay objects
    place(lv, "spawn", *P["spawn"])
    place(lv, "npc", *P["gaia"], name="gaia")
    place(lv, "npc", *P["asha"], name="asha")
    # memory fragments 1-2 (both open the road): pond glade NE and east grove
    place(lv, "fragment", *P["f2"], was=(19.5, 16.5))
    place(lv, "fragment", *P["f4"], was=(24, 38.5))
    place(lv, "health", *P["h1"], was=(12.5, 14.5))
    place(lv, "health", *P["h2"], was=(11, 22.5))
    place(lv, "health", *P["h3"], was=(20, 33.5))
    place(lv, "drone", *P["d1"], startAngle=0.0, kind="scout")
    place(lv, "drone", *P["d2"], startAngle=2.1, kind="sniper")
    place(lv, "drone", P["nest"][0] - 0.3, P["nest"][1] - 0.5, startAngle=1.2, kind="scout", nest=True)
    place(lv, "drone", P["nest"][0] + 0.6, P["nest"][1] + 0.3, startAngle=3.8, kind="swarm", nest=True)
    # South road out of the woods → City (walk off the map).
    ex = int(P["exit"][0])
    open_map_edge(lv, "south", ex, half=2)
    place_mapexit(lv, "south", ex, dest="city", entry="north", half=2, unlock=True,
                  lockedTitle="WOODS EDGE",
                  lockedBody="Two memory fragments open the road south to the City.")
    place_entry(lv, "south", P["exit"][0], P["exit"][1] - 1.0)    # arriving back from the City
    place(lv, "checkpoint", *P["spawn"], label="Crash Site")
    place(lv, "checkpoint", P["cross"][0] - 0.5, P["cross"][1] + 3.5, label="Crossroads")
    place(lv, "checkpoint", P["asha"][0] + 1.5, P["asha"][1] + 1.6, label="Asha's Camp")
    place(lv, "checkpoint", P["meadow"][0] - 2.5, P["meadow"][1] - 1.0, label="South Meadow")
    place(lv, "examine", P["spawn"][0] + 1.8, P["spawn"][1] - 0.6,
          id="woods_plaque", title="WEATHERED PLAQUE",
          text="\"We asked to stay.\" A second line: \"Bodies to soil. Minds to Gaia.\"",
          clue="gaia_plaque")
    place(lv, "examine", P["spawn"][0] - 1.2, P["spawn"][1] + 1.4,
          id="woods_mission_slate", title="FIELD BRIEF",
          text="Kaela — talk to Gaia (green) by the crash. Collect any two glowing fragments; the trails ring round, "
               "so every clearing has two ways in. The road to the City leaves the south-east meadow. "
               "Do not let the UEC wipe her.")
    place(lv, "examine", P["asha"][0] - 1.4, P["asha"][1] + 0.8,
          id="woods_boot", title="UEC BOOT PRINT",
          text="Fresh composite sole marks in the moss after rain.", clue="boot_print")
    place(lv, "examine", P["f1"][0] + 0.6, P["f1"][1] - 0.3,
          id="woods_courier_pack", title="SEALED COURIER PACK",
          text="Lantern Town wax seal. Someone meant this for Mira's board.",
          quest="courier_pack")
    place(lv, "stash", P["f1"][0] - 0.6, P["f1"][1] + 1.0, glimmer=12, was=(5.7, 11.0))
    place(lv, "examine", P["nest"][0] + 1.6, P["nest"][1] - 0.4,
          id="woods_nest_slate", title="UEC FIELD SLATE",
          text="Nest roster. Two units. 'Hold the west loop until recall.'",
          clue="quest_nest_slate")
    place(lv, "examine", P["f3"][0] + 0.5, P["f3"][1],
          id="woods_moonflower_pick", title="MOONFLOWER CLUSTER",
          text="A bloom cold as glass. Mira asked for one of these.",
          give="moonflower_bloom", quest="moonflower_draft")
    place(lv, "examine", P["cross"][0] + 1.2, P["cross"][1] + 2.4,
          id="woods_fork_sign", title="STANDING STONES",
          text="Every trail meets here. NE: the pond. E: the grove. S: Asha's camp. W: the mossy hollow and "
               "round to the crash. Fragments glow out there; any two open the City road from the south-east meadow.")
    place(lv, "examine", P["ridge"][0] + 1.5, P["ridge"][1] - 0.5,
          id="woods_ridge_lookout", title="CITY LIGHTS TO THE SOUTH",
          text="From the ridge, past the radio dish, the City's glow hangs over the treeline to the south-east. "
               "The trails below all ring round to the meadow road.")
    place(lv, "examine", P["h2"][0] + 1.4, P["h2"][1] + 0.4,
          id="woods_job_sign", title="TRAIL NOTICE",
          text="Chalk: once you reach the City, look EAST down the boulevard for Lantern Town — jobs and glimmer.")
    place(lv, "examine", P["f2"][0] - 1.4, P["f2"][1] + 0.6,
          id="woods_glade_sign", title="SIDE PATH MARK",
          text="Trails leave the pond three ways: west along the ridge, south-west to the stones, south to the grove. "
               "You will not get stuck.")
    place(lv, "examine", P["meadow"][0] + 2.0, P["meadow"][1] - 1.6,
          id="woods_portal_notice", title="SOUTH ROAD",
          text="City beyond this tree line. Walk south off the map. Its plaza looks three ways: Lantern Town east, "
               "the Archive south-east, the Ruins road south.")
    place(lv, "hidden", 13.5, 12.5, glimmer=18, was=(13.0, 43.6))
    woods_creatures_and_secrets(lv, nooks)
    lv.write("world.tmj", "tilesets/woods.png")
    return ts

# tiles that later get creatures / moonflowers / secrets / quest props (no props there)
WOODS_RESERVED = ((47.5, 7.5), (44, 12.5), (47.5, 20.5), (13, 19), (40, 12.5), (28, 12.5),
                  (24.5, 7.5), (26.5, 8), (29.5, 8.2), (26.5, 11.5), (29.5, 11.5), (27, 13.5),
                  (5.5, 21.5), (6.1, 21.2), (4.9, 22.5), (4.5, 39), (6.1, 38.6), (15.5, 36),
                  (3.5, 30.5), (13.5, 12.5), (37.5, 26), (14, 38), (13, 17), (32.5, 5.5))

def woods_creatures_and_secrets(lv, nooks):
    """M2: creatures (journal + companions) and ability-gated optional secrets.
    Nothing on the main route needs an ability; validate() checks that."""
    creature(lv, "glowmoth", 47.5, 7.5, 1.4, was=(28.5, 21.5))     # over the pond, only out at night
    creature(lv, "stoneturtle", 44, 12.5, 0.6, netted=True, was=(24.5, 24.5))   # netted on the pond bank
    creature(lv, "vinefox", 47.5, 20.5, 1.2, was=(18.5, 40.5))     # east grove
    creature(lv, "puffcap", 13, 19, 0.0, was=(11.5, 21.5))         # mossy hollow off the west loop
    creature(lv, "brookling", 40, 12.5, 0.6, was=(24.5, 21.5))     # otter on the pond bank
    creature(lv, "hushdeer", 28, 12.5, 0.8, gated=True, was=(30.0, 33.0))   # hidden glade, night only
    place(lv, "pebble", 42.5, 11.5, was=(24.5, 26.5))               # pond shallows, south bank
    # SCENT: bramble plugging the gap from the grove's stub into the glade
    lv.obj("hiddenpath", 27 * T, 9 * T, 2 * T, 2 * T, pid=f"{29 * T}_{30 * T}")
    for (fx, fy) in ((24.5, 7.5), (26.5, 8), (29.5, 8.2), (26.5, 11.5), (29.5, 11.5), (27, 13.5)):
        place(lv, "moonflower", fx, fy)
    # the vine fox's sweetroot, under a 2x2 stump in the mossy hollow
    lv.obj("stump", 12 * T, 16 * T, 2 * T, 2 * T)
    # PUSH: boulders in the nook mouths, pushed one tile east
    (b1x, b1y), (b2x, b2y) = nooks
    boulder(lv, b1x, b1y, 1, 0, was=(24, 4))
    place(lv, "stash", b1x + 2.5, b1y + 3.5, glimmer=25, was=(26.5, 6.5))
    boulder(lv, b2x, b2y, 1, 0, was=(29, 38))
    place(lv, "glyph", b2x + 2.5, b2y + 3.5, glyph="woods_nook", was=(30.5, 41.5))
    # LIGHT: dark zones with a glyph inside, off the main trails
    darkzone(lv, 40, 11, 41, 13, was=(27, 26))                     # pond's west bank, under the reeds
    place(lv, "glyph", 40.5, 11.5, glyph="woods_pond", was=(28.5, 27.5))
    darkzone(lv, 2, 29, 4, 31, was=(11, 49))                       # west loop pocket
    place(lv, "glyph", 3.5, 30.5, glyph="woods_gate", was=(12.5, 50.5))
    # SCENT: buried glimmer, invisible until the vine fox sniffs it out
    place(lv, "hidden", 15.5, 36.0, glimmer=15, was=(12.5, 12.5))
    place(lv, "hidden", 37.5, 26.0, glimmer=20, was=(14.5, 46.5))

def landmark(lv, name, x, y):
    """Stamp a set-piece prop at tile (x, y) even on a keep-out (trail
    edge, clearing): it only needs clear floor and no prop under it. The
    validator still checks that objects stay on walkable, reachable floor."""
    w, h, grid = lv.ts.props[name]
    for j in range(h):
        for i in range(w):
            if grid[j][i] < 0: continue
            cx, cy = x + i, y + j
            if not lv.floor[cy, cx] or lv.props[cy, cx] >= 0 or lv.ts.collides(lv.ground[cy, cx]):
                msg = f"landmark {name} at {x},{y} does not fit (tile {cx},{cy})"
                if not os.environ.get("MAPS_DRAFT"): raise SystemExit(msg)
                print("DRAFT:", msg); return
    lv.stamp(name, x, y)
    lv.keepout_hard[y:y + h, x:x + w] = True

def creature(lv, species, tx, ty, radius, **props):
    place(lv, "creature", tx, ty, species=species, radius=float(radius), **props)

def boulder(lv, tx, ty, push_x, push_y, was=None):
    """2x2-tile boulder with its top-left at tile (tx, ty); PUSH moves it by
    (push_x, push_y) tiles"""
    extra = {"pid": f"{was[0] * T}_{was[1] * T}"} if was else {}
    lv.obj("boulder", tx * T, ty * T, 2 * T, 2 * T, pushX=int(push_x), pushY=int(push_y), **extra)

def darkzone(lv, x0, y0, x1, y1, was=None):
    """darkness over tiles x0..x1, y0..y1 (inclusive), with a half-tile fringe"""
    extra = {"pid": f"{was[0] * T - T // 2}_{was[1] * T - T // 2}"} if was else {}
    lv.obj("darkzone", x0 * T - T // 2, y0 * T - T // 2, (x1 - x0 + 2) * T, (y1 - y0 + 2) * T, **extra)

# =============================================================== MAP 2: city
def map2():
    """City: districts around a central ARCHIVE SQUARE (layout from
    GameConcept's story graph for #26), wider than tall.

                         [N edge → Woods]
                               │
       NOODLE ─ MARKET ROW ─ ARRIVAL PLAZA ══ boulevard ══ LANTERN GATE ─► Town (E edge)
                  │              │                 (tea house)   │
       ECHO DISTRICT ───── ARCHIVE SQUARE ──────────────── EAST LOT (nest)
          │                  │ (archive_library)               │
       WEST YARD          GREENHOUSE GARDEN                PATROL ALLEY (sniper)
          │  (frag)          │                                 │
          └── yard alley ── SENTINEL PLAZA ───────────────────┘
                               │
                        VOSS ALCOVE · SOUTH GATE ─► Ruins (S edge)

    Loops (validated, >= 2): west (plaza–market–Echo–square), east (plaza–
    Lantern Gate–east lot–square), south (square–garden–Sentinel–patrol
    alley–east lot) and the west yard alley. Story order stays Echo-7 →
    Archivist → Sentinel → Voss; the edge exits keep their sides."""
    ts = Tileset("city")
    lv = Level(ts, 52, 44, seed=22)
    lv.rings_min = 2
    P = dict(spawn=(26.5, 4.5), echo7=(6, 16.5), h1=(14, 7.5), d1=(5.5, 31), arch=(26.5, 18.5),
             h2=(20.5, 20.5), d2=(39.5, 18), sentinel=(26.5, 32), h3=(45.5, 31.5), voss=(19.5, 38.5),
             gate=(26.5, 41.5), town=(49.5, 7.5), yard=(4.5, 25), lot=(46, 19), se=(45.5, 26.5),
             cache=(5.5, 11), garden=(25, 28))
    road = np.zeros((lv.H, lv.W), bool)
    rect_carve(road, 34, 6, 52, 9)             # boulevard: plaza → Lantern Gate → Town
    rect_carve(road, 45, 9, 48, 15)            # Lantern Gate street down to the east lot
    rect_carve(road, 35, 17, 45, 19)           # east street: east lot → Archive Square
    rect_carve(road, 25, 36, 28, 44)           # gate road → Ruins
    floor = np.zeros_like(road)
    rect_carve(floor, 19, 2, 34, 10)           # ARRIVAL PLAZA
    rect_carve(floor, 24, 0, 29, 3)            # north road → Woods edge
    rect_carve(floor, 3, 5, 19, 10)            # MARKET ROW (stalls both sides)
    rect_carve(floor, 4, 9, 9, 14)             # market → Echo street
    rect_carve(floor, 2, 13, 11, 20)           # ECHO DISTRICT
    rect_carve(floor, 10, 15, 19, 19)          # Echo → square street
    rect_carve(floor, 23, 9, 30, 13)           # plaza → square avenue (the dome is in view)
    rect_carve(floor, 18, 12, 36, 22)          # ARCHIVE SQUARE
    rect_carve(floor, 34, 4, 52, 11)           # boulevard sidewalks
    rect_carve(floor, 43, 10, 50, 15)          # Lantern Gate street
    rect_carve(floor, 41, 14, 50, 23)          # EAST LOT
    rect_carve(floor, 35, 16, 42, 20)          # east street
    rect_carve(floor, 44, 22, 48, 34)          # PATROL ALLEY
    rect_carve(floor, 36, 30, 48, 34)          # patrol alley → Sentinel plaza
    rect_carve(floor, 18, 22, 33, 29)          # GREENHOUSE GARDEN
    rect_carve(floor, 14, 29, 38, 36)          # SENTINEL PLAZA
    rect_carve(floor, 4, 19, 9, 22)            # Echo → west yard
    rect_carve(floor, 2, 21, 11, 29)           # WEST YARD
    rect_carve(floor, 4, 28, 7, 34)            # yard alley, down ...
    rect_carve(floor, 4, 31, 15, 34)           # ... and east into the Sentinel plaza
    rect_carve(floor, 23, 35, 30, 44)          # gate road
    rect_carve(floor, 16, 36, 24, 41)          # VOSS ALCOVE
    rect_carve(floor, 21, 40, 32, 44)          # south gate square
    # building lots (sprite top-left; door side faces the open floor below)
    LOTS = [("noodle_shop", 5, 2, (4, 2, 10, 5)),          # market row (enterable, #31)
            ("archive_library", 30, 12, (29, 12, 36, 17)),  # Archive Square (#31)
            ("tea_house", 39, 2, (38, 2, 44, 4)),           # Lantern Gate inn (#31)
            ("greenhouse", 19, 22, (18, 22, 24, 26)),       # garden
            ("apartment_block", 26, 22, (25, 22, 32, 27))]  # garden
    for _, _, _, (x0, y0, x1, y1) in LOTS:
        rect_carve(floor, x0, y0, x1, y1)
    lv.floor = floor | road
    wall = clean_walls(~lv.floor)
    lv.floor = ~wall
    road &= lv.floor
    road = clean_walls(road, border=0) & road
    sidewalk = ~road
    plaza = np.zeros_like(wall)
    for r in ((19, 2, 34, 10), (18, 12, 36, 22), (14, 29, 38, 36), (21, 40, 32, 44)):
        rect_carve(plaza, *r)
    plaza &= lv.floor & ~road
    lawn = np.zeros_like(wall)
    rect_carve(lawn, 18, 26, 33, 29)           # garden lawn
    rect_carve(lawn, 20, 3, 23, 6); rect_carve(lawn, 30, 3, 33, 6)            # plaza beds
    rect_carve(lawn, 19, 13, 23, 16)                                         # square bed
    safe = lv.floor & ~road & ~lv.dilate(road | wall, 1)
    lawn &= safe
    lawn = clean_walls(lawn, border=0) & lawn
    near_lawn = lv.dilate(lawn, 1)
    near_rw = lv.dilate(road | wall, 1)
    for y in range(lv.H):
        for x in range(lv.W):
            if wall[y, x]:
                lv.ground[y, x] = blob(ts, "sidewalk-building", wall, x, y, lv.rng)
            elif lawn[y, x]:
                lv.ground[y, x] = blob(ts, "sidewalk-grass", lawn, x, y, lv.rng)
            else:
                lv.ground[y, x] = blob(ts, "road-sidewalk", sidewalk, x, y, lv.rng, exclude={4, 5, 6, 7, 8})
                if plaza[y, x] and not near_lawn[y, x] and not near_rw[y, x]:
                    lv.ground[y, x] = 12 if (x * 7 + y * 3) % 13 else 13
    for x in range(36, 46):                    # lane arrows east to the Lantern Gate
        if road[7, x]: lv.ground[7, x] = 7
    lv.keepout = road.copy()
    lv.keepout_hard = np.zeros_like(wall)
    for k, (x, y) in P.items():
        disk_carve(lv.keepout, x, y, 2.8); disk_carve(lv.keepout_hard, x, y, 1.6)
    for r in ((19, 2, 34, 10), (18, 12, 36, 22), (14, 29, 38, 36), (21, 40, 32, 44), (23, 9, 30, 13),
              (3, 6, 19, 9), (10, 16, 19, 18), (36, 31, 48, 33), (5, 29, 6, 33), (5, 32, 15, 33)):
        rect_carve(lv.keepout, *r)             # walk lines stay free of colliding props
    for name, tx, ty, (x0, y0, x1, y1) in LOTS:
        d = BUILDINGS.defs[name]       # lot + sprite + the row in front of the door
        for m in (lv.keepout, lv.keepout_hard):
            rect_carve(m, x0, y0, x1, y1 + 1)
            rect_carve(m, tx - 1, ty, tx + d["w"] // T + 1, ty + d["h"] // T + 1)
    for (fx, fy) in CITY_RESERVED:
        disk_carve(lv.keepout, fx, fy, 1.6); disk_carve(lv.keepout_hard, fx, fy, 1.0)
    # landmarks: the plaza fountain on the axis to the Archive dome, market
    # stalls, the Lantern Gate billboard, Sentinel plaza helipad, parked cars
    for name, x, y in (("fountain", 25, 5), ("kiosk", 11, 5), ("kiosk", 13, 5), ("neon_sign", 15, 5),
                       ("vending_machine", 17, 5), ("kiosk", 6, 9), ("kiosk", 11, 9), ("neon_sign", 15, 9),
                       ("holo_billboard", 48, 4), ("neon_sign", 48, 10), ("helipad", 30, 30),
                       ("car_blue_v", 48, 15), ("car_purple_v", 42, 21), ("hover_taxi_v", 48, 21),
                       ("traffic_light", 34, 5), ("traffic_light", 37, 16), ("bus_stop", 36, 10)):
        landmark(lv, name, x, y)
    # corner lamps: every district is lit at night (#35 light pools)
    for (x, y) in ((20, 2), (32, 2), (19, 9), (33, 9), (18, 12), (18, 21), (35, 21), (14, 29), (37, 29),
                   (14, 35), (37, 35), (3, 5), (18, 5), (18, 9), (2, 13), (10, 19), (2, 21), (10, 28),
                   (41, 14), (49, 22), (44, 25), (47, 29), (16, 36), (23, 40), (35, 10), (43, 10)):
        landmark(lv, "street_lamp", x, y)
    sidewalk = lv.floor & ~road
    curb = sidewalk & lv.dilate(road, 1)
    near_wall = sidewalk & lv.fringe(wall)
    furniture = (curb | near_wall) & ~lawn
    lv.line_props("street_lamp", [(35, 4), (51, 4)], step=4)
    lv.line_props("street_lamp", [(35, 10), (42, 10)], step=3)
    lv.line_props("street_lamp", [(19, 2), (19, 9)], step=3)
    lv.line_props("street_lamp", [(33, 2), (33, 9)], step=3)
    lv.line_props("street_lamp", [(18, 12), (18, 21)], step=3)
    lv.line_props("street_lamp", [(14, 29), (14, 30)], step=1)
    lv.line_props("street_lamp", [(37, 29), (37, 30)], step=1)
    lv.line_props("street_lamp", [(23, 36), (23, 43)], step=3)
    lv.line_props("street_lamp", [(29, 36), (29, 43)], step=3)
    lv.scatter_on(["planter_small", "bench", "bollard"], 22, furniture)
    lv.scatter_on(["trash_bin", "hydrant", "vending_machine"], 12, near_wall)
    lv.scatter_on(["planter_tree", "kiosk", "bus_stop"], 6, near_wall)
    lv.scatter_on(["planter_tree", "planter_small"], 5, lawn)
    lv.cluster(["bench", "planter_small"], *P["arch"], 3, radius=3)
    lv.cluster(["bench", "trash_bin"], *P["voss"], 2, radius=2)
    interior = np.zeros_like(wall)
    interior[1:-1, 1:-1] = (wall[1:-1, 1:-1] & wall[:-2, 1:-1] & wall[2:, 1:-1] & wall[1:-1, :-2] & wall[1:-1, 2:])
    lv.scatter_on(["rooftop_ac", "solar_panel"], 22, interior, need_floor=False)
    lv.scatter_on(["rooftop_vent"], 14, interior, need_floor=False)  # animated steam
    for name, tx, ty, _ in LOTS:
        lv.building(name, tx, ty)
    place(lv, "spawn", *P["spawn"])
    place(lv, "npc", *P["echo7"], name="echo7")
    place(lv, "npc", *P["arch"], name="archivist")
    place(lv, "npc", *P["voss"], name="voss")
    place(lv, "health", *P["h1"], was=(17.5, 13.5))
    place(lv, "health", *P["h2"], was=(14.5, 22.5))
    place(lv, "health", *P["h3"], was=(17.5, 34.5))
    place(lv, "sentinel", *P["sentinel"])
    place(lv, "drone", *P["d1"], startAngle=1.0, kind="shield")
    place(lv, "drone", *P["d2"], startAngle=3.3, kind="scout")
    # Memory 3: the west yard, past two drones (optional)
    place(lv, "fragment", P["yard"][0] - 1.0, P["yard"][1] + 2.0, was=(3.5, 17.5))
    place(lv, "drone", P["yard"][0] + 3.0, P["yard"][1], startAngle=0.4, kind="swarm")
    # Walk-off edges for adjacent maps (same sides as before).
    gx = int(P["spawn"][0]); sx = int(P["gate"][0]); ey = int(P["town"][1])
    open_map_edge(lv, "north", gx, half=2)
    open_map_edge(lv, "south", sx, half=2)
    open_map_edge(lv, "east", ey, half=2)
    place_mapexit(lv, "north", gx, dest="woods", entry="south", half=2)
    place_mapexit(lv, "south", sx, dest="ruins", entry="north", half=2, unlock=True,
                  lockedTitle="SOUTH ROAD",
                  lockedBody="The Archivist opens this road after the Sentinel falls.")
    place_mapexit(lv, "east", ey, dest="town", entry="west", half=2)
    place_entry(lv, "north", *P["spawn"])
    place_entry(lv, "south", P["gate"][0], P["gate"][1] - 0.5)
    place_entry(lv, "east", *P["town"])
    place(lv, "checkpoint", *P["spawn"], label="Arrival Plaza")
    place(lv, "checkpoint", P["echo7"][0] + 1.5, P["echo7"][1] - 2.5, label="Echo District")
    place(lv, "checkpoint", 21.5, 14.0, label="Archive Square")
    place(lv, "checkpoint", P["gate"][0] + 2.0, P["gate"][1] + 0.5, label="South Gate")
    place(lv, "checkpoint", P["town"][0] - 3.5, P["town"][1] + 1.5, label="Lantern Road")
    place(lv, "examine", P["spawn"][0] + 2.0, P["spawn"][1] + 1.2,
          id="city_arrival_post", title="PLAZA POST",
          text="WEST: market and Echo-7. SOUTH: the Archive Square. EAST: Lantern Gate and the road to Town. "
               "North walks back to the Woods.")
    place(lv, "examine", 35.0, 19.0,
          id="city_archive_plaque", title="ARCHIVE PLAQUE",
          text="Sealed by the Archivist. First memory drafts keep here — not the Core itself.",
          clue="city_archive_hint")
    place(lv, "examine", P["voss"][0] + 2.2, P["voss"][1] + 1.0,
          id="city_uec_terminal", title="UEC FIELD TERMINAL",
          text="Override accepted. Field orders scroll past.",
          clue="uec_orders", item="uec_override", consume=True, flag="read_uec_orders")
    place(lv, "examine", P["yard"][0] + 1.0, P["yard"][1] + 2.5,
          id="city_yard_memo", title="DROPPED SLATE",
          text="A scout's note: \"Archive walls hum. Stay clear.\"",
          clue="city_yard_memo")
    place(lv, "stash", P["yard"][0] - 1.5, P["yard"][1] - 1.5, glimmer=18, was=(4.0, 19.5))
    place(lv, "examine", P["town"][0] - 3.5, P["town"][1] - 2.5,
          id="city_lantern_sign", title="LANTERN ROAD",
          text="Walk east off the map to Lantern Town. The inn takes travellers; the street south "
               "runs to the east lot and back round to the Archive Square.")
    place(lv, "examine", 24.0, 15.5,
          id="city_branch_sign", title="CROSS STREET",
          text="Archive Square. Every street in the old city ends up here.")
    place(lv, "drone", P["lot"][0] - 1.0, P["lot"][1] - 1.0, startAngle=0.8, kind="scout", nest="city_east_nest")
    place(lv, "drone", P["lot"][0] + 1.5, P["lot"][1] + 1.5, startAngle=2.6, kind="swarm", nest="city_east_nest")
    place(lv, "examine", P["lot"][0] + 0.5, P["lot"][1] - 2.0,
          id="city_east_slate", title="EAST LOT SLATE",
          text="Nest roster: hold the east lot. Town wants them gone.",
          clue="quest_city_east_slate")
    place(lv, "drone", *P["se"], startAngle=1.5, kind="sniper", nest="city_se_patrol")
    place(lv, "examine", P["se"][0] + 1.0, P["se"][1] + 2.0,
          id="city_se_slate", title="DEAD PATROL PAD",
          text="Last ping: the patrol alley, south-east. Someone from Town is asking for this pad.",
          quest="city_se_patrol")
    place(lv, "examine", *P["cache"],
          id="city_west_cache", title="MARKED CRATE",
          text="Trader chalk: 'For Mira's board.' Heavy with colony salvage.",
          quest="city_west_cache")
    place(lv, "stash", P["cache"][0] + 1.5, P["cache"][1] + 0.5, glimmer=14, was=(5.5, 10.5))
    lv.write("world2.tmj", "tilesets/city.png")
    return ts

CITY_RESERVED = ((4.5, 25), (3.5, 27), (7.5, 25), (5.5, 27.5), (3, 23.5), (5.5, 11), (7, 11.5),
                 (46, 19), (45, 18), (47.5, 20.5), (46.5, 17), (45.5, 26.5), (46.5, 28.5),
                 (46, 5), (46, 10), (35, 19), (24, 15.5), (21.7, 39.5), (28.5, 5.7), (21.5, 14))

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
    rect_carve(floor, 11, 20, 17, 26)          # south court
    rect_carve(floor, 0, 11, 8, 16)            # west road → City edge
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
    place(lv, "npc", *P["mira"], name="mira", sprite="mira")
    place(lv, "health", *P["h1"])
    place(lv, "stash", *P["stash"], glimmer=15)
    # West road back to the City — walk off the map.
    open_map_edge(lv, "west", int(P["mira"][1]), half=2)
    place_mapexit(lv, "west", int(P["mira"][1]), dest="city", entry="east", half=2)
    place_entry(lv, "west", 4.5, P["mira"][1])
    place_entry(lv, "north", *P["spawn"])
    place(lv, "checkpoint", *P["spawn"], label="Lantern Gate")
    place(lv, "checkpoint", *P["portal"], label="Market South")
    place(lv, "examine", P["mira"][0] + 1.6, P["mira"][1] + 0.4,
          id="town_stall", title="MIRA'S STALL",
          text="Salvage and colony trinkets. Pay in glimmer.",
          shop=True)
    place(lv, "examine", P["mira"][0] - 1.4, P["mira"][1] - 0.6,
          id="town_quest_board", title="JOB BOARD",
          text="Chalk and string. Woods and city errands for travellers.",
          board=True)
    place(lv, "examine", 5.0, P["mira"][1],
          id="town_west_road", title="CITY ROAD",
          text="West off the map returns to the City's Lantern Road.")
    lv.write("world5.tmj", "tilesets/city.png")
    return ts

# =============================================================== MAP 3: cyberpunk ruins
def map3():
    """Ruins dungeon: hub at h2, NE key wing, SE keyed gate to Core, SW Memory 5 deep path."""
    ts = Tileset("cyberpunk")
    lv = Level(ts, 46, 46, seed=33)
    P = dict(spawn=(5.5, 5.5), h1=(6, 13), d1=(16, 6), d2=(18, 12), h2=(17, 18), d3=(26, 5),
             h3=(31, 7), key=(39.5, 6.5), d4=(33, 19), h4=(35, 27), gate=(37.5, 33.5),
             d5=(23, 29), d6=(12, 36), m5a=(8, 40), m5b=(4.5, 42.5), portal=(39.5, 39.5))
    # No d5→portal shortcut: SE approach must pass the keyed gate after h4.
    edges = [("spawn", "d1"), ("spawn", "h1"), ("d1", "d2"), ("d2", "h2"), ("h1", "h2"), ("d1", "d3"),
             ("d3", "h3"), ("h3", "key"), ("h3", "d4"), ("h2", "d4"), ("d4", "h4"),
             ("h4", "gate"), ("gate", "portal"), ("h2", "d5"), ("d5", "d6"),
             ("d6", "m5a"), ("m5a", "m5b")]
    for a, b in edges: seg_carve(lv.floor, P[a], P[b], 1.9)
    for k, (x, y) in P.items():
        # Gate is a choke, not a plaza — otherwise players walk around LOCKED.
        if k == "gate":
            r = 1.8
        elif k in ("spawn", "portal"):
            r = 4.2
        elif k in ("key", "m5b"):
            r = 3.6
        else:
            r = 3.3
        disk_carve(lv.floor, x, y, r)
    # North road back to the City edge.
    seg_carve(lv.floor, P["spawn"], (P["spawn"][0], 1.0), 1.9)
    # Pinch SE approach to a 3-tile slit the storygate seals (x 36..38 at y 32..34).
    for y in range(32, 35):
        for x in range(33, 43):
            lv.floor[y, x] = 36 <= x <= 38
    # Restore portal court / short approach south of the choke.
    disk_carve(lv.floor, *P["portal"], 4.2)
    seg_carve(lv.floor, (37.5, 34.5), P["portal"], 1.35)
    wall = clean_walls(~lv.floor)
    lv.floor = ~wall
    # Re-assert choke after clean_walls (it can re-open diagonals).
    for y in range(32, 35):
        for x in range(33, 43):
            lv.floor[y, x] = 36 <= x <= 38
    wall = ~lv.floor
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
    lv.scatter_on(["steam_vent"], 6, edge | pocket)  # ground vents — animated steam
    lv.scatter_on(["neon_streetlight"], 6, edge)
    lv.cluster(["barrel_purple", "crate", "rubble_small"], *P["h2"], 4, radius=2)
    lv.cluster(["barricade", "rubble_small"], *P["spawn"], 3, radius=3)
    lv.cluster(["drone_wreck", "barrel_toxic"], *P["portal"], 3, radius=3)
    # Aetherian shrine on the SW optional road (landmark before Memory 5 deep wing)
    lv.building("ruin_shrine", 10, 31)
    lv.carve_lots(wall, [(9, 30, 14, 37)],
                  lambda x, y, w, rng: None if (metal[y, x] or sludge[y, x]) else blob(ts, "asphalt-ruin", w, x, y, rng))
    place(lv, "spawn", *P["spawn"])
    for k in ("h1", "h2", "h3", "h4"): place(lv, "health", *P[k])
    place(lv, "drone", *P["d1"], startAngle=0.5, kind="sniper")
    place(lv, "drone", *P["d3"], startAngle=3.1, kind="shield")
    place(lv, "drone", *P["d4"], startAngle=4.5, kind="scout")
    place(lv, "drone", *P["d5"], startAngle=2.3, kind="swarm")
    # NE key wing
    place(lv, "examine", *P["key"],
          id="ruins_gate_key", title="AETHERIAN KEYSTONE",
          text="A cold keystone. The SE gate toward the Core will accept this.",
          give="ruins_gate_key", clue="ruins_keystone")
    place(lv, "drone", P["key"][0] - 1.2, P["key"][1] + 0.8, startAngle=2.0, kind="shield")
    # SE keyed gate — spans the full 3-tile choke (cannot walk around).
    lv.obj("storygate", 36 * T, 32 * T, 3 * T, 3 * T, flag="ruins_gate_open")
    place(lv, "examine", 37.5, 31.6,
          id="ruins_se_gate", title="SEALED GATE",
          text="Lattice lock. The Aetherian Keystone is in the north-east wing — bring it back and USE it here.",
          item="ruins_gate_key", consume=True, flag="ruins_gate_open",
          clue="ruins_gate_open")
    # Memory 5 deep SW path (optional)
    place(lv, "fragment", *P["m5b"])
    place(lv, "drone", P["m5a"][0] + 0.8, P["m5a"][1] - 0.4, startAngle=1.2, kind="swarm")
    place(lv, "drone", P["m5b"][0] + 1.0, P["m5b"][1] - 0.6, startAngle=4.0, kind="swarm")
    place(lv, "stash", P["m5a"][0] - 0.8, P["m5a"][1] + 0.5, glimmer=22)
    # North road back to the City; Core still uses a portal (chamber gate).
    open_map_edge(lv, "north", int(P["spawn"][0]), half=2)
    place_mapexit(lv, "north", int(P["spawn"][0]), dest="city", entry="south", half=2)
    place_entry(lv, "north", *P["spawn"])
    place(lv, "portal", *P["portal"])
    place(lv, "checkpoint", *P["spawn"], label="Ruined Landing")
    place(lv, "checkpoint", P["h2"][0], P["h2"][1], label="Central Clearing")
    place(lv, "checkpoint", P["portal"][0] - 2.5, P["portal"][1] - 2.5, label="Extraction Approach")
    place(lv, "examine", P["spawn"][0] + 1.5, P["spawn"][1] + 1.0,
          id="ruins_landing_mark", title="LANDING MARK",
          text="UEC paint over Aetherian stone: \"Wipe authorized.\" Someone scratched it out. North walks back to the City.",
          clue="ruins_landing")
    place(lv, "examine", P["h2"][0] - 1.0, P["h2"][1] + 0.8,
          id="ruins_clearing_ring", title="BROKEN RING",
          text="SE path to the Core is sealed. Go NORTH-EAST for the Aetherian Keystone, then return. SW shrine is optional.",
          clue="ruins_ring")
    place(lv, "stash", P["d5"][0] - 1.5, P["d5"][1] + 1.0, glimmer=20)
    place(lv, "health", P["d5"][0] + 1.5, P["d5"][1] + 0.5)
    place(lv, "examine", P["d5"][0], P["d5"][1] - 1.2,
          id="ruins_dead_end", title="WAYMARKER",
          text="Offline UEC pad: \"Shrine sector SW — anomaly deep past the ruin. Optional.\"",
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
