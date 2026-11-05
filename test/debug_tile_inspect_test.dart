import 'dart:convert';
import 'dart:io';

import 'package:bonfire/bonfire.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/debug_tile_inspect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(DebugTileInspect.clear);

  test('loads woods map and names walkable prop / ground tiles', () {
    final file = File('assets/images/maps/world.tmj');
    expect(file.existsSync(), isTrue);
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    DebugTileInspect.loadFromJson(data);

    // Walkable crashed_ship prop cell (see props layer gid 217 @ 2,4).
    final propHits = DebugTileInspect.hitsAt(Vector2(2 * 32 + 16, 4 * 32 + 16));
    expect(propHits, isNotEmpty);
    final ship = propHits.firstWhere((h) => h.layer == 'props');
    expect(ship.tileset, 'woods');
    expect(ship.tileId, 216);
    expect(ship.propName, 'crashed_ship');
    expect(ship.label, contains('woods#216'));
    expect(ship.label, contains('crashed_ship'));

    // Spawn is on grass-ish ground around (7.5, 8.5) tiles — 240,272 px.
    final groundHits =
        DebugTileInspect.hitsAt(Vector2(240 + 16, 272 - 16));
    expect(groundHits.any((h) => h.layer == 'ground'), isTrue);
    final ground = groundHits.firstWhere((h) => h.layer == 'ground');
    expect(ground.tileset, 'woods');
    expect(ground.tileId, greaterThanOrEqualTo(0));
    expect(ground.label, contains('woods#'));
  });

  test('empty cell reports no hits', () {
    DebugTileInspect.loadFromJson({
      'width': 2,
      'height': 2,
      'tilesets': [
        {'name': 'woods', 'firstgid': 1, 'tilecount': 10, 'tiles': []},
      ],
      'layers': [
        {
          'type': 'tilelayer',
          'name': 'ground',
          'width': 2,
          'data': [0, 0, 0, 0],
        },
      ],
    });
    expect(DebugTileInspect.hitsAt(Vector2(16, 16)), isEmpty);
  });

  test('label prefers prop name over bare tile id', () {
    DebugTileInspect.loadFromJson({
      'width': 1,
      'height': 1,
      'tilesets': [
        {
          'name': 'woods',
          'firstgid': 1,
          'tilecount': 5,
          'tiles': [
            {
              'id': 2,
              'properties': [
                {'name': 'prop', 'type': 'string', 'value': 'flowers'},
              ],
            },
          ],
        },
      ],
      'layers': [
        {
          'type': 'tilelayer',
          'name': 'props',
          'width': 1,
          'data': [3], // firstgid 1 + id 2
        },
      ],
    });
    final hits = DebugTileInspect.hitsAt(Vector2(8, 8));
    expect(hits, hasLength(1));
    expect(hits.single.label, 'woods#2 · props · flowers');
  });
}
