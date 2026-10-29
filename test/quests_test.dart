import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/bonds.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/adventure.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/progression.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/quests.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/save_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SaveService.data = SaveData();
    Bonds.revision.value = 0;
    Adventure.revision.value = 0;
    Progression.revision.value = 0;
    Quests.revision.value = 0;
  });

  test('catalog is six character-driven jobs with givers', () {
    expect(Quests.catalog, hasLength(6));
    expect(
      Quests.catalog.map((q) => q.id).toSet(),
      {
        'drone_nest',
        'moonflower_draft',
        'city_east_nest',
        'city_west_cache',
        'ruins_shrine_waymarker',
        'core_console_reading',
      },
    );
    expect(Quests.def('drone_nest')!.giver, 'asha');
    expect(Quests.def('moonflower_draft')!.giver, 'dao');
    expect(Quests.def('city_east_nest')!.giver, 'mira');
    expect(Quests.def('city_west_cache')!.giver, 'echo7');
    expect(Quests.jobsForGiver('archivist'), hasLength(2));
  });

  test('accept → complete → turnIn is idempotent', () {
    expect(Quests.status('drone_nest'), QuestStatus.available);
    expect(Quests.accept('drone_nest'), isTrue);
    expect(Quests.accept('drone_nest'), isFalse);
    expect(Quests.status('drone_nest'), QuestStatus.accepted);

    expect(Quests.complete('drone_nest'), isTrue);
    expect(Quests.complete('drone_nest'), isFalse);
    expect(Quests.status('drone_nest'), QuestStatus.done);
    expect(Quests.objectiveHint, contains('Asha'));

    final before = Bonds.glimmer;
    expect(Quests.turnIn('drone_nest'), isTrue);
    expect(Quests.turnIn('drone_nest'), isFalse);
    expect(Quests.status('drone_nest'), QuestStatus.turnedIn);
    expect(Bonds.glimmer, before + 10);
    expect(Adventure.hasClue('quest_nest'), isTrue);
  });

  test('nest completes after two drone kills', () {
    Quests.accept('drone_nest');
    Quests.onNestDroneKilled('drone_nest');
    expect(Quests.status('drone_nest'), QuestStatus.accepted);
    Quests.onNestDroneKilled('drone_nest');
    expect(Quests.status('drone_nest'), QuestStatus.done);
  });

  test('city east nest uses its own kill counter', () {
    Quests.accept('city_east_nest');
    Quests.onNestDroneKilled('city_east_nest');
    expect(Quests.status('city_east_nest'), QuestStatus.accepted);
    Quests.onNestDroneKilled('city_east_nest');
    expect(Quests.status('city_east_nest'), QuestStatus.done);
  });

  test('moonflower turn-in requires bloom item', () {
    Quests.accept('moonflower_draft');
    Quests.complete('moonflower_draft');
    expect(Quests.turnIn('moonflower_draft'), isFalse);
    Bonds.giveItem('moonflower_bloom');
    expect(Quests.turnIn('moonflower_draft'), isTrue);
    expect(Bonds.hasItem('moonflower_bloom'), isFalse);
    expect(Adventure.hasClue('quest_moonflower'), isTrue);
  });

  test('ending coda mentions jobs when two turned in', () {
    Quests.accept('city_east_nest');
    Quests.complete('city_east_nest');
    Quests.turnIn('city_east_nest');
    Quests.accept('drone_nest');
    Quests.complete('drone_nest');
    Quests.turnIn('drone_nest');
    expect(Adventure.endingCoda, contains('Lantern Town'));
  });

  test('cut jobs are gone from the catalog', () {
    for (final id in [
      'courier_pack',
      'city_se_patrol',
      'ruins_landing_rubbing',
      'ruins_lattice_sweep',
      'core_static',
    ]) {
      expect(Quests.def(id), isNull);
    }
  });

  test('dialogueChoicesFor offers accept then turn-in at the giver', () {
    final accept = Quests.dialogueChoicesFor('asha');
    expect(accept, hasLength(1));
    expect(accept.single.acceptQuest, 'drone_nest');
    expect(accept.single.turnInQuest, isNull);

    Quests.accept('drone_nest');
    expect(Quests.dialogueChoicesFor('asha'), isEmpty);

    Quests.complete('drone_nest');
    final turnIn = Quests.dialogueChoicesFor('asha');
    expect(turnIn, hasLength(1));
    expect(turnIn.single.turnInQuest, 'drone_nest');
    expect(turnIn.single.acceptQuest, isNull);
  });
}
