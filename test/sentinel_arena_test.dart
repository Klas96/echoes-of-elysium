import 'dart:io';
import 'dart:ui' as ui;

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

  group('SentinelDrone.resetEncounter', () {
    tearDown(() {
      SentinelArena.instance = null;
      SentinelDrone.instance = null;
    });

    test('no-ops when the fight was never started', () {
      final s = SentinelDrone(Vector2(10, 20), onDefeated: () {});
      expect(s.isEngaged, isFalse);
      s.resetEncounter();
      expect(s.isEngaged, isFalse);
      expect(s.health, s.maxHealth);
      expect(s.phase, 1);
    });

    test('restores idle HP/phase and opens a sealed arena', () {
      final arena = SentinelArena(Vector2(100, 200));
      SentinelArena.instance = arena;
      arena.sealed = true;

      final origin = Vector2(80, 180);
      final s = SentinelDrone(origin, onDefeated: () {});
      s.position = origin + Vector2(40, 20);
      s.debugMarkEngaged(health: (s.maxHealth * 0.25).round());
      expect(s.isEngaged, isTrue);
      expect(s.phase, 3);

      s.resetEncounter();

      expect(s.isEngaged, isFalse);
      expect(s.health, s.maxHealth);
      expect(s.phase, 1);
      expect(s.position, origin);
      expect(arena.sealed, isFalse);
    });
  });

  group('Sentinel arena hard-pixel art (#65)', () {
    Future<(int, int)> dims(String path) async {
      final codec =
          await ui.instantiateImageCodec(File(path).readAsBytesSync());
      final image = (await codec.getNextFrame()).image;
      return (image.width, image.height);
    }

    Future<void> expectSize(
        WidgetTester tester, String path, int w, int h) async {
      await tester.runAsync(() async {
        expect(File(path).existsSync(), isTrue, reason: path);
        expect(await dims(path), (w, h), reason: path);
      });
    }

    testWidgets('lockdown + telegraph sprites are hard pixel sizes',
        (tester) async {
      const sprites = 'assets/images/sprites';
      await expectSize(tester, '$sprites/sentinel_fence.png', 32, 32);
      await expectSize(tester, '$sprites/sentinel_pylon.png', 32, 32);
      await expectSize(tester, '$sprites/sentinel_rim.png', 32, 32);
      await expectSize(tester, '$sprites/fx/sentinel_slam_tele.png', 160, 160);
      await expectSize(tester, '$sprites/fx/sentinel_sweep_tele.png', 128, 128);
      await expectSize(tester, '$sprites/fx/sentinel_ring_tell.png', 64, 64);
    });
  });
}
