#!/usr/bin/env python3
"""Unit tests for the main-route gate rule in make_tiled_maps.py
(validate_main_gates): gates may sit on the main route as long as each
creature and the objects its bond needs are reachable without passing its own
gate, every opening order works, and no gate can be skipped.

    python3 tools/test_main_gates.py      (needs numpy + Pillow, like the generator)
"""
import os, sys, unittest
from collections import deque
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
_argv = sys.argv; sys.argv = [sys.argv[0], "/tmp"]       # the generator reads argv at import
import make_tiled_maps as m                              # noqa: E402
sys.argv = _argv
T = m.T


class Stub:
    """Just enough of Level for validate_main_gates on a hand-made grid."""
    def __init__(self, rows):
        self.ok = np.array([[c != "#" for c in r] for r in rows])
        self.H, self.W = self.ok.shape
        self.objects, self.goal = [], dict(fragments=1)

    def obj(self, name, tx, ty, tw=1, th=1, **props):
        self.objects.append(dict(name=name, x=float(tx * T), y=float(ty * T), w=float(tw * T), h=float(th * T), props=props))

    def check(self):
        def cells(o):
            x0, y0 = int(o["x"] // T), int(o["y"] // T)
            x1, y1 = int((o["x"] + o["w"] - 0.01) // T), int((o["y"] + o["h"] - 0.01) // T)
            return [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]
        sx, sy = cells(next(o for o in self.objects if o["name"] == "spawn"))[0]
        def flood(mask):
            seen = np.zeros_like(mask); q = deque([(sx, sy)]); seen[sy, sx] = True
            while q:
                x, y = q.popleft()
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.W and 0 <= ny < self.H and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True; q.append((nx, ny))
            return seen
        m.Level.validate_main_gates(self, self.ok, cells, flood)


# Spawn in a clearing at the top; a 3-wide neck (x 4-6) runs south to the
# exit. The road boulder (3x2) sits at rows 4-5; closed, its collision
# blocks the bottom row (row 5), like the Woods road.
ROWS = [
    "############",
    "#..........#",
    "#..........#",
    "#..........#",
    "####...#####",
    "####...#####",
    "####...#####",
    "####...#####",
    "############",
]


def corridor(turtle_at=(2, 1)):
    s = Stub(ROWS)
    s.obj("spawn", 1, 2)
    s.obj("abilitygate", 4, 4, 3, 2, kind="boulder", gate="g_boulder", ability="push", creature="stoneturtle")
    s.obj("creature", *turtle_at, species="stoneturtle", radius=0.5)
    s.obj("fragment", 9, 2)
    s.obj("mapexit", 4, 7, 3, 1, unlock=True)
    return s


class MainGates(unittest.TestCase):
    def test_gate_on_the_route_is_allowed(self):
        corridor().check()

    def test_creature_behind_its_own_gate_is_a_deadlock(self):
        with self.assertRaisesRegex(SystemExit, "stoneturtle not reachable before it opens"):
            corridor(turtle_at=(5, 6)).check()

    def test_a_gate_that_can_be_skipped_is_refused(self):
        s = corridor()
        s.ok[3:8, 8] = True                                   # a trail round the boulder
        s.ok[6, 7] = True
        with self.assertRaisesRegex(SystemExit, "g_boulder can be skipped"):
            s.check()

    def test_needed_item_behind_the_gate_is_a_deadlock(self):
        s = corridor()
        s.objects[1]["props"]["needs"] = "stump"
        s.obj("stump", 5, 6)
        with self.assertRaisesRegex(SystemExit, "stump .*not reachable before it opens"):
            s.check()
        s.objects[-1]["x"] = 8 * T; s.objects[-1]["y"] = 1 * T   # stump in the clearing: fine
        s.check()

    def test_covering_gate_locks_its_fragment_until_open(self):
        s = corridor()
        s.objects = [o for o in s.objects if o["name"] != "fragment"]
        # a grotto in the clearing; its fragment is taken from the bank below
        s.obj("abilitygate", 7, 1, 3, 2, kind="grotto", gate="g_grotto", ability="light", creature="glowmoth")
        s.obj("fragment", 8, 1, gate="g_grotto")
        s.obj("creature", 2, 3, species="glowmoth", radius=1.0)
        s.check()
        # with the moth beyond the boulder the turtle-first order still works,
        # but grotto-first deadlocks: refused (any order must work)
        s.objects[-1]["x"] = 5 * T; s.objects[-1]["y"] = 7 * T
        with self.assertRaisesRegex(SystemExit, "glowmoth not reachable before it opens"):
            s.check()

    def test_two_gates_whose_creatures_wait_behind_each_other(self):
        s = corridor(turtle_at=(1, 7))                            # turtle in the bramble pocket
        s.ok[4:8, 1:3] = True
        s.obj("abilitygate", 1, 4, 2, 2, kind="bramble", gate="g_brambles", ability="scent", creature="vinefox")
        s.obj("creature", 5, 6, species="vinefox", radius=0.5)    # fox beyond the boulder
        with self.assertRaisesRegex(SystemExit, "not reachable before it opens"):
            s.check()

    def test_unknown_gate_reference(self):
        s = corridor()
        s.obj("fragment", 9, 3, gate="nope")
        with self.assertRaisesRegex(SystemExit, "unknown gate"):
            s.check()

    def test_blocked_cells_follow_the_art_state(self):
        g = dict(name="abilitygate", x=40.0 * T, y=40.0 * T, w=3.0 * T, h=2.0 * T, props=dict(kind="boulder"))
        self.assertEqual(m.gate_blocked_cells(g, "closed"), {(40, 41), (41, 41), (42, 41)})
        self.assertEqual(m.gate_blocked_cells(g, "open"), {(42, 41)})     # passage x 0-64 free
        b = dict(name="abilitygate", x=50.0 * T, y=26.0 * T, w=2.0 * T, h=2.0 * T, props=dict(kind="bramble"))
        self.assertEqual(m.gate_blocked_cells(b, "closed"), {(50, 27), (51, 27)})
        self.assertEqual(m.gate_blocked_cells(b, "open"), set())


if __name__ == "__main__":
    unittest.main()
