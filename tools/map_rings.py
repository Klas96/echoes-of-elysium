"""Loop / ring metric shared by make_tiled_maps.py and render_map_overview.py.

A "ring" is a walkable loop around a solid block (forest, city block, ruin
mass). On a planar grid the number of independent cycles of the walkable
region equals the number of holes in it, so we count the connected blocked
areas that the reachable floor completely surrounds. Tiny holes (a single
tree, a lamp, a building standing in a plaza) are not loops anyone would
notice, so a hole only counts when it is big enough: area >= MIN_AREA tiles,
a bounding box of at least MIN_SIDE tiles each way, and a loop around it of
at least MIN_LOOP floor tiles.
"""
from collections import deque
import numpy as np

MIN_AREA = 24
MIN_SIDE = 4
MIN_LOOP = 28


def rings(reach, min_area=MIN_AREA, min_side=MIN_SIDE, min_loop=MIN_LOOP):
    """reach: bool HxW array of floor reachable from the spawn (ability
    gates closed). Returns a list of dicts (x0, y0, x1, y1, area, loop) for
    every non-trivial hole, i.e. every independent walkable ring."""
    H, W = reach.shape
    blocked = ~reach
    label = np.full((H, W), -1, int)
    out = []
    n = 0
    for sy in range(H):
        for sx in range(W):
            if not blocked[sy, sx] or label[sy, sx] >= 0:
                continue
            q = deque([(sx, sy)]); label[sy, sx] = n
            cells = []; border = False
            while q:
                x, y = q.popleft(); cells.append((x, y))
                if x == 0 or y == 0 or x == W - 1 or y == H - 1:
                    border = True
                for dx in (-1, 0, 1):          # 8-connected blocked areas: a
                    for dy in (-1, 0, 1):      # diagonal gap is not walkable
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < W and 0 <= ny < H and blocked[ny, nx] and label[ny, nx] < 0:
                            label[ny, nx] = n; q.append((nx, ny))
            n += 1
            if border:
                continue
            xs = [c[0] for c in cells]; ys = [c[1] for c in cells]
            x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
            hole = np.zeros_like(blocked); hole[ys, xs] = True
            ring = np.zeros_like(blocked)
            ring[1:, :] |= hole[:-1, :]; ring[:-1, :] |= hole[1:, :]
            ring[:, 1:] |= hole[:, :-1]; ring[:, :-1] |= hole[:, 1:]
            loop = int((ring & reach).sum())
            if len(cells) >= min_area and x1 - x0 + 1 >= min_side and y1 - y0 + 1 >= min_side and loop >= min_loop:
                out.append(dict(x0=x0, y0=y0, x1=x1, y1=y1, area=len(cells), loop=loop))
    return out
