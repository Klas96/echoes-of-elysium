import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/ambient_prop_fx.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/adventure.dart';
import 'package:flutter_test/flutter_test.dart';

/// Designer's art batch for #24 #25 #28 #29 #33 #34: files exist with the
/// sizes the code slices them at.
void main() {
  Future<(int, int)> dims(String path) async {
    final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
    final image = (await codec.getNextFrame()).image;
    return (image.width, image.height);
  }

  const sprites = 'assets/images/sprites';

  Future<void> expectSize(WidgetTester tester, String path, int w, int h) async {
    await tester.runAsync(() async {
      expect(File(path).existsSync(), isTrue, reason: path);
      expect(await dims(path), (w, h), reason: path);
    });
  }

  testWidgets('Kaela shoot sheet is 4x4 frames of 32px (#24)', (tester) async {
    await expectSize(tester, '$sprites/kaela_shoot.png', 128, 128);
  });

  testWidgets('key item icons, drops and sparkles (#25)', (tester) async {
    for (final id in itemsWithArt) {
      await expectSize(tester, '$sprites/items/$id.png', 32, 32);
      await expectSize(tester, '$sprites/items/${id}_16.png', 16, 16);
      await expectSize(tester, '$sprites/items/${id}_drop.png', 32, 32);
      await expectSize(tester, '$sprites/items/${id}_drop_sparkle.png', 64, 32);
      expect(itemIconAsset(id), '$sprites/items/$id.png');
      expect(itemIconAsset(id, small: true), '$sprites/items/${id}_16.png');
      expect(itemDropSparkle(id), 'sprites/items/${id}_drop_sparkle.png');
    }
  });

  test('every item the game hands out has a journal label (#25)', () {
    for (final id in ['uec_override', 'archive_seal', 'ruins_gate_key', 'moonflower_bloom', 'sweetroot', 'pebble']) {
      expect(itemLabels[id], isNotNull, reason: id);
    }
    expect(itemsWithArt.every(itemLabels.containsKey), isTrue);
    expect(File(itemIconAsset('pebble')!).existsSync(), isTrue);
    expect(File(itemIconAsset('sweetroot')!).existsSync(), isTrue);
  });

  testWidgets('UEC drone sprites per kind + Sentinel (#28)', (tester) async {
    for (final k in ['scout', 'shield', 'sniper', 'swarm']) {
      await expectSize(tester, '$sprites/uec_$k.png', 32, 32);
      await expectSize(tester, '$sprites/uec_${k}_hover.png', 64, 32);
    }
    await expectSize(tester, '$sprites/sentinel_boss.png', 64, 64);
    final src = File('lib/cyberpunk_space_rpg/components/uec_drone.dart').readAsStringSync();
    for (final k in ['scout', 'shield', 'sniper', 'swarm']) {
      expect(src, contains("'sprites/uec_$k.png'"), reason: k);
    }
  });

  testWidgets('Mira has her own walk sheet and Lantern Town uses it (#29)', (tester) async {
    await expectSize(tester, '$sprites/mira_walk.png', 192, 128);
    await expectSize(tester, '$sprites/npc_mira.png', 30, 30);
    final tmj = jsonDecode(File('assets/images/maps/world5.tmj').readAsStringSync()) as Map;
    final npcs = [
      for (final l in (tmj['layers'] as List).cast<Map>())
        for (final o in (l['objects'] as List? ?? const []).cast<Map>())
          if (o['name'] == 'npc') {for (final p in (o['properties'] as List).cast<Map>()) p['name']: p['value']}
    ];
    final mira = npcs.singleWhere((p) => p['name'] == 'mira');
    expect(mira['sprite'], 'mira');
  });

  testWidgets('ambient FX loops match their json (#33)', (tester) async {
    for (final kind in ['steam', 'smoke', 'ember', 'fire', 'mist']) {
      for (final cyan in [false, true]) {
        final sheet = AmbientPropFx.sheetFor(kind, cyan: cyan);
        final meta = jsonDecode(File('$sprites/fx/$sheet.json').readAsStringSync()) as Map;
        await expectSize(tester, '$sprites/fx/$sheet.png', (meta['frameWidth'] as int) * (meta['frames'] as int),
            meta['frameHeight'] as int);
      }
    }
    expect(AmbientPropFx.sheetFor('steam', cyan: true), 'steam_loop_cyan');
    expect(AmbientPropFx.sheetFor('ember'), 'fire_loop');
  });

  testWidgets('story gate closed / open / pulse art (#34)', (tester) async {
    await expectSize(tester, '$sprites/obstacles/story_gate.png', 96, 96);
    await expectSize(tester, '$sprites/obstacles/story_gate_open.png', 96, 96);
    await expectSize(tester, '$sprites/obstacles/story_gate_pulse.png', 192, 96);
  });

  test('new asset folders are listed in pubspec', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    for (final d in ['fx', 'items', 'obstacles']) {
      expect(pub, contains('- assets/images/sprites/$d/'), reason: d);
    }
  });
}
