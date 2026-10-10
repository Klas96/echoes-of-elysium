import 'dart:convert';
import 'dart:io';

import 'package:bonfire/bonfire.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/lamp_light.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/day_cycle.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> _lights(String map) {
  final d = jsonDecode(File('assets/images/maps/$map.tmj').readAsStringSync()) as Map<String, dynamic>;
  final out = <Map<String, dynamic>>[];
  for (final l in d['layers'] as List) {
    if (l['type'] != 'objectgroup') continue;
    for (final o in l['objects'] as List) {
      if (o['name'] != 'light') continue;
      final props = {for (final p in o['properties'] as List) p['name']: p['value']};
      out.add({...o as Map<String, dynamic>, 'props': props});
    }
  }
  return out;
}

void main() {
  group('night lights (#35)', () {
    test('maps carry light objects next to lamps, lanterns and fires', () {
      final city = _lights('world2');
      final town = _lights('world5');
      final woods = _lights('world');
      expect(city.where((l) => l['props']['kind'] == 'lamp'), isNotEmpty);
      expect(town.where((l) => l['props']['kind'] == 'lamp'), isNotEmpty);
      expect(woods.where((l) => l['props']['kind'] == 'lantern'), isNotEmpty);
      expect(woods.where((l) => l['props']['kind'] == 'fire'), isNotEmpty);
      for (final l in [...city, ...town, ...woods]) {
        expect((l['props']['radius'] as num) > 32, isTrue);
        expect(LightKindStyle.parse(l['props']['kind'] as String).name, l['props']['kind']);
      }
    });

    test('City street lamps are cyan neon, Town/Woods warm (designer art)', () {
      final city = _lights('world2').where((l) => l['props']['kind'] == 'lamp');
      final town = _lights('world5').where((l) => l['props']['kind'] == 'lamp');
      expect(city.every((l) => l['props']['style'] == 'neon'), isTrue);
      expect(town.every((l) => l['props']['style'] == null), isTrue);
      expect(NightLights.styleFor(LightKind.lamp, 'neon'), 'neon');
      expect(NightLights.styleFor(LightKind.lamp, ''), 'warm');
      expect(NightLights.styleFor(LightKind.lantern, ''), 'warm');
      expect(NightLights.styleFor(LightKind.energy, ''), 'neon');
      // Magenta ruins neon reuses the warm rings, recoloured.
      expect(NightLights.artMatches(LightKind.neon, 'warm'), isFalse);
      expect(NightLights.artMatches(LightKind.lamp, 'warm'), isTrue);
      for (final files in NightLights.artAssets.values) {
        for (final f in files) {
          expect(File(f).existsSync(), isTrue, reason: f);
        }
      }
    });

    test('no glow by day, full glow in deep night', () {
      for (final t in [0.3, 0.5, 0.7]) {
        expect(DayCycle.darkness(t), 0);
        expect(NightLights.strength(DayCycle.darkness(t), LightKind.lamp, 1, 3), 0);
      }
      final s = NightLights.strength(DayCycle.darkness(0.95), LightKind.lamp, 1, 3);
      expect(s, greaterThan(0.9));
      // dusk is in between
      final dusk = NightLights.strength(DayCycle.darkness(0.78), LightKind.lamp, 1, 3);
      expect(dusk, greaterThan(0));
      expect(dusk, lessThan(s));
    });

    test('fire flickers more than a street lamp but stays bounded', () {
      double spread(LightKind k) {
        var lo = 1.0, hi = 0.0;
        for (var i = 0; i < 400; i++) {
          final v = NightLights.strength(1, k, 0.4, i * 0.05);
          lo = v < lo ? v : lo;
          hi = v > hi ? v : hi;
          expect(v, inInclusiveRange(0, 1));
        }
        return hi - lo;
      }

      expect(spread(LightKind.fire), greaterThan(spread(LightKind.lamp)));
    });

    test('world to screen follows the camera and zoom', () {
      const screen = Size(412, 915);
      final cam = Vector2(500, 400);
      final r = NightLights.screenRect(Vector2(500, 400), 80, cam, 2, screen);
      expect(r.center.dx, closeTo(206, 1e-6));
      expect(r.center.dy, closeTo(457.5, 1e-6));
      expect(r.width, 320);
      expect(r.height, closeTo(320 * NightLights.squash, 1e-6));
      final moved = NightLights.screenRect(Vector2(540, 400), 80, cam, 2, screen);
      expect(moved.center.dx - r.center.dx, closeTo(80, 1e-6));
    });

    test('procedural cookie: bright centre, banded falloff, clear edge', () {
      const n = NightLights.cookieSize;
      final centre = NightLights.cookieAlpha(n ~/ 2, n ~/ 2);
      expect(centre, greaterThan(0.8));
      expect(NightLights.cookieAlpha(0, 0), 0);
      expect(NightLights.cookieAlpha(0, n ~/ 2), lessThan(0.2));
      final levels = <double>{for (var x = 0; x < n; x++) NightLights.cookieAlpha(x, n ~/ 2)};
      expect(levels.length, lessThanOrEqualTo(9)); // hard pixel bands, no smooth ramp
    });
  });
}
