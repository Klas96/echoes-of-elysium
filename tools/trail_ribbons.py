#!/usr/bin/env python3
"""Diagonal / soft-turn dirt tracks for the woods trails (#64).

The blob autotile only turns on the square grid, so a diagonal route reads as
a staircase. These tiles are a walkable dirt band with grass verges. A name
like ``trail-N1-E0`` joins edge N/E/S/W at port 0/1/2 (8 / 16 / 24 px).
``hero-`` is the wider Woods → City strip. Tiles do not collide: the meadow
around the band is already walkable, and the band is only stamped on cells
that were already open path.

``apply_woods_ribbons`` rewrites those path cells in a ground array. The
woods route coordinates match ``map1`` in ``make_tiled_maps.py``.
"""
import math
import xml.etree.ElementTree as ET

# Tile centres / carve space, same numbers as map1().
WOODS_P = dict(
    spawn=(8, 9), gaia=(11, 8), h1=(17, 12), cabin=(19.5, 7.5), ridge=(31, 6),
    pond=(42, 10), f2=(37.41, 11.84), cross=(27, 20), d2=(34, 15.5), ebend=(36, 24),
    egrove=(48.5, 23), f4=(51, 29.5), whollow=(6, 23), f1=(5.5, 21.5), hollow=(13, 19),
    swbend=(9, 34), nest=(4.5, 39), asha=(24, 33), h2=(23, 26), brook=(32, 35),
    meadow=(42, 36), h3=(44.5, 30.5), exit=(42, 40), f3=(15, 36), d1=(16, 33.5),
)
WOODS_TRAILS = [
    ["spawn", "h1", "cross"],
    ["h1", "cabin"],
    ["cabin", "ridge", "pond"],
    ["pond", "d2", "cross"],
    ["pond", "egrove"],
    ["cross", "ebend", "egrove"],
    ["egrove", "meadow"],
    ["cross", "h2", "asha"],
    ["asha", "brook", "meadow"],
    ["ebend", "brook"],
    ["spawn", "whollow", "swbend", "asha"],
    ["whollow", "hollow"],
    ["swbend", "nest"],
    ["meadow", "exit"],
]
# Round dirt pads where trails meet, so a bend is not a 90° kink.
# Radius is in tiles. The south exit stays small so the hero road can reach the map edge.
PLAZA_R = dict(
    cross=2.6, meadow=1.9, pond=1.65, asha=1.55, spawn=1.45, egrove=1.45,
    cabin=1.35, whollow=1.35, brook=1.35, ridge=1.25, ebend=1.25, swbend=1.25,
    h1=1.15, h2=1.15, d2=1.15, hollow=1.15, nest=1.15, exit=0.85,
)
HERO_SEGMENTS = {("meadow", "exit")}

EDGES = ("N", "E", "S", "W")
PORTS = (0, 1, 2)
PORT_PX = (8, 16, 24)
ORDER = {e: i for i, e in enumerate(EDGES)}
OPPOSITE = {"N": "S", "S": "N", "E": "W", "W": "E"}
# Grass-path blob ids the carver stamps on the open trail (no collision).
PATH_IDS = set(range(8, 12)) | set(range(16, 63))


def tile_names(prefix):
    names = []
    for i, e0 in enumerate(EDGES):
        for e1 in EDGES[i + 1:]:
            for p0 in PORTS:
                for p1 in PORTS:
                    names.append(f"{prefix}{e0}{p0}-{e1}{p1}")
    return names


TRAIL_NAMES = tile_names("trail-")
HERO_NAMES = tile_names("hero-")
ALL_PATH_NAMES = TRAIL_NAMES + HERO_NAMES


def canonical(e0, p0, e1, p1, hero):
    a = (ORDER[e0], p0, e0, p0)
    b = (ORDER[e1], p1, e1, p1)
    if a > b:
        a, b = b, a
    return ("hero-" if hero else "trail-") + f"{a[2]}{a[3]}-{b[2]}{b[3]}"


