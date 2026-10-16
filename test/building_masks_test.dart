import 'dart:convert';
import 'dart:io';

import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/building.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/building_masks.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/obstacle_masks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loadFromDisk matches tools/buildings JSON footprints', () {
    BuildingMasks.loadFromDisk();
    final raw = jsonDecode(
            File('tools/buildings/noodle_shop.json').readAsStringSync())
        as Map;
    final c = (raw['collision'] as List).first as Map;
    final expected = Rect.fromLTWH(
      (c['x'] as num).toDouble(),
      (c['y'] as num).toDouble(),
      (c['w'] as num).toDouble(),
      (c['h'] as num).toDouble(),
    );
    expect(buildingDefs['noodle_shop']!.collision, expected);
  });

  test('save writes collision into tools JSON', () async {
    BuildingMasks.loadFromDisk();
    final def = buildingDefs['tea_house']!;
    final before = def.collision;
    def.collision = const Rect.fromLTWH(14, 62, 100, 60);
    final err = await BuildingMasks.save('tea_house');
    expect(err, isNull);
    expect(BuildingMasks.savedPath, contains('tea_house.json'));
    final j = jsonDecode(File(BuildingMasks.savedPath!).readAsStringSync())
        as Map;
    final c = (j['collision'] as List).first as Map;
    expect(c['x'], 14);
    expect(c['y'], 62);
    expect(c['w'], 100);
    expect(c['h'], 60);
    // restore
    def.collision = before;
    await BuildingMasks.save('tea_house');
    // project root helper still works
    expect(ObstacleMasks.projectRoot(), isNotNull);
  });
}
