import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Layout pass #26 moved the roads, not the travel API: every edge exit must
/// stay on the same side of its map, lead to the same place, and land on an
/// arrival pad that exists on the far side.
void main() {
  List<Map> objects(String map) {
    final tmj = jsonDecode(File('assets/images/maps/$map.tmj').readAsStringSync()) as Map;
    final layer = (tmj['layers'] as List).firstWhere((l) => l['name'] == 'gameplay') as Map;
    return (layer['objects'] as List).cast<Map>();
  }

  Map<String, dynamic> props(Map o) =>
      {for (final p in (o['properties'] as List? ?? [])) p['name'] as String: p['value']};

  String sideOf(String map, Map o) {
    final tmj = jsonDecode(File('assets/images/maps/$map.tmj').readAsStringSync()) as Map;
    final w = (tmj['width'] as int) * 32.0, h = (tmj['height'] as int) * 32.0;
    final x = (o['x'] as num).toDouble(), y = (o['y'] as num).toDouble();
    if (y <= 0) return 'north';
    if (x <= 0) return 'west';
    if (y + (o['height'] as num) >= h) return 'south';
    if (x + (o['width'] as num) >= w) return 'east';
    return 'inside';
  }

  const files = {'woods': 'world', 'city': 'world2', 'ruins': 'world3', 'town': 'world5'};
  // map -> {exit side: (dest, entry side on dest)}
  const expected = {
    'world': {'south': ('city', 'north')},
    'world2': {'north': ('woods', 'south'), 'south': ('ruins', 'north'), 'east': ('town', 'west')},
    'world5': {'west': ('city', 'east')},
    'world3': {'north': ('city', 'south')},
  };

  for (final MapEntry(key: map, value: exits) in expected.entries) {
    test('$map edge exits keep their sides and destinations', () {
      final found = {
        for (final o in objects(map).where((o) => o['name'] == 'mapexit'))
          sideOf(map, o): (props(o)['dest'] as String, props(o)['entry'] as String),
      };
      expect(found, exits);
      for (final (dest, entry) in exits.values) {
        final pads = objects(files[dest]!).where((o) => o['name'] == 'entry').map((o) => props(o)['side']);
        expect(pads, contains(entry), reason: '$dest needs an arrival pad for $entry');
      }
    });
  }
}
