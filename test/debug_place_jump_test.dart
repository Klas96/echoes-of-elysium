import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/debug_place_jump.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/game_state.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/interiors/room_scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug place catalog covers maps, interiors, story', () {
    expect(DebugPlaceJump.places, isNotEmpty);
    expect(DebugPlaceJump.groups, ['Maps', 'Interiors', 'Story']);

    final ids = DebugPlaceJump.places.map((p) => p.id).toSet();
    expect(ids.length, DebugPlaceJump.places.length, reason: 'unique ids');

    for (final p in DebugPlaceJump.places) {
      expect(GameState.mapIds.containsKey(p.level), isTrue,
          reason: '${p.id} level ${p.level}');
      if (p.interiorId != null) {
        expect(Interiors.rooms, contains(p.interiorId),
            reason: '${p.id} interior');
      }
      if (p.entrySide != null) {
        expect(['north', 'south', 'east', 'west'], contains(p.entrySide));
      }
      if (p.spawnX != null) {
        expect(p.spawnY, isNotNull);
      }
    }

    // One landing per major overworld map.
    for (final level in GameState.mapIds.keys) {
      expect(
        DebugPlaceJump.places.any((p) => p.level == level && p.group == 'Maps'),
        isTrue,
        reason: 'Maps entry for level $level',
      );
    }
  });
}
