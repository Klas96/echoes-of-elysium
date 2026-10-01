import 'package:bonfire/bonfire.dart';

class CustomMap extends WorldMapByTiled {
  CustomMap([String tmjPath = 'maps/world.tmj']) : super(
    WorldMapReader.fromAsset(tmjPath),
    forceTileSize: Vector2.all(32),
  );
}
