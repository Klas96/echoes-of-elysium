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

  test('accept → complete → turnIn is idempotent', () {
    expect(Quests.status('courier_pack'), QuestStatus.available);
    expect(Quests.accept('courier_pack'), isTrue);
    expect(Quests.accept('courier_pack'), isFalse);
    expect(Quests.status('courier_pack'), QuestStatus.accepted);

    expect(Quests.complete('courier_pack'), isTrue);
    expect(Quests.complete('courier_pack'), isFalse);
    expect(Quests.status('courier_pack'), QuestStatus.done);

    final before = Bonds.glimmer;
    expect(Quests.turnIn('courier_pack'), isTrue);
    expect(Quests.turnIn('courier_pack'), isFalse);
    expect(Quests.status('courier_pack'), QuestStatus.turnedIn);
    expect(Bonds.glimmer, before + 25);
    expect(Adventure.hasClue('quest_courier'), isTrue);
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
    Quests.accept('courier_pack');
    Quests.complete('courier_pack');
    Quests.turnIn('courier_pack');
    Quests.accept('drone_nest');
    Quests.complete('drone_nest');
    Quests.turnIn('drone_nest');
    expect(Adventure.endingCoda, contains('Lantern Town'));
  });
}
