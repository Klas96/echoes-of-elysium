import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/bonds.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/creature_species.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/gate_components.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/gates.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/obstacles.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/region_gates.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/regions.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/game_state.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/save_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// brief-woods-befriend-gates: three friends to get through the Woods,
/// companions stay in their home region, save v2 + migration.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SaveService.data = SaveData();
    SaveService.hasSave.value = false;
    SaveService.snapshot = null;
    Regions.current = 'woods';
    Regions.previous = '';
  });

  group('gates', () {
    test('a gate opens only with its own creature befriended, any follower', () {
      expect(Gates.canOpen('woods_boulder'), isFalse);
      Bonds.befriend('glowmoth');
      expect(Gates.canOpen('woods_boulder'), isFalse);
      expect(Gates.canOpen('woods_grotto'), isTrue);
      Bonds.befriend('stoneturtle');
      Bonds.setActive('glowmoth'); // the moth follows; the turtle still comes over
      expect(Gates.canOpen('woods_boulder'), isTrue);
      Gates.open('woods_boulder');
      expect(Gates.isOpen('woods_boulder'), isTrue);
      expect(Gates.canOpen('woods_boulder'), isFalse, reason: 'already open, stays open');
      expect(SaveService.data.regions['woods']!['gates'], {'woods_boulder': true});
    });

    test('three friends, any order: each gate needs its own creature', () {
      for (final order in [
        ['stoneturtle', 'glowmoth', 'vinefox'],
        ['vinefox', 'stoneturtle', 'glowmoth'],
      ]) {
        SaveService.data = SaveData();
        for (final id in order) {
          final gate = gatesIn('woods').firstWhere((g) => g.creature == id);
          final others = gatesIn('woods').where((g) => g != gate && !Bonds.isBefriended(g.creature));
          Bonds.befriend(id);
          expect(Gates.canOpen(gate.id), isTrue);
          for (final o in others) {
            expect(Gates.canOpen(o.id), isFalse, reason: '${o.id} still waits for ${o.creature}');
          }
          Gates.open(gate.id);
        }
        expect(Gates.allOpen('woods'), isTrue);
      }
    });

    test('hints escalate: examine toast twice, then Gaia names the place', () {
      final h1 = Gates.registerPass('woods_grotto')!;
      final h2 = Gates.registerPass('woods_grotto')!;
      final h3 = Gates.registerPass('woods_grotto')!;
      expect(h1.gaia, isFalse);
      expect(h1.line, 'Too dark to see. Something that glows might help, and those only come out at night.');
      expect(h2.gaia, isFalse);
      expect(h3.gaia, isTrue);
      expect(h3.line, 'The moths dance over the pond after dark.');
      expect(Gates.passes('woods_grotto'), 3);
      expect(Gates.passes('woods_boulder'), 0, reason: 'counted per gate');
      for (var i = 0; i < 3; i++) {
        Gates.registerPass('woods_brambles');
      }
      expect(Gates.registerPass('woods_brambles')!.line, 'Foxes love sweetroot. I felt one growing in the western hollow.');
      expect(Gates.registerPass('woods_boulder')!.line,
          'Far too heavy for one person. Something patient and strong, maybe from the river.');
      Bonds.befriend('stoneturtle');
      Gates.open('woods_boulder');
      expect(Gates.registerPass('woods_boulder'), isNull, reason: 'no hints at an open gate');
    });

    test('brief lines verbatim', () {
      expect(woodsGoal.goalLine,
          "The woods won't let you through alone. Find three friends: something that glows, something that sniffs, something strong.");
      expect(woodsGoal.tracker(0), 'Friends of the Woods 0/3');
      expect(woodsGoal.exitLocked, 'The road south is blocked. The woods still want something from you.');
      expect(woodsGoal.exitOpens, 'The boulder rolls aside. The road to the City is open.');
      expect(woodsGoal.farewellGaia, 'They belong to the forest, Kaela. It will keep them for you.');
      expect(woodsGoal.farewellKaela, "I'll come back.");
      expect(woodsGoal.returnLine, 'Your friends find you at the treeline.');
      expect(gateDefs['woods_brambles']!.blockedHint, 'Thorns. Something with a good nose could find a way through.');
      expect(gateDefs['woods_boulder']!.gaiaHint, 'Someone has trapped a turtle by the pond.');
    });
  });

  group('tracker and exit rule', () {
    test('Asha sets the goal; the tracker counts friends as bonds form', () {
      GameState.resetMap1();
      GameState.onNpcTalk('gaia');
      expect(GameState.objective.value, isNot(contains('Friends of the Woods')));
      GameState.onNpcTalk('asha');
      expect(Gates.goalSet('woods'), isTrue);
      expect(GameState.objective.value, 'Friends of the Woods 0/3');
      Bonds.befriend('vinefox');
      expect(GameState.objective.value, 'Friends of the Woods 1/3');
      Bonds.befriend('puffcap'); // optional, journal only
      expect(GameState.objective.value, 'Friends of the Woods 1/3');
      Bonds.befriend('glowmoth');
      Bonds.befriend('stoneturtle');
      expect(GameState.objective.value, startsWith('Friends of the Woods 3/3'));
      expect(GameState.objective.value, contains('fragments 0/2'));
    });

    test('exit: 2 fragments AND the boulder, in either order', () {
      GameState.resetMap1();
      GameState.onNpcTalk('asha');
      Bonds.befriend('stoneturtle');
      Gates.open('woods_boulder');
      expect(GameState.portalUnlocked.value, isFalse);
      GameState.onFragmentCollected();
      GameState.onFragmentCollected();
      expect(GameState.portalUnlocked.value, isTrue);

      SaveService.data = SaveData();
      GameState.resetMap1();
      GameState.onFragmentCollected();
      GameState.onFragmentCollected();
      expect(GameState.portalUnlocked.value, isFalse);
      GameState.writeTo(SaveService.data);
      expect(SaveService.data.flag('portalUnlocked:world'), isFalse);
      Gates.open('woods_boulder');
      expect(GameState.portalUnlocked.value, isTrue);
    });

    test('walking back into the woods from the City keeps the road open', () {
      final d = SaveData(fragments: 2, collected: {
        'world:fragment:615_519',
        'world:fragment:759_1223',
      });
      d.setFlag('portalUnlocked:world');
      d.regions['woods'] = {
        'goalSet': true,
        'gates': {'woods_boulder': true, 'woods_grotto': true, 'woods_brambles': true}
      };
      SaveService.data = d;
      GameState.resetMap1(); // map exit City -> Woods (no CONTINUE)
      expect(GameState.fragmentsCollected.value, 2);
      expect(GameState.portalUnlocked.value, isTrue);
      expect(GameState.objective.value, startsWith('Mission: take the south-east meadow road'));
    });

    test('a fresh game still starts at Gaia', () {
      SaveService.data = SaveData();
      GameState.resetMap1();
      expect(GameState.fragmentsCollected.value, 0);
      expect(GameState.portalUnlocked.value, isFalse);
      expect(GameState.objective.value, contains('talk to Gaia'));
    });

    test('CONTINUE restores the exit only with the boulder pushed', () {
      final d = SaveData(fragments: 2);
      SaveService.data = d;
      GameState.restore(1, d);
      expect(GameState.portalUnlocked.value, isFalse);
      d.regions['woods'] = {
        'gates': {'woods_boulder': true}
      };
      GameState.restore(1, d);
      expect(GameState.portalUnlocked.value, isTrue);
    });
  });

  group('region rule', () {
    test('Woods companions follow and use abilities only in the Woods', () {
      Bonds.befriend('glowmoth');
      Bonds.befriend('stoneturtle');
      Bonds.setActive('stoneturtle');
      expect(Bonds.activeHere, 'stoneturtle');
      expect(Bonds.has(Ability.push), isTrue);
      expect(Gates.canOpen('woods_grotto'), isTrue);

      Regions.current = 'city';
      expect(Bonds.active, 'stoneturtle', reason: 'still the chosen friend (journal)');
      expect(Bonds.activeHere, isNull, reason: 'waits at home');
      expect(Bonds.has(Ability.push), isFalse);
      expect(Regions.abilityWorksIn('stoneturtle', 'city'), isFalse);
      expect(Gates.canOpen('woods_grotto'), isFalse);

      Regions.current = 'woods';
      expect(Bonds.has(Ability.push), isTrue, reason: 'back home, back to work (optional secrets too)');
    });

    test('every current creature lives in the Woods', () {
      for (final s in creatureSpecies.values) {
        expect(s.region, 'woods');
        expect(Regions.followsIn(s.id, 'woods'), isTrue);
        expect(Regions.followsIn(s.id, 'ruins'), isFalse);
      }
    });

    test('farewell once, on leaving with friends; the return line after it', () {
      expect(Gates.wantsFarewell('woods'), isFalse, reason: 'no friends yet');
      Bonds.befriend('vinefox');
      expect(Gates.wantsFarewell('woods'), isTrue);
      expect(Gates.wantsReturnLine('woods', from: 'city'), isFalse);
      Gates.markFarewell('woods');
      expect(Gates.wantsFarewell('woods'), isFalse);
      expect(Gates.wantsReturnLine('woods', from: 'city'), isTrue);
      expect(Gates.wantsReturnLine('woods', from: 'woods'), isFalse);
      expect(Gates.wantsReturnLine('woods', from: ''), isFalse, reason: 'not on CONTINUE');
      expect(Gates.wantsFarewell('city'), isFalse);
    });
  });

  group('save v2', () {
    Map<String, dynamic> v1(Map<String, dynamic> extra) => {
          'version': 1,
          'mapId': 'world',
          'regionId': 'woods',
          'objectiveStep': 2,
          ...extra,
        };
    SaveData load(Map<String, dynamic> j) => SaveService.decode(jsonEncode(j))!;
    bool open(SaveData d, String id) => (d.regions['woods']?['gates'] as Map?)?[id] == true;

    test('round trip keeps gates, hints, goal, friends and farewell', () {
      Bonds.befriend('glowmoth');
      Gates.setGoal('woods');
      Gates.open('woods_grotto');
      Gates.registerPass('woods_boulder');
      Gates.markFarewell('woods');
      GameState.resetMap1();
      GameState.writeTo(SaveService.data);
      final back = SaveService.decode(SaveService.encode(SaveService.data))!;
      expect(back.version, 2);
      expect(back.regions['woods'], {
        'goalSet': true,
        'gates': {'woods_grotto': true},
        'hints': {'woods_boulder': 1},
        'farewellSeen': true,
        'friends': 1,
      });
    });

    test('fresh v1 save in the Woods: nothing opens by itself', () {
      final d = load(v1({'player': {'x': 300, 'y': 300}}));
      expect(d.version, 2);
      for (final g in gatesIn('woods')) {
        expect(open(d, g.id), isFalse, reason: g.id);
      }
      expect(d.regions['woods']!['farewellSeen'], isNull);
    });

    test('past the Woods (City save): all gates open, farewell seen', () {
      for (final j in [
        v1({'mapId': 'world2', 'regionId': 'city'}),
        v1({'mapId': 'world5', 'regionId': 'town'}),
        v1({'storyFlags': {'visited:city': true}}), // came back to the Woods
      ]) {
        final d = load(j);
        for (final g in gatesIn('woods')) {
          expect(open(d, g.id), isTrue, reason: '${g.id} for $j');
        }
        expect(d.regions['woods']!['farewellSeen'], isTrue);
        expect(d.regions['woods']!['goalSet'], isTrue);
      }
    });

    test('old exit rule already met in the Woods keeps the road open', () {
      final d = load(v1({
        'fragments': 2,
        'storyFlags': {'portalUnlocked:world': true},
        'collected': [woodsPondFragment, woodsGroveFragment],
      }));
      expect(gatesIn('woods').every((g) => open(d, g.id)), isTrue);
      expect(d.regions['woods']!['farewellSeen'], isNull, reason: 'they have not left yet');
      SaveService.data = d;
      GameState.restore(1, d);
      expect(GameState.portalUnlocked.value, isTrue);
    });

    test('a fragment already taken opens its gate only', () {
      final d = load(v1({'fragments': 1, 'collected': [woodsGroveFragment]}));
      expect(open(d, 'woods_brambles'), isTrue);
      expect(open(d, 'woods_grotto'), isFalse);
      expect(open(d, 'woods_boulder'), isFalse);
    });

    // positions are the player's top-left in map px (centre = +16)
    test('standing south of the boulder: the boulder opens', () {
      final d = load(v1({'player': {'x': 41 * 32.0, 'y': 42 * 32.0}}));
      expect(open(d, 'woods_boulder'), isTrue);
      expect(open(d, 'woods_brambles'), isFalse);
    });

    test('standing in the east grove pocket: the brambles open', () {
      final d = load(v1({'player': {'x': 50 * 32.0, 'y': 29 * 32.0}}));
      expect(open(d, 'woods_brambles'), isTrue);
      expect(open(d, 'woods_boulder'), isFalse);
    });

    test('standing in the grotto: the grotto opens', () {
      final d = load(v1({'player': {'x': 36.6 * 32, 'y': 11.2 * 32}}));
      expect(open(d, 'woods_grotto'), isTrue);
    });

    test('respawn checkpoint behind a gate counts too', () {
      final d = load(v1({
        'player': {'x': 300, 'y': 300},
        'checkpoint': {'x': 50.5 * 32, 'y': 28.5 * 32},
      }));
      expect(open(d, 'woods_brambles'), isTrue);
    });

    test('a newer save is read as is', () {
      final d = load({
        'version': 3,
        'regions': {
          'woods': {
            'gates': {'woods_grotto': true}
          }
        },
        'future': 1,
      });
      expect(d.version, 3);
      expect(open(d, 'woods_grotto'), isTrue);
      expect(d.extra['future'], 1);
    });
  });

  group('map + art', () {
    List<Map> objects(String map) {
      final tmj = jsonDecode(File('assets/images/maps/$map.tmj').readAsStringSync()) as Map;
      final layer = (tmj['layers'] as List).firstWhere((l) => l['name'] == 'gameplay') as Map;
      return (layer['objects'] as List).cast<Map>();
    }

    Map<String, dynamic> props(Map o) =>
        {for (final p in (o['properties'] as List? ?? [])) p['name'] as String: p['value']};

    test('the Woods map has exactly the three main gates, matching gateDefs', () {
      final gates = objects('world').where((o) => o['name'] == 'abilitygate').toList();
      expect({for (final g in gates) props(g)['gate']}, gateDefs.keys.where((k) => k.startsWith('woods_')).toSet());
      for (final g in gates) {
        final def = gateDefs[props(g)['gate']]!;
        expect(props(g)['kind'], def.kind.name);
        expect(props(g)['creature'], def.creature);
        expect(props(g)['ability'], def.ability.name);
        // the migration zones cover the gate itself
        final cx = (g['x'] as num) + (g['width'] as num) / 2, cy = (g['y'] as num) + (g['height'] as num) / 2;
        expect(def.zones.any((z) => z.containsPx(cx.toDouble(), cy.toDouble())), isTrue, reason: def.id);
      }
      expect(objects('world2').where((o) => o['name'] == 'abilitygate'), isEmpty);
      expect(objects('world3').where((o) => o['name'] == 'abilitygate'), isEmpty);
    });

    test('the road fragments keep their old pickup ids; the pond one is in the grotto', () {
      final frags = objects('world').where((o) => o['name'] == 'fragment').map(props).toList();
      expect(frags.map((p) => 'world:fragment:${p['pid']}').toSet(), {woodsPondFragment, woodsGroveFragment});
      expect(frags.firstWhere((p) => 'world:fragment:${p['pid']}' == woodsPondFragment)['gate'], 'woods_grotto');
      final exit = objects('world').firstWhere((o) => o['name'] == 'mapexit');
      expect(props(exit)['lockedBody'], woodsGoal.exitLocked);
    });

    List<Rect> rects(Object? j) => [
          for (final r in (j as List).cast<List>())
            Rect.fromLTWH((r[0] as num).toDouble(), (r[1] as num).toDouble(), (r[2] as num).toDouble(),
                (r[3] as num).toDouble())
        ];
    Map json(String f) => jsonDecode(File('assets/images/obstacles/$f').readAsStringSync()) as Map;

    test('gate colliders match Designer\'s JSON for each state', () {
      final g = json('pond_grotto.json');
      expect(GateArt.grottoDarkColliders, rects((g['dark'] as Map)['collision']));
      expect(GateArt.grottoLitColliders, rects((g['lit'] as Map)['collision']));
      expect([GateArt.grottoFragmentPoint.dx, GateArt.grottoFragmentPoint.dy], g['fragment_point']);
      expect([GateArt.grottoInteract.dx, GateArt.grottoInteract.dy], [g['interaction']['x'], g['interaction']['y']]);
      final b = json('road_boulder.json');
      expect(GateArt.boulderClosedColliders, rects((b['closed'] as Map)['collision']));
      expect(GateArt.boulderOpenColliders, rects((b['open'] as Map)['collision']));
      final roll = json('road_boulder_roll_anim.json');
      expect(GateArt.boulderRollFrames, roll['frames']);
      expect(GateArt.boulderRollFps, roll['fps']);
      expect(HiddenPath.closedColliders, rects(json('bramble_closed.json')['collision']));
      expect(HiddenPath.openColliders, rects(json('bramble_open.json')['collision']));
      for (final f in [GateArt.grottoClosed, GateArt.grottoOpen, GateArt.boulderClosed, GateArt.boulderOpen, GateArt.boulderRoll]) {
        expect(File('assets/images/$f').existsSync(), isTrue, reason: f);
      }
    });
  });
}
