# Hubs (first experiment)

Klas: skills depth is enough; hubs need a map remake — **start small**.

This PR expands one existing enterable interior instead of inventing a
district or remaking City / Woods overworld lots.

## What shipped: Lantern Gate tea house as a mini-hub

| | |
|---|---|
| Building | `tea_house` (already on City Lantern Gate + Lantern Town lots) |
| Before | 12×8 corridor-scale room: talk (Wen, Ferro) + rest bed |
| After | **16×10** tiled room with three readable zones |

Zones inside the same shell language (`tools/interiors/build_rooms.py`,
32 px tiles, shared `tileset.png`):

1. **Lounge (center)** — open floor, rug, table, Ferro by the window (talk / riddles)
2. **Tea counter (west)** — Wen (talk) + **ORDER** shop (`tea_menu`: Lantern tea / Quiet cup for glimmer → HP)
3. **Rest alcove (east)** — paper screen + bed (REST → save + well rested)

Walkable floor went from ~40 tiles to **84**. Door / spawn stay centred on
the south wall; leave flow unchanged (doormat).

## How to reach it in-game

1. Reach **The City** (south road from the Woods once gates allow).
2. Walk **east** along the boulevard to the **Lantern Gate**.
3. Enter the **tea house** building (E at the door) — same exterior sprite as before.
4. Alternate: **Lantern Town** also places a `tea_house` lot; same interior JSON.

Inside: talk to Wen or Ferro, ORDER at the brass counter, REST on the
alcove bed, step the south doormat to leave.

## What we did *not* do (too big for one PR)

- Remake City / Town overworld maps or add a new district shell
- Merge noodle shop into the inn (Dao stays on Market Row)
- Cursor-gen art pass for tea tiles (still Pillow placeholders; cabin /
  grotto / archive remain the gen pilots)
- Multi-room connected interiors or outdoor plaza hub geometry

Next hub steps (separate PRs): optional second zone on an existing City
lot, or a woods cabin expansion, once this interior scale feels right.
