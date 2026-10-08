import 'package:bonfire/bonfire.dart';
import 'package:bonfire/map/tiled/builder/tiled_world_builder.dart' show ObjectBuilder;

/// A Tiled map (.tmj with embedded tilesets). Walls come from the tilesets'
/// per-tile collision rects, which Bonfire turns into TileWithCollision, so
/// BlockMovementCollision on the player handles blocking and sliding.
/// Gameplay objects in the map's object layer are built by [objectsBuilder],
/// keyed by object name (spawn, portal, npc, fragment, health, drone, sentinel,
/// checkpoint, building). Drones take an optional Tiled `kind` property:
/// scout | sniper | shield | swarm.
class CustomMap extends WorldMapByTiled {
  CustomMap(
    String tmjPath, {
    Map<String, ObjectBuilder>? objectsBuilder,
  }) : super(
          WorldMapReader.fromAsset(tmjPath),
          forceTileSize: Vector2.all(32),
          objectsBuilder: objectsBuilder,
        );
}
