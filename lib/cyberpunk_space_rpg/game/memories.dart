import 'dart:async';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/ai_fragment.dart';
import '../components/custom_player.dart';
import '../components/npc_character.dart';
import '../ui/cutscene_player.dart';
import '../ui/cutscenes.dart';
import 'save_service.dart';

/// The five Aetherian memory flashbacks (dialogue-flashbacks-and-finale.md).
///
/// Memory fragments:
///   1-2  the two fragments in the Whispering Woods (both open the portal)
///   3    the City's west yard, past two drones (optional)
///   4    the Archivist's gift: talk to him after the Sentinel is quieted
///        (optional)
///   5    the Ruins, by the shrine in the south-west dead end, past two
///        drones (optional)
///
/// Flashbacks always play in story order: whichever memory fragment Kaela
/// finds next plays the next unseen memory. Each one is recorded as the story
/// flag `cutscene:memoryN` the moment its fragment is picked up (so quitting
/// mid-flashback never loses it), and [found] is derived from those flags.
/// Finding all five ([allFound]) is what makes Voss stand down at the end.
class Memories {
  Memories._();

  static const total = 5;

  /// Story flag for the Archivist's gift (fragment 4's source).
  static const archivistGiftFlag = 'archivistGift';

  static String idFor(int n) => 'memory$n';

  /// Memories found in this save (0..5), from the `cutscene:memoryN` flags.
  static int get found {
    var n = 0;
    for (var i = 1; i <= total; i++) {
      if (Cutscenes.seen(idFor(i))) n++;
    }
    return n;
  }

  static bool get allFound => found >= total;

  /// Live copy of [found] for UI (updated whenever a memory is claimed and
  /// when a map starts).
  static final foundNotifier = ValueNotifier<int>(0);

  /// The next memory in story order, or null when all five are found.
  static int? get next {
    for (var i = 1; i <= total; i++) {
      if (!Cutscenes.seen(idFor(i))) return i;
    }
    return null;
  }

  /// Records the next memory as found and saves; returns its number (null if
  /// all five were already found).
  static int? claimNext() {
    final n = next;
    if (n == null) return null;
    SaveService.data.setFlag(Cutscenes.flagFor(idFor(n)));
    foundNotifier.value = found;
    SaveService.requestAutosave();
    return n;
  }

  // ------------------------------------------------------------- live game

  static BonfireGameInterface? _game;
  static bool _listening = false;
  static String? _talkingTo;
  static bool _playing = false;
  static final _queue = <int>[];

  /// Called when a map is ready: flashbacks pause and resume this game.
  static void attach(BonfireGameInterface game) {
    _game = game;
    _queue.clear();
    _playing = false;
    foundNotifier.value = found;
  }

  /// A memory fragment was picked up on the map.
  static void onFragmentPicked() {
    final n = claimNext();
    if (n != null) _enqueue(n);
  }

  /// From GameState.onNpcTalk: remembers who the open dialogue belongs to.
  static void onNpcTalk(String npc) {
    _talkingTo = npc;
    if (!_listening) {
      _listening = true;
      NpcCharacter.activeDialogue.addListener(_onDialogueChanged);
    }
  }

  /// Fragment 4: closing the Archivist's dialogue after the Sentinel.
  static void _onDialogueChanged() {
    if (NpcCharacter.activeDialogue.value != null) return;
    final who = _talkingTo;
    _talkingTo = null;
    if (who != 'archivist') return;
    final d = SaveService.data;
    if (!d.flag('sentinelDefeated') || d.flag(archivistGiftFlag)) return;
    d.setFlag(archivistGiftFlag);
    onFragmentPicked();
  }

  static void _enqueue(int n) {
    _queue.add(n);
    // Not from inside a component's update or a listener: next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
    WidgetsBinding.instance.scheduleFrame();
  }

  static Future<void> _drain() async {
    if (_playing) return;
    final game = _game;
    if (game == null || !game.context.mounted) {
      _queue.clear();
      return;
    }
    _playing = true;
    try {
      while (_queue.isNotEmpty && identical(game, _game) && game.context.mounted) {
        await play(game, _queue.removeAt(0));
      }
    } finally {
      _playing = false;
    }
  }

  /// Plays memory [n] over the running game: pauses the engine, closes any
  /// open dialogue, then resumes with the player standing still.
  static Future<void> play(BonfireGameInterface game, int n) async {
    NpcCharacter.activeDialogue.value = null;
    AIFragment.activeDialogue.value = null;
    CustomPlayer.pendingShot.value = null;
    final wasPaused = game.paused;
    if (!wasPaused) game.pauseEngine();
    // Not opaque: the paused game stays mounted (and untouched) underneath.
    await Navigator.of(game.context).push(PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (context, _, __) => _MemoryPage(id: idFor(n)),
      transitionsBuilder: (context, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ));
    _settleControls(game);
    if (!wasPaused) game.resumeEngine();
  }

  /// Keys released and fingers lifted while the flashback had focus never
  /// reached the game: stop the player unless a movement key is still down.
  static void _settleControls(BonfireGameInterface game) {
    CustomPlayer.pendingShot.value = null;
    final held = HardwareKeyboard.instance.logicalKeysPressed.any(_movementKeys.contains);
    if (held) return;
    final player = game.player;
    if (player is CustomPlayer) {
      player.onJoystickChangeDirectional(
          JoystickDirectionalEvent(directional: JoystickMoveDirectional.IDLE));
    }
  }

  static final _movementKeys = {
    LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyD,
  };

  // ------------------------------------------------------------- ending

  /// Ending hook (dialogue doc: Ending A with all five, otherwise B). The
  /// full Voss finale isn't built yet; the victory screen uses these lines.
  static String get endingVoss => allFound
      ? 'Kaela shows Commander Voss what the Aetherians chose. "Stand down. All units, stand down."'
      : 'The UEC drones go silent. Commander Voss withdraws.';

  static String get endingLine => allFound
      ? 'Gaia\'s memory is restored. The Aetherians live on, and so does the colony.'
      : 'Mission complete. Gaia\'s memory is restored. The Aetherians live on.';

  /// Test hook: forget the live game.
  @visibleForTesting
  static void reset() {
    _game = null;
    _queue.clear();
    _playing = false;
    _talkingTo = null;
  }
}

class _MemoryPage extends StatefulWidget {
  const _MemoryPage({required this.id});
  final String id;

  @override
  State<_MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<_MemoryPage> {
  bool _closed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CutscenePlayer(
        asset: Cutscenes.assetFor(widget.id),
        onFinished: () {
          if (_closed || !mounted) return;
          _closed = true;
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
