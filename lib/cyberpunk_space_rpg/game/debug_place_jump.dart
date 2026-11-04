import 'package:bonfire/bonfire.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_debug.dart';
import 'travel.dart';

/// One debug warp target (map + spawn, optional interior).
class DebugPlace {
  final String id;
  final String label;
  final String group; // Maps · Interiors · Story
  final String blurb;
  final int level;

  /// Edge spawn side on the dest map (`north` / `south` / `east` / `west`).
  final String? entrySide;

  /// Absolute player top-left in world px (overrides [entrySide] / map spawn).
  final double? spawnX;
  final double? spawnY;

  /// Enter this room after landing (tea_house, pond_grotto, …).
  final String? interiorId;

  const DebugPlace({
    required this.id,
    required this.label,
    required this.group,
    required this.blurb,
    required this.level,
    this.entrySide,
    this.spawnX,
    this.spawnY,
    this.interiorId,
  });
}

/// Debug-only place jumper. Never mounts outside [kDebugMode].
///
/// Open with **F2** while DEBUG is on, or long-press the `` ` DEBUG`` chip.
class DebugPlaceJump {
  DebugPlaceJump._();

  static final open = ValueNotifier<bool>(false);

  /// Consumed once by [_PlayerSpawn] / map ready.
  static Vector2? pendingSpawn;
  static String? pendingInterior;

  static Vector2? takePendingSpawn() {
    final v = pendingSpawn;
    pendingSpawn = null;
    return v;
  }

  static String? takePendingInterior() {
    final v = pendingInterior;
    pendingInterior = null;
    return v;
  }

  static void toggle() {
    if (!kDebugMode || !GameDebug.isOn) return;
    open.value = !open.value;
  }

  static void hide() {
    open.value = false;
  }

  /// F2 while DEBUG is on.
  static bool handleKey(KeyEvent event) {
    if (!kDebugMode || !GameDebug.isOn || event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.f2) {
      toggle();
      return true;
    }
    if (open.value && event.logicalKey == LogicalKeyboardKey.escape) {
      hide();
      return true;
    }
    return false;
  }

