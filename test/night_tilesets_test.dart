import 'dart:io';

import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/day_cycle.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/night_tilesets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('night tilesets (EOE-99)', () {
    test('every day sheet has a baked night twin on disk', () {
      for (final e in NightTilesets.pairs.entries) {
        expect(File('assets/images/${e.key}').existsSync(), isTrue, reason: e.key);
        expect(File('assets/images/${e.value}').existsSync(), isTrue, reason: e.value);
        expect(e.value, contains('_night.png'));
      }
      expect(NightTilesets.sheets.length, 5);
      expect(NightTilesets.buildings.length, 7);
    });

    test('swap follows DayCycle.isNight (nightfall / dawn)', () {
      expect(NightTilesets.shouldBeNight(0.5), isFalse);
      expect(NightTilesets.shouldBeNight(0.79), isFalse);
      expect(NightTilesets.shouldBeNight(DayCycle.nightStart), isTrue);
      expect(NightTilesets.shouldBeNight(0.0), isTrue);
      expect(NightTilesets.shouldBeNight(DayCycle.nightEnd - 0.01), isTrue);
      expect(NightTilesets.shouldBeNight(DayCycle.nightEnd), isFalse);
    });

    test('DayCycle.tint still describes the bake colour', () {
      final tint = DayCycle.tint(0.0);
      expect(tint.a, closeTo(0.46, 0.01));
      expect(tint.r * 255, closeTo(0x0A, 1));
      expect(tint.g * 255, closeTo(0x12, 1));
      expect(tint.b * 255, closeTo(0x36, 1));
    });
  });
}