def _clip(a, b, xmin, ymin, xmax, ymax):
    """Liang–Barsky. Returns the segment clipped to the closed rect, or None."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    u1, u2 = 0.0, 1.0
    for pi, qi in ((-dx, a[0] - xmin), (dx, xmax - a[0]), (-dy, a[1] - ymin), (dy, ymax - a[1])):
        if abs(pi) < 1e-12:
            if qi < -1e-9:
                return None
            continue
        t = qi / pi
        if pi < 0:
            if t > u2:
                return None
            if t > u1:
                u1 = t
        else:
            if t < u1:
                return None
            if t < u2:
                u2 = t
    if u1 > u2:
        return None
    return (a[0] + u1 * dx, a[1] + u1 * dy), (a[0] + u2 * dx, a[1] + u2 * dy)


def _edges_at(x, y, cx, cy, eps=1e-3):
    hits = []
    if abs(y - cy) <= eps:
        hits.append(("N", (x - cx) * 32.0))
    if abs(y - (cy + 1)) <= eps:
        hits.append(("S", (x - cx) * 32.0))
    if abs(x - cx) <= eps:
        hits.append(("W", (y - cy) * 32.0))
    if abs(x - (cx + 1)) <= eps:
        hits.append(("E", (y - cy) * 32.0))
    return hits


def _snap(pixel):
    pixel = min(max(pixel, 0.0), 31.999)
    return min(PORTS, key=lambda i: abs(pixel - PORT_PX[i]))


def _pick_edge(hits, used):
    if not hits:
        return None
    for h in hits:
        if h[0] not in used:
            return h
    return hits[0]


def segment_cells(a, b):
    """Cells the carve-space segment crosses, with snapped entry/exit ports.

    A cell owns its min edges and not its max edges, so a line that runs on a
    grid boundary is claimed once. Yields (cx, cy, e0, p0, e1, p1).
    """
    ax, ay = a
    bx, by = b
    minx, maxx = int(math.floor(min(ax, bx))), int(math.floor(max(ax, bx)))
    miny, maxy = int(math.floor(min(ay, by))), int(math.floor(max(ay, by)))
    for cy in range(miny, maxy + 1):
        for cx in range(minx, maxx + 1):
            # Max edges belong to the next cell. A segment that only rides the
            # max boundary is skipped here.
            hit = _clip(a, b, cx, cy, cx + 1, cy + 1)
            if hit is None:
                continue
            p, q = hit
            on_max = (p[0] >= cx + 1 - 1e-6 and q[0] >= cx + 1 - 1e-6) or (
                p[1] >= cy + 1 - 1e-6 and q[1] >= cy + 1 - 1e-6)
            interior = (cx + 1e-4 < p[0] < cx + 1 - 1e-4 or cx + 1e-4 < q[0] < cx + 1 - 1e-4
                        or cy + 1e-4 < p[1] < cy + 1 - 1e-4 or cy + 1e-4 < q[1] < cy + 1 - 1e-4)
            if on_max and not interior:
                continue
            if math.hypot(q[0] - p[0], q[1] - p[1]) < 0.22 and interior:
                continue
            hp, hq = _edges_at(*p, cx, cy), _edges_at(*q, cx, cy)
            e_p = _pick_edge(hp, {h[0] for h in hq})
            e_q = _pick_edge(hq, {e_p[0]} if e_p else set())
            if e_p is None and e_q is None:
                continue
            if e_p is None:
                e_p = (OPPOSITE[e_q[0]], e_q[1])
            elif e_q is None:
                e_q = (OPPOSITE[e_p[0]], e_p[1])
            if e_p[0] == e_q[0]:
                continue
            yield cx, cy, e_p[0], _snap(e_p[1]), e_q[0], _snap(e_q[1])


def _segments(hero_only=None):
    out = []
    for trail in WOODS_TRAILS:
        for n0, n1 in zip(trail, trail[1:]):
            hero = (n0, n1) in HERO_SEGMENTS or (n1, n0) in HERO_SEGMENTS
            if hero_only is True and not hero:
                continue
            if hero_only is False and hero:
                continue
            out.append((WOODS_P[n0], WOODS_P[n1], hero))
    # The south neck continues off the map toward the City.
    ex = WOODS_P["exit"]
    out.append((ex, (ex[0], 43.5), True))
    return out


def _plaza_nodes():
    nodes = []
    seen = set()
    for trail in WOODS_TRAILS:
        for name in trail:
            if name in seen:
                continue
            seen.add(name)
            nodes.append((WOODS_P[name], PLAZA_R.get(name, 1.2)))
    return nodes


def _plaza_mask(h, w, ground, ts):
    """Round pads on open ground, not only the chunky path mask, so a junction
    is a clearing instead of a square blob. Colliding cells stay put."""
    import numpy as np
    mask = np.zeros((h, w), bool)
    nodes = _plaza_nodes()
    for y in range(h):
        for x in range(w):
            if ts.collides(int(ground[y, x])):
                continue
            px, py = x + 0.5, y + 0.5
            for (nx, ny), r in nodes:
                if (px - nx) ** 2 + (py - ny) ** 2 <= r * r:
                    mask[y, x] = True
                    break
    return mask


def _in_inner_plaza(x, y):
    px, py = x + 0.5, y + 0.5
    for trail in WOODS_TRAILS:
        for name in trail:
            r = PLAZA_R.get(name, 1.2) * 0.62
            nx, ny = WOODS_P[name]
            if (px - nx) ** 2 + (py - ny) ** 2 <= r * r:
                return True
    return False


def _blob_pick(wang, key, x, y):
    cands = wang.get(key, [])
    if not cands:
        raise SystemExit(f"grass-path: no tile for {key} at {x},{y}")
    if len(cands) == 1:
        return cands[0][0]
    total = sum(p for _, p in cands)
    h = (x * 2246822519 ^ y * 3266489917) & 0xFFFFFFFF
    u = (h % 10000) / 10000.0 * total
    acc = 0.0
    for tid, p in cands:
        acc += p
        if u <= acc:
            return tid
    return cands[-1][0]


def _paint_plazas(ground, mask, wang):
    import numpy as np
    h, w = mask.shape

    def B(xx, yy):
        return bool(mask[min(max(yy, 0), h - 1), min(max(xx, 0), w - 1)])

    ys, xs = np.nonzero(mask)
    for y, x in zip(ys.tolist(), xs.tolist()):
        t, r, b, l = B(x, y - 1), B(x + 1, y), B(x, y + 1), B(x - 1, y)
        tr = t and r and B(x + 1, y - 1)
        br = b and r and B(x + 1, y + 1)
        bl = b and l and B(x - 1, y + 1)
        tl = t and l and B(x - 1, y - 1)
        key = tuple(int(v) for v in (t, tr, r, br, b, bl, l, tl))
        ground[y, x] = _blob_pick(wang, key, x, y)


def _grass_variant(x, y):
    h = (x * 73856093 ^ y * 19349663) & 0xFFFFFFFF
    if h % 5 == 0:
        return 1 + (h % 7)
    return 0


def apply_woods_ribbons(ground, ts):
    """Replace open path cells with grass, round plazas, and diagonal tracks.

    ``ground`` is a local-id array (H, W). ``ts`` provides ``.wang``, ``.tiles``
    and ``.collides(tid)``. No-op when the refined path tiles are not on the sheet.
    Returns a small stats dict.
    """
    import numpy as np
    index = {}
    for tid, t in ts.tiles.items():
        prop = t["props"].get("path")
        if prop:
            index[prop[1]] = tid
    if "trail-N1-S1" not in index or "hero-N1-S1" not in index:
        print("trail ribbons: sheet has no trail tiles, left the blob paths in place")
        return {"ribbons": 0, "plazas": 0, "shoulders": 0}
    wang = ts.wang["grass-path"]
    h, w = ground.shape
    path = np.zeros((h, w), bool)
    for y in range(h):
        for x in range(w):
            tid = int(ground[y, x])
            if tid in PATH_IDS and not ts.collides(tid):
                path[y, x] = True
    before = ground.copy()
    plaza = _plaza_mask(h, w, ground, ts)
    ribbons = {}
    for a, b, hero in _segments():
        for cx, cy, e0, p0, e1, p1 in segment_cells(a, b):
            if not (0 <= cx < w and 0 <= cy < h):
                continue
            if not path[cy, cx] or _in_inner_plaza(cx, cy):
                continue
            name = canonical(e0, p0, e1, p1, hero)
            tid = index.get(name)
            if tid is None or ts.collides(tid):
                continue
            # Hero wins over a thin track. Two thin names in one cell: keep the first.
            prev = ribbons.get((cx, cy))
            if prev is None or hero:
                ribbons[(cx, cy)] = tid
    shoulders = 0
    for y in range(h):
        for x in range(w):
            if not path[y, x] or plaza[y, x]:
                continue
            if (x, y) in ribbons:
                continue
            ground[y, x] = _grass_variant(x, y)
            shoulders += 1
    _paint_plazas(ground, plaza, wang)
    for (x, y), tid in ribbons.items():
        ground[y, x] = tid
    # Collision stays what it was: only previously open cells change, and only
    # to tiles that do not collide.
    for y in range(h):
        for x in range(w):
            new, old = int(ground[y, x]), int(before[y, x])
            if new == old:
                continue
            if ts.collides(old) or ts.collides(new):
                raise SystemExit(f"trail ribbon changed collision at {x},{y}: {old} -> {new}")
    stats = {"ribbons": len(ribbons), "plazas": int(plaza.sum()), "shoulders": shoulders,
             "path_cells": int(path.sum())}
    print(f"trail ribbons: {stats}")
    return stats


def load_tsx(path):
    """Minimal tileset view: ``.tiles``, ``.wang``, ``.collides`` — enough for apply."""
    root = ET.parse(path).getroot()
    tiles = {}
    for t in root.findall("tile"):
        tid = int(t.get("id"))
        props = {}
        for p in t.findall("properties/property"):
            props[p.get("name")] = (p.get("type", "string"), p.get("value"))
        rects = t.findall("objectgroup/object")
        tiles[tid] = {"props": props, "rects": rects, "prob": float(t.get("probability", 1))}
    wang = {}
    for ws in root.findall("wangsets/wangset"):
        m = {}
        for wt in ws.findall("wangtile"):
            wid = tuple(int(v) for v in wt.get("wangid").split(","))
            key = tuple(1 if v == 2 else 0 for v in wid)
            tid = int(wt.get("tileid"))
            prob = tiles.get(tid, {}).get("prob", 1.0)
            m.setdefault(key, []).append((tid, prob))
        wang[ws.get("name")] = m

    class TS:
        def collides(self, tid):
            t = tiles.get(int(tid))
            return bool(t and t["rects"])

    ts = TS()
    ts.tiles = tiles
    ts.wang = wang
    return ts
