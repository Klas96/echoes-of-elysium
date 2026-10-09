import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/ai_fragment.dart';
import '../components/custom_player.dart';
import '../components/npc_character.dart';
import '../ui/cutscene_player.dart';
import '../ui/cutscenes.dart';
import 'game_state.dart';
import 'pause.dart';

/// Mid-game story moments played over a live map (like Memories).
class StoryBeats {
  StoryBeats._();

  static BonfireGameInterface? _game;
  static bool _busy = false;

  static void attach(BonfireGameInterface game) {
    _game = game;
  }

  /// After the City Sentinel: quiet cutscene, then Archivist unlocks the road.
  static void onSentinelDefeated() {
    GameState.onSentinelDefeated();
    final game = _game;
    if (game == null || !game.context.mounted) return;
    if (Cutscenes.seen(Cutscenes.afterSentinel)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      playOverGame(game, Cutscenes.afterSentinel);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// First Archive open: Asha on comms reacts to the whisper-vote draft.
  static void onArchiveOpened() {
    final game = _game;
    if (game == null || !game.context.mounted) return;
    if (Cutscenes.seen(Cutscenes.archiveAsh)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      playOverGame(game, Cutscenes.archiveAsh);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  static Future<void> playOverGame(BonfireGameInterface game, String id) async {
    if (_busy || Cutscenes.seen(id)) return;
    _busy = true;
    CustomPlayer.pendingShot.value = null;
    final fromTalk = NpcCharacter.activeDialogue.value != null ||
        AIFragment.activeDialogue.value != null;
    Pause.dismissDialogueForStory();
    final wasPaused = game.paused;
    if (!wasPaused) game.pauseEngine();
    try {
      await Navigator.of(game.context).push(PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 450),
        reverseTransitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, _, __) => _BeatPage(id: id),
        transitionsBuilder: (context, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ));
    } finally {
      CustomPlayer.pendingShot.value = null;
      final held = HardwareKeyboard.instance.logicalKeysPressed.any(_move.contains);
      if (!held) {
        final player = game.player;
        if (player is CustomPlayer) {
          player.onJoystickChangeDirectional(
              JoystickDirectionalEvent(directional: JoystickMoveDirectional.IDLE));
        }
      }
      if (!wasPaused || fromTalk) game.resumeEngine();
      _busy = false;
    }
  }

  static final _move = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyD,
  };
}

class _BeatPage extends StatefulWidget {
  const _BeatPage({required this.id});
  final String id;

  @override
  State<_BeatPage> createState() => _BeatPageState();
}

class _BeatPageState extends State<_BeatPage> {
  bool _closed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CutscenePlayer(
        asset: Cutscenes.assetFor(widget.id),
        onFinished: () async {
          if (_closed || !mounted) return;
          _closed = true;
          await Cutscenes.markSeen(widget.id);
          if (mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}
