# Interiors (#31)

Enterable rooms: `tea_house` (the inn at Lantern Gate), `noodle_shop`
(Market Row), `archive_library` (after the Archivist's seal) and
`ranger_cabin` (Asha's place in the Woods). Every other building door stays
locked and shows its GameConcept flavour line.

Per room: `<id>.png` (512x288 = 16x9 tiles of 32 px, hard pixels; never
commit the @2x previews or sources) + `<id>.json`. Code:
`lib/cyberpunk_space_rpg/interiors/` (data, scene, actions, text). Lines are
verbatim from GameConcept in `room_text.dart`; the JSON `note` is only a
fallback for plain flavour spots.

Preview: `flutter run -d chrome -t tools/room_preview.dart` then
`?id=noodle_shop&spot=dao`.

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
| `id`, `title`, `image` | room id, display name (text before `:` is shown), background next to the JSON |
| `size`, `tile` | [16, 9] tiles of 32 px |
| `collision` | solid tile rects [x, y, w, h]; everything else is floor |
| `door` | doormat rect |
| `spawn` | entry tile [x, y], right above the mat |
| `npcs` | `{name, sprite, tile, role}`; `sprites/<sprite>_walk.png`, else `npc_<sprite>.png`; their tile blocks |
| `interact` | `{id, rect, kind, note}`; usable from on/4-next to the rect while facing it. Kinds: npc, rest, shop, errand, lore, clue, stash, journal, map, note, flavour. Two spots with the same rect share one prompt (Dao's menu + errand) |
| `lights` | `{tile, kind}`: warm, fire, neon or cyan; a subtle additive glow in #35's colours |

`test/interiors_test.dart` checks every room: art size, spawn/door, a
flood fill that every spot is reachable, sprites exist and every spot opens
something.
