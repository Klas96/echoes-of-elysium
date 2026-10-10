import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/npc_character.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/bonds.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/day_cycle.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/interaction.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/journal_ui.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/custom_map_game.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/game_state.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/quests.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/save_service.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/well_rested.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/ui/hud_layout.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/ui/mmo_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sizes = [Size(412, 915), Size(360, 800), Size(915, 412)];

/// Busiest HUD state: Town (STALL chip), night, companion, long objective,
/// three tracked jobs, zone banner, well rested, a hold prompt, a toast and
/// loot pops all at once.
void busyState({bool talk = false}) {
  SaveService.data = SaveData(mapId: 'world5', regionId: 'town', glimmer: 1234);
  SaveService.data.bonds['glowmoth'] = {'seen': true, 'befriended': true};
  SaveService.data.activeCompanion = 'glowmoth';
  for (final id in ['courier_pack', 'drone_nest', 'city_east_nest']) {
    SaveService.data.setFlag('quest:$id:accepted');
  }
  Quests.revision.value++;
  Bonds.revision.value++;
  DayCycle.time.value = 0.95;
  GameState.objective.value =
      'Mira\'s stall (trade glimmer) · job board · west road → City, then follow the lantern road south';
  MmoFeedback.zoneTitle.value = 'Lantern Town';
  MmoFeedback.zoneBlurb.value = 'Market hub · job board · Mira\'s stall';
  WellRested.remaining.value = 178;
  MmoFeedback.pops.value = const [
    HudPop(id: 1, text: '+22 XP', color: Color(0xFFFFE08A)),
    HudPop(id: 2, text: '+3 ◆', color: Color(0xFF88DDFF)),
    HudPop(id: 3, text: 'Equip · Swarm Thrusters', color: Color(0xFF66CCFF)),
  ];
  GameToast.current.value =
      const ToastMessage('NIGHTFALL', 'HP restored · Well rested (+20% DMG, regen)', Color(0xFFB8C4FF), null, 1,
          compact: true);
  if (talk) {
    NpcCharacter.showPrompt.value = true;
  } else {
    Interaction.info.value = const PromptInfo('REST UNTIL MORNING', hold: 0.6);
  }
}

void clearState() {
  NpcCharacter.showPrompt.value = false;
  Interaction.info.value = null;
  GameToast.current.value = null;
  MmoFeedback.pops.value = const [];
  MmoFeedback.zoneTitle.value = null;
  WellRested.remaining.value = 0;
}

Future<void> pumpHud(WidgetTester tester, Size size, {bool talk = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  busyState(talk: talk);
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(
      body: Stack(children: [
        SizedBox.expand(),
        GameHud(),
        TalkPrompt(),
        InteractPromptLayer(),
        ToastLayer(),
      ]),
    ),
  ));
  await tester.pump();
}

Rect? rectOf(WidgetTester tester, String key) {
  final f = find.byKey(ValueKey(key));
  if (f.evaluate().isEmpty) return null;
  return tester.getRect(f.first);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(clearState);

  for (final size in sizes) {
    for (final talk in [false, true]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}${talk ? ' talk' : ''}';
      testWidgets('HUD fits without overflow or overlap at $label', (tester) async {
        await pumpHud(tester, size, talk: talk);
        expect(tester.takeException(), isNull, reason: 'layout overflow at $label');

        final screen = Offset.zero & size;
        final r = {
          for (final k in ['hud-health', 'hud-tracker', 'hud-chips', 'hud-rested', 'hud-banner-card', 'hud-pops', 'hud-toast'])
            k: rectOf(tester, k),
          'prompt': rectOf(tester, talk ? 'hud-talk-prompt' : 'hud-prompt'),
        };
        for (final e in r.entries) {
          expect(e.value, isNotNull, reason: '${e.key} missing at $label');
          final v = e.value!;
          expect(screen.inflate(0.5).contains(v.topLeft) && screen.inflate(0.5).contains(v.bottomRight), isTrue,
              reason: '${e.key} $v clipped at $label');
        }
        // Every chip in the row is on screen.
        final chips = find.descendant(of: find.byKey(const ValueKey('hud-chips')), matching: find.byType(GestureDetector));
        for (final el in chips.evaluate()) {
          final cr = tester.getRect(find.byWidget(el.widget).first);
          expect(cr.right <= size.width && cr.left >= 0, isTrue, reason: 'chip clipped $cr at $label');
        }
        // No two HUD blocks overlap; prompt/pops/toast stay off the joystick.
        final names = r.keys.toList();
        for (var i = 0; i < names.length; i++) {
          for (var j = i + 1; j < names.length; j++) {
            final a = r[names[i]]!, b = r[names[j]]!;
            expect(a.overlaps(b), isFalse, reason: '${names[i]} $a overlaps ${names[j]} $b at $label');
          }
        }
        final stick = HudLayout.joystickRect(size);
        for (final k in ['prompt', 'hud-pops', 'hud-toast']) {
          expect(r[k]!.overlaps(stick), isFalse, reason: '$k ${r[k]} on joystick $stick at $label');
        }
      });
    }
  }

  test('compact chips below 560 px wide', () {
    expect(HudLayout.compactChips(412 - 24), isTrue);
    expect(HudLayout.compactChips(915 - 24), isFalse);
  });
}
