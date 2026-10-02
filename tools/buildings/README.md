# Buildings v2: placeable building sprites

Seven buildings made from `gen_src/buildings/*_front_magenta.jpg` by `tools/process_buildings.py`.
That script reuses `tools/process_gen.py` (magenta key, despill, area downscale, sharpen, palette, binary alpha,
selective navy outline). Re-run it with `.venv/bin/python tools/process_buildings.py`.

## Files
- `<name>.png`: RGBA sprite. Alpha is binary (0/255), there is no magenta fringe, and transparent pixels are RGB 0.
  Each canvas is a whole number of 32 px tiles. The building's base sits on the bottom row, and any extra
  space is padding at the top. The sprite is centred horizontally, so a few px of transparent margin at the
  sides is normal.
- `<name>.json`: sidecar file, shaped like this:
  `{"size_tiles":[w,h], "size_px":[W,H], "collision":[{"x","y","w","h"}], "door":{"x","y"}, "anchor":"bottom-left", "biome", "name", "image"}`
- `buildings.tsj`: Tiled **collection of images** tileset in JSON. Tile ids 0-6 follow the order below. Each tile carries
  its collision rect as an objectgroup object (`type: "collision"`, `"rotation": 0`) and has the tile properties
  `building`, `biome`, `door_x` and `door_y`. Use `.tsj` and not `.tsx`, because Bonfire can't load external `.tsx`.
- `preview_buildings.png`: every building at 2x on a mock street built from tilesets_v2 city sidewalk/road/plaza
  tiles, plus woods grass/dirt. The bottom half is the same scene with the collision boxes (translucent red) and
  the door points (yellow dots).

