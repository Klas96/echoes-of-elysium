import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/uec_drone.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/progression.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/save_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    SaveService.data = SaveData();
  });

  test('grantXp levels up and spends overflow', () {
    Progression.grantXp(Progression.xpToNext(1));
    expect(Progression.level, 2);
    expect(Progression.xp, 0);
  });

  test('drone kill grants xp and glimmer', () {
    Progression.onDroneKilled(DroneKind.scout);
    expect(Progression.xp, 15);
    expect(SaveService.data.glimmer, 2);
  });

  test('gear bonuses stack on level', () {
    SaveService.data.level = 4; // +2 damage from levels
    SaveService.data.equipped = {'rifle': 'pulse_optic'}; // +5
    expect(Progression.bonusDamage, 2 + 5);
    expect(Progression.bonusHealth, 3 * 5); // (4-1)*5
  });

  test('save round-trips level and gear', () {
    SaveService.data.level = 3;
    SaveService.data.xp = 12;
    SaveService.data.inventory = ['scrap_plating'];
    SaveService.data.equipped = {'suit': 'scrap_plating'};
    final again = SaveData.fromJson(SaveService.data.toJson());
    expect(again.level, 3);
    expect(again.xp, 12);
    expect(again.inventory, ['scrap_plating']);
    expect(again.equipped['suit'], 'scrap_plating');
  });

  test('equip and unequip update slots', () {
    SaveService.data.inventory = ['scrap_plating', 'barrier_coil'];
    Progression.equip('scrap_plating');
    expect(Progression.equippedIn(GearSlot.suit)?.id, 'scrap_plating');
    Progression.equip('barrier_coil');
    expect(Progression.equippedIn(GearSlot.suit)?.id, 'barrier_coil');
    Progression.unequip(GearSlot.suit);
    expect(Progression.equippedIn(GearSlot.suit), isNull);
    expect(Progression.inventory, containsAll(['scrap_plating', 'barrier_coil']));
  });
}
