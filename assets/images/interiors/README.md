# Interiors (#31, scaled in #62)

Enterable rooms: `tea_house` (the inn at Lantern Gate), `noodle_shop`
(Market Row), `archive_library` (after the Archivist's seal),
`ranger_cabin` (Asha's place in the Woods) and `pond_grotto` (Woods pond
cave after LIGHT / `woods_grotto`). Every other building door stays locked
and shows its GameConcept flavour line.

## Grid

Every room is **12×8 tiles of 32 px** (384×256). 32 px is Kaela's height
and the overworld tile, so a chair, a counter and a door frame are one
tile and a bed is two. The old 16×9 painted backdrops drew those props at
illustration scale; she read as a figurine in a hall.

| | |
|---|---|
| Tile | 32 px, hard pixels, nearest-neighbour |
| Room | 12 columns × 8 rows |
| Door | 2 tiles wide on the south wall. The mat is the south row (`y = 7`, `x = 5..6`). Spawn is `(5, 5)`, one floor tile inside the threshold |
| Furniture | 1 tile (counter, table, chest, desk, crystal). Bed is 1×2, head then foot |

Rebuild art and JSON together:

```
python3 tools/interiors/assemble_cabin_gen.py
python3 tools/interiors/assemble_grotto_gen.py
python3 tools/interiors/build_rooms.py
```

That script is the layout source. It writes `tileset.png`, each `<id>.png`
(the baked picture, for review) and each `<id>.json`. The game draws the
JSON layers, not the PNG. Do not commit @2x previews.

**Cursor-gen pilots:** `ranger_cabin` and `pond_grotto` tiles live under
`tools/interiors/gen_src/{cabin,grotto}/`, pixelized to 32px. Other rooms
still use Pillow placeholders until their pass.

## Tileset

`assets/images/interiors/tileset.png` — 16 columns, 32 px, spacing 0,
margin 0. Local id `n` is column `n % 16`, row `n ~/ 16`.

| ids | layer | contents |
|---|---|---|
| 0–1 | floor | tea-house planks |
| 2–3 | floor | noodle-shop tiles |
| 4–5 | floor | cabin planks |
| 6–7 | floor | archive flagstone |
| 8–9 | floor | grotto stone |
| 10 | floor | pool (solid) |
| 11 | floor | moss |
| 12–13 | floor | doormat (inn / cave). Walkable; stepping on it leaves |
| 16–25 | floor | walls (N/S face): tea, tea window, noodle, neon, log, hearth, books, cave, map, drip |
| 26–35 | floor | door jambs (tea, noodle, log, cave, books), left then right |
| 40–69 | props | counter, urn, pots, tin, table, cushion, bed, plant, screen, chest, draft desk, journal, note, lamp, crate, fridge, bowl, crystal, rock, logs, nightstand, stool, rug, cabin bed, lectern, glyph, barrel, fern |
| 70–74 | floor | E/W side walls (tea, noodle, log, books, cave) |
| 75–79 | floor | corner posts (same order) |

`floor` in the JSON is opaque ground and walls. `props` is 0 or a
transparent prop drawn on top (the floor shows through). Rugs (`63`) and
ferns (`69`) do not block. Every other prop, every wall, and the pool
are collision. NPCs stand on an empty floor tile; the game blocks that
tile. Collision rects in the JSON are those solid cells, merged.

## Door flow
1. E at an enterable building's door: fade out, the room loads over the
   paused overworld, Kaela appears on `spawn` facing up, fade in.
2. Stepping onto the `door` rect (doormat) fades back to the same exterior
   door, one step in front of it, facing down. The mat only triggers once
   she has been off it.
3. Saving inside (rest, autosave, app backgrounded) stores the exterior
   position in front of the door, so CONTINUE resumes there.

## JSON
| field | meaning |
|---|---|
| `id`, `title`, `image` | room id, display name (text before `:` is shown), baked PNG next to the JSON |
| `tileset`, `sheetCols` | tileset file, columns (16) |
| `size`, `tile` | `[12, 8]` tiles of 32 px |
| `floor`, `props` | row-major tile ids. `props` 0 = nothing |
| `collision` | solid tile rects `[x, y, w, h]`; everything else is floor |
| `door` | doormat rect |
| `spawn` | entry tile `[x, y]`, right above the mat |
| `npcs` | `{name, sprite, tile, role}`; `sprites/<sprite>_walk.png`, else `npc_<sprite>.png`; their tile blocks |
| `interact` | `{id, rect, kind, note}`; usable from on/4-next to the rect while facing it. Kinds: npc, rest, shop, errand, lore, clue, stash, journal, map, note, flavour. Two spots with the same rect share one prompt (Dao's menu + errand) |
| `lights` | `{tile, kind}`: warm, fire, neon or cyan; a subtle additive glow in #35's colours |

Code: `lib/cyberpunk_space_rpg/interiors/` (data, scene, actions, text).
Lines are verbatim from GameConcept in `room_text.dart`; the JSON `note`
is only a fallback for plain flavour spots.

Preview: `flutter run -d chrome -t tools/room_preview.dart` then
`?id=noodle_shop&spot=dao`.

`test/interiors_test.dart` checks every room: grid and art size, tileset
ids, spawn/door, a flood fill that every spot is reachable, sprites exist
and every spot opens something.
