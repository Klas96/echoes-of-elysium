import 'package:bonfire/bonfire.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/npc_character.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/adventure.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/game_state.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/memories.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/save_service.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/ui/cutscene_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Just enough of a Bonfire game for Memories.play: pause state + context.
class _FakeGame implements BonfireGameInterface {
  _FakeGame(this.context);
  @override
  final BuildContext context;
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
  Player? get player => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SaveService.data = SaveData();
    SaveService.hasSave.value = false;
    SaveService.snapshot = null;
    Memories.reset();
    NpcCharacter.activeDialogue.value = null;
  });

  test('memories are claimed in story order and counted from the save flags', () {
    expect(Memories.found, 0);
    expect(Memories.next, 1);
    expect(Memories.claimNext(), 1);
    expect(SaveService.data.flag('cutscene:memory1'), isTrue);
    // Order never depends on which fragment: the gap is filled first.
    SaveService.data.setFlag('cutscene:memory3');
    expect(Memories.found, 2);
    expect(Memories.claimNext(), 2);
    expect(Memories.claimNext(), 4);
    expect(Memories.claimNext(), 5);
    expect(Memories.allFound, isTrue);
    expect(Memories.claimNext(), isNull);
    expect(Memories.foundNotifier.value, 5);

    final stored = SaveService.decode(SaveService.encode(SaveService.data))!;
    SaveService.data = stored;
    expect(Memories.found, 5);
    expect(Memories.endingLine, contains('remembers fully'));
    expect(Memories.endingVoss, contains('stand down'));
  });

  test('fewer than five: ending B', () {
    for (var i = 0; i < 4; i++) {
      Memories.claimNext();
    }
    expect(Memories.allFound, isFalse);
    expect(Memories.endingLine, startsWith('Mission complete'));
    expect(Memories.endingVoss, contains('another fleet'));
    expect(Memories.endingVoss, contains('caution'));
  });

  test('adventure clues deepen ending A and the victory coda', () {
    for (var i = 0; i < 5; i++) {
      Memories.claimNext();
    }
    Adventure.discover('uec_orders');
    Adventure.discover('archive_first_memory');
    Adventure.setFlag('archive_opened');
    expect(Memories.endingVoss, contains('field-terminal'));
    expect(Memories.endingVoss, contains('archive draft'));
    expect(Memories.endingVoss, contains('murdering a civilization'));
    expect(Memories.endingLine, contains('vote'));
    expect(Adventure.endingCoda, contains('Station Seven orders'));
    expect(Adventure.endingCoda, contains('archive draft'));
  });

  test('woods: two fragments open the portal; city fragments never do', () {
    GameState.resetMap1();
    GameState.onFragmentCollected();
    expect(GameState.portalUnlocked.value, isFalse);
    expect(GameState.objective.value, contains('(1/2)'));
    GameState.onFragmentCollected();
    expect(GameState.portalUnlocked.value, isTrue);

    GameState.resetMap2();
    GameState.onFragmentCollected();
    expect(GameState.portalUnlocked.value, isFalse, reason: 'the Sentinel still guards the city portal');
  });

  test('city south portal opens only after Archivist talk post-Sentinel', () {
    GameState.resetMap2();
    GameState.onSentinelDefeated();
    expect(GameState.portalUnlocked.value, isFalse);
    expect(GameState.objective.value.toLowerCase(), contains('archivist'));
    GameState.onNpcTalk('archivist');
    expect(SaveService.data.flag('archivistPostSentinel'), isTrue);
    expect(GameState.portalUnlocked.value, isTrue);
  });

  test("the Archivist's gift is memory 4's source, once, after the Sentinel", () {
    const archivist = NpcDialogue(name: 'ARCHIVIST', color: Colors.amber, lines: ['...'], voicePaths: []);
    void talk() {
      NpcCharacter.activeDialogue.value = archivist;
      GameState.onNpcTalk('archivist');
      NpcCharacter.activeDialogue.value = null;
    }

    talk();
    expect(Memories.found, 0, reason: 'not before the Sentinel');
    SaveService.data.setFlag('sentinelDefeated');
    talk();
    expect(Memories.found, 1);
    expect(SaveService.data.flag(Memories.archivistGiftFlag), isTrue);
    talk();
    expect(Memories.found, 1, reason: 'only once');
  });

  testWidgets('a flashback pauses the game and resumes it when skipped', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: Text('GAME'));
      }),
    ));
    final game = _FakeGame(ctx);
    var done = false;
    Memories.play(game, 1).then((_) => done = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(game.paused, isTrue);
    expect(find.byType(CutscenePlayer), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // precache timeout
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done, isTrue);
    expect(find.byType(CutscenePlayer), findsNothing);
    expect(find.text('GAME'), findsOneWidget);
    expect(game.paused, isFalse);
    expect(game.pauses, 1);
    expect(game.resumes, 1);
  });
}