  /// Major maps, hubs, interiors, and story-adjacent landings.
  static const places = <DebugPlace>[
    // —— Maps ——
    DebugPlace(
      id: 'woods',
      label: 'Whispering Woods',
      group: 'Maps',
      blurb: 'Skiff wreck · Gaia · default spawn',
      level: 1,
      spawnX: 240,
      spawnY: 272,
    ),
    DebugPlace(
      id: 'woods_south',
      label: 'Woods · City road',
      group: 'Maps',
      blurb: 'South exit toward the City',
      level: 1,
      entrySide: 'south',
    ),
    DebugPlace(
      id: 'city',
      label: 'The City',
      group: 'Maps',
      blurb: 'Neon streets · north spawn',
      level: 2,
      spawnX: 832,
      spawnY: 128,
    ),
    DebugPlace(
      id: 'city_south',
      label: 'City · Ruins road',
      group: 'Maps',
      blurb: 'South edge toward the Ruins',
      level: 2,
      entrySide: 'south',
    ),
    DebugPlace(
      id: 'city_east',
      label: 'City · Town gate',
      group: 'Maps',
      blurb: 'East edge toward Lantern Town',
      level: 2,
      entrySide: 'east',
    ),
    DebugPlace(
      id: 'town',
      label: 'Lantern Town',
      group: 'Maps',
      blurb: 'Quiet market hub',
      level: 5,
      spawnX: 496,
      spawnY: 160,
    ),
    DebugPlace(
      id: 'ruins',
      label: 'The Ruins',
      group: 'Maps',
      blurb: 'Collapsed districts · shrine road',
      level: 3,
      spawnX: 160,
      spawnY: 160,
    ),
    DebugPlace(
      id: 'core',
      label: "Gaia's Core",
      group: 'Maps',
      blurb: 'Sacred chamber · Core Record',
      level: 4,
      spawnX: 464,
      spawnY: 128,
    ),

    // —— Interiors ——
    DebugPlace(
      id: 'int_cabin',
      label: 'Ranger Cabin',
      group: 'Interiors',
      blurb: 'Woods · Asha\'s cabin',
      level: 1,
      interiorId: 'ranger_cabin',
      spawnX: 576,
      spawnY: 280,
    ),
    DebugPlace(
      id: 'int_grotto',
      label: 'Pond Grotto',
      group: 'Interiors',
      blurb: 'Woods · LIGHT cave (forced open)',
      level: 1,
      interiorId: 'pond_grotto',
      spawnX: 1152,
      spawnY: 400,
    ),
    DebugPlace(
      id: 'int_tea_city',
      label: 'Tea House (City)',
      group: 'Interiors',
      blurb: 'Wen · Ferro · rest bed',
      level: 2,
      interiorId: 'tea_house',
      spawnX: 1248,
      spawnY: 280,
    ),
    DebugPlace(
      id: 'int_archive',
      label: 'Archive Library',
      group: 'Interiors',
      blurb: 'City · stacks (forced unlock)',
      level: 2,
      interiorId: 'archive_library',
      spawnX: 960,
      spawnY: 640,
    ),
    DebugPlace(
      id: 'int_noodle_city',
      label: 'Noodle Shop (City)',
      group: 'Interiors',
      blurb: 'City · Dao\'s counter',
      level: 2,
      interiorId: 'noodle_shop',
      spawnX: 160,
      spawnY: 280,
    ),
    DebugPlace(
      id: 'int_tea_town',
      label: 'Tea House (Town)',
      group: 'Interiors',
      blurb: 'Lantern Town twin',
      level: 5,
      interiorId: 'tea_house',
      spawnX: 96,
      spawnY: 400,
    ),
    DebugPlace(
      id: 'int_noodle_town',
      label: 'Noodle Shop (Town)',
      group: 'Interiors',
      blurb: 'Lantern Town twin',
      level: 5,
      interiorId: 'noodle_shop',
      spawnX: 864,
      spawnY: 280,
    ),

    // —— Story beats (map + spawn near the moment) ——
    DebugPlace(
      id: 'story_gaia',
      label: 'Gaia (woods)',
      group: 'Story',
      blurb: 'Opening hologram by the wreck',
      level: 1,
      spawnX: 320,
      spawnY: 240,
    ),
    DebugPlace(
      id: 'story_asha',
      label: 'Asha camp',
      group: 'Story',
      blurb: 'Woods friends · first bond',
      level: 1,
      spawnX: 736,
      spawnY: 1024,
    ),
    DebugPlace(
      id: 'story_archivist',
      label: 'Archivist',
      group: 'Story',
      blurb: 'City mid · post-Sentinel road',
      level: 2,
      spawnX: 800,
      spawnY: 560,
    ),
    DebugPlace(
      id: 'story_sentinel',
      label: 'Sentinel arena',
      group: 'Story',
      blurb: 'City south checkpoint zone',
      level: 2,
      spawnX: 800,
      spawnY: 1180,
    ),
    DebugPlace(
      id: 'story_shrine',
      label: 'Ruin shrine',
      group: 'Story',
      blurb: 'Ruins · examine the shrine',
      level: 3,
      spawnX: 320,
      spawnY: 1200,
    ),
    DebugPlace(
      id: 'story_core_gaia',
      label: 'Core · Gaia',
      group: 'Story',
      blurb: 'Before the Core Record',
      level: 4,
      spawnX: 448,
      spawnY: 600,
    ),
  ];

  static List<String> get groups {
    final seen = <String>{};
    final out = <String>[];
    for (final p in places) {
      if (seen.add(p.group)) out.add(p.group);
    }
    return out;
  }

  static TravelDest? asTravelDest(DebugPlace p) => Travel.byLevel(p.level);
}

typedef DebugPlaceWarp = Future<void> Function(BuildContext context, DebugPlace place);

/// Scrollable warp menu. Parent must only mount this in [kDebugMode].
class DebugPlaceJumpPanel extends StatelessWidget {
  final DebugPlaceWarp onWarp;
  const DebugPlaceJumpPanel({super.key, required this.onWarp});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DebugPlaceJump.open,
      builder: (_, show, __) {
        if (!show) return const SizedBox.shrink();
        return Positioned.fill(
          child: Material(
            color: Colors.black54,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xF0080C10),
                      border: Border.all(color: const Color(0xFF00FF88), width: 1.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'DEBUG · PLACE JUMP',
                                  style: TextStyle(
                                    color: Color(0xFF00FF88),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: DebugPlaceJump.hide,
                                child: const Text('CLOSE',
                                    style: TextStyle(
                                        color: Colors.white54, letterSpacing: 1)),
                              ),
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            'F2 · long-press DEBUG chip · skips story gates / cutscenes',
                            style: TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            children: [
                              for (final group in DebugPlaceJump.groups) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                                  child: Text(
                                    group.toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xFF66FFAA),
                                      fontSize: 11,
                                      letterSpacing: 2,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                for (final p in DebugPlaceJump.places
                                    .where((e) => e.group == group))
                                  _PlaceTile(
                                    place: p,
                                    onTap: () => onWarp(context, p),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlaceTile extends StatelessWidget {
  final DebugPlace place;
  final VoidCallback onTap;
  const _PlaceTile({required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: const Color(0xFF12181E),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  place.blurb,
                  style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
