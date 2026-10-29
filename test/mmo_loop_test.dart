import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/damage_number.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/bonds.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/adventure.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/progression.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/quests.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/save_service.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/trade.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/well_rested.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/ui/mmo_feedback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SaveService.data = SaveData();
    WellRested.remaining.value = 0;
  });

  group('well rested', () {
    test('rest grants a timed damage buff that runs out', () {
      expect(WellRested.applyDamage(20), 20);
      WellRested.grant();
      expect(WellRested.active, isTrue);
      expect(WellRested.label, '3:00');
      expect(WellRested.applyDamage(20), 24);
      WellRested.tick(61);
      expect(WellRested.label, '1:59');
      WellRested.tick(500);
      expect(WellRested.active, isFalse);
      expect(WellRested.applyDamage(20), 20);
      expect(SaveService.data.extra.containsKey('wellRested'), isFalse);
    });

    test('remaining time survives a save round trip', () {
      WellRested.grant();
      WellRested.tick(30.4);
      final json = SaveService.encode(SaveService.data);
      SaveService.data = SaveService.decode(json)!;
      WellRested.remaining.value = 0;
      WellRested.load();
      expect(WellRested.remaining.value, closeTo(149.6, 0.6));
    });
  });

  group('ruins / core jobs', () {
    test('board keeps one ruins and one core lore job for the Archivist', () {
      final late = Quests.catalog.where((q) => q.region == 'ruins' || q.region == 'core').toList();
      expect(late, hasLength(2));
      for (final q in late) {
        expect(Adventure.byId(q.clueId), isNotNull, reason: q.id);
        expect(q.examineId, isNotNull, reason: q.id);
        expect(q.giver, 'archivist');
      }
    });

    test('locked until the story reaches the ruins / core', () {
      expect(Quests.status('ruins_shrine_waymarker'), QuestStatus.locked);
      expect(Quests.accept('ruins_shrine_waymarker'), isFalse);
      SaveService.data.setFlag('sentinelDefeated');
      expect(Quests.status('ruins_shrine_waymarker'), QuestStatus.available);
      expect(Quests.status('core_console_reading'), QuestStatus.locked);
      SaveService.data.setFlag('ruins_gate_open');
      expect(Quests.status('core_console_reading'), QuestStatus.available);
    });

    test('examining the marked hotspot completes the job', () {
      SaveService.data.setFlag('ruins_gate_open');
      Quests.onExamined('core_console');
      expect(Quests.status('core_console_reading'), QuestStatus.available);
      Quests.accept('core_console_reading');
      Quests.onExamined('core_console');
      expect(Quests.status('core_console_reading'), QuestStatus.done);
      expect(Quests.objectiveHint, contains('Archivist'));
      expect(Quests.turnIn('core_console_reading'), isTrue);
    });

    test('shrine waymarker completes on examine and turns in at Archivist', () {
      SaveService.data.setFlag('sentinelDefeated');
      Quests.accept('ruins_shrine_waymarker');
      Quests.onExamined('ruins_dead_end');
      expect(Quests.status('ruins_shrine_waymarker'), QuestStatus.done);
      final before = Bonds.glimmer;
      expect(Quests.turnIn('ruins_shrine_waymarker'), isTrue);
      expect(Bonds.glimmer, before + 20);
    });
  });

  group('sell / buyback at Mira', () {
    test('junk sells for glimmer and can be bought back', () {
      expect(Trade.rollDroneJunk(roll: 0.99), isNull);
      expect(Trade.rollDroneJunk(roll: 0.0, pick: 1), 'bent_servo');
      Trade.addJunk('cracked_lens', 2);
      expect(Trade.junkTotal, 3);
      expect(Trade.junkValue, 3 + 8);
      expect(Trade.sellJunk('bent_servo'), isTrue);
      expect(Bonds.glimmer, 3);
      expect(Trade.sellJunk('bent_servo'), isFalse);
      expect(Trade.buyback.first.id, 'bent_servo');
      expect(Trade.buyBack(0), isTrue);
      expect(Bonds.glimmer, 0);
      expect(Trade.junkCount('bent_servo'), 1);
      expect(Trade.sellAllJunk(), 11);
      expect(Trade.junkTotal, 0);
      expect(Bonds.glimmer, 11);
    });

    test('only spare gear sells, below shop price; buyback restores it', () {
      Progression.grantGear('scrap_plating'); // auto-equipped
      Progression.grantGear('barrier_coil'); // better suit: equipped, plating spare
      expect(Trade.spareGear, ['scrap_plating']);
      expect(Trade.sellGear('barrier_coil'), isFalse);
      final g = Bonds.glimmer;
      final price = Trade.gearSellPrice('scrap_plating');
      expect(price, lessThan(8));
      expect(Trade.sellGear('scrap_plating'), isTrue);
      expect(Progression.inventory, isNot(contains('scrap_plating')));
      expect(Bonds.glimmer, g + price);
      expect(Trade.buyBack(0), isTrue);
      expect(Progression.inventory, contains('scrap_plating'));
    });

    test('buyback keeps the newest few and survives a save', () {
      Trade.addJunk('frayed_wiring', 9);
      for (var i = 0; i < 9; i++) {
        Trade.sellJunk('frayed_wiring');
      }
      expect(Trade.buyback.length, Trade.buybackSize);
      final json = SaveService.encode(SaveService.data);
      SaveService.data = SaveService.decode(json)!;
      expect(Trade.buyback.length, Trade.buybackSize);
      expect(Bonds.glimmer, 18);
    });
  });

  group('damage numbers', () {
    test('style, colour and rise/fade curve', () {
      expect(DamageNumber.textFor(18, DamageNumberStyle.dealt), '18');
      expect(DamageNumber.textFor(12, DamageNumberStyle.taken), '-12');
      expect(DamageNumber.colorFor(DamageNumberStyle.dealt), MmoFeedback.hitColor);
      expect(DamageNumber.colorFor(DamageNumberStyle.dealt, rested: true), MmoFeedback.restedHitColor);
      expect(DamageNumber.colorFor(DamageNumberStyle.shield), MmoFeedback.shieldColor);
      final (dy0, a0) = DamageNumber.curve(0);
      final (dy1, a1) = DamageNumber.curve(1);
      expect(dy0, 0);
      expect(a0, 1);
      expect(dy1, -DamageNumber.rise);
      expect(a1, 0);
    });
  });
}
