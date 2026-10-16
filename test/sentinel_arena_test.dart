import 'package:bonfire/bonfire.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/sentinel_arena.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/sentinel_drone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SentinelDrone.phaseForHpRatio', () {
    test('maps HP bands to phases 1–3', () {
      expect(SentinelDrone.phaseForHpRatio(1.0), 1);
      expect(SentinelDrone.phaseForHpRatio(0.61), 1);
      expect(SentinelDrone.phaseForHpRatio(0.6), 2);
      expect(SentinelDrone.phaseForHpRatio(0.31), 2);
      expect(SentinelDrone.phaseForHpRatio(0.3), 3);
      expect(SentinelDrone.phaseForHpRatio(0.0), 3);
    });
  });

  group('SentinelArena', () {
    test('containsWorld is axis-aligned square around center', () {
      final a = SentinelArena(Vector2(100, 200));
      final h = SentinelArena.halfExtent;
      expect(a.containsWorld(Vector2(100, 200)), isTrue);
      expect(a.containsWorld(Vector2(100 + h, 200)), isTrue);
      expect(a.containsWorld(Vector2(100 + h + 1, 200)), isFalse);
      expect(a.containsWorld(Vector2(100, 200 - h - 1)), isFalse);
    });

    test('open is idempotent when never sealed', () {
      final a = SentinelArena(Vector2.zero());
      expect(a.sealed, isFalse);
      a.open();
      expect(a.sealed, isFalse);
    });
  });
}
