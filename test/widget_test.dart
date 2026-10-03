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

  SaveData sample() => SaveData(
        mapId: 'world2',
        regionId: 'city',
        player: const SavePoint(412.5, 96),
        health: 73,
        checkpoint: const SavePoint(400, 80),
        objectiveStep: 3,
        fragments: 3,
        storyFlags: {'talked:gaia': true, 'sentinelDefeated': true},
        collected: {'world:fragment:120_340', 'world:health:10_20'},
        bonds: {
          'glowmoth': {'seen': true, 'befriended': true}
        },
        activeCompanion: 'glowmoth',
        abilities: {'light'},
        glimmer: 42,
        challenges: {
          'race_courier': {'done': true, 'best': 41.2}
        },
        dayTime: 0.75,
        settings: {'storyMode': true},
        playTimeSeconds: 125,
      );

  void expectSame(SaveData a, SaveData b) {
    expect(a.toJson(), b.toJson());
  }

  test('JSON round trip keeps every field', () {
    final d = sample();
    final back = SaveService.decode(SaveService.encode(d))!;
    expectSame(back, d);
    expect(back.player, const SavePoint(412.5, 96));
    expect(back.flag('sentinelDefeated'), isTrue);
    expect(back.bonds['glowmoth']!['befriended'], isTrue);
    expect(back.version, SaveData.currentVersion);
  });

  test('saveNow then load restores from shared_preferences', () async {
    await SaveService.load();
    expect(SaveService.hasSave.value, isFalse);

    SaveService.data = sample();
    SaveService.snapshot = (d) => d.glimmer += 1; // live state copied on save
    await SaveService.saveNow();

    SaveService.data = SaveData();
    SaveService.hasSave.value = false;
    await SaveService.load();
    expect(SaveService.hasSave.value, isTrue);
    expect(SaveService.data.glimmer, 43);
    expect(SaveService.data.mapId, 'world2');
    expect(SaveService.data.checkpoint, const SavePoint(400, 80));
  });

  test('new game overwrites progress but keeps settings', () async {
    SaveService.data = sample();
    await SaveService.saveNow();
    await SaveService.startNewGame();
    await SaveService.load();
    expect(SaveService.hasSave.value, isTrue);
    expect(SaveService.data.mapId, 'world');
    expect(SaveService.data.collected, isEmpty);
    expect(SaveService.data.glimmer, 0);
    expect(SaveService.data.settings['storyMode'], isTrue);
  });

  test('lenient parsing: unknown keys survive, bad fields fall back', () {
    final d = SaveService.decode(
        '{"version":1,"mapId":"world3","glimmer":"lots","player":{"x":"?"},'
        '"futureThing":{"a":1}}')!;
    expect(d.mapId, 'world3');
    expect(d.glimmer, 0);
    expect(d.player, isNull);
    expect(d.dayTime, SaveData.defaultDayTime);
    expect(d.toJson()['futureThing'], {'a': 1});
  });

  test('garbage in storage is ignored', () async {
    SharedPreferences.setMockInitialValues({SaveService.storageKey: 'not json'});
    await SaveService.load();
    expect(SaveService.hasSave.value, isFalse);
    expect(SaveService.data.mapId, 'world');
  });
}
