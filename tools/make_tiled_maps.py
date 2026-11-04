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
  <out>/world6.tmj  Canal Works yard  (tileset junkyard; west of City SW)
  <out>/tilesets/<name>.png
  <preview>/preview_world*.png        (only with --preview: render + walkability)

Layers per map: "ground" (blob/wang terrain incl. walls), "props" (decor,
some collide via per-tile collision rects) and an object layer "gameplay"
with objects named spawn, portal, npc (property name), fragment, health,
drone (properties startAngle, kind=scout|sniper|shield|swarm), dronespawn (kind + optional nest/max/interval;
rectangle = spawn area, pad at centre), sentinel, checkpoint (property label). Object x/y = component top-left in
world px, width/height = component size (same coords the code used before).

M2 (woods only): creature (species, radius in tiles, netted, gated), stump
(hollow stump scenery), sweetroot (vine fox pickup on grass), pebble
(the brookling's river pebble), stash
(glimmer), moonflower (decor), glyph (glyph id), hidden (glimmer; brookling DIG),
hiddenpath (brambles the vine fox's SCENT opens), boulder (2x2 tiles,
pushX/pushY in tiles; needs the stone turtle's PUSH) and darkzone (a rect of
darkness; the glowmoth's LIGHT reveals the glyph inside). Those optional
ability gates only guard secrets (glyph, stash, hidden, creatures marked gated).

Main-route ability gates (brief-woods-befriend-gates): abilitygate objects with
kind (grotto | bramble | boulder), gate (save id), ability, creature (species
that opens it) and optional needs (comma list of object names the creature's
bond needs, e.g. stump for the sweetroot). Each kind blocks the tiles its
Designer collision covers in that state (GATE_ART, closed vs open); an object
whose gate property names a gate (the pond fragment in the grotto mouth) is
locked until that gate opens and is then taken from its interaction point. validate_main_gates() checks every
opening order: each gate's creature, its items and the gate itself are
reachable before that gate opens, all gates together complete the map's goal
(lv.goal: fragments + unlocked exit) and no single gate can be skipped.

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
import itertools, json, math, os, shutil, sys
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

    # Walk-on / ground-plane props: always stay on the tile layer under Kaela.
    # (Multi-tile pads would otherwise become dynamicAbove and draw over her.)
    FLOOR_PROPS = frozenset({
        "helipad", "portal_platform", "portal_hexpad",
        "dock_planks_h", "dock_planks_v", "ship_debris",
        "solar_panel", "loose_cables", "floor_ring_marker",
    })

    def to_json(self, firstgid, image_path):
        # Prop stamp height (tiles): tall / solid props become Bonfire
        # `dynamicAbove` decorations so they y-sort with Kaela (tile-layer
        # props always draw under the player, which looks wrong in front).
        prop_h = {n: h for n, (_, h, _) in self.props.items()}
        tiles = []
        for tid in sorted(self.tiles):
            t = self.tiles[tid]
            d = {"id": tid}
            if t["prob"] != 1: d["probability"] = t["prob"]
            typ = t["type"]
            if not typ:
                prop_name = t["props"].get("prop", (None, None))[1]
                if (prop_name and prop_name not in self.FLOOR_PROPS
                        and (prop_h.get(prop_name, 1) >= 2 or t["rects"])):
                    typ = "dynamicAbove"
            if typ: d["type"] = typ
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
        self.goal = None            # main-route gates: dict(fragments=N), see validate_main_gates

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

    def _prop_centre(self, name, x, y):
        w, h, _ = self.ts.props[name]
        return x + w / 2, y + h / 2

    def _spaced(self, name, x, y, min_dist, centres):
        if min_dist <= 0: return True
        cx, cy = self._prop_centre(name, x, y)
        r2 = min_dist * min_dist
        for ox, oy in centres:
            if (cx - ox) ** 2 + (cy - oy) ** 2 < r2:
                return False
        return True

    def _instance_centres(self):
        return [self._prop_centre(n, x, y) for n, x, y in self.instances]

    def scatter_on(self, names, n, mask, tries=None, need_floor=True, min_dist=0):
        """Place up to n props among tiles where mask is True.

        With [min_dist] > 0, candidates must stay that many tiles away from
        every already-stamped prop (and each other), so clutter doesn't clump.
        """
        cells = self.cells_of(mask)
        if not cells or n <= 0: return 0
        self.rng.shuffle(cells)
        tries = tries or max(n * 50, 1000)
        placed = 0
        centres = self._instance_centres()
        i = 0
        for _ in range(tries):
            if placed >= n: break
            name = names[self.rng.integers(len(names))]
            x, y = cells[i % len(cells)]
            i += 1
            if not self.prop_fits(name, x, y, need_floor): continue
            if not self._spaced(name, x, y, min_dist, centres): continue
            self.stamp(name, x, y)
            centres.append(self._prop_centre(name, x, y))
            placed += 1
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

    def vignette(self, cx, cy, pieces, need_floor=True):
        """Author a small scene: [(prop, dx, dy), ...] around a story tile."""
        placed = 0
        for name, dx, dy in pieces:
            x, y = int(round(cx + dx)), int(round(cy + dy))
            if name not in self.ts.props: continue
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

    def line_mix(self, names, points, step=3, need_floor=True):
        """Alternate props from [names] along a polyline (street furniture)."""
        if not names: return 0
        placed = 0
        i = 0
        for a, b in zip(points, points[1:]):
            ax, ay = a; bx, by = b
            dist = max(abs(bx - ax), abs(by - ay), 1)
            for t in range(0, int(dist) + 1, step):
                u = t / dist
                x, y = int(round(ax + (bx - ax) * u)), int(round(ay + (by - ay) * u))
                name = names[i % len(names)]; i += 1
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
                if o["name"] in ("drone", "sentinel", "dronespawn"):
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
        self.validate_main_gates(ok, cells, flood)
        self.validate_rings(ok, cells, flood)
        # UECDrone detection radius is 160 px (220 before the calm pass; centre
        # to centre) and it patrols a 70 px circle around its origin; keep
        # enemies outside that reach so the player isn't attacked at the spawn.
        scx, scy = spawn[0]["x"] + spawn[0]["w"] / 2, spawn[0]["y"] + spawn[0]["h"] / 2
        for o in self.objects:
            if o["name"] in ("drone", "sentinel", "dronespawn"):
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
            if o["name"] == "abilitygate":
                for (x, y) in gate_blocked_cells(o, "closed"): closed[y, x] = False
        reach = flood(closed)
        self.rings = rings(reach)
        for g in (o for o in self.objects if o["name"] == "storygate"):
            for o in self.objects:
                if o["name"] == "portal" and any(reach[y, x] for (x, y) in cells(o)):
                    raise SystemExit(f"storygate at {g['x']},{g['y']} can be walked around (portal reachable)")
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
                # push 0,0 = opens in place (road boulder rolls aside in art
                # only; the 3×2 mouth stays walkable). Don't re-block it.
                if px != 0 or py != 0:
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
            if o["name"] in ("drone", "sentinel", "darkzone", "boulder", "hiddenpath", "ambient", "light",
                             "abilitygate"):
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

    def validate_main_gates(self, ok, cells, flood):
        """Main-route ability gates: allowed as long as nothing deadlocks.
        For every order of opening them, the next gate's creature, the
        objects its bond needs and the gate itself must be reachable with the
        not-yet-opened gates still closed; all gates open must complete the
        goal, and leaving out any single gate must not (each one matters)."""
        objs = self.objects
        gates = [o for o in objs if o["name"] == "abilitygate"]
        if not gates:
            return
        if self.goal is None:
            raise SystemExit("abilitygate on a map without lv.goal")
        ids = [g["props"]["gate"] for g in gates]
        if len(set(ids)) != len(ids):
            raise SystemExit(f"duplicate gate ids {ids}")
        for o in objs:
            gid = o["props"].get("gate")
            if o["name"] != "abilitygate" and gid and gid not in ids:
                raise SystemExit(f"{o['name']} {o['props']} names unknown gate {gid}")
        H, W = ok.shape

        by_id = {g["props"]["gate"]: g for g in gates}

        def reach_with(opened):
            m = ok.copy()
            for g in gates:
                state = "open" if g["props"]["gate"] in opened else "closed"
                for (x, y) in gate_blocked_cells(g, state): m[y, x] = False
            return flood(m)

        def usable(o, reach, opened):
            gid = o["props"].get("gate")
            if o["name"] != "abilitygate" and gid:
                # inside a gate (the grotto fragment): taken from the gate's
                # interaction point once that gate is open
                if gid not in opened: return False
                x, y = gate_interact_cell(by_id[gid])
                return bool(reach[y, x])
            if o["name"] == "creature" and o["props"]["species"] in FLYING:
                cx, cy = (o["x"] + o["w"] / 2) / T, (o["y"] + o["h"] / 2) / T
                r = o["props"]["radius"] + 1.5
                return any(reach[y, x] for y in range(max(0, int(cy - r)), min(H, int(cy + r) + 1))
                           for x in range(max(0, int(cx - r)), min(W, int(cx + r) + 1))
                           if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r)
            return all(reach[y, x] for (x, y) in cells(o))

        def gate_reachable(g, reach):
            x, y = gate_interact_cell(g)
            return 0 <= x < W and 0 <= y < H and bool(reach[y, x])

        def goal_done(opened):
            reach = reach_with(opened)
            frags = sum(1 for o in objs if o["name"] == "fragment" and usable(o, reach, opened))
            exits = [o for o in objs if o["name"] == "mapexit" and o["props"].get("unlock")]
            return frags >= self.goal.get("fragments", 0) and all(
                any(reach[y, x] for (x, y) in cells(e)) for e in exits)

        def needs_of(g):
            sp = g["props"]["creature"]
            found = [o for o in objs if o["name"] == "creature" and o["props"]["species"] == sp]
            if not found:
                raise SystemExit(f"gate {g['props']['gate']}: no {sp} on this map")
            names = [n for n in str(g["props"].get("needs", "")).split(",") if n]
            items = [o for o in objs if o["name"] in names]
            if len({o["name"] for o in items}) != len(names):
                raise SystemExit(f"gate {g['props']['gate']}: missing needed object(s) {names}")
            return found + items

        for order in itertools.permutations(gates):
            opened = set()
            for g in order:
                reach = reach_with(opened)
                gid = g["props"]["gate"]
                path = " -> ".join(o["props"]["gate"] for o in order)
                for o in needs_of(g):
                    if not usable(o, reach, opened):
                        raise SystemExit(f"gate {gid}: {o['name']} {o['props'].get('species', '')} not reachable "
                                         f"before it opens (order {path})")
                if not gate_reachable(g, reach):
                    raise SystemExit(f"gate {gid} itself is not reachable (order {path})")
                opened.add(gid)
        if not goal_done(set(ids)):
            raise SystemExit(f"goal {self.goal} not reachable with every main gate open")
        for gid in ids:
            if goal_done(set(ids) - {gid}):
                raise SystemExit(f"gate {gid} can be skipped (goal reachable without it)")

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
            if name in self.EMITTERS:
                px, py = self.EMITTERS[name]
                cx, cy = x * T + px, y * T + py
            elif kind in ("steam", "smoke"):
                cy = (y + 0.15 * h) * T
            elif kind == "ember":
                # Bowl / brazier mouth (not the top rim — FX was floating behind).
                cy = (y + 0.42 * h) * T
            self.obj("ambient", cx - 12, cy - 12, 24, 24, kind=kind)
        # chimney / kitchen smoke: px from the building sprite top-left, at the
        # stack mouth so the plume base sits on the chimney (not in the sky).
        for bd in self.buildings:
            for (px, py) in self.CHIMNEYS.get(bd["name"], ()):
                self.obj("ambient", bd["tx"] * T + px - 12, bd["ty"] * T + py - 12, 24, 24, kind="smoke")
        # mist drifting over open water (ponds), set per map in tile coords
        for (tx, ty) in self.mist:
            self.obj("ambient", tx * T - 12, ty * T - 12, 24, 24, kind="mist")

    # emitter point (px from the prop's top-left) where the default above misses the art
    EMITTERS = {
        "crashed_ship": (52, 62),      # skiff fuselage ridge behind the canopy (#47); block top is empty air
    }

    CHIMNEYS = {
        "ranger_cabin": ((48, 20),),       # left stone chimney tip
        "apartment_block": ((30, 8),),     # left roof stack
        "noodle_shop": ((64, 22),),        # kitchen roof line
        "tea_house": ((64, 18),),          # roof peak
    }

    # Night light pools (#35): prop -> (kind, glow radius px, pool centre as a
    # fraction of the prop height). The game draws a cached cookie per light.
    LIGHTS = {
        # Anchor near the prop; game shifts the drawn pool toward the ground so
        # the NightTint cookie doesn't cover the lantern/lamp sprite.
        "street_lamp": ("lamp", 68, 0.75),
        "lantern": ("lantern", 56, 0.7),
        "campfire": ("fire", 80, 0.5),
        "energy_brazier": ("energy", 64, 0.5),
        "neon_streetlight": ("neon", 64, 0.75),
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
                   health=(0, 255, 120), drone=(255, 60, 60), dronespawn=(255, 90, 140), sentinel=(255, 120, 0),
                   checkpoint=(120, 255, 220), creature=(255, 170, 255), stump=(200, 140, 60),
                   sweetroot=(255, 180, 80),
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
SZ = dict(spawn=32, portal=96, npc=30, fragment=18, health=16, drone=24, sentinel=48, checkpoint=32,
          creature=32, stump=64, sweetroot=32, stash=32, glyph=24, hidden=24, pebble=16, moonflower=16, examine=20,
          storygate=64, entry=32)
# Travel light (crystal + pool): centred on the portal tile. Keep in sync with
# PortalComponent.lightW / lightH.
PORTAL_LIGHT = (48, 48)

def _edge_sample(lv, side, cx, half):
    """Ground tile from the corridor centre (not the sidewalk fringe).

    Scanning left→right / top→bottom often hits a road-sidewalk edge piece
    (city 61/67) and paints the whole mouth as a fake wall strip.
    """
    W, H = lv.W, lv.H
    sample = 1
    if side in ("south", "north"):
        sy = min(H - 4, H - 1) if side == "south" else min(3, H - 1)
        x0, x1 = max(0, cx - half), min(W, cx + half + 1)
        order = [cx] + [x for x in range(x0, x1) if x != cx]
        for x in order:
            if 0 <= x < W and lv.floor[sy, x] and int(lv.ground[sy, x]) >= 0:
                return int(lv.ground[sy, x])
    else:
        sx = min(W - 4, W - 1) if side == "east" else min(3, W - 1)
        y0, y1 = max(0, cx - half), min(H, cx + half + 1)
        order = [cx] + [y for y in range(y0, y1) if y != cx]
        for y in order:
            if 0 <= y < H and lv.floor[y, sx] and int(lv.ground[y, sx]) >= 0:
                return int(lv.ground[y, sx])
    return sample

def open_map_edge(lv, side, cx, half=2):
    """Punch a walkable corridor through the sealed map border (after clean_walls).
    [side] is north/south/east/west; [cx] is the centre tile along that edge.

    Only flips [lv.floor] — ground wang tiles stay stale until the caller
    re-blobs (see [retile_woods_edge] / [retile_city_edge]). A temporary
    sample fill keeps the layer non-empty if retile is skipped.
    """
    W, H = lv.W, lv.H
    sample = _edge_sample(lv, side, cx, half)
    if side == "south":
        x0, x1 = max(0, cx - half), min(W, cx + half + 1)
        for y in range(H - 3, H):
            for x in range(x0, x1):
                lv.floor[y, x] = True
                if lv.ground[y, x] < 0 or y >= H - 2:
                    lv.ground[y, x] = sample
    elif side == "north":
        x0, x1 = max(0, cx - half), min(W, cx + half + 1)
        for y in range(0, 3):
            for x in range(x0, x1):
                lv.floor[y, x] = True
                lv.ground[y, x] = sample
    elif side == "east":
        y0, y1 = max(0, cx - half), min(H, cx + half + 1)
        for x in range(W - 3, W):
            for y in range(y0, y1):
                lv.floor[y, x] = True
                if lv.ground[y, x] < 0 or x >= W - 2:
                    lv.ground[y, x] = sample
    elif side == "west":
        y0, y1 = max(0, cx - half), min(H, cx + half + 1)
        for x in range(0, 3):
            for y in range(y0, y1):
                lv.floor[y, x] = True
                lv.ground[y, x] = sample

def retile_woods_edge(lv, ts, path, water, side, cx, half=2, margin=2):
    """Re-blob grass-forest / path around a punched woods edge.

    Without this, forest cells still look like interior wall (dense 14/15)
    flush against the punched grass — no grass-forest edge piece.
    """
    W, H = lv.W, lv.H
    wall = ~lv.floor
    if side == "south":
        x0, x1 = max(0, cx - half), min(W, cx + half + 1)
        # Road continues through the mouth.
        for y in range(H - 3, H):
            for x in range(x0, x1):
                if lv.floor[y, x]:
                    path[y, x] = True
        rx0, rx1 = max(0, cx - half - margin), min(W, cx + half + 1 + margin)
        ry0, ry1 = max(0, H - 3 - margin - 1), H
    elif side == "north":
        x0, x1 = max(0, cx - half), min(W, cx + half + 1)
        for y in range(0, 3):
            for x in range(x0, x1):
                if lv.floor[y, x]:
                    path[y, x] = True
        rx0, rx1 = max(0, cx - half - margin), min(W, cx + half + 1 + margin)
        ry0, ry1 = 0, min(H, 3 + margin + 1)
    elif side == "east":
        y0, y1 = max(0, cx - half), min(H, cx + half + 1)
        for x in range(W - 3, W):
            for y in range(y0, y1):
                if lv.floor[y, x]:
                    path[y, x] = True
        rx0, rx1 = max(0, W - 3 - margin - 1), W
        ry0, ry1 = max(0, cx - half - margin), min(H, cx + half + 1 + margin)
    elif side == "west":
        y0, y1 = max(0, cx - half), min(H, cx + half + 1)
        for x in range(0, 3):
            for y in range(y0, y1):
                if lv.floor[y, x]:
                    path[y, x] = True
        rx0, rx1 = 0, min(W, 3 + margin + 1)
        ry0, ry1 = max(0, cx - half - margin), min(H, cx + half + 1 + margin)
    else:
        return
    path &= lv.floor & ~water
    for y in range(ry0, ry1):
        for x in range(rx0, rx1):
            if wall[y, x] or not (water[y, x] or path[y, x]):
                lv.ground[y, x] = blob(ts, "grass-forest", wall, x, y, lv.rng)
            if water[y, x]:
                lv.ground[y, x] = blob(ts, "grass-water", water, x, y, lv.rng)
            if path[y, x]:
                lv.ground[y, x] = blob(ts, "grass-path", path, x, y, lv.rng)

def retile_city_edge(lv, ts, road, lawn, side, cx, half=2, margin=2, plaza=None,
                     extend_road=True):
    """Re-blob sidewalk-building / road-sidewalk around a punched city edge.

    Without this, the sealed border keeps interior building tiles (or a bad
    sample strip) flush on the mouth — same class of bug as [retile_woods_edge].
    """
    W, H = lv.W, lv.H
    wall = ~lv.floor
    if side == "south":
        x0, x1 = max(0, cx - half), min(W, cx + half + 1)
        if extend_road:
            for y in range(H - 3, H):
                for x in range(x0, x1):
                    if lv.floor[y, x]:
                        road[y, x] = True
        rx0, rx1 = max(0, cx - half - margin), min(W, cx + half + 1 + margin)
        ry0, ry1 = max(0, H - 3 - margin - 1), H
    elif side == "north":
        x0, x1 = max(0, cx - half), min(W, cx + half + 1)
        if extend_road:
            for y in range(0, 3):
                for x in range(x0, x1):
                    if lv.floor[y, x]:
                        road[y, x] = True
        rx0, rx1 = max(0, cx - half - margin), min(W, cx + half + 1 + margin)
        ry0, ry1 = 0, min(H, 3 + margin + 1)
    elif side == "east":
        y0, y1 = max(0, cx - half), min(H, cx + half + 1)
        if extend_road:
            for x in range(W - 3, W):
                for y in range(y0, y1):
                    if lv.floor[y, x]:
                        road[y, x] = True
        rx0, rx1 = max(0, W - 3 - margin - 1), W
        ry0, ry1 = max(0, cx - half - margin), min(H, cx + half + 1 + margin)
    elif side == "west":
        y0, y1 = max(0, cx - half), min(H, cx + half + 1)
        if extend_road:
            for x in range(0, 3):
                for y in range(y0, y1):
                    if lv.floor[y, x]:
                        road[y, x] = True
        rx0, rx1 = 0, min(W, 3 + margin + 1)
        ry0, ry1 = max(0, cx - half - margin), min(H, cx + half + 1 + margin)
    else:
        return
    road &= lv.floor
    if lawn is not None:
        lawn &= lv.floor & ~road
    sidewalk = ~road
    near_lawn = lv.dilate(lawn, 1) if lawn is not None else np.zeros_like(wall)
    near_rw = lv.dilate(road | wall, 1)
    for y in range(ry0, ry1):
        for x in range(rx0, rx1):
            if wall[y, x]:
                lv.ground[y, x] = blob(ts, "sidewalk-building", wall, x, y, lv.rng)
            elif lawn is not None and lawn[y, x]:
                lv.ground[y, x] = blob(ts, "sidewalk-grass", lawn, x, y, lv.rng)
            else:
                lv.ground[y, x] = blob(ts, "road-sidewalk", sidewalk, x, y, lv.rng,
                                       exclude={4, 5, 6, 7, 8})
                if (plaza is not None and plaza[y, x]
                        and not near_lawn[y, x] and not near_rw[y, x]):
                    lv.ground[y, x] = 12 if (x * 7 + y * 3) % 13 else 13

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
# Main-route gate art: collision rects [x, y, w, h] in art px for each state
# and the interaction point, from Designer's JSON (copied next to the PNGs in
# assets/images/obstacles/: pond_grotto.json, road_boulder.json,
# bramble_closed/open.json). test/woods_gates_test.dart keeps the game's
# copies of these rects in sync with the JSON. A tile counts as blocked in a
# state when one of that state's rects covers the tile centre.
GATE_ART = {
    "grotto": dict(size=(96, 64), interact=(46, 66),
                   # Façade stays solid lit or dark; cave entry is ENTER (#57).
                   closed=[(16, 3, 19, 30), (58, 3, 19, 30), (35, 3, 23, 10), (14, 33, 65, 29), (35, 13, 23, 20)],
                   open=[(16, 3, 19, 30), (58, 3, 19, 30), (35, 3, 23, 10), (14, 33, 65, 29), (35, 13, 23, 20)]),
    # Designer's interaction point is the south side; on the Woods road
    # Kaela arrives from the meadow, so the game uses the north side (48, 10)
    "boulder": dict(size=(96, 64), interact=(48, 10),
                    closed=[(0, 18, 96, 42)], open=[(58, 16, 38, 48)]),
    "bramble": dict(size=(64, 64), interact=(32, 20),
                    closed=[(4, 16, 56, 46)], open=[(1, 39, 15, 22), (48, 39, 15, 22)]),
}

def gate_blocked_cells(g, state):
    """Map tiles the gate object [g] blocks in [state] ('closed' / 'open')."""
    art = GATE_ART[g["props"]["kind"]]
    kx, ky = g["w"] / art["size"][0], g["h"] / art["size"][1]
    out = set()
    for ty in range(int(g["y"] // T), int((g["y"] + g["h"] - 0.01) // T) + 1):
        for tx in range(int(g["x"] // T), int((g["x"] + g["w"] - 0.01) // T) + 1):
            cx, cy = tx * T + T / 2, ty * T + T / 2
            for (x, y, w, h) in art[state]:
                x0, y0 = g["x"] + x * kx, g["y"] + y * ky
                if x0 < cx < x0 + w * kx and y0 < cy < y0 + h * ky:
                    out.add((tx, ty)); break
    return out

def gate_interact_cell(g):
    art = GATE_ART[g["props"]["kind"]]
    ix, iy = art["interact"]
    return (int((g["x"] + ix * g["w"] / art["size"][0]) // T), int((g["y"] + iy * g["h"] / art["size"][1]) // T))
# min centre distance from a checkpoint to each enemy kind (see validate)
CP_CLEAR = dict(drone=260, sentinel=300, dronespawn=260)
# Designer spawn rectangle for dronespawn (pad sits at centre). 2×2 tiles —
# whole rect must be walkable (no props); keep modest so city alleys fit.
DRONESPAWN_AREA = 64

def place(lv, obj, tx, ty, was=None, **props):
    """place an object whose CENTRE is at tile coords (tx, ty) (floats).
    Extra kwargs become Tiled properties (e.g. kind='sniper', name='gaia').
    was=(tx, ty): where the object sat before the #26 layout pass; its
    old pickup id is kept as property pid so existing saves still know it
    was collected / solved (the game ids pickups by map position).

    Portals are a light source: the glow centre sits on (tx, ty)."""
    if obj == "portal":
        w, h = PORTAL_LIGHT
        x = round(tx * T - w / 2)
        y = round(ty * T - h / 2)
        if was is not None:
            props["pid"] = f"{round(was[0] * T - w / 2)}_{round(was[1] * T - h / 2)}"
        lv.obj(obj, x, y, w, h, **props)
        return
    s = SZ[obj]
    if was is not None:
        props["pid"] = f"{round(was[0] * T - s / 2)}_{round(was[1] * T - s / 2)}"
    lv.obj(obj, round(tx * T - s / 2), round(ty * T - s / 2), s, s, **props)

def place_dronespawn(lv, tx, ty, kind, area=DRONESPAWN_AREA, **props):
    """Destructible one-kind spawn pad (GH #66). Rectangle centred on (tx, ty).

    Properties: kind (required), nest, interval, max, hp, delay, id, level."""
    w = h = int(area)
    x = round(tx * T - w / 2)
    y = round(ty * T - h / 2)
    lv.obj("dronespawn", x, y, w, h, kind=kind, **props)

def carve_route(lv, pts, half, mask=None):
    m = lv.floor if mask is None else mask
    for a, b in zip(pts, pts[1:]):
        seg_carve(m, a, b, half)

# =============================================================== MAP 1: woods
def map1():
    """Woods: expand the existing graph — same story spine, new side areas.

    All original clearings / gates / creatures keep their tile coords. The map
    grows east (+16) so new optional regions hang off the old east grove and
    pond without relocating the crash, Asha, or City exit:

        crash ── h1 ── cabin ─── ridge ─── pond (frag) ── willow creek (NEW)
          │        \\                  /      │              │
        west       CROSSROADS ── east bend ──┤── egrove ── watchtower (NEW)
        hollow    /     │              \\     │   (frag)        │
          │      /      │               \\    │                 fern gallery (NEW)
        sw bend ── ASHA'S CAMP ──── brook ── meadow ── old cart road (NEW)
          │                              \\     │
        nest spur ── nestloop (NEW) ──────┘    └── exit S → City

    Nest pads stay at the spur tip; nestloop only adds a way back so the spur
    is no longer a pure dead hallway. rings_min 3 after the east wilds land."""
    ts = Tileset("woods")
    # Was 56×54; grow east for willow / watch / fern / oldroad. Height unchanged
    # so the City exit and nest spur stay on the same rows.
    lv = Level(ts, 72, 54, seed=11)
    lv.rings_min = 3
    south = lv.H - 0.5  # path punch to the south edge
    # Original story places — DO NOT MOVE (gates, saves, playtested nooks).
    P = dict(spawn=(8, 9), gaia=(11, 8), h1=(17, 12), cabin=(19.5, 7.5), ridge=(31, 6),
             pond=(42, 10), f2=(37.41, 11.84), cross=(27, 20), d2=(34, 15.5), ebend=(36, 24),
             egrove=(48.5, 23), f4=(51, 29.5), whollow=(6, 23), f1=(5.5, 21.5), hollow=(13, 19),
             swbend=(9, 34), nestbend=(6, 42), nest=(4.5, 49), asha=(24, 33), h2=(23, 26),
             brook=(32, 35), meadow=(42, 36), h3=(44.5, 30.5), exit=(42, 50), f3=(15, 36),
             d1=(16, 33.5),
             # NEW expansion places (east wilds + nest reconnect)
             willow=(58, 9), watch=(64, 18), fern=(60, 28), oldroad=(56, 36),
             nestloop=(14, 44))
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
        ["swbend", "nestbend", "nest"],             # nest spur (Asha job) — long south walk
        ["meadow", "exit"],
        # --- expansion (optional exploration; does not relocate the spine) ---
        ["pond", "willow", "watch"],                # east of the pond
        ["egrove", "watch"],                        # grove → watchtower
        ["watch", "fern", "oldroad", "meadow"],     # east wilds down to meadow
        ["nest", "nestloop", "f3", "brook"],        # nest spur reconnects
    ]
    def route_pts(r):
        return [P[k] for k in r]
    for r in trails:
        carve_route(lv, route_pts(r), 2.0)
    big = dict(cross=5.5, asha=4.6, pond=5.2, meadow=4.6, spawn=4.6, egrove=4.4, whollow=3.8,
               nest=4.8, nestbend=2.8, willow=3.6, watch=4.0, fern=3.4, oldroad=3.2, nestloop=2.8)
    for k in ("spawn", "h1", "cabin", "ridge", "pond", "cross", "d2", "ebend", "egrove", "whollow",
              "hollow", "swbend", "nestbend", "nest", "asha", "h2", "brook", "meadow", "f3",
              "willow", "watch", "fern", "oldroad", "nestloop"):
        disk_carve(lv.floor, *P[k], big.get(k, 3.2))
    rect_carve(lv.floor, 16, 2, 24, 9)                # ranger cabin clearing
    seg_carve(lv.floor, P["exit"], (P["exit"][0], south), 2.0)
    # secret pockets (walls >= 2 thick around them; see the gates below)
    disk_carve(lv.floor, 4.5, 6.5, 3.4)                # crash scar under the wreck
    disk_carve(lv.floor, 3.5, 30.5, 2.2)              # LIGHT pocket off the west loop
    seg_carve(lv.floor, (6, 29.5), (3.5, 30.5), 1.4)
    wall = clean_walls(~lv.floor)
    lv.floor = ~wall
    # ---- ability-gated nooks, carved through solid forest after clean_walls
    # Mouth top-left of a 3×2 road boulder (same art as the south exit).
    # (11, 26) west brookling nook — leave as-is (playtested).
    # (49, 8) NE stash: keep this mouth (looks good); pocket used to reach the
    # east map border so you could walk into the camera void — keep it inland.
    nooks = [(49, 8), (11, 26)]
    gated = np.zeros_like(wall)
    for (bx, by) in nooks:
        gated[by:by + 2, bx - 3:bx] = True            # tunnel from the west
        gated[by:by + 2, bx:bx + 3] = True            # 3-wide mouth under the boulder
        # Nook east of the boulder — same 2-row height as the mouth. 3 tiles
        # deep (not 4): on the NE nook a 4-tile pocket hit the map edge.
        gated[by:by + 2, bx + 3:bx + 6] = True
    # SCENT side-bramble: ridge + moonflowers → 2x2 thorns → hushdeer glade,
    # hidden inside the forest block between the ridge and the crossroads
    gated[8:11, 27:29] = True                         # bramble cells (+ the trail row above)
    gated[11:14, 26:30] = True                        # hidden glade
    # Main-route SCENT gate: the east grove fragment sits in a pocket south of
    # the grove, behind a 2x2 bramble (trail row above + bramble + pocket)
    gated[25:28, 50:52] = True
    gated[28:31, 49:53] = True
    wall &= ~gated
    # Nook mouths: seal two rows above/below the 3-wide plug so you cannot
    # walk around the road boulder without PUSH (same idea as the south neck).
    for (bx, by) in nooks:
        wall[by - 2:by, bx:bx + 3] = True
        wall[by + 2:by + 4, bx:bx + 3] = True
        # No tall pocket: keep the east nook only on the mouth rows.
        wall[by - 3:by, bx + 3:bx + 6] = True
        wall[by + 2:by + 5, bx + 3:bx + 6] = True
        wall[by - 2:by, bx - 1] = True
        wall[by + 2:by + 4, bx - 1] = True
        # Cap the pocket's east end with forest so it never opens onto the
        # map border (NE nook sits one column from the edge).
        wall[by:by + 2, bx + 6] = True
    # Woods has no east/west edge exit — keep a 2-tile forest frame so a
    # carved pocket cannot dump you into the camera void past the map.
    wall[:, :2] = True
    wall[:, -2:] = True
    wall[:2, :] = True
    # south edge opened later by open_map_edge; leave rows 2.. alone here.
    # (north stays sealed — no north exit on this map.)
    # Egrove's clearing disk opens flanks around the thorns; seal both sides
    # (and the pocket corners) so the fragment is only entered through the gate.
    wall[26:29, 49] = True
    wall[26:29, 52] = True
    # Main-route PUSH gate: the south road narrows to a 3-tile neck (rows
    # 50-51, x 40-42) that the fallen boulder fills — seal east (and west)
    # so the nest spur / meadow flanks cannot walk around it.
    wall[50:52, 43] = True
    wall[50:52, 39] = True
    lv.floor = ~wall
    water = np.zeros_like(wall); rect_carve(water, 41, 7, 46, 10); water &= lv.floor
    lv.mist = [(42.5, 8.0), (44.5, 8.6)]
    path = np.zeros_like(wall)
    for r in trails:
        carve_route(lv, route_pts(r), 1.1, path)
    seg_carve(path, P["exit"], (P["exit"][0], south), 1.1)
    disk_carve(path, *P["cross"], 2.6)               # the crossroads reads as a plaza
    path &= lv.floor & ~water
    path = clean_walls(path, border=0) & path
    for y in range(lv.H):
        for x in range(lv.W):
            if wall[y, x] or not (water[y, x] or path[y, x]):
                lv.ground[y, x] = blob(ts, "grass-forest", wall, x, y, lv.rng)
            if water[y, x]: lv.ground[y, x] = blob(ts, "grass-water", water, x, y, lv.rng)
            if path[y, x]: lv.ground[y, x] = blob(ts, "grass-path", path, x, y, lv.rng)
    # NE stash nook: 2-tile-thick forest wall (x=53–54). Path ends at x=52.
    # West face 138 (shadow toward path), east face 149 (shadow toward willow).
    # Band edges 146/141 only over dirt; corners 157/158 at the path notch.
    lv.ground[8, 52] = 28   # grass-path east end (top)
    lv.ground[9, 52] = 31   # grass-path east end (bottom)
    lv.ground[8, 53] = 138  # left-edge forest (faces path)
    lv.ground[9, 53] = 138
    lv.ground[7, 52] = 146  # south-edge band over path only
    lv.ground[10, 52] = 141
    lv.ground[7, 53] = 157  # SW grass corner toward path end
    lv.ground[10, 53] = 158  # NW grass corner toward path end
    for y in (6, 11):
        lv.ground[y, 53] = 159
    for y in (6, 7, 8, 9, 10, 11):
        lv.ground[y, 54] = 149  # right-edge forest (faces willow clearing)
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
    for (x0, y0, x1, y1) in GATE_CLEAR:                # main-route gates + the ground in front of them
        rect_carve(lv.keepout, x0, y0, x1, y1); rect_carve(lv.keepout_hard, x0, y0, x1, y1)
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
                       ("signpost", 33, 33), ("signpost", 45, 15),
                       # East wilds beacons (new)
                       ("signpost", 55, 10), ("lantern", 57, 8), ("lantern", 59, 10),
                       ("signpost", 62, 17), ("radio_dish", 63, 15),
                       ("signpost", 58, 27), ("signpost", 54, 35)):
        landmark(lv, name, x, y)
    # Decor: authored lanterns (colliding — random scatter can seal secret paths),
    # spaced forest wall, path-verge soft props, story-clearing vignettes.
    fringe = lv.fringe(wall)
    edge = lv.path_edge()
    trees = ["tree_green", "tree_teal", "tree_blue", "tree_purple", "tree_pine", "tree_big"]
    bigp = ["log", "stump"]  # not boulder — random boulders choke ability-gate mouths
    bush = ["bush_green", "bush_glow", "rock_small", "rock_moss"]
    lv.scatter_on(trees, 40, fringe, min_dist=2.4)
    lv.scatter_on(bigp, 10, fringe, min_dist=4.0)
    lv.scatter_on(bush, 14, edge, min_dist=3.2)
    lv.scatter_on(["flowers", "mushrooms"], 12, edge, min_dist=4.0)
    lv.vignette(*P["cross"], [
        ("flowers", 2, 1), ("flowers", 1, -2), ("mushrooms", -1, 1), ("bush_glow", -2, 0),
    ])
    lv.vignette(*P["asha"], [
        ("flowers", 1, 1), ("bush_glow", 2, -1), ("stump", -1, 2),
    ])
    lv.vignette(*P["pond"], [
        ("flowers", -2, 2), ("flowers", 2, 1), ("rock_moss", 1, 2), ("bush_green", -1, 3),
    ])
    lv.vignette(*P["meadow"], [
        ("flowers", -1, -1), ("flowers", 2, 0), ("rock_moss", 1, 2), ("bush_green", -2, 1),
    ])
    lv.vignette(*P["hollow"], [
        ("mushrooms", 0, 1), ("mushrooms", -1, -1), ("flowers", 1, 0), ("bush_glow", 1, 1),
    ])
    lv.vignette(*P["ridge"], [
        ("rock_small", 2, 0), ("log", 1, 2), ("rock_moss", -1, 1),
    ])
    lv.vignette(*P["cabin"], [
        ("stump", 2, 2), ("flowers", 1, 3), ("bush_green", -1, 3),
    ])
    lv.vignette(*P["nest"], [
        ("log", 1, 0), ("bush_green", -1, 1), ("rock_moss", 0, -1),
    ])
    lv.vignette(*P["willow"], [
        ("flowers", 1, 1), ("flowers", -1, 0), ("bush_glow", 0, 2), ("rock_moss", 2, 0),
    ])
    lv.vignette(*P["watch"], [
        ("log", 1, 1), ("rock_small", -1, 0), ("bush_green", 2, -1),
    ])
    lv.vignette(*P["fern"], [
        ("mushrooms", 0, 1), ("flowers", 1, -1), ("bush_glow", -1, 0),
    ])
    lv.vignette(*P["oldroad"], [
        ("rock_moss", 1, 0), ("log", -1, 1), ("flowers", 0, -1),
    ])
    lv.building("ranger_cabin", 18, 2)
    # gameplay objects
    place(lv, "spawn", *P["spawn"])
    place(lv, "npc", *P["gaia"], name="gaia")
    place(lv, "npc", *P["asha"], name="asha")
    # memory fragments 1-2 (both open the road): pond grotto NE (LIGHT) and
    # the east grove pocket behind the brambles (SCENT)
    place(lv, "fragment", *P["f2"], was=(19.5, 16.5), gate="woods_grotto")
    place(lv, "fragment", *P["f4"], was=(24, 38.5))
    place(lv, "health", *P["h1"], was=(12.5, 14.5))
    place(lv, "health", *P["h2"], was=(11, 22.5))
    place(lv, "health", *P["h3"], was=(20, 33.5))
    place(lv, "drone", *P["d1"], startAngle=0.0, kind="scout")
    place(lv, "drone", *P["d2"], startAngle=2.1, kind="sniper")
    # Nest spur: one-kind pads (GH #66) — scout + swarm for Asha's nest job.
    # Keep both pads inside the nest clearing (second used to sit on the rim).
    place_dronespawn(lv, *P["nest"], kind="scout", nest=True, max=2, interval=7)
    place_dronespawn(lv, P["nest"][0] + 1.2, P["nest"][1] - 0.2, kind="swarm", nest=True, max=1, interval=9)
    # South road out of the woods → City (walk off the map).
    ex = int(P["exit"][0])
    open_map_edge(lv, "south", ex, half=2)
    # Forest beside the punched mouth must use grass-forest edge tiles (not
    # dense 14 flush on grass) — retile with path continuing through the exit.
    retile_woods_edge(lv, ts, path, water, "south", ex, half=2)
    place_mapexit(lv, "south", ex, dest="city", entry="north", half=2, unlock=True,
                  lockedTitle="WOODS EDGE",
                  lockedBody="The road south is blocked. The woods still want something from you.")
    place_entry(lv, "south", P["exit"][0], P["exit"][1] - 1.0)    # arriving back from the City
    # One backup per stage: spawn only (no mid-woods rings).
    place(lv, "checkpoint", *P["spawn"], label="Crash Site")
    # Kaela's diagnostic skiff (landmark crashed_ship at 2,4) — lore on the
    # walkable scar edge toward spawn, not on the prop footprint.
    place(lv, "examine", 6.5, 8.2,
          id="woods_skiff", title="DIAGNOSTIC SKIFF",
          text="Hull still warm. Flight log ends mid-sentence: ORBITAL PASS · GAIA DIAG · CHANNEL LOCK — then static. "
               "You woke here. Gaia was already waiting in the trees.",
          clue="skiff_crash")
    # Keep lore props outside NPC talk radius (72px ≈ 2.25 tiles).
    place(lv, "examine", P["spawn"][0] - 0.5, P["spawn"][1] + 2.8,
          id="woods_plaque", title="WEATHERED PLAQUE",
          text="\"We asked to stay.\" A second line: \"Bodies to soil. Minds to Gaia.\"",
          clue="gaia_plaque")
    place(lv, "examine", P["spawn"][0] - 1.2, P["spawn"][1] + 1.4,
          id="woods_mission_slate", title="FIELD BRIEF",
          text="Kaela — talk to Gaia (green) by the crash, then Asha at her camp: the woods need friends. Both glowing "
               "fragments open the road; trails ring round, and east of the grove the older wilds keep going. The road "
               "to the City leaves the south-east meadow. Do not let the UEC wipe her.")
    place(lv, "examine", P["asha"][0] - 3.4, P["asha"][1] + 1.2,
          id="woods_boot", title="UEC BOOT PRINT",
          text="Fresh composite sole marks in the moss after rain.", clue="boot_print")
    place(lv, "examine", P["f1"][0] + 0.6, P["f1"][1] - 0.3,
          id="woods_courier_pack", title="SEALED COURIER PACK",
          text="Lantern Town wax seal. Someone meant this for Mira's board.",
          quest="courier_pack")
    place(lv, "stash", P["f1"][0] - 0.6, P["f1"][1] + 1.0, glimmer=12, was=(5.7, 11.0))
    place(lv, "examine", P["nest"][0] + 2.4, P["nest"][1] - 0.8,
          id="woods_nest_slate", title="UEC FIELD SLATE",
          text="Nest roster. Scout and swarm pads online. 'Hold the west loop until recall.'",
          clue="quest_nest_slate")
    place(lv, "examine", P["f3"][0] + 0.5, P["f3"][1],
          id="woods_moonflower_pick", title="MOONFLOWER CLUSTER",
          text="A bloom cold as glass. Mira asked for one of these.",
          give="moonflower_bloom", quest="moonflower_draft")
    place(lv, "examine", P["cross"][0] + 1.2, P["cross"][1] + 2.4,
          id="woods_fork_sign", title="STANDING STONES",
          text="Every trail meets here. NE: the pond (and willow creek beyond). E: the grove, then the old watchtower. "
               "S: Asha's camp. W: the mossy hollow and round to the crash. Fragments: dark grotto by the pond, thorns "
               "past the grove. A fallen boulder still blocks the City road beyond the south-east meadow.")
    place(lv, "examine", P["ridge"][0] + 1.5, P["ridge"][1] - 0.5,
          id="woods_ridge_lookout", title="CITY LIGHTS TO THE SOUTH",
          text="From the ridge, past the radio dish, the City's glow hangs over the treeline to the south-east. "
               "The trails below all ring round to the meadow road.")
    place(lv, "examine", P["h2"][0] + 1.4, P["h2"][1] + 0.4,
          id="woods_job_sign", title="TRAIL NOTICE",
          text="Chalk: once you reach the City, look EAST down the boulevard for Lantern Town — jobs and glimmer.")
    place(lv, "examine", 36.1, 13.1,
          id="woods_glade_sign", title="SIDE PATH MARK",
          text="Trails leave the pond three ways: west along the ridge, south-west to the stones, south to the grove. "
               "A fourth path now runs east into willow creek. You will not get stuck.")
    place(lv, "examine", P["meadow"][0] + 2.0, P["meadow"][1] - 1.6,
          id="woods_portal_notice", title="SOUTH ROAD",
          text="City beyond this tree line. Walk south off the map. Its plaza looks three ways: Lantern Town east, "
               "the Archive south-east, the Ruins road south.")
    place(lv, "examine", P["willow"][0] + 0.5, P["willow"][1] + 1.8,
          id="woods_willow_mark", title="WILLOW CREEK",
          text="Water from the pond thins into a willow ditch. East: a crooked watchtower on the old rim. South: ferns "
               "down toward the cart road that rejoins the meadow.")
    place(lv, "examine", P["watch"][0] - 0.8, P["watch"][1] + 1.5,
          id="woods_watch_slate", title="FALLEN WATCH",
          text="UEC glass cracked in the moss. Someone watched the grove from here — then walked south into the ferns.")
    place(lv, "examine", P["fern"][0] + 0.6, P["fern"][1],
          id="woods_fern_cache", title="FERN SHELTER",
          text="A lean-to of cut fronds. Still dry inside. Trail chalk: OLD ROAD → MEADOW.")
    place(lv, "examine", P["oldroad"][0] + 1.0, P["oldroad"][1] - 0.8,
          id="woods_oldroad_post", title="CART-ROAD POST",
          text="Weathered mile-mark: LANTERN 6 / GROVE 1. The ruts turn west into the meadow you already know.")
    place(lv, "examine", P["nestloop"][0] + 0.8, P["nestloop"][1],
          id="woods_nest_return", title="RETURN CUT",
          text="A newer path cuts back toward the brook — the nest spur is no longer a one-way crawl.")
    place(lv, "hidden", 13.5, 12.5, glimmer=18, was=(13.0, 43.6))
    place(lv, "hidden", P["fern"][0] - 1.2, P["fern"][1] + 0.8, glimmer=16, was=(16.0, 40.0))
    place(lv, "health", P["watch"][0] + 1.5, P["watch"][1] - 0.8, was=(22.0, 30.0))
    woods_creatures_and_secrets(lv, nooks)
    woods_main_gates(lv)
    # After all objects exist: add path-verge lanterns that don't seal secrets.
    _place_woods_lanterns(lv, lv.path_edge())
    lv.write("world.tmj", "tilesets/woods.png")
    return ts

# tiles that later get creatures / moonflowers / secrets / quest props (no props there)
WOODS_RESERVED = ((43.5, 8.5), (44, 12.5), (47.5, 20.5), (13, 19), (40, 12.5), (28, 12.5),
                  (24.5, 7.5), (26.5, 8), (29.5, 8.2), (26.5, 11.5), (29.5, 11.5), (27, 13.5),
                  (5.5, 21.5), (6.1, 21.2), (4.9, 22.5), (4.5, 49), (6.1, 48.6), (15.5, 36),
                  (3.5, 30.5), (13.5, 12.5), (37.5, 26), (14, 38), (13, 17), (14.5, 18.5),
                  (6.0, 42.0), (32.5, 5.5),
                  # expansion clearings / new examines
                  (58, 9), (64, 18), (60, 28), (56, 36), (14, 44),
                  (58.5, 10.8), (63.2, 19.5), (60.6, 28), (57, 35.2), (14.8, 44),
                  (58.8, 28.8), (65.5, 17.2))

# keep props off the main-route gates (x0, y0, x1, y1 tiles, end exclusive)
GATE_CLEAR = ((35, 10, 40, 15), (49, 24, 53, 31), (39, 48, 44, 52))

def woods_main_gates(lv):
    """Three friends to get through the Woods (brief-woods-befriend-gates):
    the pond fragment lies in a dark grotto (glowmoth LIGHT), the east grove
    fragment behind brambles (vine fox SCENT, sweetroot from the stump), and a
    fallen boulder fills the south road (stone turtle PUSH). Any order."""
    lv.goal = dict(fragments=2)
    lv.obj("abilitygate", 36 * T, 11 * T, 3 * T, 2 * T, kind="grotto", gate="woods_grotto",
           ability="light", creature="glowmoth")
    lv.obj("abilitygate", 50 * T, 26 * T, 2 * T, 2 * T, kind="bramble", gate="woods_brambles",
           ability="scent", creature="vinefox", needs="sweetroot")
    lv.obj("abilitygate", 40 * T, 50 * T, 3 * T, 2 * T, kind="boulder", gate="woods_boulder",
           ability="push", creature="stoneturtle")

def woods_creatures_and_secrets(lv, nooks):
    """M2: creatures (journal + companions) and ability-gated optional secrets
    (the main-route gates are in woods_main_gates)."""
    # Centre of the NE pond (water tiles ~41–45, 7–9). Flying — no floor needed.
    creature(lv, "glowmoth", 43.5, 8.5, 1.0, was=(28.5, 21.5))
    creature(lv, "stoneturtle", 44, 12.5, 0.6, netted=True, was=(24.5, 24.5))   # netted on the pond bank
    creature(lv, "vinefox", 47.5, 20.5, 1.2, was=(18.5, 40.5))     # east grove
    creature(lv, "puffcap", 13, 19, 0.0, was=(11.5, 21.5))         # mossy hollow off the west loop
    # Centre of the 2-row east pocket (creature sprite is 1 tile; (15,26)
    # spilled onto the sealed row above and failed validate). gated=True so
    # validate allows it behind the PUSH boulder (same as hushdeer).
    creature(lv, "brookling", 15.5, 26.5, 0.6, gated=True, was=(24.5, 21.5))
    # Night-only inside the glade (vine fox SCENT opens the thorns above).
    creature(lv, "hushdeer", 28, 12.5, 0.8, gated=True, was=(30.0, 33.0))
    place(lv, "pebble", 42.5, 11.5, was=(24.5, 26.5))               # pond shallows, south bank
    # SCENT (vine fox): bramble plugging the gap into the moonflower glade
    lv.obj("hiddenpath", 27 * T, 9 * T, 2 * T, 2 * T, pid=f"{29 * T}_{30 * T}")
    for (fx, fy) in ((24.5, 7.5), (26.5, 8), (29.5, 8.2), (26.5, 11.5), (29.5, 11.5), (27, 13.5)):
        place(lv, "moonflower", fx, fy)
    # hollow stump + sweetroot on grass just south of it (clearer than on-stump art)
    lv.obj("stump", 12 * T, 16 * T, 2 * T, 2 * T)
    place(lv, "sweetroot", 14.5, 18.5)
    # PUSH: 3×2 road boulders (exit stone). Open in place — pushX unused.
    (b1x, b1y), (b2x, b2y) = nooks
    boulder(lv, b1x, b1y, 0, 0)
    # Stash/glyph sit inside the 2-row nook east of the boulder (not south of it).
    # Pocket is 3 tiles (bx+3..bx+5); centre at bx+4.
    place(lv, "stash", b1x + 4.0, b1y + 1.0, glimmer=25, was=(26.5, 6.5))
    boulder(lv, b2x, b2y, 0, 0)
    place(lv, "glyph", b2x + 4.0, b2y + 1.0, glyph="woods_nook", was=(30.5, 41.5))
    # LIGHT: dark zones with a glyph inside, off the main trails
    darkzone(lv, 40, 11, 41, 13, was=(27, 26))                     # pond's west bank, under the reeds
    place(lv, "glyph", 40.5, 11.5, glyph="woods_pond", was=(28.5, 27.5))
    darkzone(lv, 2, 29, 4, 31, was=(11, 49))                       # west loop pocket
    place(lv, "glyph", 3.5, 30.5, glyph="woods_gate", was=(12.5, 50.5))
    # DIG: buried glimmer, invisible until the brookling is along
    place(lv, "hidden", 15.5, 36.0, glimmer=15, was=(12.5, 12.5))
    place(lv, "hidden", 37.5, 26.0, glimmer=20, was=(14.5, 46.5))

def _place_woods_lanterns(lv, edge, want=8):
    """Colliding lanterns can seal ability-gate mouths if scattered freely.
    Try verge cells and keep a stamp only when validate() still passes."""
    cells = lv.cells_of(edge)
    lv.rng.shuffle(cells)
    kept = 0
    for x, y in cells:
        if kept >= want: break
        if not lv.prop_fits("lantern", x, y): continue
        lv.stamp("lantern", x, y)
        try:
            lv.validate()
            kept += 1
        except SystemExit:
            w, h, grid = lv.ts.props["lantern"]
            for j in range(h):
                for i in range(w):
                    if grid[j][i] >= 0:
                        lv.props[y + j, x + i] = -1
            lv.instances = [(n, ix, iy) for n, ix, iy in lv.instances
                            if not (n == "lantern" and ix == x and iy == y)]
    return kept

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
    """3x2 road boulder (same art as the south exit) at tile (tx, ty).
    Opens in place; pushX/pushY kept for Tiled compat (unused by runtime)."""
    extra = {"pid": f"{was[0] * T}_{was[1] * T}"} if was else {}
    lv.obj("boulder", tx * T, ty * T, 3 * T, 2 * T, pushX=int(push_x), pushY=int(push_y), **extra)

def darkzone(lv, x0, y0, x1, y1, was=None):
    """darkness over tiles x0..x1, y0..y1 (inclusive), with a half-tile fringe"""
    extra = {"pid": f"{was[0] * T - T // 2}_{was[1] * T - T // 2}"} if was else {}
    lv.obj("darkzone", x0 * T - T // 2, y0 * T - T // 2, (x1 - x0 + 2) * T, (y1 - y0 + 2) * T, **extra)

# =============================================================== MAP 2: city
def map2():
    """City: expand the #26 district graph — same spine, new east canal loop.

                         [N edge → Woods]
                               │
       NOODLE ─ MARKET ROW ─ ARRIVAL PLAZA ══ boulevard ══ LANTERN GATE ─► Town (E edge)
                  │              │                 (tea house)   │
       ECHO DISTRICT ───── ARCHIVE SQUARE ──────────────── EAST LOT ── DOCKS (NEW)
          │                  │ (archive_library)               │         │
       WEST YARD          GREENHOUSE GARDEN                PATROL ── CANAL QUAY (NEW)
          │  (frag)          │                                 │
          └── yard alley ── SENTINEL PLAZA ───────────────────┘
                               │
                        VOSS ALCOVE · SOUTH GATE ─► Ruins (S edge)

    Original districts / NPCs / exits keep their tiles; the map grows east so
    docks + canal quay hang off the east lot without relocating the Archive."""
    ts = Tileset("city")
    # Was 52×44; +14 east for docks / canal. Story P coords unchanged.
    lv = Level(ts, 66, 44, seed=22)
    lv.rings_min = 3
    P = dict(spawn=(26.5, 4.5), echo7=(6, 16.5), h1=(14, 7.5), d1=(5.5, 31), arch=(26.5, 18.5),
             h2=(20.5, 20.5), d2=(39.5, 18), sentinel=(26.5, 32), h3=(45.5, 31.5), voss=(19.5, 38.5),
             gate=(26.5, 41.5), town=(63.5, 7.5), yard=(4.5, 25), lot=(46, 19), se=(45.5, 26.5),
             cache=(5.5, 11), garden=(25, 28),
             # NEW east expansion
             docks=(58, 16), canal=(58, 28), quay=(54, 34))
    road = np.zeros((lv.H, lv.W), bool)
    rect_carve(road, 34, 6, 66, 9)             # boulevard: plaza → Lantern Gate → Town (extended)
    rect_carve(road, 45, 9, 48, 15)            # Lantern Gate street down to the east lot
    rect_carve(road, 35, 17, 45, 19)           # east street: east lot → Archive Square
    rect_carve(road, 24, 36, 29, 44)           # gate road → Ruins (matches exit half=2)
    rect_carve(road, 48, 15, 60, 17)           # NEW: lot → docks road
    rect_carve(road, 56, 17, 59, 30)           # NEW: docks → canal
    rect_carve(road, 48, 30, 59, 33)           # NEW: canal → patrol / quay
    floor = np.zeros_like(road)
    rect_carve(floor, 19, 2, 34, 10)           # ARRIVAL PLAZA
    rect_carve(floor, 24, 0, 29, 3)            # north road → Woods edge
    rect_carve(floor, 3, 5, 19, 10)            # MARKET ROW (stalls both sides)
    rect_carve(floor, 4, 9, 9, 14)             # market → Echo street
    rect_carve(floor, 2, 13, 11, 20)           # ECHO DISTRICT
    rect_carve(floor, 10, 15, 19, 19)          # Echo → square street
    rect_carve(floor, 23, 9, 30, 13)           # plaza → square avenue (the dome is in view)
    rect_carve(floor, 18, 12, 36, 22)          # ARCHIVE SQUARE
    rect_carve(floor, 34, 4, 66, 11)           # boulevard sidewalks (extended)
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
    # SW west spur → Canal Works (world6)
    rect_carve(road, 0, 29, 8, 32)
    rect_carve(floor, 0, 27, 9, 34)
    # NEW east districts
    rect_carve(floor, 50, 12, 64, 20)          # DOCKS / freight apron
    rect_carve(floor, 54, 20, 64, 32)          # CANAL QUAY
    rect_carve(floor, 48, 28, 56, 36)          # quay → sentinel fringe
    rect_carve(floor, 58, 6, 66, 12)           # town approach walks
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
    for x in range(36, 64):                    # lane arrows east to the Lantern Gate / Town
        if road[7, x]: lv.ground[7, x] = 7
    lv.keepout = road.copy()
    lv.keepout_hard = np.zeros_like(wall)
    for k, (x, y) in P.items():
        disk_carve(lv.keepout, x, y, 2.8); disk_carve(lv.keepout_hard, x, y, 1.6)
    for r in ((19, 2, 34, 10), (18, 12, 36, 22), (14, 29, 38, 36), (21, 40, 32, 44), (23, 9, 30, 13),
              (3, 6, 19, 9), (10, 16, 19, 18), (36, 31, 48, 33), (5, 29, 6, 33), (5, 32, 15, 33),
              (50, 14, 62, 18), (54, 22, 62, 30), (48, 30, 56, 34),
              (0, 27, 9, 34)):                 # SW west spur → Canal Works
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
                       ("traffic_light", 34, 5), ("traffic_light", 37, 16), ("bus_stop", 36, 10),
                       # east docks / canal (new)
                       ("holo_billboard", 60, 12), ("neon_sign", 55, 14), ("car_blue_v", 61, 18),
                       ("bus_stop", 56, 26), ("traffic_light", 52, 30), ("helipad", 60, 24)):
        landmark(lv, name, x, y)
    # corner lamps: every district is lit at night (#35 light pools)
    for (x, y) in ((20, 2), (32, 2), (19, 9), (33, 9), (18, 12), (18, 21), (35, 21), (14, 29), (37, 29),
                   (14, 35), (37, 35), (3, 5), (18, 5), (18, 9), (2, 13), (10, 19), (2, 21), (10, 28),
                   (41, 14), (49, 22), (44, 25), (47, 29), (16, 36), (23, 40), (35, 10), (43, 10),
                   (52, 14), (62, 14), (54, 22), (62, 28), (50, 32), (56, 32)):
        landmark(lv, "street_lamp", x, y)
    # Street furniture follows the roads; plazas get small authored sets.
    sidewalk = lv.floor & ~road
    curb = sidewalk & lv.dilate(road, 1)
    near_wall = sidewalk & lv.fringe(wall)
    lv.line_props("street_lamp", [(35, 4), (63, 4)], step=4)
    lv.line_props("street_lamp", [(35, 10), (42, 10)], step=3)
    lv.line_props("street_lamp", [(19, 2), (19, 9)], step=3)
    lv.line_props("street_lamp", [(33, 2), (33, 9)], step=3)
    lv.line_props("street_lamp", [(18, 12), (18, 21)], step=3)
    lv.line_props("street_lamp", [(14, 29), (14, 30)], step=1)
    lv.line_props("street_lamp", [(37, 29), (37, 30)], step=1)
    lv.line_props("street_lamp", [(23, 36), (23, 43)], step=3)
    lv.line_props("street_lamp", [(29, 36), (29, 43)], step=3)
    lv.line_mix(["bollard", "planter_small"], [(36, 5), (50, 5)], step=3)
    lv.line_mix(["bollard", "planter_small"], [(36, 9), (41, 9)], step=3)
    lv.line_mix(["bench", "planter_small"], [(20, 13), (20, 20)], step=3)
    lv.line_mix(["bench", "planter_small"], [(32, 13), (32, 20)], step=3)
    lv.line_mix(["bollard", "planter_small"], [(24, 37), (24, 42)], step=3)
    lv.line_mix(["bollard", "planter_small"], [(28, 37), (28, 42)], step=3)
    lv.scatter_on(["trash_bin", "hydrant"], 6, near_wall, min_dist=5.0)
    lv.scatter_on(["vending_machine", "kiosk"], 3, near_wall, min_dist=7.0)
    lv.scatter_on(["planter_tree"], 4, lawn, min_dist=4.0)
    lv.vignette(*P["arch"], [
        ("bench", -1, 1), ("planter_small", 1, 1), ("bench", 0, 2), ("planter_tree", 2, 0),
    ])
    lv.vignette(*P["voss"], [
        ("bench", 1, 0), ("trash_bin", -1, 1), ("bollard", 2, 1),
    ])
    lv.vignette(*P["spawn"], [
        ("planter_small", 2, 1), ("bench", -2, 1), ("bollard", 1, 2),
    ])
    lv.vignette(*P["echo7"], [
        ("bench", 1, -1), ("planter_small", -1, 1), ("planter_tree", 2, 1),
    ])
    lv.vignette(*P["town"], [
        ("planter_small", -2, 0), ("bench", -1, 1), ("bollard", -3, 1),
    ])
    interior = np.zeros_like(wall)
    interior[1:-1, 1:-1] = (wall[1:-1, 1:-1] & wall[:-2, 1:-1] & wall[2:, 1:-1] & wall[1:-1, :-2] & wall[1:-1, 2:])
    lv.scatter_on(["rooftop_ac", "solar_panel"], 14, interior, need_floor=False, min_dist=3.5)
    lv.scatter_on(["rooftop_vent"], 8, interior, need_floor=False, min_dist=4.0)
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
    wx = 30  # SW west mouth → Canal Works
    open_map_edge(lv, "west", wx, half=2)
    # Re-blob mouths so border building tiles / bad samples don't seal the road.
    retile_city_edge(lv, ts, road, lawn, "north", gx, half=2, plaza=plaza, extend_road=False)
    retile_city_edge(lv, ts, road, lawn, "south", sx, half=2, plaza=plaza)
    retile_city_edge(lv, ts, road, lawn, "east", ey, half=2, plaza=plaza)
    retile_city_edge(lv, ts, road, lawn, "west", wx, half=2, plaza=plaza)
    place_mapexit(lv, "north", gx, dest="woods", entry="south", half=2)
    place_mapexit(lv, "south", sx, dest="ruins", entry="north", half=2, unlock=True,
                  lockedTitle="SOUTH ROAD",
                  lockedBody="The Archivist opens this road after the Sentinel falls.")
    place_mapexit(lv, "east", ey, dest="town", entry="west", half=2)
    place_mapexit(lv, "west", wx, dest="works", entry="east", half=2)
    place_entry(lv, "north", *P["spawn"])
    place_entry(lv, "south", P["gate"][0], P["gate"][1] - 0.5)
    place_entry(lv, "east", *P["town"])
    place_entry(lv, "west", 3.5, float(wx))
    place(lv, "checkpoint", *P["spawn"], label="Arrival Plaza")
    place(lv, "examine", P["spawn"][0] + 2.0, P["spawn"][1] + 1.2,
          id="city_arrival_post", title="PLAZA POST",
          text="WEST: market and Echo-7 — south-west yard walks out to the Canal Works. SOUTH: the Archive Square. "
               "EAST: Lantern Gate and the road to Town. North walks back to the Woods.")
    place(lv, "examine", 35.0, 19.0,
          id="city_archive_plaque", title="ARCHIVE PLAQUE",
          text="Sealed by the Archivist. First memory drafts keep here — not the Core itself.",
          clue="city_archive_hint")
    # Stay inside the Voss alcove floor (x 16..23) and outside talk radius.
    place(lv, "examine", P["voss"][0] + 2.5, P["voss"][1] - 1.5,
          id="city_uec_terminal", title="UEC FIELD TERMINAL",
          text="Override accepted. Field orders scroll past.",
          clue="uec_orders", item="uec_override", consume=True, flag="read_uec_orders")
    place(lv, "examine", P["yard"][0] + 1.0, P["yard"][1] + 2.5,
          id="city_yard_memo", title="DROPPED SLATE",
          text="A scout's note: \"Archive walls hum. Stay clear.\"",
          clue="city_yard_memo")
    place(lv, "stash", P["yard"][0] - 1.5, P["yard"][1] - 1.5, glimmer=18, was=(4.0, 19.5))
    place(lv, "examine", P["town"][0] - 4.0, P["town"][1] + 1.2,
          id="city_lantern_sign", title="LANTERN ROAD",
          text="Walk east off the map to Lantern Town. South of the boulevard the docks and canal quay "
               "loop back to the east lot and Sentinel plaza.")
    place(lv, "examine", 24.0, 15.5,
          id="city_branch_sign", title="CROSS STREET",
          text="Archive Square. Every street in the old city ends up here.")
    place_dronespawn(lv, 44.5, 17.5, kind="scout",
                     nest="city_east_nest", max=1, interval=7)
    place_dronespawn(lv, 47.5, 19.5, kind="swarm",
                     nest="city_east_nest", max=1, interval=8)
    place(lv, "examine", P["lot"][0] + 0.5, P["lot"][1] - 2.0,
          id="city_east_slate", title="EAST LOT SLATE",
          text="Nest roster: scout and swarm pads hold the east lot. Town wants them gone.",
          clue="quest_city_east_slate")
    place_dronespawn(lv, 46.0, 27.0, kind="sniper", nest="city_se_patrol", max=1, interval=10)
    place(lv, "examine", P["se"][0] + 1.0, P["se"][1] + 2.0,
          id="city_se_slate", title="DEAD PATROL PAD",
          text="Last ping: the sniper pad in the south-east patrol alley. Someone from Town is asking.",
          quest="city_se_patrol")
    place(lv, "examine", *P["cache"],
          id="city_west_cache", title="MARKED CRATE",
          text="Trader chalk: 'For Mira's board.' Heavy with colony salvage.",
          quest="city_west_cache")
    place(lv, "stash", P["cache"][0] + 1.5, P["cache"][1] + 0.5, glimmer=14, was=(5.5, 10.5))
    place(lv, "examine", P["docks"][0] + 0.5, P["docks"][1] + 1.5,
          id="city_docks_board", title="FREIGHT BOARD",
          text="Manifests for the canal quay. South along the water returns to the patrol alley; west is the east lot.")
    place(lv, "examine", P["canal"][0] - 1.0, P["canal"][1],
          id="city_canal_rail", title="CANAL RAIL",
          text="Black water under grate. The quay road west rejoins Sentinel plaza.")
    place(lv, "examine", 4.5, 30.0,
          id="city_works_gate", title="CANAL WORKS ROAD",
          text="West off the map: dry docks, salvage cranes, and the old freight canal. Quiet if the City isn't.")
    place(lv, "stash", P["docks"][0] + 1.5, P["docks"][1] + 0.5, glimmer=12, was=(48.0, 16.0))
    place(lv, "health", P["quay"][0] + 1.0, P["quay"][1] - 0.5, was=(40.0, 36.0))
    lv.vignette(*P["docks"], [
        ("bench", 1, 1), ("bollard", -1, 0), ("planter_small", 2, 0),
    ])
    lv.vignette(*P["canal"], [
        ("bollard", 0, 1), ("trash_bin", 1, -1), ("planter_small", -1, 1),
    ])
    for name, x, y in (("street_lamp", 2, 28), ("bollard", 2, 31), ("traffic_light", 5, 28)):
        landmark(lv, name, x, y)
    lv.write("world2.tmj", "tilesets/city.png")
    return ts

CITY_RESERVED = ((4.5, 25), (3.5, 27), (7.5, 25), (5.5, 27.5), (3, 23.5), (5.5, 11), (7, 11.5),
                 (46, 19), (45, 18), (47.5, 20.5), (46.5, 17), (45.5, 26.5), (46.5, 28.5),
                 (46, 5), (46, 10), (35, 19), (24, 15.5), (21.7, 39.5), (28.5, 5.7), (21.5, 14),
                 # dronespawn pads (east lot + SE patrol)
                 (44.5, 17.5), (47.5, 19.5), (46.0, 27.0),
                 # east expansion
                 (58, 16), (58, 28), (54, 34), (56, 15), (57, 28), (55, 33.5),
                 # SW west spur / Canal Works mouth
                 (3.5, 30), (4.5, 30), (2.5, 30))

# =============================================================== MAP 5: Lantern Town
def map5():
    """Peaceful colony hub — expand with a south quay loop; Mira / west exit stay."""
    ts = Tileset("city")
    # Was 36×28; +8 east / +4 south for quay + reed walk around the pond.
    lv = Level(ts, 44, 32, seed=55)
    lv.rings_min = 2
    P = dict(spawn=(16, 5.5), mira=(10, 13.5), h1=(21.5, 12.5), portal=(16, 23), stash=(32.5, 21.5),
             pond=(29, 14),
             quay=(36, 22), reeds=(38, 12))
    road = np.zeros((lv.H, lv.W), bool)
    rect_carve(road, 9, 6, 23, 8)              # north lane
    rect_carve(road, 9, 18, 23, 20)            # south lane
    rect_carve(road, 9, 6, 11, 20)             # west lane
    rect_carve(road, 21, 6, 23, 20)            # east lane
    rect_carve(road, 0, 12, 9, 15)             # west road → City
    rect_carve(road, 23, 18, 36, 20)           # NEW: south lane → quay
    rect_carve(road, 34, 10, 36, 22)           # NEW: reeds ↔ quay
    floor = np.zeros_like(road)
    rect_carve(floor, 12, 2, 21, 6)            # Lantern Gate court (spawn)
    rect_carve(floor, 8, 5, 25, 9)             # north lane + walks
    rect_carve(floor, 8, 17, 25, 21)           # south lane + walks
    rect_carve(floor, 8, 5, 12, 21)            # west lane + walks
    rect_carve(floor, 20, 5, 25, 21)           # east lane + walks
    rect_carve(floor, 0, 11, 9, 16)            # west road
    rect_carve(floor, 12, 20, 21, 26)          # south court (Market South)
    rect_carve(floor, 24, 6, 34, 23)           # east green around Lantern Pond
    rect_carve(floor, 32, 8, 42, 26)           # NEW: reeds + quay green
    rect_carve(floor, 20, 24, 38, 30)          # NEW: south quay court
    LOTS = [("tea_house", 3, 6, (2, 6, 8, 11)), ("greenhouse", 3, 17, (2, 17, 8, 22)),
            ("noodle_shop", 27, 2, (26, 2, 33, 5))]
    for _, _, _, r in LOTS:
        rect_carve(floor, *r)
    lv.floor = floor | road
    wall = clean_walls(~lv.floor)
    lv.floor = ~wall
    road &= lv.floor
    road = clean_walls(road, border=0) & road
    water = np.zeros_like(wall); rect_carve(water, 26, 10, 34, 18); water &= lv.floor
    lv.mist = [(28.0, 12.0), (30.0, 15.5), (32.5, 14.0)]          # Lantern Pond
    paving = lv.dilate(water, 1) & ~water & lv.floor
    sidewalk = ~road
    for y in range(lv.H):
        for x in range(lv.W):
            if wall[y, x]:
                lv.ground[y, x] = blob(ts, "sidewalk-building", wall, x, y, lv.rng)
            elif water[y, x]:
                lv.ground[y, x] = blob(ts, "plaza-water", water, x, y, lv.rng)
            elif paving[y, x]:
                lv.ground[y, x] = 13 if (x * 5 + y * 3) % 7 else 14
            else:
                lv.ground[y, x] = blob(ts, "road-sidewalk", sidewalk, x, y, lv.rng, exclude={4, 5, 6, 7, 8})
    lv.keepout = road | paving
    lv.keepout_hard = np.zeros_like(wall)
    for k, (x, y) in P.items():
        disk_carve(lv.keepout, x, y, 2.6); disk_carve(lv.keepout_hard, x, y, 1.5)
    rect_carve(lv.keepout, 8, 5, 25, 9); rect_carve(lv.keepout, 8, 17, 25, 21)
    rect_carve(lv.keepout, 9, 5, 11, 21); rect_carve(lv.keepout, 21, 5, 23, 21)
    rect_carve(lv.keepout, 32, 10, 40, 24)
    for name, tx, ty, (x0, y0, x1, y1) in LOTS:
        d = BUILDINGS.defs[name]
        for m in (lv.keepout, lv.keepout_hard):
            rect_carve(m, x0, y0, x1, y1 + 1)
            rect_carve(m, tx - 1, ty, tx + d["w"] // T + 1, ty + d["h"] // T + 1)
    for (fx, fy) in ((8.4, 14), (11.6, 13.9), (5, 13.5), (32.5, 21.5), (21.5, 12.5), (25, 9),
                     (36, 22), (38, 12)):
        disk_carve(lv.keepout, fx, fy, 1.4); disk_carve(lv.keepout_hard, fx, fy, 1.0)
    sidewalk = lv.floor & ~road & ~water
    curb = sidewalk & lv.dilate(road, 1) & ~paving
    near_wall = sidewalk & lv.fringe(wall)
    lv.line_props("street_lamp", [(12, 4), (20, 4)], step=4)
    lv.line_props("street_lamp", [(24, 9), (24, 21)], step=4)
    lv.line_props("street_lamp", [(33, 7), (33, 21)], step=4)
    lv.line_props("street_lamp", [(12, 21), (12, 25)], step=4)
    lv.line_props("street_lamp", [(20, 21), (20, 25)], step=4)
    lv.line_mix(["bollard", "planter_small"], [(13, 10), (13, 16)], step=3)
    lv.line_mix(["bench", "planter_small"], [(25, 10), (25, 18)], step=3)
    lv.scatter_on(["trash_bin", "vending_machine"], 3, near_wall, min_dist=5.0)
    lv.scatter_on(["planter_tree"], 3, curb | near_wall, min_dist=4.5)
    lv.vignette(*P["mira"], [
        ("bench", 1, 1), ("planter_small", -1, 1), ("planter_tree", 2, 0), ("bollard", -2, 0),
    ])
    lv.vignette(*P["portal"], [
        ("bollard", -1, 0), ("planter_small", 1, 0), ("bench", 0, 1),
    ])
    lv.vignette(*P["spawn"], [
        ("planter_small", 1, 1), ("bollard", -1, 1),
    ])
    interior = np.zeros_like(wall)
    interior[1:-1, 1:-1] = (wall[1:-1, 1:-1] & wall[:-2, 1:-1] & wall[2:, 1:-1] & wall[1:-1, :-2] & wall[1:-1, 2:])
    lv.scatter_on(["rooftop_ac", "solar_panel"], 6, interior, need_floor=False, min_dist=3.5)
    lv.scatter_on(["rooftop_vent"], 4, interior, need_floor=False, min_dist=4.0)
    for name, tx, ty, _ in LOTS:
        lv.building(name, tx, ty)
    place(lv, "spawn", *P["spawn"])
    place(lv, "npc", *P["mira"], name="mira", sprite="mira")
    place(lv, "health", *P["h1"], was=(17.5, 12.5))
    place(lv, "stash", *P["stash"], glimmer=15, was=(20.5, 16.5))
    # West road back to the City — walk off the map.
    wy = int(P["mira"][1])
    open_map_edge(lv, "west", wy, half=2)
    retile_city_edge(lv, ts, road, None, "west", wy, half=2)
    place_mapexit(lv, "west", wy, dest="city", entry="east", half=2)
    place_entry(lv, "west", 4.5, P["mira"][1])
    place_entry(lv, "north", *P["spawn"])
    place(lv, "checkpoint", *P["spawn"], label="Lantern Gate")
    # Stall / board on the west lane, past talk radius (72px), still walkable.
    place(lv, "examine", P["mira"][0], P["mira"][1] - 3.3,
          id="town_stall", title="MIRA'S STALL",
          text="Salvage and colony trinkets. Pay in glimmer.",
          shop=True)
    place(lv, "examine", P["mira"][0] - 3.5, P["mira"][1],
          id="town_quest_board", title="JOB BOARD",
          text="Chalk and string. Woods and city errands for travellers.",
          board=True)
    place(lv, "examine", 5.0, P["mira"][1],
          id="town_west_road", title="CITY ROAD",
          text="West off the map returns to the City's Lantern Gate.")
    place(lv, "examine", 25.0, 9.0,
          id="town_pond_sign", title="LANTERN POND",
          text="Colonists float paper lanterns here on the first night of each season. The promenade rings the pond; "
               "east past the reeds a quay loop returns to the south market court.")
    place(lv, "examine", P["quay"][0] - 0.5, P["quay"][1] + 1.0,
          id="town_quay_mark", title="QUAY BENCH",
          text="Ferry chalk: 'No boats tonight.' Walk north through the reeds to the pond, west to Mira's lanes.")
    place(lv, "examine", P["reeds"][0] - 0.8, P["reeds"][1],
          id="town_reed_walk", title="REED WALK",
          text="Soft ground. Lanterns hang from willow poles along the water.")
    lv.vignette(*P["quay"], [
        ("bench", 1, 0), ("planter_small", -1, 1), ("bollard", 0, 1),
    ])
    lv.write("world5.tmj", "tilesets/city.png")
    return ts

# =============================================================== MAP 3: cyberpunk ruins
def map3():
    """Ruins: expand the wing graph — same keyed SE choke, new east/north side loops.

    Original hub / key / Memory 5 / portal / storygate tiles stay put. Grow the
    canvas east so a vent stack and crane yard hang off the key wing without
    opening a walk-around past the sealed gate."""
    ts = Tileset("cyberpunk")
    # Was 46×46; +12 east for vent/crane loops. Gate choke coords unchanged.
    lv = Level(ts, 58, 46, seed=33)
    lv.rings_min = 3
    P = dict(spawn=(5.5, 5.5), h1=(6, 13), d1=(16, 6), d2=(18, 12), h2=(17, 18), d3=(26, 5),
             h3=(31, 7), key=(39.5, 6.5), d4=(33, 19), h4=(35, 27), gate=(37.5, 33.5),
             d5=(23, 29), d6=(12, 36), m5a=(8, 40), m5b=(4.5, 42.5), portal=(39.5, 39.5),
             west=(5, 25),
             # NEW — stay north of the SE choke so the gate cannot be skipped
             vent=(50, 8), crane=(52, 18), service=(48, 24))
    # No d5→portal shortcut: SE approach must pass the keyed gate after h4.
    edges = [("spawn", "d1"), ("spawn", "h1"), ("d1", "d2"), ("d2", "h2"), ("h1", "h2"), ("d1", "d3"),
             ("d3", "h3"), ("h3", "key"), ("h3", "d4"), ("h2", "d4"), ("d4", "h4"),
             ("h4", "gate"), ("gate", "portal"), ("h2", "d5"), ("d5", "d6"),
             ("d6", "m5a"), ("m5a", "m5b"),
             # #26: a west gallery (landing → shrine road) and a south link
             # (shrine road → gate approach) close two more rings, so the
             # central clearing is no longer the only way between wings
             ("h1", "west"), ("west", "d6"), ("d5", "h4"),
             # expansion: key wing → vent → crane → service → d4 (north of choke)
             ("key", "vent"), ("vent", "crane"), ("crane", "service"), ("service", "d4")]
    for a, b in edges: seg_carve(lv.floor, P[a], P[b], 1.9)
    for k, (x, y) in P.items():
        # Gate is a choke, not a plaza — otherwise players walk around LOCKED.
        if k == "gate":
            r = 1.8
        elif k in ("spawn", "portal"):
            r = 4.2
        elif k in ("key", "m5b"):
            r = 3.6
        elif k in ("vent", "crane", "service"):
            r = 3.2
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
    seg_carve(lv.keepout, P["spawn"], (P["spawn"][0], 0.0), 2.6)   # north road to the City stays clear
    for k, (x, y) in P.items():
        disk_carve(lv.keepout, x, y, 2.8); disk_carve(lv.keepout_hard, x, y, 1.6)
    # Scenery: wreckage hugs walls; path edges get spaced tech/lights; nodes get dumps.
    fringe = lv.fringe(wall)
    edge = lv.path_edge()
    heavy = ["rubble_large", "wrecked_car_v", "wrecked_car_h", "dumpster", "broken_pillar", "barricade"]
    clutter = ["rubble_small", "barrel_purple", "barrel_toxic", "crate", "drone_wreck", "vending_broken"]
    tech = ["terminal", "steam_vent", "loose_cables"]
    lv.scatter_on(heavy, 8, fringe, min_dist=4.5)
    lv.scatter_on(clutter, 6, fringe, min_dist=3.5)
    lv.scatter_on(tech, 5, edge, min_dist=4.0)
    lv.scatter_on(["steam_vent"], 4, edge, min_dist=5.0)
    lv.scatter_on(["neon_streetlight"], 5, edge, min_dist=5.5)
    lv.vignette(*P["spawn"], [
        ("barricade", 1, 1), ("rubble_small", -1, 2), ("crate", 2, 0),
    ])
    lv.vignette(*P["h2"], [
        ("barrel_purple", 0, 1), ("crate", 1, -1), ("rubble_small", -1, 0), ("barrel_toxic", 1, 1),
    ])
    # Core travel gate is a light (crystal + pool) from PortalComponent —
    # keep the court clear of clutter.
    lv.vignette(*P["portal"], [
        ("drone_wreck", 2, 0), ("barrel_toxic", -2, 1), ("rubble_small", 0, 3),
    ])
    lv.vignette(*P["key"], [
        ("broken_pillar", -1, 1), ("loose_cables", 1, 0), ("terminal", 0, -1),
    ])
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
    place_dronespawn(lv, P["key"][0] - 1.4, P["key"][1] + 1.0, kind="shield", max=2, interval=8)
    # SE keyed gate — spans the full 3-tile choke (cannot walk around).
    lv.obj("storygate", 36 * T, 32 * T, 3 * T, 3 * T, flag="ruins_gate_open")
    place(lv, "examine", 37.5, 31.6,
          id="ruins_se_gate", title="SEALED GATE",
          text="Lattice lock. The Aetherian Keystone is in the north-east wing — bring it back and USE it here.",
          item="ruins_gate_key", consume=True, flag="ruins_gate_open",
          clue="ruins_gate_open")
    # Memory 5 deep SW path (optional)
    place(lv, "fragment", *P["m5b"])
    place_dronespawn(lv, P["m5a"][0] + 0.4, P["m5a"][1] - 0.2, kind="swarm", max=2, interval=7)
    place(lv, "stash", P["m5a"][0] - 0.8, P["m5a"][1] + 0.5, glimmer=22)
    # North road back to the City; Core still uses a portal (chamber gate).
    open_map_edge(lv, "north", int(P["spawn"][0]), half=2)
    place_mapexit(lv, "north", int(P["spawn"][0]), dest="city", entry="south", half=2)
    place_entry(lv, "north", *P["spawn"])
    place(lv, "portal", *P["portal"])
    place(lv, "checkpoint", *P["spawn"], label="Ruined Landing")
    place(lv, "examine", P["spawn"][0] + 1.5, P["spawn"][1] + 1.0,
          id="ruins_landing_mark", title="LANDING MARK",
          text="UEC paint over Aetherian stone: \"Wipe authorized.\" Someone scratched it out. North walks back to the City.",
          clue="ruins_landing")
    place(lv, "examine", P["h2"][0] - 1.0, P["h2"][1] + 0.8,
          id="ruins_clearing_ring", title="BROKEN RING",
          text="SE path to the Core is sealed. Go NORTH-EAST for the Aetherian Keystone, then return. "
               "The west gallery and the shrine road loop back here; the SW shrine is optional.",
          clue="ruins_ring")
    place(lv, "stash", P["d5"][0] - 1.5, P["d5"][1] + 1.0, glimmer=20)
    place(lv, "health", P["d5"][0] + 1.5, P["d5"][1] + 0.5)
    place(lv, "examine", P["d5"][0], P["d5"][1] - 1.2,
          id="ruins_dead_end", title="WAYMARKER",
          text="Offline UEC pad: \"Shrine sector SW — anomaly deep past the ruin. Optional.\"",
          clue="ruins_dead_end")
    place(lv, "examine", P["vent"][0] + 0.5, P["vent"][1] + 1.2,
          id="ruins_vent_mark", title="VENT STACK",
          text="Heat and ozone. The crane yard south loops back to the mid ruins — this does not bypass the SE gate.")
    place(lv, "examine", P["crane"][0] - 1.0, P["crane"][1],
          id="ruins_crane_cab", title="CRANE CAB",
          text="Boom frozen over a slag pit. Service catwalk west rejoins the hub roads.")
    place(lv, "stash", P["vent"][0] - 1.2, P["vent"][1] - 0.5, glimmer=18)
    place(lv, "health", P["service"][0] + 1.0, P["service"][1] + 0.5)
    lv.vignette(*P["vent"], [
        ("steam_vent", 1, 0), ("loose_cables", -1, 1), ("barrel_toxic", 0, 1),
    ])
    lv.vignette(*P["crane"], [
        ("wrecked_car_h", 1, 1), ("rubble_large", -1, 0), ("drone_wreck", 0, -1),
    ])
    lv.write("world3.tmj", "tilesets/cyberpunk.png")
    return ts

# =============================================================== MAP 4: Gaia Core
def map4():
    """Sacred chamber under the ruins — expand with side ambulatories, keep the dais readable."""
    ts = Tileset("core")
    # Was 30×36; grow east (+12) and a little south. Original spine tiles stay.
    # rings_min stays 0: Core is a chamber (void reads as border); loops are still
    # authored so players can leave the processional without a hallway feel.
    lv = Level(ts, 42, 40, seed=44)
    lv.rings_min = 0
    P = dict(
        spawn=(15, 4.5),
        h1=(15, 11),
        d1=(6.5, 17),
        d2=(23.5, 17),
        gaia=(15, 20),
        h2=(15, 24),
        d3=(23.5, 25),
        portal=(15, 30),
        # NEW side loops off the existing hall (east growth + west memorial alcove)
        memorial=(5, 22),
        ambulatory=(34, 18),
        annex=(34, 28),
    )
    edges = [
        ("spawn", "h1"), ("h1", "gaia"), ("gaia", "portal"),
        ("h1", "d1"), ("h1", "d2"), ("gaia", "h2"), ("gaia", "d3"),
        # expansion rings around the hall
        ("d1", "memorial"), ("memorial", "gaia"),
        ("d2", "ambulatory"), ("ambulatory", "annex"), ("annex", "d3"),
        ("ambulatory", "gaia"),
    ]
    for a, b in edges:
        seg_carve(lv.floor, P[a], P[b], 2.1)
    for k, (x, y) in P.items():
        if k in ("spawn", "portal", "gaia"):
            r = 4.5
        elif k in ("memorial", "ambulatory", "annex"):
            r = 3.4
        else:
            r = 3.2
        disk_carve(lv.floor, x, y, r)
    # Original processional hall (unchanged column)
    rect_carve(lv.floor, 12, 6, 17, 30)
    # Compact pillar masses inside the side loops (keep aisles open).
    for (x0, y0, x1, y1) in ((8, 19, 10, 21), (27, 18, 29, 21), (27, 25, 29, 27)):
        lv.floor[y0:y1, x0:x1] = False
    wall = clean_walls(~lv.floor)
    lv.floor = ~wall
    for (x0, y0, x1, y1) in ((8, 19, 10, 21), (27, 18, 29, 21), (27, 25, 29, 27)):
        lv.floor[y0:y1, x0:x1] = False
    wall = ~lv.floor
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
    # Scenery: processional frame along the hall; relics clustered at the dais.
    fringe = lv.fringe(wall)
    edge = lv.path_edge()
    dais_edge = lv.floor & lv.dilate(dais, 1) & ~dais
    solemn = ["orb_pylon", "orb_pylon_large", "energy_brazier", "broken_pillar"]
    soft = ["data_crystals", "gold_glyph_stone", "memory_pedestal", "root_bulb", "floor_ring_marker"]
    gear = ["core_terminal", "core_console", "lattice_panel"]
    lv.scatter_on(solemn, 6, fringe | edge, min_dist=4.0)
    lv.scatter_on(soft, 5, dais_edge, min_dist=3.5)
    lv.scatter_on(gear, 3, fringe, min_dist=5.0)
    lv.vignette(*P["gaia"], [
        ("floor_ring_marker", -1, 0), ("gold_glyph_stone", 1, 0),
        ("memory_pedestal", 0, 1), ("data_crystals", -1, 1),
    ])
    lv.vignette(*P["portal"], [
        ("energy_brazier", -1, 0), ("orb_pylon", 1, 0), ("energy_brazier", 0, 1),
    ])
    lv.vignette(*P["spawn"], [
        ("orb_pylon", 1, 1), ("lattice_panel", -1, 0),
    ])
    place(lv, "spawn", *P["spawn"])
    place(lv, "npc", *P["gaia"], name="gaia")
    place(lv, "health", *P["h1"])
    place(lv, "health", *P["h2"])
    place(lv, "drone", *P["d1"], startAngle=1.2, kind="sniper")
    place(lv, "drone", *P["d2"], startAngle=4.0, kind="swarm")
    place(lv, "drone", *P["d3"], startAngle=2.5, kind="shield")
    place(lv, "portal", *P["portal"])
    place(lv, "checkpoint", *P["spawn"], label="Core Threshold")
    place(lv, "examine", P["spawn"][0] + 1.5, P["spawn"][1] + 1.2,
          id="core_console", title="CORE CONSOLE",
          text="Activation waits on a living neural match. A remote wipe is already queued.",
          clue="core_console")
    place(lv, "examine", *P["memorial"],
          id="core_memorial", title="NAMELESS STELE",
          text="Names the forest took. The ambulatory east of the hall loops back to Gaia without leaving the Core.")
    place(lv, "examine", *P["ambulatory"],
          id="core_ambulatory", title="LATTICE WALK",
          text="Side aisle. South to the annex, west back to the living dais.")
    place(lv, "health", *P["annex"])
    lv.vignette(*P["memorial"], [
        ("gold_glyph_stone", 1, 0), ("memory_pedestal", 0, 1), ("data_crystals", -1, 0),
    ])
    lv.vignette(*P["ambulatory"], [
        ("orb_pylon", 0, 1), ("lattice_panel", 1, 0), ("energy_brazier", -1, 0),
    ])
    lv.write("world4.tmj", "tilesets/core.png")
    return ts

def retile_junkyard_edge(lv, ts, path, oil, metal, side, cx, half=2, margin=2):
    """Re-blob dirt-heap / dirt-metal around a punched junkyard edge."""
    W, H = lv.W, lv.H
    wall = ~lv.floor
    if side == "east":
        y0, y1 = max(0, cx - half), min(H, cx + half + 1)
        for x in range(W - 3, W):
            for y in range(y0, y1):
                if lv.floor[y, x]:
                    path[y, x] = True
        rx0, rx1 = max(0, W - 3 - margin - 1), W
        ry0, ry1 = max(0, cx - half - margin), min(H, cx + half + 1 + margin)
    elif side == "west":
        y0, y1 = max(0, cx - half), min(H, cx + half + 1)
        for x in range(0, 3):
            for y in range(y0, y1):
                if lv.floor[y, x]:
                    path[y, x] = True
        rx0, rx1 = 0, min(W, 3 + margin + 1)
        ry0, ry1 = max(0, cx - half - margin), min(H, cx + half + 1 + margin)
    else:
        return
    path &= lv.floor
    for y in range(ry0, ry1):
        for x in range(rx0, rx1):
            if wall[y, x]:
                lv.ground[y, x] = blob(ts, "dirt-heap", wall, x, y, lv.rng)
            elif oil is not None and oil[y, x]:
                lv.ground[y, x] = blob(ts, "dirt-oil", oil, x, y, lv.rng)
            elif metal is not None and metal[y, x]:
                lv.ground[y, x] = blob(ts, "dirt-metal", metal, x, y, lv.rng)
            elif path[y, x] or lv.floor[y, x]:
                # dirt base (non-overlay)
                empty = np.zeros_like(wall)
                lv.ground[y, x] = blob(ts, "dirt-heap", empty, x, y, lv.rng)

# =============================================================== MAP 6: Canal Works
def map6():
    """Canal Works — scrapyard west of the City's SW yard (junkyard tileset).

    East edge walks back to the City. Scrap-heap islands and oil pans make
    two walkable rings so the yard reads as a place, not a corridor stub."""
    ts = Tileset("junkyard")
    lv = Level(ts, 44, 34, seed=66)
    lv.rings_min = 2
    P = dict(spawn=(40.5, 16), basin=(22, 16), crane=(8, 22), salvage=(24, 26),
             north=(22, 6), westpad=(6, 10), h1=(30.5, 12.5), stash=(26.5, 29.5))
    path = np.zeros((lv.H, lv.W), bool)
    rect_carve(path, 36, 14, 44, 18)           # east road → City
    rect_carve(path, 14, 8, 34, 10)
    rect_carve(path, 14, 22, 34, 24)
    rect_carve(path, 14, 8, 16, 24)
    rect_carve(path, 32, 8, 34, 24)
    rect_carve(path, 4, 20, 16, 24)
    rect_carve(path, 20, 24, 28, 28)
    rect_carve(path, 4, 8, 8, 20)
    floor = np.zeros_like(path)
    rect_carve(floor, 34, 10, 44, 22)          # EAST GATE COURT
    rect_carve(floor, 12, 6, 36, 26)           # basin apron
    rect_carve(floor, 2, 16, 16, 30)           # CRANE YARD
    rect_carve(floor, 16, 24, 32, 32)          # SALVAGE LOT
    rect_carve(floor, 10, 2, 30, 10)           # NORTH WORKS
    rect_carve(floor, 2, 4, 12, 16)            # WEST PAD
    cores = ((18, 12, 30, 20), (4, 13, 12, 21))
    for x0, y0, x1, y1 in cores:
        floor[y0:y1, x0:x1] = False
        path[y0:y1, x0:x1] = False
        rect_carve(floor, x0 - 3, y0 - 3, x1 + 3, y0)
        rect_carve(floor, x0 - 3, y1, x1 + 3, y1 + 3)
        rect_carve(floor, x0 - 3, y0, x0, y1)
        rect_carve(floor, x1, y0, x1 + 3, y1)
    lv.floor = floor | path
    wall = clean_walls(~lv.floor)
    lv.floor = ~wall
    path &= lv.floor
    path = clean_walls(path, border=0) & path
    for x0, y0, x1, y1 in cores:
        lv.floor[y0:y1, x0:x1] = False
        path[y0:y1, x0:x1] = False
        for y in range(max(0, y0 - 3), min(lv.H, y1 + 3)):
            for x in range(max(0, x0 - 3), min(lv.W, x1 + 3)):
                if not (x0 <= x < x1 and y0 <= y < y1):
                    lv.floor[y, x] = True
    wall = ~lv.floor
    oil = np.zeros_like(wall)
    rect_carve(oil, 20, 14, 28, 18)
    rect_carve(oil, 8, 24, 12, 28)
    oil &= lv.floor & ~path
    metal = np.zeros_like(wall)
    rect_carve(metal, 34, 12, 42, 20)
    rect_carve(metal, 22, 24, 30, 30)
    metal &= lv.floor & ~path & ~oil
    for y in range(lv.H):
        for x in range(lv.W):
            if wall[y, x]:
                lv.ground[y, x] = blob(ts, "dirt-heap", wall, x, y, lv.rng)
            elif oil[y, x]:
                lv.ground[y, x] = blob(ts, "dirt-oil", oil, x, y, lv.rng)
            elif metal[y, x]:
                lv.ground[y, x] = blob(ts, "dirt-metal", metal, x, y, lv.rng)
            else:
                empty = np.zeros_like(wall)
                lv.ground[y, x] = blob(ts, "dirt-heap", empty, x, y, lv.rng)
    lv.keepout = path.copy()
    lv.keepout_hard = np.zeros_like(wall)
    for k, (x, y) in P.items():
        disk_carve(lv.keepout, x, y, 2.6); disk_carve(lv.keepout_hard, x, y, 1.5)
    for r in ((14, 8, 34, 10), (14, 22, 34, 24), (14, 8, 16, 24), (32, 8, 34, 24),
              (34, 10, 44, 22), (4, 20, 16, 24), (20, 24, 28, 28)):
        rect_carve(lv.keepout, *r)
    for (fx, fy) in ((40.5, 16), (22, 16), (8, 22), (24, 26), (22, 6), (6, 10), (30.5, 12.5), (26.5, 29.5)):
        disk_carve(lv.keepout, fx, fy, 1.4); disk_carve(lv.keepout_hard, fx, fy, 1.0)
    for name, x, y in (("crane_pad", 5, 22), ("salvage_board", 36, 11), ("yard_sign", 38, 19),
                       ("wreck_car_v", 28, 26), ("wreck_car_h", 14, 28),
                       ("skip_bin", 20, 26), ("arc_welder", 2, 8)):
        landmark(lv, name, x, y)
    for (x, y) in ((35, 11), (41, 11), (35, 20), (41, 20), (16, 7), (30, 7), (2, 22), (14, 26),
                   (22, 28), (16, 22), (30, 22)):
        landmark(lv, "yard_lamp", x, y)
    near_wall = (lv.floor & ~path) & lv.fringe(wall)
    lv.line_props("yard_lamp", [(37, 13), (37, 19)], step=3)
    lv.line_mix(["drum_sealed", "scrap_crate"], [(35, 15), (35, 17)], step=2)
    lv.scatter_on(["scrap_pile", "drum_leaking", "cable_tangle"], 6, near_wall, min_dist=4.0)
    lv.scatter_on(["broken_vendor", "weigh_console", "vent_stack"], 3, near_wall, min_dist=5.5)
    lv.vignette(*P["spawn"], [
        ("drum_sealed", -1, 0), ("scrap_crate", -2, 1), ("tire_wall", -1, 2),
    ])
    lv.vignette(*P["crane"], [
        ("scrap_pile", 1, 0), ("drone_hulk", 0, 1), ("drum_leaking", 1, 1),
    ])
    lv.vignette(*P["salvage"], [
        ("scrap_crate", 1, 0), ("cable_tangle", -1, 1), ("concrete_stub", 0, -1),
    ])
    interior = np.zeros_like(wall)
    interior[1:-1, 1:-1] = (wall[1:-1, 1:-1] & wall[:-2, 1:-1] & wall[2:, 1:-1] & wall[1:-1, :-2] & wall[1:-1, 2:])
    lv.scatter_on(["scrap_heap", "radar_dish"], 4, interior, need_floor=False, min_dist=4.0)
    place(lv, "spawn", *P["spawn"])
    place(lv, "health", *P["h1"])
    place(lv, "stash", *P["stash"], glimmer=16)
    place(lv, "drone", 16.0, 25.0, startAngle=0.8, kind="scout")
    place(lv, "drone", 20.0, 28.0, startAngle=2.4, kind="swarm")
    place_dronespawn(lv, 6.0, 26.0, kind="scout", max=1, interval=9)
    ey = int(P["spawn"][1])
    open_map_edge(lv, "east", ey, half=2)
    retile_junkyard_edge(lv, ts, path, oil, metal, "east", ey, half=2)
    place_mapexit(lv, "east", ey, dest="city", entry="west", half=2)
    place_entry(lv, "east", *P["spawn"])
    place(lv, "checkpoint", *P["spawn"], label="Works Gate")
    place(lv, "examine", P["spawn"][0] - 2.0, P["spawn"][1] + 2.0,
          id="works_gate_post", title="YARD GATE",
          text="Canal Works scrapyard. East walks back to the City. Heaps west hide the crane pad.")
    place(lv, "examine", 22.0, 10.5,
          id="works_basin_mark", title="DRY BASIN",
          text="Oil and rust where barge water used to sit. The heap ring still loops the pit.")
    place(lv, "examine", P["crane"][0] + 1.5, P["crane"][1],
          id="works_crane_slate", title="CRANE SLATE",
          text="UEC inventory: scrap alloy, dead drones, one sealed crate marked for Mira.")
    place(lv, "examine", P["salvage"][0], P["salvage"][1] - 1.2,
          id="works_salvage_bin", title="SALVAGE BIN",
          text="Colony scrap sorted by glimmer weight. Someone still works this lot after dark.")
    place(lv, "examine", P["north"][0] + 0.5, P["north"][1],
          id="works_north_rail", title="NORTH RAIL",
          text="Service track ends in a wall of scrap. Loop south through the basin.")
    lv.write("world6.tmj", "tilesets/junkyard.png")
    return ts

if __name__ == "__main__":
    os.makedirs(os.path.join(OUT, "tilesets"), exist_ok=True)
    for n in ("woods", "city", "cyberpunk", "core", "junkyard"):
        src = os.path.join(TSDIR, f"{n}.png")
        if os.path.isfile(src):
            shutil.copy(src, os.path.join(OUT, "tilesets", f"{n}.png"))
    map1(); map2(); map3(); map4(); map5(); map6()
