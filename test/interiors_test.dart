import 'dart:io';
import 'dart:typed_data';

import 'package:bonfire/bonfire.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/building.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/custom_player.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/bonds.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/day_cycle.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/journal_ui.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/adventure.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/save_service.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/well_rested.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/interiors/room_actions.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/interiors/room_data.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/interiors/room_panel.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/interiors/room_scene.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/interiors/room_services.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/interiors/room_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

RoomData _room(String id) => RoomData.parse(File(RoomData.assetFor(id)).readAsStringSync());

(int, int) _pngSize(String path) {
  final b = ByteData.sublistView(File(path).readAsBytesSync());
  return (b.getUint32(16), b.getUint32(20));
}

class _FakeGame implements BonfireGameInterface {
  _FakeGame(this.context, this.player);
  @override
  final BuildContext context;
  @override
  final Player? player;
  @override
  bool paused = false;
  int pauses = 0, resumes = 0;
  @override
  void pauseEngine() {
    paused = true;
    pauses++;
  }

  @override
  void resumeEngine() {
    paused = false;
    resumes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // SFX/footsteps: no audio plugin under `flutter test`.
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
      m.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SaveService.data = SaveData();
    SaveService.hasSave.value = false;
    SaveService.snapshot = null;
    RoomPanel.close();
    RoomPanel.onOpenChanged = null;
    Journal.open.value = false;
    Journal.onOpenChanged = null;
    RoomDay.resetForTest();
  });

  group('room data', () {
    for (final id in Interiors.rooms) {
      test('$id parses, art matches, every spot and the door are reachable', () {
        final r = _room(id);
        expect(r.id, id);
        expect((r.cols, r.rows, r.tile), (16, 9, 32));
        expect(_pngSize('assets/images/interiors/${r.image}'), (512, 288));
        expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/images/interiors/'));

        final floor = r.reachable();
        expect(floor, contains(r.spawn));
        expect(r.door.contains(r.spawn.$1, r.spawn.$2), isFalse, reason: 'spawn is not on the mat');
        expect(r.door.tiles.any(floor.contains), isTrue, reason: 'doormat reachable');
        // Spawn sits right above the mat.
        expect(r.door.contains(r.spawn.$1, r.spawn.$2 + 1), isTrue);
        expect(floor.length, greaterThanOrEqualTo(20));

        for (final s in r.spots) {
          expect(RoomSpot.kinds, contains(s.kind), reason: s.id);
          expect(r.spotReachable(s, floor), isTrue, reason: '${s.id} reachable');
        }
        for (final n in r.npcs) {
          final sheet = File('assets/images/sprites/${n.sprite}_walk.png');
          final still = File('assets/images/sprites/npc_${n.sprite}.png');
          expect(sheet.existsSync() || still.existsSync(), isTrue, reason: n.sprite);
          expect(r.solid(n.tx, n.ty), isTrue, reason: 'NPC tile blocks');
        }
        for (final l in r.lights) {
          expect(['warm', 'fire', 'neon', 'cyan'], contains(l.kind));
          expect(r.inBounds(l.tx, l.ty), isTrue);
        }
      });
    }

    test('rooms have the people and spots from the brief', () {
      expect(_room('tea_house').npcs.map((n) => n.sprite), ['wen', 'ferro']);
      expect(_room('tea_house').spots.map((s) => s.kind), contains('rest'));
      expect(_room('noodle_shop').npcs.single.sprite, 'dao');
      expect(_room('archive_library').npcs.single.sprite, 'archivist');
      expect(_room('archive_library').spots.where((s) => s.kind == 'lore' || s.kind == 'clue'), hasLength(3));
      expect(_room('ranger_cabin').npcs, isEmpty);
      expect(_room('ranger_cabin').spots.map((s) => s.kind).toSet(),
          containsAll(['note', 'stash', 'journal', 'map']));
      for (final n in ['wen', 'ferro', 'dao']) {
        expect(_pngSize('assets/images/sprites/${n}_walk.png'), (192, 128));
        expect(_pngSize('assets/images/sprites/npc_$n.png'), (30, 30));
      }
    });

    test('facing rule: next to a rect and facing it', () {
      final r = _room('ranger_cabin');
      final map = r.spots.firstWhere((s) => s.id == 'wall_map').rect; // [6,0,3,3]
      expect(r.stepInto(map, 7, 3), (0, -1));
      expect(RoomSpotComponent.facing(Direction.up, (0, -1)), isTrue);
      expect(RoomSpotComponent.facing(Direction.down, (0, -1)), isFalse);
      expect(r.stepInto(map, 7, 5), isNull);
    });
  });

  group('every spot does something', () {
    for (final id in Interiors.rooms) {
      test(id, () {
        final r = _room(id);
        for (final s in r.spots) {
          RoomPanel.close();
          Journal.open.value = false;
          useSpot(r, s);
          expect(RoomPanel.isOpen || Journal.open.value, isTrue, reason: s.id);
          final d = RoomPanel.current.value;
          if (d != null) {
            expect(d.pages, isNotEmpty, reason: s.id);
            for (final p in d.pages) {
              expect(p.trim(), isNotEmpty, reason: s.id);
            }
          }
        }
      });
    }

    test('lines are GameConcept text (stove: lit fire version)', () {
      final r = _room('ranger_cabin');
      useSpot(r, r.spots.firstWhere((s) => s.id == 'stove'));
      expect(RoomPanel.current.value!.pages.single, RoomText.stove);
      expect(RoomText.stove, startsWith('A low fire, still crackling.'));
      RoomPanel.close();
      final t = _room('tea_house');
      useSpot(t, t.spots.firstWhere((s) => s.id == 'wen'));
      expect(RoomPanel.current.value!.pages.single, RoomText.wenFirst);
      RoomPanel.close();
      useSpot(t, t.spots.firstWhere((s) => s.id == 'wen'));
      expect(RoomPanel.current.value!.pages.single, RoomText.wenLater);
    });
  });

  group('services', () {
    test('Dao: meals cost glimmer, buff, expire; errand gives a free bowl tomorrow', () {
      Bonds.addGlimmer(10);
      expect(Meals.order('night_bowl'), isNull);
      expect(Bonds.glimmer, 2);
      expect(Meals.isActive('night_bowl'), isTrue);
      expect(Meals.order('ember_broth'), isNotNull, reason: 'too poor');
      Meals.tick(500);
      expect(Meals.active.value, isNull);

      expect(DaoErrand.canAsk, isTrue);
      DaoErrand.accept();
      expect(DaoErrand.wantsFlower, isTrue);
      DaoErrand.pick();
      expect(Bonds.hasItem(DaoErrand.item), isTrue);
      expect(DaoErrand.deliver(), isTrue);
      expect(Bonds.hasItem(DaoErrand.item), isFalse);
      expect(DaoErrand.canAsk, isFalse, reason: 'once a day');
      expect(Meals.freeBowlToday, isFalse);
      RoomDay.observe(0.9);
      RoomDay.observe(0.05); // midnight
      expect(RoomDay.today, 1);
      expect(Meals.freeBowlToday, isTrue);
      expect(Meals.order('ember_broth'), isNull);
      expect(Bonds.glimmer, 2, reason: 'free');
      expect(Meals.regenMultiplier, Meals.regenBoost);
      expect(Meals.freeBowlToday, isFalse);
      expect(DaoErrand.canAsk, isTrue, reason: 'new day, new errand');
    });

    test('meal survives a save round-trip', () {
      Bonds.addGlimmer(6);
      Meals.order('moss_noodles');
      Meals.tick(10.2);
      final copy = SaveData.fromJson(SaveService.data.toJson());
      SaveService.data = copy;
      expect(Meals.isActive('moss_noodles'), isTrue);
      expect(Meals.remaining.value, closeTo(110, 1));
      expect(Meals.speedMultiplier, Meals.speedBoost);
    });

    test('stash banks glimmer', () {
      Bonds.addGlimmer(9);
      expect(Stash.depositAll(), 9);
      expect(Bonds.glimmer, 0);
      expect(Stash.stored, 9);
      expect(Stash.withdrawAll(), 9);
      expect(Bonds.glimmer, 9);
      expect(Stash.stored, 0);
    });

    test('inn rest: morning, full HP, well rested, checkpoint at the door', () async {
      DayCycle.time.value = 0.5;
      CustomPlayer.healthNotifier.value = 10;
      var checkpointed = false;
      InnRest.setCheckpoint = () => checkpointed = true;
      await InnRest.rest();
      InnRest.setCheckpoint = null;
      expect(DayCycle.time.value, 0.3);
      expect(RoomDay.today, 1);
      expect(CustomPlayer.healthNotifier.value, CustomPlayer.maxHealth);
      expect(checkpointed, isTrue);
      expect(WellRested.active, isTrue);
      expect(SaveService.data.extra['wellRested'], WellRested.duration);
    });

    test('archive enterable only after the seal; locked doors keep their lines', () {
      expect(Interiors.canEnter('tea_house'), isTrue);
      expect(Interiors.canEnter('archive_library'), isFalse);
      Adventure.setFlag('archive_opened');
      expect(Interiors.canEnter('archive_library'), isTrue);
      for (final id in ['apartment_block', 'greenhouse', 'ruin_shrine']) {
        expect(Interiors.canEnter(id), isFalse);
        expect(RoomText.lockedDoors[id], isNotEmpty);
      }
      expect(Adventure.catalog.map((c) => c.id), contains(fieldNotesClue));
    });
  });

  test('door front is just outside the wall base, at the door prompt', () {
    for (final e in buildingDefs.entries) {
      final def = e.value;
      final topLeft = Vector2(320, 480);
      final front = Interiors.doorFrontFor(topLeft, def);
      // Feet hitbox (as CustomPlayer) clears the building's solid box.
      final feetTop = front.y + CustomPlayer.sizePlayer * 0.65;
      expect(feetTop, greaterThan(topLeft.y + def.collision.bottom), reason: e.key);
      final centre = front + Vector2.all(CustomPlayer.sizePlayer / 2);
      final prompt = topLeft + Vector2(def.door.dx, def.door.dy + 8);
      expect(centre.distanceTo(prompt), lessThan(4), reason: e.key);
    }
  });

  testWidgets('door round-trip: E fades in, the doormat fades back to the door', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: Text('OUTSIDE'));
      }),
    ));
    final kaela = CustomPlayer(Vector2(5, 5))..lastDirection = Direction.up;
    final game = _FakeGame(ctx, kaela);
    final front = Vector2(100, 200);
    var back = false;
    await tester.runAsync(() async {
      await Interiors.load('tea_house');
    });
    Interiors.enterAt(game, 'tea_house', front).then((_) => back = true);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(RoomScreen), findsOneWidget);
    expect(Interiors.current.value?.id, 'tea_house');
    expect(game.paused, isTrue);
    expect(kaela.position, front, reason: 'saved in front of the door');

    Interiors.leave(); // what stepping on the doormat does
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(back, isTrue);
    expect(find.byType(RoomScreen), findsNothing);
    expect(find.text('OUTSIDE'), findsOneWidget);
    expect(game.paused, isFalse);
    expect((game.pauses, game.resumes), (1, 1));
    expect(kaela.position, front);
    expect(kaela.lastDirection, Direction.down);
    expect(Interiors.current.value, isNull);
  });
}
