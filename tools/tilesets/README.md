# Tilesets: Echoes of Elysium / cyberpunk_space_rpg

Four 32x32 tilesets for Tiled + Bonfire (`forceTileSize: 32`). Each sheet is 16 columns wide, laid out as a grid with **spacing 0 and margin 0**. Tile ids below are 0-based, which is the Tiled local id (in a map, gid = firstgid + id).

Files per tileset: `<name>.png` (sheet), `<name>.tsx` (Tiled tileset with collision, properties and wangsets), `preview_<name>.png` (2x preview with grid and ids; ids of tiles that collide are yellow), and `sample_<name>.png` + `sample_<name>.tmj` (a small map built only from that tileset to show the joins; you can open the .tmj in Tiled).

## How it works
- **Ground layer:** opaque tiles. **Props:** transparent tiles meant for a layer above the ground. Multi-tile props occupy a contiguous rectangle in the sheet, so you can select them as a stamp in Tiled.
- **Collision:** every blocking tile has a bool property `collides=true` **and** a per-tile collision object (`<objectgroup>` with rectangles). Edge pieces get 16x16-quarter rectangles that roughly follow the blocking part, and blocking props get their pixel bounding box. Bonfire reads tileset collision objects; `collides` is there if you'd rather build collision yourself.
- **Auto-tiling:** each terrain transition is a full **47-tile blob** set, stored as a Tiled wangset with `type="mixed"` and 2 colours (colour 1 = base terrain, colour 2 = overlay terrain). Use it with the Terrain/Wang brush. The plain variants of each terrain are also in the wangset, with low `probability` for the decorated ones, so big areas get some variety. All blob tiles share one periodic base texture per terrain, so the tiles join seamlessly. The wang ids follow the blob rule (a corner only counts as overlay when both of its neighbouring edges do). If the brush asks for a corner-only combination, Tiled falls back to the nearest tile.
- Within each 47-tile blob block the order is: index 0 = all base, then sorted by how many overlay zones the tile has, and the last index (+46) = all overlay. The 48th slot of each block (+47) is left empty.
- **Core only:** two 16-tile **edge/connection sets** (wangset `type="edge"`): glowing roots and cyan conduits. These are transparent overlays for a layer above the floor. Tile = set start + bitmask (N=1, E=2, S=4, W=8).

