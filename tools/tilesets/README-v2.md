# Tilesets v2

Drop-in replacements for `../tilesets/` (v1). Tile indices, tile counts, 32 px tiles, 16 columns, spacing 0 and margin 0 are unchanged, and so are the collision rects and the wang tile ids/wangids except for the decal fixes below.
Prop tiles come from generated art in `gen_src/<biome>/prop_*.png` (all 91 props of the four biomes have a source now: woods 30, city 24, cyberpunk 22, core 15. `gen_src` holds 92 `prop_*.png` files because
`city/prop_planter_flowers_extra.png` is a spare that no tileset uses);
a prop without a source keeps its v1 art byte-identical. Prop tile indices, footprints and collision rects are the v1 ones.

## Files
- `<biome>.png`: tileset image (woods, city, cyberpunk, core)
- `<biome>.tsj`: Tiled JSON tileset. **Use this one in Bonfire** (Bonfire cannot load external .tsx).
  Every collision object has `"rotation": 0` and every wang colour has `"probability"`.
- `<biome>.tsx`: the same tileset in Tiled XML, for editing in Tiled
- `sample_<biome>.tmj` / `.png`: sample map. It references `<biome>.tsj`.
- `compare_<biome>.png`: one painted test patch per terrain wangset (brush logic plus tile probabilities), v1 left, v2 right
- `compare_all.png`: overview of all four biomes
- `compare_<biome>_map.png`: the sample map rendered with v1 and with v2
- `preview_<biome>.png`: the whole sheet with ids
- `preview_props.png`: contact sheet of all generated props per biome at 2x

## Map-making rules (Bonfire 3.15)
- **Walls and other collidable terrain must be at least 2 tiles thick.** One-tile-thick walls or isolated single
  wall tiles draw as floor with no collision in Bonfire. This applies to buildings, ruins, water, sludge, void and roots.
- Decals are placed by hand and are not part of the terrain brush:
  - city 4-8: lane-h, lane-v, crosswalk-h, crosswalk-v, arrow. Removed from `road-sidewalk`.
  - cyberpunk 6-9: cable-h, cable-v, dash-h, dash-v. Removed from all three asphalt wangsets.
  - city 13-14: plaza inlay and emblem. Still in `plaza-water`, but tile probability lowered from 1.0 to 0.08.
- City sidewalk mix (`SETPROB` in `tools/v2_export.py`): tile probabilities 23 (plain, faint wear) = 0.60, 10 (grate) = 0.24,
  11 (drain) = 0.16 (all three were 0.15). Each sidewalk wangset's plain interior tile (78 / 80 / 176) stays at 1.0, so a brushed
  sidewalk cell comes out plain 80 % / grate 12 % / drain 8 %. `sidewalk-grass` had no plain variant besides 176, so tile 23
  was added to it as an all-sidewalk wangtile (`ADDWANG`). That is the only wangtile addition; all other wang ids are unchanged.
- City plaza (tiles 12-14 and the plaza side of `plaza-water`) reads as stone: the gen_src plaza came out saturated navy and
  looked like water next to the canal, so `v2_city.py` remaps it by luminance onto a slate-stone ramp (`STONE`) with a sparse
  granite speckle. Indices and sizes are unchanged.

## Rebuild
`tools/build_v2.sh` runs `v2_<biome>.py` (art), `v2_export.py` (tsx patch, .tsj, validation),
`v2_compare.py` and `check_tilesets.py tilesets_v2`.
Ground textures come from `gen_src/<biome>/ground_*.png` (any aspect ratio). Each one is cropped to a square, the crop
period is chosen so the wrap strips match, it is made seamless by cross-fading the overlap at full resolution,
large blotches are evened out, it is downscaled to a 128 px periodic texture and quantized to 18 colours, and then
cut into 32 px tiles. The most even, best-wrapping 32 px window becomes the base tile.
Regular patterns are snapped to the tile grid instead of being cross-faded (`GRID_SRC` in `tools/v2lib.py`):
- city plaza: 1 slab per tile, grout centred on the tile borders
- city sidewalk: 1 brick and 4 bond rows per tile
- cyberpunk metal: the plate layout repeats every 1x2 tiles

Calm palette: the sludge rim is soft teal/lavender (it used to be lime), and the core roots and conduit glows are muted.
`tools/v2_texseams.py` prints per-texture seam scores.

## Props from gen_src
`tools/cut_prop_sheets.py` cuts the 12 magenta prop sheets in `gen_src/prop_sheets/` into transparent
`gen_src/<biome>/prop_<name>.png` files (corner bg estimate, colour/hue-distance alpha, unmix + edge-only despill so violets
survive, blob grouping for steam/sparkles/petals, reading-order mapping in its `JOBS` table; debug overlays in
`gen_src/prop_sheets/_debug/`). `cyberpunk/prop_drone_wreck` reuses the core cutout, `cyberpunk/prop_portal_hexpad` comes
from `core_big`, and `city/prop_planter_flowers_extra.png` is a spare that no tileset uses.
`src_prop()` in `tools/v2lib.py` fits each one into its footprint: a 1x1 prop as large as the tile allows, bigger props inside
the v1 art bbox plus up to 6 px (never past the tile footprint), docks/fences stretched edge to edge so they join. Then a
premultiplied box downscale, a per-prop adaptive palette (20-28 colours), a 1px navy outline and a 2px soft drop shadow.
Steam/smoke wisps (steam_vent, crashed_ship, energy_brazier) keep one translucent alpha level (150).
