#!/usr/bin/env python3
"""Derive per-tile collision rects for a multi-tile prop from its art.

    python3 tools/tilesets/prop_collision.py [--write] [prop]   (default prop: crashed_ship)

Builds a "solid" mask from the prop's opaque pixels (alpha > 0), drops the
loose scorched-dirt ring (dark, saturated browns) and the thin fin tip, cleans
it up (small specks out, gaps closed, holes filled), then approximates the
mask in every 32x32 tile with a few rects (8px row bands, merged when their
x-extent barely changes). Without --write it prints the rects and the
coverage; with --write it updates woods.tsx and woods.tsj in place (the
`collides` property + collision objectgroup of each prop tile), keeping the
rest of both files byte-identical. Re-run make_tiled_maps.py afterwards.
Needs numpy + Pillow.
"""
import json, os, re, sys
from collections import deque
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
T, COLS = 32, 16
# prop -> (tileset, ignore pixels above this y in the block = thin fin tip)
PROPS = {"crashed_ship": ("woods", 56)}
BAND, MERGE, MIN_PX = 8, 3, 24


def _shift(m, dy, dx):
    o = np.zeros_like(m)
    h, w = m.shape
    o[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = m[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return o


def dilate(m, n=1):
    for _ in range(n):
        m = m | _shift(m, 1, 0) | _shift(m, -1, 0) | _shift(m, 0, 1) | _shift(m, 0, -1)
    return m


def erode(m, n=1):
    return ~dilate(~m, n)


def components(m):
    lab = np.zeros(m.shape, int); n = 0
    for y, x in zip(*np.nonzero(m)):
        if lab[y, x]: continue
        n += 1; lab[y, x] = n; q = deque([(y, x)])
        while q:
            cy, cx = q.popleft()
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < m.shape[0] and 0 <= nx < m.shape[1] and m[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = n; q.append((ny, nx))
    return lab, n


def fill_holes(m):
    lab, _ = components(np.pad(~m, 1, constant_values=True))
    return ~(lab[1:-1, 1:-1] == lab[0, 0]) | m


def solid_mask(rgba, fin_y):
    r, g, b, a = (rgba[..., i].astype(int) for i in range(4))
    mx = np.maximum(np.maximum(r, g), b); mn = np.minimum(np.minimum(r, g), b)
    sat = (mx - mn) / np.maximum(mx, 1)
    dirt = (r >= g) & (g >= b - 5) & (sat > 0.3) & (mx < 170)
    m = (a > 0) & ~dirt
    m = dilate(erode(m))                     # opening: drop 1px specks
    lab, n = components(m)
    sizes = np.bincount(lab.ravel(), minlength=n + 1)
    m = np.isin(lab, [i for i in range(1, n + 1) if sizes[i] > 150])
    m = erode(dilate(m, 3), 3)               # closing: bridge rust gaps
    m = fill_holes(m)
    m[:fin_y] = False
    return m


def tile_rects(tm):
    """[(x, y, w, h)] approximating the True pixels of one tile mask."""
    if tm.sum() < MIN_PX: return []
    bands = []
    for y0 in range(0, T, BAND):
        cols = np.nonzero(tm[y0:y0 + BAND].sum(0) >= 2)[0]
        rows = np.nonzero(tm[y0:y0 + BAND].any(1))[0]
        if len(cols) == 0 or len(rows) < 2: continue
        bands.append([int(cols[0]), y0 + int(rows[0]), int(cols[-1]) + 1, y0 + int(rows[-1]) + 1])
    out = []
    for bd in bands:
        if out and bd[1] - out[-1][3] <= 1 and abs(bd[0] - out[-1][0]) <= MERGE and abs(bd[2] - out[-1][2]) <= MERGE:
            p = out[-1]; out[-1] = [min(p[0], bd[0]), p[1], max(p[2], bd[2]), bd[3]]
        else:
            out.append(bd)
    return [(x0, y0, x1 - x0, y1 - y0) for x0, y0, x1, y1 in out]


def prop_tiles(tsx_text, prop):
    ids = [int(m.group(1)) for m in re.finditer(r'<tile id="(\d+)">(?:(?!</tile>).)*?value="%s"' % re.escape(prop),
                                                 tsx_text, re.S)]
    return sorted(ids)


def derive(prop):
    ts, fin_y = PROPS[prop]
    tsx = open(os.path.join(HERE, f"{ts}.tsx")).read()
    ids = prop_tiles(tsx, prop)
    x0 = min(i % COLS for i in ids); y0 = min(i // COLS for i in ids)
    w = max(i % COLS for i in ids) - x0 + 1; h = max(i // COLS for i in ids) - y0 + 1
    img = np.array(Image.open(os.path.join(HERE, f"{ts}.png")).convert("RGBA"))
    blk = img[y0 * T:(y0 + h) * T, x0 * T:(x0 + w) * T]
    m = solid_mask(blk, fin_y)
    rects = {}
    for tid in ids:
        tx, ty = tid % COLS - x0, tid // COLS - y0
        rects[tid] = tile_rects(m[ty * T:(ty + 1) * T, tx * T:(tx + 1) * T])
    cov = np.zeros_like(m)
    for tid, rs in rects.items():
        tx, ty = tid % COLS - x0, tid // COLS - y0
        for (rx, ry, rw, rh) in rs:
            cov[ty * T + ry:ty * T + ry + rh, tx * T + rx:tx * T + rx + rw] = True
    opaque = blk[..., 3] > 0
    print(f"{prop}: {sum(map(len, rects.values()))} rects on {sum(1 for r in rects.values() if r)} tiles; "
          f"{(cov & opaque).sum() / max(cov.sum(), 1):.0%} of collision px on opaque art, "
          f"{(cov & m).sum() / max(m.sum(), 1):.0%} of the hull covered")
    return ts, rects


def write_tsx(path, rects):
    s = open(path).read()
    for tid, rs in rects.items():
        pat = re.compile(r'( <tile id="%d">\n)(.*?)( </tile>\n)' % tid, re.S)
        mt = pat.search(s); assert mt, tid
        props = [l for l in re.findall(r'   <property [^\n]*\n', mt.group(2)) if 'name="collides"' not in l]
        body = "  <properties>\n"
        if rs: body += '   <property name="collides" type="bool" value="true" />\n'
        body += "".join(props) + "  </properties>\n"
        if rs:
            body += '  <objectgroup draworder="index" id="2">\n'
            body += "".join(f'   <object id="{i + 1}" type="collision" x="{x}" y="{y}" width="{w}" height="{h}" rotation="0" />\n'
                            for i, (x, y, w, h) in enumerate(rs))
            body += "  </objectgroup>\n"
        s = s[:mt.start(2)] + body + s[mt.end(2):]
    open(path, "w").write(s)


def write_tsj(path, rects):
    j = json.load(open(path))
    for t in j["tiles"]:
        rs = rects.get(t["id"])
        if rs is None: continue
        t["properties"] = [p for p in t["properties"] if p["name"] != "collides"]
        t.pop("objectgroup", None)
        if rs:
            t["properties"].insert(0, {"name": "collides", "type": "bool", "value": True})
            t["objectgroup"] = {"draworder": "index", "id": 2, "name": "", "opacity": 1, "type": "objectgroup",
                                "visible": True, "x": 0, "y": 0,
                                "objects": [{"id": i + 1, "name": "", "type": "collision", "x": x, "y": y,
                                             "width": w, "height": h, "rotation": 0, "visible": True}
                                            for i, (x, y, w, h) in enumerate(rs)]}
    open(path, "w").write(json.dumps(j, indent=1))


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--write"]
    ts, rects = derive(args[0] if args else "crashed_ship")
    for tid, rs in rects.items():
        print(f"  {tid}: {rs}")
    if "--write" in sys.argv:
        write_tsx(os.path.join(HERE, f"{ts}.tsx"), rects)
        write_tsj(os.path.join(HERE, f"{ts}.tsj"), rects)
        print(f"updated {ts}.tsx and {ts}.tsj")