## Woods / starter: `woods.png` / `woods.tsx`
272 tiles (16 x 17), 163 with collision. Night forest in the neon palette. The crashed ship (Kaela's diagnostic skiff, #47), the portal platform and the dock pieces are props. The skiff's collision rects are derived from its art by `prop_collision.py` (`python3 tools/tilesets/prop_collision.py --write`, then re-run `tools/make_tiled_maps.py`); its smoke emitter sits on the fuselage (`EMITTERS` in `make_tiled_maps.py`). The dock planks don't collide, but the water tiles under them do, so leave the collision off the tiles under a dock (or build the dock on grass at the shore).

| ids | contents |
|---|---|
| 0-15 | ground variants: 0-7 grass, 8-11 dirt path, 12-13 water (collides), 14-15 dense forest (collides) |
| 16-62 | blob 'grass-path' (grass -> dirt) |
| 64-110 | blob 'grass-water' (grass -> water) collides |
| 112-158 | blob 'grass-forest' (grass -> forest) collides |
| 160-222, 225, 227-235, 245-251, 261-267 | props (below) |

Props (`name`: tile ids, row-major):

`tree_green` 160-161, 176-177, `tree_teal` 162-163, 178-179, `tree_blue` 164-165, 180-181, `tree_purple` 166-167, 182-183, `tree_big` 168-170, 184-186, 200-202, `tree_pine` 171-172, 187-188, `bush_green` 173, `bush_glow` 174, `rock_small` 175, `rock_moss` 189, `boulder` 190-191, 206-207, `log` 192-193, `stump` 194, `mushrooms` 195, `flowers` 196, `campfire` 197, `tent` 198-199, 214-215, `crate` 203, `lantern` 204, `signpost` 205, `standing_stone` 208, `monolith` 209, 225, `ship_debris` 210, `radio_dish` 211-212, 227-228, `crashed_ship` 216-219, 232-235, 248-251, 264-267, `dock_planks_h` 213, `dock_planks_v` 220, `fence_h` 221, `fence_v` 222, `portal_platform` 229-231, 245-247, 261-263

Wangsets: `grass-path` (mixed, 58 tiles), `grass-water` (mixed, 56 tiles), `grass-forest` (mixed, 56 tiles)

## City: `city.png` / `city.tsx`
320 tiles (16 x 20), 148 with collision. Buildings: the edge pieces show a lit south facade and a parapet, and the roof-only props (AC, vents, solar, helipad, neon sign, archive dome) go on top of roofs. The crosswalk, lane and arrow decals on row 0 are not in the wangset's random variants, so place them by hand.

| ids | contents |
|---|---|
| 0-23 | ground: 0-8 asphalt (plain, cracks, manhole, oil, lane-h, lane-v, crosswalk-h, crosswalk-v, arrow), 9-11 sidewalk, 12-14 plaza, 15 grass; 16-17 roof (collides), 18-19 water (collides), 20-21 bridge N-S/E-W, 22 grass, 23 sidewalk |
| 32-78 | blob 'road-sidewalk' (asphalt -> sidewalk) |
| 80-126 | blob 'sidewalk-building' (sidewalk -> building) collides |
| 128-174 | blob 'plaza-water' (plaza -> water) collides |
| 176-222 | blob 'sidewalk-grass' (sidewalk -> grass) |
| 224-266, 268-270, 272-277, 284-286, 288-290, 304-306 | props (below) |

Props (`name`: tile ids, row-major):

`street_lamp` 224, `planter_tree` 225-226, 241-242, `planter_small` 227, `bench` 228, `kiosk` 229-230, `car_blue_v` 231, 247, `car_purple_v` 232, 248, `car_magenta_h` 233-234, `hover_taxi_v` 235, 251, `rooftop_ac` 236, `rooftop_vent` 237, `helipad` 243-245, 259-261, 275-277, `solar_panel` 238-239, `neon_sign` 249-250, `bollard` 240, `trash_bin` 246, `fountain` 252-254, 268-270, 284-286, `holo_billboard` 256-257, `road_barrier` 262-263, `bus_stop` 264-265, `vending_machine` 255, `hydrant` 258, `archive_dome` 272-274, 288-290, 304-306, `traffic_light` 266

Wangsets: `road-sidewalk` (mixed, 58 tiles), `sidewalk-building` (mixed, 51 tiles), `plaza-water` (mixed, 50 tiles), `sidewalk-grass` (mixed, 50 tiles)

## Cyberpunk ruins: `cyberpunk.png` / `cyberpunk.tsx`
256 tiles (16 x 16), 133 with collision. Ruined buildings have a neon roof edge and a lit window facade. Puddles, cables and neon spill are low-probability asphalt variants. The portal hex pad is 3x3 and doesn't collide.

| ids | contents |
|---|---|
| 0-20 | ground: 0-11 wet asphalt (plain, cracked, puddle, grate, manhole, debris, cable-h, cable-v, dash-h, dash-v, magenta spill, cyan spill), 12 hazard floor, 13-14 metal plate, 15 puddle+debris; 16-17 ruin roof (collides), 18-19 toxic sludge (collides), 20 metal w/ cyan strip |
| 32-78 | blob 'asphalt-ruin' (asphalt -> ruin) collides |
| 80-126 | blob 'asphalt-sludge' (asphalt -> sludge) collides |
| 128-174 | blob 'asphalt-metal' (asphalt -> metal) |
| 176-213, 217-218, 224-228, 240-242 | props (below) |

Props (`name`: tile ids, row-major):

`rubble_small` 176, `rubble_large` 177-178, 193-194, `wrecked_car_v` 179, 195, `wrecked_car_h` 180-181, `barrel_purple` 182, `barrel_toxic` 183, `neon_kiosk` 184-185, `vending_broken` 186, `terminal` 187, `holo_billboard` 188-189, 204-205, `neon_sign` 190-191, `dumpster` 196-197, `crate` 192, `steam_vent` 198, `broken_pillar` 199, `neon_streetlight` 200, `satellite_dish` 201-202, 217-218, `portal_hexpad` 208-210, 224-226, 240-242, `drone_wreck` 203, `barricade` 206-207, `generator` 211-212, 227-228, `loose_cables` 213

Wangsets: `asphalt-ruin` (mixed, 60 tiles), `asphalt-sludge` (mixed, 60 tiles), `asphalt-metal` (mixed, 61 tiles)

## Gaia's Core room: `core.png` / `core.tsx`
240 tiles (16 x 15), 116 with collision. Matches the painted Core room (navy flagstones, cyan rim at the void, magenta/purple inlays, green-gold roots, purple orb pylons). The Core Record tree is a separate sprite and isn't in this sheet. Use `floor_ring_marker` and the inlay-dash tiles to build rings around it.

| ids | contents |
|---|---|
| 0-15 | ground: 0-5 floor (plain, crack, moss, gold glyph, purple node, circuit), 6-11 inlay dashes (cyan h/v, magenta h/v, purple h/v), 12-13 void (collides), 14 dais, 15 root tangle (collides) |
| 16-62 | blob 'floor-void' (floor -> void) collides |
| 64-110 | blob 'floor-dais' (floor -> dais) |
| 112-158 | blob 'floor-roots' (floor -> roots) collides |
| 160-175 | edge set 'roots' (bitmask N=1,E=2,S=4,W=8 -> index offset) |
| 176-191 | edge set 'conduits' (bitmask N=1,E=2,S=4,W=8 -> index offset) |
| 192-213, 216, 228-229 | props (below) |

Props (`name`: tile ids, row-major):

`orb_pylon` 192, `orb_pylon_large` 193-194, 209-210, `core_terminal` 195, `core_console` 196-197, `data_crystals` 198, `gold_glyph_stone` 199, `lattice_panel` 200, 216, `sealed_door` 201-203, `root_bulb` 204, `conduit_junction` 205, `drone_wreck` 206, `energy_brazier` 207, `broken_pillar` 208, `memory_pedestal` 211, `floor_ring_marker` 212-213, 228-229

Wangsets: `floor-void` (mixed, 53 tiles), `floor-dais` (mixed, 52 tiles), `floor-roots` (mixed, 52 tiles), `roots` (edge, 16 tiles), `conduits` (edge, 16 tiles)

## Regenerating
The scripts are in `/workspace/klas-game/tools/`: `tilelib.py` (shared blob/wang/tsx code), `ts_woods.py`, `ts_city.py`, `ts_cyber.py`, `ts_core.py`, and `check_tilesets.py` (validates the tsx format and does a seam check). Run them with `/workspace/klas-game/.venv/bin/python`.