| id | name | biome | px | tiles | collision (px, from the sprite's top-left) | door (px) |
|---|---|---|---|---|---|---|
| 0 | `noodle_shop` | city | 128x128 | 4x4 | x12 y60 w104 h64 | (61, 124) |
| 1 | `tea_house` | city | 128x128 | 4x4 | x10 y60 w108 h64 | (64, 124) |
| 2 | `greenhouse` | city | 128x128 | 4x4 | x12 y60 w104 h64 | (63, 124) |
| 3 | `apartment_block` | city | 160x160 | 5x5 | x8 y78 w144 h64 | (80, 142) |
| 4 | `archive_library` | city | 160x160 | 5x5 | x8 y82 w142 h64 | (80, 146) |
| 5 | `ranger_cabin` | woods | 128x128 | 4x4 | x6 y54 w108 h64 | (63, 118) |
| 6 | `ruin_shrine` | core | 128x160 | 4x5 | x16 y88 w96 h64 | (64, 152) |

## Scale
- **City (the first 5): one shared scale** (0.307 output px per source px), so the buildings keep their sizes
  relative to each other. The scale was picked so the widest city building, the apartment block, fills 5 tiles.
  The three set-1 buildings then come out about 3.5 tiles wide and sit on 4-tile canvases. In the source art the
  apartment block and the library are the same width, so with one shared scale both are 5x5. The brief suggested
  a 4-wide apartment and a 5-wide library, but you can't get both from one scale.
- Ranger cabin and ruin shrine each have their own scale, set to fill 4 tiles wide.
- Doors come out about 26-35 px tall, which matches the 32 px player.

## Collision and door conventions
- All coordinates are in px, measured from the **top-left of the sprite image**.
- There is one rectangle per building. It covers the lower walls/footprint and is **64 px (2 tiles) tall and at least 64 px wide**,
  as Bonfire needs. Its bottom edge is the front face of the walls or entrance steps. The cobble apron, porch lip or
  grass below it stays walkable, and the roof above it can be walked behind.
- `door` is the entry threshold. It lies on the collision box's **bottom edge**, centred on the door. Put the
  interaction/entry trigger just below it, for example a 32x16 sensor centred on `(door.x, door.y + 8)`.
- Ruin shrine: the arch's pillars are each under 2 tiles wide, so the whole base (pillars, portal floor and steps) is
  one 96x64 block. `door` sits on the front step under the portal, so use it as the portal interaction point.
- Ranger cabin: the box also covers the log pile on the left (x 6-114).
- Bonfire y-sorts each component by the bottom of its hitboxes. If the building is a `GameDecorationWithCollision`
  carrying this rect, the player draws behind the building north of the box and in front of it south of the box.

## Placing them in Tiled
1. Map > Add External Tileset > `buildings.tsj`, or embed it to match the existing maps. Keep the image paths
   relative to wherever the tileset ends up.
2. On an **object layer**, use Insert Tile (T) to drop the building as a tile object. Tiled anchors tile objects
   **bottom-left**: the object's `x,y` is the bottom-left of the image. Snap to the 32 px grid so the base lands on a tile line.
3. Name the object `building` and add a string property `building = <name>` **on the placed object**. Tiled shows
   the tile's own properties in the editor, but it doesn't write inherited tile properties into the .tmj, and
   Bonfire's object builder only sees the object's own properties.
4. Every object needs `"rotation": 0` (Tiled always writes it, but generated maps must include it too). Don't rotate
   or scale building objects.
5. **Don't paint buildings into tile layers.** Bonfire 3.15.1 draws every tile-layer cell at the map tile size
   (32x32), so a 128x128 image would be squashed.

## Loading in Bonfire 3.15.1 (important)
`TiledWorldBuilder._addObjects` **does not draw tile objects (gid)** on object layers. It only builds objects whose
name has an entry in `objectsBuilder`, or objects of class `collision`. Buildings therefore need a builder,
just like `spawn`, `npc` and the other existing objects in `custom_map_game.dart`. Also, the `position` Bonfire passes in
is Tiled's raw `x,y`, which is the **bottom-left** for tile objects, so subtract the height:

```dart
class BuildingDef {
  final double w, h; final Rect collision; final Offset door;
  const BuildingDef(this.w, this.h, this.collision, this.door);
}
const buildingDefs = <String, BuildingDef>{   // generated from buildings_v2/<name>.json
  'noodle_shop': BuildingDef(128, 128, Rect.fromLTWH(12, 60, 104, 64), Offset(61, 124)),
  'tea_house': BuildingDef(128, 128, Rect.fromLTWH(10, 60, 108, 64), Offset(64, 124)),
  'greenhouse': BuildingDef(128, 128, Rect.fromLTWH(12, 60, 104, 64), Offset(63, 124)),
  'apartment_block': BuildingDef(160, 160, Rect.fromLTWH(8, 78, 144, 64), Offset(80, 142)),
  'archive_library': BuildingDef(160, 160, Rect.fromLTWH(8, 82, 142, 64), Offset(80, 146)),
  'ranger_cabin': BuildingDef(128, 128, Rect.fromLTWH(6, 54, 108, 64), Offset(63, 118)),
  'ruin_shrine': BuildingDef(128, 160, Rect.fromLTWH(16, 88, 96, 64), Offset(64, 152)),
};

// in _mapObjects():
'building': (p) {
  final id = (p.others['building'] ?? '').toString();
  final d = buildingDefs[id] ?? (throw ArgumentError('Unknown building "$id"'));
  final topLeft = p.position - Vector2(0, d.h);          // tile objects are anchored bottom-left
  return GameDecorationWithCollision.withSprite(
    sprite: Sprite.load('maps/buildings/$id.png'),
    position: topLeft,
    size: Vector2(d.w, d.h),
    collisions: [RectangleHitbox(
      position: Vector2(d.collision.left, d.collision.top),
      size: Vector2(d.collision.width, d.collision.height),
      isSolid: true)],
  );
},
```
Copy the PNGs to `assets/images/maps/buildings/` and add that folder to `pubspec.yaml` `assets:`. For a door
trigger, add a sensor component at `topLeft + Vector2(d.door.dx, d.door.dy)`. If you put the collision rect into the
map yourself as a `collision`-class object, keep it at least 2 tiles thick.

Bonfire indexes collection-of-images tiles by list position (`tiles[index - firstgid]`), so the ids in
`buildings.tsj` must stay contiguous from 0 in list order. If you edit the tileset in Tiled, don't delete tiles
from the middle.

## Known quirks
- The ranger cabin and ruin shrine bases are irregular (grass tufts, rubble, crystals). Their bottom row is only
  partly opaque, so the visible base reads a few px above the canvas bottom edge.
- The enclosed background pockets in the source (between the cabin, its log pile and the mushrooms) are kept transparent.
