import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../components/custom_player.dart';
import '../ui/cutscene_player.dart';
import '../ui/cutscenes.dart';
import 'game_input.dart';
import 'game_state.dart';
import 'pause.dart';

/// Mid-game story moments played over a live map (like Memories).
class StoryBeats {
  StoryBeats._();

  static BonfireGameInterface? _game;
  static bool _busy = false;

  /// Journal titles for replayable story slideshows (not memory fragments).
  /// Order here is the Memories-tab STORY section order.
  static const titles = <String, String>{
    Cutscenes.coalition: 'First Contact',
    Cutscenes.afterSentinel: 'The Sentinel Falls',
  };

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

  /// First-time overlay: skips if already seen; marks seen when finished.
  static Future<void> playOverGame(BonfireGameInterface game, String id) async {
    if (_busy || Cutscenes.seen(id)) return;
    await _playOverlay(game, id, markSeenOnFinish: true, resumeLikeMemories: false);
  }

  /// Journal/menu replay for a slideshow already marked seen. Keeps the engine
  /// paused when the Menu tablet already held pause (same as [Memories.replay]).
  static Future<void> replay(String id) async {
    final game = _game;
    if (_busy || game == null || !Cutscenes.seen(id) || !game.context.mounted) {
      return;
    }
    await _playOverlay(game, id, markSeenOnFinish: false, resumeLikeMemories: true);
  }

  static Future<void> _playOverlay(
    BonfireGameInterface game,
    String id, {
    required bool markSeenOnFinish,
    required bool resumeLikeMemories,
  }) async {
    if (_busy) return;
    _busy = true;
    CustomPlayer.pendingShot.value = null;
    Pause.dismissDialogueForStory();
    final wasPaused = game.paused;
    if (!wasPaused) game.pauseEngine();
    const fade = Duration(milliseconds: 450);
    try {
      await Navigator.of(game.context).push(PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: fade,
        reverseTransitionDuration: fade,
        pageBuilder: (context, _, __) => _BeatPage(
          id: id,
          markSeenOnFinish: markSeenOnFinish,
        ),
        transitionsBuilder: (context, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ));
      await Future<void>.delayed(fade);
    } finally {
      CustomPlayer.pendingShot.value = null;
      if (game.context.mounted) {
        if (!GameInput.overworldKeysEnabled) {
          // archive_ash / memories inside a building — restore room WASD.
          GameInput.reclaim();
        } else if (resumeLikeMemories) {
          // Menu replay: leave the engine paused if the journal already held it.
          GameInput.reclaim();
          if (!wasPaused) game.resumeEngine();
          GameInput.reclaim(releaseKeys: false);
        } else {
          // Always unpause the overworld after a first-time story beat
          // (wasPaused can stay true after nested pauses and leave Kaela frozen).
          if (game.paused) game.resumeEngine();
          GameInput.reclaim();
          GameInput.reclaim(releaseKeys: false);
        }
      }
      _busy = false;
    }
  }

  /// Test hook: forget the live game.
  @visibleForTesting
  static void reset() {
    _game = null;
    _busy = false;
  }
}

class _BeatPage extends StatefulWidget {
  const _BeatPage({required this.id, required this.markSeenOnFinish});
  final String id;
  final bool markSeenOnFinish;

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
          if (widget.markSeenOnFinish) {
            await Cutscenes.markSeen(widget.id);
          }
          if (mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}
