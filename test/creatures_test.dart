import 'dart:convert';
import 'dart:io';

import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/bonds.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/creature_species.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/day_cycle.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/save_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SaveService.data = SaveData();
    SaveService.hasSave.value = false;
    SaveService.snapshot = null;
  });

  CreatureSpecies sp(String id) => creatureSpecies[id]!;

  group('bond conditions', () {
    test('glowmoth: night and a quiet approach', () {
      expect(checkBond(sp('glowmoth'), const BondContext(isNight: false)).ok, isFalse);
      expect(checkBond(sp('glowmoth'), const BondContext(isNight: true, quiet: false)).ok, isFalse);
      final ok = checkBond(sp('glowmoth'), const BondContext(isNight: true));
      expect(ok.ok, isTrue);
      expect(ok.label, 'BEFRIEND');
    });

    test('vine fox and brookling want their item', () {
      expect(checkBond(sp('vinefox'), const BondContext()).ok, isFalse);
      expect(checkBond(sp('vinefox'), const BondContext(items: {'pebble'})).ok, isFalse);
      expect(checkBond(sp('vinefox'), const BondContext(items: {'sweetroot'})).label, 'OFFER SWEETROOT');
      expect(checkBond(sp('brookling'), const BondContext(items: {'pebble'})).label, 'OFFER RIVER PEBBLE');
      expect(checkBond(sp('brookling'), const BondContext(items: {'sweetroot'})).ok, isFalse);
    });

    test('stone turtle: freeing it from the net is the bond', () {
      final c = checkBond(sp('stoneturtle'), const BondContext(netted: true));
      expect(c.ok, isTrue);
      expect(c.label, 'FREE IT');
    });

    test('puffcap only once it has come out, hushdeer only at night', () {
      expect(checkBond(sp('puffcap'), const BondContext()).ok, isFalse);
      expect(checkBond(sp('puffcap'), const BondContext(emerged: true)).ok, isTrue);
      expect(checkBond(sp('hushdeer'), const BondContext()).ok, isFalse);
      expect(checkBond(sp('hushdeer'), const BondContext(isNight: true)).ok, isTrue);
    });

    test('a failed check is a gentle clue, never empty', () {
      for (final s in creatureSpecies.values) {
        final c = checkBond(s, const BondContext(quiet: false));
        if (!c.ok) expect(c.note, isNotEmpty, reason: s.id);
      }
    });
  });

  group('quiet approach', () {
    test('a nearby shot startles; a distant one does not', () {
      final q = QuietTracker();
      expect(q.onShot(QuietTracker.hearing + 10), isFalse);
      expect(q.quiet, isTrue);
      expect(q.onShot(40), isTrue);
      expect(q.quiet, isFalse);
      for (var i = 0; i < 60; i++) {
        q.tick(0.1, movingClose: false);
      }
      expect(q.quiet, isTrue);
    });

    test('walking right up to it for too long startles it', () {
      final q = QuietTracker();
      q.tick(0.9, movingClose: true);
      expect(q.quiet, isFalse, reason: 'noise builds while moving close');
      final q2 = QuietTracker();
      var startled = false;
      for (var i = 0; i < 20; i++) {
        startled |= q2.tick(0.1, movingClose: true);
      }
      expect(startled, isTrue);
    });

    test('puffcap comes out after 5 s of stillness and hides from footsteps', () {
      final w = StillWatch();
      for (var i = 0; i < 45; i++) {
        w.tick(0.1, near: true, moving: false);
      }
      expect(w.out, isFalse);
      w.tick(0.1, near: true, moving: true); // a step resets the count
      for (var i = 0; i < 49; i++) {
        w.tick(0.1, near: true, moving: false);
      }
      expect(w.out, isFalse);
      for (var i = 0; i < 2; i++) {
        w.tick(0.1, near: true, moving: false);
      }
      expect(w.out, isTrue);
      for (var i = 0; i < 13; i++) {
        w.tick(0.1, near: true, moving: true);
      }
      expect(w.out, isFalse);
    });
  });

  group('day cycle', () {
    test('a day lasts 10 minutes and wraps', () {
      expect(DayCycle.advance(0.5, DayCycle.dayLengthSeconds), closeTo(0.5, 1e-9));
      expect(DayCycle.advance(0.95, 60), closeTo(0.05, 1e-9));
    });

    test('night, rest and tint', () {
      expect(DayCycle.isNight(0.0), isTrue);
      expect(DayCycle.isNight(0.5), isFalse);
      expect(DayCycle.isNight(0.85), isTrue);
      expect(DayCycle.isNight(DayCycle.restTarget(0.5)), isTrue);
      expect(DayCycle.isNight(DayCycle.restTarget(0.9)), isFalse);
      expect(DayCycle.tint(0.5).a, 0);
      expect(DayCycle.tint(0.0).a, greaterThan(0.3));
    });
  });

  group('bonds in the save', () {
    test('befriending fills the journal, unlocks the ability and picks a companion', () {
      expect(Bonds.isSeen('glowmoth'), isFalse);
      expect(Bonds.markSeen('glowmoth'), isTrue);
      expect(Bonds.markSeen('glowmoth'), isFalse);
      Bonds.befriend('puffcap');
      expect(Bonds.active, 'puffcap', reason: 'first friend comes along');
      Bonds.befriend('glowmoth');
      expect(Bonds.active, 'glowmoth', reason: 'a friend with an ability replaces one without');
      expect(Bonds.has(Ability.light), isTrue);
      Bonds.befriend('stoneturtle');
      expect(Bonds.active, 'glowmoth', reason: 'no auto swap between ability friends');
      expect(Bonds.unlocked(Ability.push), isTrue);
      expect(Bonds.has(Ability.push), isFalse);
      Bonds.setActive('stoneturtle');
      expect(Bonds.has(Ability.push), isTrue);
      Bonds.setActive('hushdeer'); // not befriended: ignored
      expect(Bonds.active, 'stoneturtle');
      expect(Bonds.befriendedCount, 3);
      expect(SaveService.data.abilities, {'light', 'push'});
    });

    test('items are carried, then given away', () {
      Bonds.giveItem('sweetroot');
      expect(Bonds.items, {'sweetroot'});
      Bonds.useItem('sweetroot');
      expect(Bonds.items, isEmpty);
      expect(Bonds.usedItem('sweetroot'), isTrue);
    });

    test('bonds, companion, secrets, glimmer and time survive save + load', () async {
      Bonds.markSeen('hushdeer');
      Bonds.befriend('vinefox');
      Bonds.befriend('brookling');
      Bonds.setActive('brookling');
      Bonds.markSecret('world:boulder:768_128');
      Bonds.markSecret('world:hiddenpath:864_928');
      Bonds.addGlimmer(25);
      SaveService.data.dayTime = 0.9;
      await SaveService.saveNow();

      SaveService.data = SaveData();
      await SaveService.load();
      expect(Bonds.isSeen('hushdeer'), isTrue);
      expect(Bonds.isBefriended('hushdeer'), isFalse);
      expect(Bonds.isBefriended('vinefox'), isTrue);
      expect(Bonds.active, 'brookling');
      expect(Bonds.unlocked(Ability.scent), isTrue);
      expect(Bonds.secretDone('world:boulder:768_128'), isTrue);
      expect(Bonds.secretDone('world:hiddenpath:864_928'), isTrue);
      expect(Bonds.secretDone('world:glyph:0_0'), isFalse);
      expect(Bonds.glimmer, 25);
      expect(SaveService.data.dayTime, 0.9);
    });

    test('a new game forgets every bond', () async {
      Bonds.befriend('glowmoth');
      await SaveService.startNewGame();
      expect(Bonds.befriendedCount, 0);
      expect(Bonds.active, isNull);
    });
  });

  group('assets and map', () {
    test('every species has its sheet, shadow and three portraits; flying matches the sheet json', () {
      for (final s in creatureSpecies.values) {
        final dir = 'assets/images/creatures';
        for (final f in ['sheet.png', 'shadow.png', 'portrait.png', 'portrait_sketch.png', 'portrait_silhouette.png']) {
          expect(File('$dir/${s.id}_$f').existsSync(), isTrue, reason: '${s.id}_$f');
        }
        final j = jsonDecode(File('$dir/${s.id}_sheet.json').readAsStringSync()) as Map;
        expect(j['flying'] == true, s.flying, reason: s.id);
      }
      expect(creatureOrder.toSet(), creatureSpecies.keys.toSet());
    });

    test('the woods map places all six creatures and their ability gates', () {
      final tmj = jsonDecode(File('assets/images/maps/world.tmj').readAsStringSync()) as Map;
      final layer = (tmj['layers'] as List).firstWhere((l) => l['name'] == 'gameplay') as Map;
      final objects = (layer['objects'] as List).cast<Map>();
      String? prop(Map o, String k) {
        for (final p in (o['properties'] as List? ?? [])) {
          if (p['name'] == k) return p['value'].toString();
        }
        return null;
      }

      final species = objects.where((o) => o['name'] == 'creature').map((o) => prop(o, 'species')).toSet();
      expect(species, creatureSpecies.keys.toSet());
      int count(String n) => objects.where((o) => o['name'] == n).length;
      expect(count('boulder'), inInclusiveRange(1, 2));
      expect(count('darkzone'), inInclusiveRange(1, 2));
      expect(count('hidden') + count('hiddenpath'), greaterThanOrEqualTo(2));
      expect(count('stump'), 1);
      expect(count('pebble'), 1);
    });
  });
}
