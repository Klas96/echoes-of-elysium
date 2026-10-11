import 'dart:async';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../components/ai_fragment.dart';
import '../components/custom_player.dart';
import '../components/npc_character.dart';
import '../ui/cutscene_player.dart';
import '../ui/cutscenes.dart';
import 'adventure.dart';
import 'game_input.dart';
import 'game_state.dart';
import 'pause.dart';
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

  /// Short titles for the pause-menu collection browser.
  static const titles = <int, String>{
    1: 'The Edge of War',
    2: 'Into the Lattice',
    3: 'One Who Remembers',
    4: 'Ships Across the Dark',
    5: 'The Lost Child',
  };

  static String idFor(int n) => 'memory$n';

  static bool has(int n) => n >= 1 && n <= total && Cutscenes.seen(idFor(n));

  static String titleFor(int n) => titles[n] ?? 'Memory $n';

  /// Memories found in this save (0..5), from the `cutscene:memoryN` flags.
  static int get found {
    var n = 0;
    for (var i = 1; i <= total; i++) {
      if (has(i)) n++;
    }
    return n;
  }

  static bool get allFound => found >= total;

  static String get progressLabel => '$found/$total';

  /// Story-order list of memories already claimed (for the menu browser).
  static List<int> get collected => [
        for (var i = 1; i <= total; i++)
          if (has(i)) i,
      ];

  /// High-level where-to-look lines for memories still missing (Core warn UI).
  static List<String> get missingHints {
    final out = <String>[];
    if (!Cutscenes.seen(idFor(1)) || !Cutscenes.seen(idFor(2))) {
      out.add('Whispering Woods · trail fragments');
    }
    if (!Cutscenes.seen(idFor(3))) {
      out.add('City · west yard fragment (optional side path)');
    }
    if (!Cutscenes.seen(idFor(4))) {
      out.add('City · Archivist\'s gift after the Sentinel is quiet');
    }
    if (!Cutscenes.seen(idFor(5))) {
      out.add('Ruins · south-west shrine path (past the gate fork)');
    }
    return out;
  }

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
  /// Also re-asserts the south portal unlock (town hops used to clear it).
  static void _onDialogueChanged() {
    if (NpcCharacter.activeDialogue.value != null) return;
    final who = _talkingTo;
    _talkingTo = null;
    if (who != 'archivist') return;
    final d = SaveService.data;
    if (d.flag('sentinelDefeated')) {
      GameState.openCitySouth();
    }
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

  /// Replay a memory already in the collection (pause menu). No-op if missing
  /// or no map is attached.
  static Future<void> replay(int n) async {
    final game = _game;
    if (game == null || !has(n) || !game.context.mounted) return;
    await play(game, n);
  }

  /// Plays memory [n] over the running game: pauses the engine, closes any
  /// open dialogue, then resumes with the player standing still.
  static Future<void> play(BonfireGameInterface game, int n) async {
    CustomPlayer.pendingShot.value = null;
    // Talk already freezes the engine; keep that pause across dismiss → flashback.
    final fromTalk = NpcCharacter.activeDialogue.value != null ||
        AIFragment.activeDialogue.value != null;
    Pause.dismissDialogueForStory();
    final wasPaused = game.paused;
    if (!wasPaused) game.pauseEngine();
    // Not opaque: the paused game stays mounted (and untouched) underneath.
    const fade = Duration(milliseconds: 450);
    await Navigator.of(game.context).push(PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: fade,
      reverseTransitionDuration: fade,
      pageBuilder: (context, _, __) => _MemoryPage(id: idFor(n)),
      transitionsBuilder: (context, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ));
    // push() resolves when pop is called; the cutscene Focus is still
    // mounted through the reverse fade — wait it out before reclaiming WASD.
    await Future<void>.delayed(fade);
    if (!game.context.mounted) return;
    CustomPlayer.pendingShot.value = null;
    // Inside a room (pond grotto fragment): keep overworld paused and give
    // keys back to the room — do not resume/reclaim the map underneath.
    if (!GameInput.overworldKeysEnabled) {
      GameInput.reclaim();
      return;
    }
    GameInput.reclaim();
    if (!wasPaused || fromTalk) game.resumeEngine();
    GameInput.reclaim(releaseKeys: false);
  }

  // ------------------------------------------------------------- ending

  /// Ending hook (Ending A with all five memories, otherwise B).
  /// Key adventure clues (UEC orders, archive draft) deepen the same branches.
  static String get endingVoss {
    if (allFound) {
      final buf = StringBuffer(
          'He had treated Gaia like Station Seven — a lattice to erase before it ate a colony. '
          'The full Core proves otherwise: a people who refused war, voted to merge, and left a living key in you. '
          'Wiping her would mean murdering a civilization to quiet his fear. So he orders every drone to stand down.');
      if (Adventure.readUecOrders) {
        buf.write(
            ' Your field-terminal readout leaves him no room to call that fear theoretical.');
      }
      if (Adventure.openedArchive) {
        buf.write(
            ' The archive draft — fear beside hope — hits harder than any UEC briefing.');
      }
      return buf.toString();
    }
    if (Adventure.readUecOrders) {
      return 'Without every memory he still sees a lattice risk. He holds the drones as caution — not belief — and vows Earth will send another fleet.';
    }
    return 'Without every memory he still sees a lattice risk. He holds the drones as caution — not belief — and vows Earth will send another fleet.';
  }

  static String get endingLine {
    if (allFound) {
      if (Adventure.openedArchive && Adventure.readUecOrders) {
        return 'Gaia is fully online — vote, fear, and proof. The colony lives.';
      }
      if (Adventure.openedArchive) {
        return 'Gaia is fully online — including the whisper of a vote. The colony lives.';
      }
      return 'Gaia is fully online. The colony lives — and so do the Aetherians.';
    }
    if (Adventure.readUecOrders) {
      return 'Mission complete. Gaia is online; Voss has seen his own orders. The story is still unfinished.';
    }
    return 'Mission complete. Gaia is online, but the story is still unfinished.';
  }

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
