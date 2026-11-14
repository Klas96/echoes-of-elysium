import 'package:bonfire/bonfire.dart';
import 'package:bonfire/map/util/map_assets_manager.dart';

import '../creatures/day_cycle.dart';

/// Day ↔ night tilesheet swap (EOE-99).
///
/// Night sheets are the day art with [DayCycle.tint] baked in
/// (`tools/tilesets/bake_night_tilesets.py`). At nightfall every cached
/// map [Sprite] retargets its [Sprite.image] to the night twin; dawn
/// restores the day image. Same src rects / collision — only pixels change.
///
/// Light-fixture tiles stay day-bright in the night sheets so lanterns still
/// read as lit without a HUD redraw over Kaela. Glow cookies stay in-world.
class NightTilesets {
  NightTilesets._();

  /// Overworld sheets keyed by Flame path (under `assets/images/`).
  static const sheets = <String, String>{
    'maps/tilesets/woods.png': 'maps/tilesets/woods_night.png',
    'maps/tilesets/city.png': 'maps/tilesets/city_night.png',
    'maps/tilesets/cyberpunk.png': 'maps/tilesets/cyberpunk_night.png',
    'maps/tilesets/core.png': 'maps/tilesets/core_night.png',
    'maps/tilesets/junkyard.png': 'maps/tilesets/junkyard_night.png',
  };

  /// Building props (individual tile images in the `buildings` tileset).
  static const buildings = <String, String>{
    'maps/buildings/apartment_block.png':
        'maps/buildings/apartment_block_night.png',
    'maps/buildings/archive_library.png':
        'maps/buildings/archive_library_night.png',
    'maps/buildings/greenhouse.png': 'maps/buildings/greenhouse_night.png',
    'maps/buildings/noodle_shop.png': 'maps/buildings/noodle_shop_night.png',
    'maps/buildings/ranger_cabin.png': 'maps/buildings/ranger_cabin_night.png',
    'maps/buildings/ruin_shrine.png': 'maps/buildings/ruin_shrine_night.png',
    'maps/buildings/tea_house.png': 'maps/buildings/tea_house_night.png',
  };

  static Map<String, String> get pairs => {...sheets, ...buildings};

  static bool _loaded = false;
  static bool _night = false;

  /// Whether cached sprites currently point at night sheets.
  static bool get night => _night;

  /// Nightfall gate used for the swap (same as [DayCycle.isNight]).
  static bool shouldBeNight([double? t]) => DayCycle.isNight(t ?? DayCycle.time.value);

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    for (final e in pairs.entries) {
      await Flame.images.load(e.key);
      await Flame.images.load(e.value);
    }
    _loaded = true;
  }

  /// Retarget every map sprite that uses a known day sheet.
  /// Safe every frame: only writes when a sprite still points at the wrong
  /// image (covers tiles cached after the first night sync).
  static void apply(bool night) {
    if (!_loaded) return;
    _night = night;
    for (final e in pairs.entries) {
      final dayImg = Flame.images.fromCache(e.key);
      final nightImg = Flame.images.fromCache(e.value);
      final target = night ? nightImg : dayImg;
      final prefix = '${e.key}/';
      for (final entry in MapAssetsManager.spriteCache.entries) {
        if (entry.key.startsWith(prefix) &&
            !identical(entry.value.image, target)) {
          entry.value.image = target;
        }
      }
    }
  }

  /// Sync to [DayCycle] — call from DayClock / map mount.
  static void syncToCycle([double? t]) => apply(shouldBeNight(t));

  /// Tests / map teardown.
  static void reset() {
    _night = false;
    _loaded = false;
  }
}
