import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:bonfire/bonfire.dart';
import 'package:bonfire/map/tiled/builder/tiled_world_builder.dart' show ObjectBuilder;
import '../components/custom_player.dart';
import '../components/custom_map.dart';
import '../components/portal_component.dart';
import '../components/uec_drone.dart';
import '../components/ai_fragment.dart';
import '../components/npc_character.dart';
import '../components/fragment_pickup.dart';
import '../components/health_pickup.dart';
import '../components/sentinel_drone.dart';
import '../components/checkpoint.dart';
import '../components/building.dart';
import '../audio/music_manager.dart';
import 'game_state.dart';
import 'save_service.dart';
import 'settings.dart';

// ---------------------------------------------------------------------------
// NPC dialogue data
// ---------------------------------------------------------------------------

const _gaia = NpcDialogue(
  name: 'GAIA',
  color: Color(0xFF00FF88),
  lines: [
    'Kaela... you can hear me? The UEC signal suppressors are finally weakening.',
    'I am Gaia — this world\'s consciousness. What they call an anomaly is a memory. The Aetherians lived here long before humanity arrived.',
    'Find their fragments scattered across Elysium. They hold the truth the UEC wants buried. The portal will take you deeper.',
  ],
  voicePaths: ['audio/voices/gaia_1.mp3', 'audio/voices/gaia_2.mp3', 'audio/voices/gaia_3.mp3'],
);

const _asha = NpcDialogue(
  name: 'ASHA  ·  EX-UEC',
  color: Color(0xFFFFAA00),
  lines: [
    'Keep moving. Name\'s Asha — ex-UEC. I\'ve seen what they do to people who find what you\'re looking for.',
    'The portal leads to the old ruins. That\'s where Gaia\'s core memory is stored.',
    'Watch yourself. Commander Voss personally authorized this hunt. You\'ve already found something that scares them.',
  ],
  voicePaths: ['audio/voices/asha_1.mp3', 'audio/voices/asha_2.mp3', 'audio/voices/asha_3.mp3'],
);

const _echo7 = NpcDialogue(
  name: 'ECHO-7  ·  AETHERIAN',
  color: Color(0xFFCC66FF),
  lines: [
    'Traveller... you carry the resonance of one who seeks. We have waited ten thousand years for such a signal.',
    'We are the Aetherians. Not extinct — transformed. Our consciousness lives within Gaia\'s neural lattice.',
    'Help Gaia remember us. A civilization that chose harmony over conquest must not be forgotten.',
  ],
  voicePaths: ['audio/voices/echo7_1.mp3', 'audio/voices/echo7_2.mp3', 'audio/voices/echo7_3.mp3'],
);

const _archivist = NpcDialogue(
  name: 'THE ARCHIVIST  ·  AETHERIAN',
  color: Color(0xFFFFDD44),
  lines: [
    'The Core Record lies below us. Gaia\'s first memory — the moment we chose to merge our consciousness with this world.',
    'Commander Voss seeks to delete it. Without that memory, Gaia loses herself. The planet dies. We die again.',
    'Your neural signature matches the Aetherian activation code, Kaela. Only you can protect the Core.',
  ],
  voicePaths: ['audio/voices/archivist_1.mp3', 'audio/voices/archivist_2.mp3', 'audio/voices/archivist_3.mp3'],
);

const _voss = NpcDialogue(
  name: 'COMMANDER VOSS  ·  UEC',
  color: Color(0xFFFF4444),
  lines: [
    'Doctor Kaela Osei. You\'ve caused considerable trouble. I\'m giving you one final chance to walk away.',
    'Whatever this "Gaia" has told you is fabrication. Alien interference in planetary governance cannot be permitted.',
    'The Aetherians are a data corruption. Nothing more. Stand down — or be classified as a hostile element.',
  ],
  voicePaths: ['audio/voices/voss_1.mp3', 'audio/voices/voss_2.mp3', 'audio/voices/voss_3.mp3'],
);

// ---------------------------------------------------------------------------
// Tiled object layer -> gameplay components
// ---------------------------------------------------------------------------

const _npcDialogues = <String, NpcDialogue>{
  'gaia': _gaia,
  'asha': _asha,
  'echo7': _echo7,
  'archivist': _archivist,
  'voss': _voss,
};

double _numProp(TiledObjectProperties p, String key, [double fallback = 0]) {
  final v = p.others[key];
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

/// Builders keyed by object name in the map's "gameplay" object layer.
/// Object x/y is the component's top-left corner in map pixels (except for
/// buildings, which are bottom-left anchored tile objects).
/// Stable id for a one-time pickup, from its map and Tiled position.
String _pickupId(String mapId, String kind, Vector2 pos) =>
    '$mapId:$kind:${pos.x.round()}_${pos.y.round()}';

Map<String, ObjectBuilder> _mapObjects(String mapId) => {
      'spawn': (p) => _PlayerSpawn(p.position),
      'portal': (p) => PortalComponent(p.position),
      'npc': (p) {
        final name = (p.others['name'] ?? '').toString().toLowerCase();
        final dialogue = _npcDialogues[name];
        if (dialogue == null) {
          throw ArgumentError('Unknown npc name "$name" in Tiled map');
        }
        return NpcCharacter(p.position,
            dialogue: dialogue, spritePath: 'sprites/npc_$name.png', npcKey: name);
      },
      'fragment': (p) {
        final id = _pickupId(mapId, 'fragment', p.position);
        if (SaveService.data.collected.contains(id)) return _Gone();
        return FragmentPickup(p.position,
            onCollected: () => SaveService.data.collected.add(id));
      },
      'health': (p) {
        final id = _pickupId(mapId, 'health', p.position);
        if (SaveService.data.collected.contains(id)) return _Gone();
        return HealthPickup(p.position, onCollected: () {
          SaveService.data.collected.add(id);
          SaveService.requestAutosave();
        });
      },
      'drone': (p) => UECDrone(p.position, startAngle: _numProp(p, 'startAngle')),
      'sentinel': (p) => SaveService.data.flag('sentinelDefeated')
          ? _Gone()
          : SentinelDrone(p.position, onDefeated: GameState.onSentinelDefeated),
      'checkpoint': (p) => Checkpoint(p.position, label: (p.others['label'] ?? '').toString()),
      // Tile objects: Tiled anchors them bottom-left, so x/y is the sprite's
      // bottom-left corner.
      'building': (p) {
        final id = (p.others['building'] ?? '').toString();
        final def = buildingDefs[id];
        if (def == null) {
          throw ArgumentError('Unknown building "$id" in Tiled map');
        }
        return Building(p.position - Vector2(0, def.h), id: id, def: def);
      },
    };

/// Stand-in for a map object that is already used up in the save (collected
/// pickup, quieted Sentinel): removes itself straight away.
class _Gone extends GameComponent {
  @override
  void onMount() {
    super.onMount();
    removeFromParent();
  }
}

/// The player that has been moved to its spawn/saved spot on this map. Until
/// then its position is meaningless and must not be saved.
CustomPlayer? _placedPlayer;

/// Moves the player to the map's spawn object (or, on CONTINUE, to the saved
/// position and checkpoint) once the map is loaded, then removes itself.
class _PlayerSpawn extends GameComponent {
  _PlayerSpawn(Vector2 spawn) {
    position = spawn;
    size = Vector2.all(CustomPlayer.sizePlayer);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final player = gameRef.player;
    if (player == null) return;
    final save = SaveService.data;
    if (SaveService.resumePlayer && player is CustomPlayer) {
      SaveService.resumePlayer = false;
      final at = save.player ?? save.checkpoint;
      final cp = save.checkpoint;
      player.position = at != null ? Vector2(at.x, at.y) : position.clone();
      player.respawnPoint = cp != null ? Vector2(cp.x, cp.y) : position.clone();
      CustomPlayer.healthNotifier.value =
          (save.health ?? CustomPlayer.maxHealth).clamp(1, CustomPlayer.maxHealth);
    } else {
      player.position = position.clone();
      // Until a checkpoint is touched, Gaia pulls Kaela back to the spawn.
      if (player is CustomPlayer) player.respawnPoint ??= position.clone();
    }
    if (player is CustomPlayer) _placedPlayer = player;
    gameRef.camera.moveToPlayer();
    removeFromParent();
  }
}

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------

class CustomMapGame extends StatefulWidget {
  const CustomMapGame({super.key});

  @override
  State<CustomMapGame> createState() => _CustomMapGameState();
}

class _CustomMapGameState extends State<CustomMapGame> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounded (phone home button, app switcher, web tab hidden, window
    // closing): save where Kaela stands right now.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_activeGame != null) SaveService.saveNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Echoes of Elysium',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const IntroScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Intro / title screen
// ---------------------------------------------------------------------------

class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  static const _brief =
      'Year 2387 · Elysium Colony\n\n'
      'You are Kaela, an AI engineer who accidentally awakened an ancient alien intelligence within Gaia — '
      'the planet\'s caretaker system.\n\n'
      'The United Earth Coalition has dispatched drone squads to "contain" the anomaly.\n\n'
      'Seek the Aetherian fragments scattered across Elysium. '
      'Their echoes hold the key to Gaia\'s future — and the resurrection of a lost civilisation.\n\n'
      'The UEC must not succeed.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          // Phones in landscape are only ~400 logical px tall: shrink and
          // put the brief beside the title/buttons so it all fits; always
          // scrollable as a fallback.
          final compact = box.maxHeight < 600;
          final wide = box.maxWidth >= 700;
          final pad = compact ? 16.0 : 40.0;

          final title = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ECHOES OF ELYSIUM',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFF00FFCC),
                    fontSize: compact ? 24 : 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: compact ? 4 : 6,
                  )),
              const SizedBox(height: 8),
              const Text('A story of AI, nature, and the echoes of a lost world',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 13, letterSpacing: 1)),
            ],
          );

          final brief = Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: EdgeInsets.all(compact ? 16 : 24),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF00FFCC).withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white.withOpacity(0.03),
            ),
            child: Text(_brief,
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: compact ? 13 : 14,
                    height: compact ? 1.5 : 1.7)),
          );

          final actions = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: SaveService.hasSave,
                builder: (context, saved, _) => saved
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        _CyberButton(
                          label: 'CONTINUE',
                          filled: true,
                          onTap: () => _continueGame(context),
                        ),
                        const SizedBox(height: 6),
                        Text(_saveSummary(SaveService.data),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11, letterSpacing: 1)),
                        SizedBox(height: compact ? 10 : 14),
                        _CyberButton(
                          label: 'BEGIN JOURNEY',
                          color: Colors.white54,
                          onTap: () => _confirmNewGame(context),
                        ),
                      ])
                    : _CyberButton(
                        label: 'BEGIN JOURNEY',
                        onTap: () => _beginNewGame(context),
                      ),
              ),
              SizedBox(height: compact ? 12 : 20),
              const _StoryModeToggle(),
              SizedBox(height: compact ? 10 : 16),
              Text(_isTouch
                      ? 'Joystick to move · tap TALK to interact · tap to shoot'
                      : 'WASD / Arrow keys · E to interact · Esc to pause · ` to debug',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white24, fontSize: 11, letterSpacing: 1.2)),
            ],
          );

          final Widget content = (compact && wide)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [title, const SizedBox(height: 24), actions],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(child: brief),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title,
                    SizedBox(height: compact ? 20 : 36),
                    brief,
                    SizedBox(height: compact ? 20 : 36),
                    actions,
                  ],
                );

          return SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - pad * 2),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: content,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Save / continue
// ---------------------------------------------------------------------------

const _regionNames = {
  'woods': 'Whispering Woods',
  'city': 'The City',
  'ruins': 'The Ruins',
};

String _saveSummary(SaveData d) {
  final region = _regionNames[d.regionId] ?? d.regionId;
  final mins = (d.playTimeSeconds / 60).floor();
  final time = mins < 1 ? '' : (mins < 60 ? '  ·  ${mins}m' : '  ·  ${mins ~/ 60}h ${mins % 60}m');
  return '$region$time';
}

Widget _screenForMap(String mapId) {
  switch (mapId) {
    case 'world2':
      return const Map2GameScreen();
    case 'world3':
      return const Map3GameScreen();
    default:
      return const CustomMapGameScreen();
  }
}

void _continueGame(BuildContext context) {
  SaveService.prepareResume();
  Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => _screenForMap(SaveService.data.mapId)));
}

Future<void> _beginNewGame(BuildContext context) async {
  final nav = Navigator.of(context);
  await SaveService.startNewGame();
  nav.pushReplacement(MaterialPageRoute(builder: (_) => const CustomMapGameScreen()));
}

Future<void> _confirmNewGame(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF06060F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: const Color(0xFF00FFCC).withValues(alpha: 0.6)),
      ),
      title: const Text('Begin a new journey?',
          style: TextStyle(color: Color(0xFF00FFCC), fontSize: 18, letterSpacing: 1)),
      content: const Text(
          'Your saved journey will be replaced by a fresh start in the woods.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('KEEP MY SAVE', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('START OVER',
              style: TextStyle(color: Color(0xFF00FFCC), fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) await _beginNewGame(context);
}

/// Session clock for play time, running while a map is on screen.
final _playClock = Stopwatch();

/// Copies live game state into the save record before every write.
void _snapshot(SaveData d) {
  d.settings['storyMode'] = GameSettings.storyMode.value;
  d.playTimeSeconds += _playClock.elapsedMilliseconds / 1000;
  _playClock.reset();
  if (_activeGame == null) return;
  GameState.writeTo(d);
  final p = CustomPlayer.current;
  if (p != null && identical(p, _placedPlayer)) {
    final cp = p.respawnPoint;
    // Mid-respawn the body is about to be moved to the checkpoint.
    final pos = p.isRespawning && cp != null ? cp : p.position;
    d.player = SavePoint(pos.x, pos.y);
    d.checkpoint = cp == null ? null : SavePoint(cp.x, cp.y);
    d.health = p.isRespawning ? CustomPlayer.maxHealth : CustomPlayer.healthNotifier.value;
  }
}

/// Leaving the current map (portal, main menu, ending): save, then stop
/// treating the old map as live.
Future<void> _leaveMap({String? nextMapId}) async {
  await SaveService.saveNow();
  _activeGame = null;
  _placedPlayer = null;
  _playClock.stop();
  if (nextMapId != null) {
    // Map transition: the next map starts fresh at its spawn.
    final d = SaveService.data;
    d.mapId = nextMapId;
    d.regionId = GameState.regionIds[GameState.levelForMap(nextMapId)]!;
    d.player = null;
    d.checkpoint = null;
    d.objectiveStep = 0;
    d.fragments = 0;
    await SaveService.saveNow(takeSnapshot: false);
  }
}

/// onReady for every map: restore the objective on CONTINUE, otherwise start
/// the level fresh and save the transition.
void _startLevel(BonfireGameInterface game, int level) {
  _onMapReady(game);
  SaveService.snapshot = _snapshot;
  _playClock
    ..reset()
    ..start();
  final d = SaveService.data;
  if (SaveService.resumeObjective && d.mapId == GameState.mapIds[level]) {
    SaveService.resumeObjective = false;
    GameState.restore(level, d);
    return;
  }
  SaveService.resumeObjective = false;
  switch (level) {
    case 1:
      GameState.resetMap1();
    case 2:
      GameState.resetMap2();
    default:
      GameState.resetMap3();
  }
  SaveService.saveNow();
}

// ---------------------------------------------------------------------------
// Shared debug state
// ---------------------------------------------------------------------------

final _debugMode = ValueNotifier<bool>(false);

KeyEventResult _handleDebugKey(FocusNode _, KeyEvent event) {
  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backquote) {
    _debugMode.value = !_debugMode.value;
    return KeyEventResult.handled;
  }
  if (event is KeyDownEvent &&
      (event.logicalKey == LogicalKeyboardKey.escape ||
          event.logicalKey == LogicalKeyboardKey.keyP)) {
    _setPaused(!_paused.value);
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

// ---------------------------------------------------------------------------
// Pause (Esc / P or the PAUSE button): freezes the game, offers Story Mode.
// ---------------------------------------------------------------------------

final _paused = ValueNotifier<bool>(false);
BonfireGameInterface? _activeGame;

void _setPaused(bool on) {
  _paused.value = on;
  final g = _activeGame;
  if (g == null) return;
  if (on) SaveService.saveNow();
  if (on) {
    g.pauseEngine();
  } else {
    g.resumeEngine();
  }
}

/// Called from each map's onReady.
void _onMapReady(BonfireGameInterface game) {
  _activeGame = game;
  _paused.value = false;
}

// Joystick + keyboard (WASD and arrows) both feed Bonfire's movement, which
// applies speed * dt. Only the movement keys are accepted so other keys
// (` for debug, E to interact) still reach the rest of the app.
List<PlayerController> _playerControllers() => [
      Joystick(directional: JoystickDirectional()),
      Keyboard(
        config: KeyboardConfig(
          directionalKeys: [
            KeyboardDirectionalKeys.arrows(),
            KeyboardDirectionalKeys.wasd(),
          ],
          acceptedKeys: [], // filled with the directional keys by KeyboardConfig
        ),
      ),
    ];

// ---------------------------------------------------------------------------
// Map 1 — Elysium Forest
// ---------------------------------------------------------------------------

class CustomMapGameScreen extends StatelessWidget {
  const CustomMapGameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    CustomPlayer.healthNotifier.value = CustomPlayer.maxHealth;
    return Focus(
      autofocus: true,
      onKeyEvent: _handleDebugKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) {
              if (NpcCharacter.activeDialogue.value != null) return;
              if (AIFragment.activeDialogue.value != null) return;
              CustomPlayer.pendingShot.value =
                  Vector2(d.localPosition.dx, d.localPosition.dy);
            },
            child: BonfireWidget(
            playerControllers: _playerControllers(),
            player: CustomPlayer(Vector2.zero()),
            map: CustomMap('maps/world.tmj', objectsBuilder: _mapObjects('world')),
            cameraConfig: CameraConfig(moveOnlyMapArea: true, zoom: 2.0),
            overlayBuilderMap: {
              'portalReached': (ctx, game) => _PortalOverlay(
                    game: game,
                    onEnter: () async {
                      final nav = Navigator.of(ctx);
                      await _leaveMap(nextMapId: 'world2');
                      nav.pushReplacement(
                          MaterialPageRoute(builder: (_) => const Map2GameScreen()));
                    },
                  ),
            },
            onReady: (game) {
              _startLevel(game, 1);
              MusicManager().play('assets/audio/music/Whispering_Pines.mp3');
            },
          )),
          const _Vignette(),
          const _GameHUD(),
          const _NpcDialogueLayer(),
          // NPC interact prompt
          const _InteractPrompt(),
          const _CalmLayer(),
          _DebugOverlay(),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map 2 — The Aetherian Ruins
// ---------------------------------------------------------------------------

class Map2GameScreen extends StatelessWidget {
  const Map2GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleDebugKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) => CustomPlayer.pendingShot.value =
                Vector2(d.localPosition.dx, d.localPosition.dy),
            child: BonfireWidget(
            playerControllers: _playerControllers(),
            player: CustomPlayer(Vector2.zero()),
            map: CustomMap('maps/world2.tmj', objectsBuilder: _mapObjects('world2')),
            cameraConfig: CameraConfig(moveOnlyMapArea: true, zoom: 2.0),
            overlayBuilderMap: {
              'portalReached': (ctx, game) => _PortalOverlay(
                    game: game,
                    label: 'THE CORE',
                    subtitle: 'Gaia\'s memory is restored. Elysium lives.',
                    onEnter: () async {
                      final nav = Navigator.of(ctx);
                      await _leaveMap(nextMapId: 'world3');
                      nav.pushReplacement(
                          MaterialPageRoute(builder: (_) => const Map3GameScreen()));
                    },
                  ),
            },
            onReady: (game) {
              _startLevel(game, 2);
              MusicManager().play('assets/audio/music/Neon_Shadows.mp3');
            },
          )),
          const _Vignette(),
          const _GameHUD(),
          // AI Fragment dialogue overlay
          ValueListenableBuilder<String?>(
            valueListenable: AIFragment.activeDialogue,
            builder: (_, text, __) =>
                text != null ? _DialogueOverlay(text: text) : const SizedBox.shrink(),
          ),
          const _NpcDialogueLayer(),
          const _InteractPrompt(),
          const _CalmLayer(),
          _DebugOverlay(),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map 3 — Cyberpunk City Ruins
// ---------------------------------------------------------------------------

class Map3GameScreen extends StatelessWidget {
  const Map3GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleDebugKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) => CustomPlayer.pendingShot.value =
                Vector2(d.localPosition.dx, d.localPosition.dy),
            child: BonfireWidget(
              playerControllers: _playerControllers(),
              player: CustomPlayer(Vector2.zero()),
              map: CustomMap('maps/world3.tmj', objectsBuilder: _mapObjects('world3')),
              cameraConfig: CameraConfig(moveOnlyMapArea: true, zoom: 2.0),
              overlayBuilderMap: {
                'portalReached': (ctx, game) => _PortalOverlay(
                      game: game,
                      label: 'EXTRACTION POINT',
                      subtitle: 'The ruins hold the final truth.\nElysium\'s fate is decided here.',
                      onEnter: () async {
                        final nav = Navigator.of(ctx);
                        SaveService.data.setFlag('completed');
                        await _leaveMap();
                        nav.pushReplacement(
                            MaterialPageRoute(builder: (_) => const _VictoryScreen()));
                      },
                    ),
              },
              onReady: (game) {
                _startLevel(game, 3);
                MusicManager().play('assets/audio/music/Neon_Mirage.mp3');
              },
            ),
          ),
          const _Vignette(),
          const _GameHUD(),
          const _NpcDialogueLayer(),
          const _InteractPrompt(),
          const _CalmLayer(),
          _DebugOverlay(),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NPC Dialogue Layer
// ---------------------------------------------------------------------------

class _NpcDialogueLayer extends StatefulWidget {
  const _NpcDialogueLayer();

  @override
  State<_NpcDialogueLayer> createState() => _NpcDialogueLayerState();
}

class _NpcDialogueLayerState extends State<_NpcDialogueLayer> {
  NpcDialogue? _dialogue;
  int _line = 0;

  @override
  void initState() {
    super.initState();
    NpcCharacter.activeDialogue.addListener(_onDialogueChange);
  }

  @override
  void dispose() {
    NpcCharacter.activeDialogue.removeListener(_onDialogueChange);
    super.dispose();
  }

  void _onDialogueChange() {
    final d = NpcCharacter.activeDialogue.value;
    setState(() { _dialogue = d; _line = 0; });
    if (d != null && d.voicePaths.isNotEmpty) {
      SfxManager().playVoice(d.voicePaths[0]);
    }
  }

  void _advance() {
    final d = _dialogue;
    if (d == null) return;
    final next = _line + 1;
    if (next >= d.lines.length) {
      NpcCharacter.activeDialogue.value = null;
    } else {
      setState(() => _line = next);
      if (next < d.voicePaths.length) SfxManager().playVoice(d.voicePaths[next]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _dialogue;
    if (d == null) return const SizedBox.shrink();
    final isLast = _line >= d.lines.length - 1;
    return Positioned(
      bottom: 24, left: 24, right: 24,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF06060F).withOpacity(0.96),
              border: Border.all(color: d.color, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name,
                    style: TextStyle(
                        color: d.color, fontSize: 11,
                        fontWeight: FontWeight.bold, letterSpacing: 3)),
                const SizedBox(height: 10),
                Text(d.lines[_line],
                    style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.7)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => NpcCharacter.activeDialogue.value = null,
                      child: const Text('SKIP', style: TextStyle(color: Colors.white24, fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    _CyberButton(
                      label: isLast ? 'CLOSE' : 'NEXT ›',
                      color: d.color,
                      onTap: _advance,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared UI widgets
// ---------------------------------------------------------------------------

class _GameHUD extends StatefulWidget {
  const _GameHUD();

  @override
  State<_GameHUD> createState() => _GameHUDState();
}

class _GameHUDState extends State<_GameHUD> {
  @override
  void initState() {
    super.initState();
    CustomPlayer.damageFlash.addListener(_onFlash);
  }

  @override
  void dispose() {
    CustomPlayer.damageFlash.removeListener(_onFlash);
    super.dispose();
  }

  void _onFlash() {
    if (CustomPlayer.damageFlash.value) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) CustomPlayer.damageFlash.value = false;
      });
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Damage flash overlay (kept soft: calm direction)
      if (CustomPlayer.damageFlash.value)
        IgnorePointer(
          child: Container(color: const Color(0xFFFF6666).withValues(alpha: 0.12)),
        ),
      // Health bar
      Positioned(
        top: 12,
        left: 12,
        child: ValueListenableBuilder<int>(
          valueListenable: CustomPlayer.healthNotifier,
          builder: (_, hp, __) {
            final pct = hp / CustomPlayer.maxHealth;
            final barColor = pct > 0.5
                ? const Color(0xFF00FF88)
                : pct > 0.25
                    ? const Color(0xFFFFAA00)
                    : const Color(0xFFFF3333);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('KAELA',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 10, letterSpacing: 2)),
                const SizedBox(height: 3),
                Container(
                  width: 120,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: pct.clamp(0, 1),
                    child: Container(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text('$hp / ${CustomPlayer.maxHealth}',
                    style: const TextStyle(color: Colors.white38, fontSize: 9)),
              ],
            );
          },
        ),
      ),
      // Objective
      Positioned(
        top: 12,
        right: 12,
        child: ValueListenableBuilder<String>(
          valueListenable: GameState.objective,
          builder: (_, obj, __) => obj.isEmpty
              ? const SizedBox.shrink()
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    border: Border.all(color: const Color(0xFF00FFCC).withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('▶  ', style: TextStyle(color: Color(0xFF00FFCC), fontSize: 10)),
                    Text(obj,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11, letterSpacing: 0.5)),
                  ]),
                ),
        ),
      ),
    ]);
  }
}

class _DialogueOverlay extends StatelessWidget {
  final String text;
  const _DialogueOverlay({required this.text});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => AIFragment.activeDialogue.value = null,
      child: Container(
        color: Colors.black.withOpacity(0.6),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.all(40),
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0020),
            border: Border.all(color: const Color(0xFFAA44FF), width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 15, height: 1.75)),
              const SizedBox(height: 24),
              _CyberButton(
                label: 'ABSORB ECHO',
                color: const Color(0xFFAA44FF),
                onTap: () {
                  AIFragment.nearbyFragment?.absorb();
                  AIFragment.activeDialogue.value = null;
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => AIFragment.activeDialogue.value = null,
                child: const Text('CLOSE',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.85,
            colors: [Colors.transparent, Color(0xCC000000)],
            stops: [0.55, 1.0],
          ),
        ),
      ),
    );
  }
}

class _DebugOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      ValueListenableBuilder<bool>(
        valueListenable: _debugMode,
        builder: (_, debug, __) =>
            debug ? const _DebugHud() : const SizedBox.shrink(),
      ),
      Positioned(
        top: 8,
        right: 8,
        child: ValueListenableBuilder<bool>(
          valueListenable: _debugMode,
          builder: (_, debug, __) => _DebugToggleButton(
              active: debug,
              onTap: () => _debugMode.value = !_debugMode.value),
        ),
      ),
    ]);
  }
}

class _DebugToggleButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _DebugToggleButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          border: Border.all(
              color: active ? const Color(0xFF00FF88) : Colors.white24),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('`  DEBUG',
            style: TextStyle(
              color: active ? const Color(0xFF00FF88) : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            )),
      ),
    );
  }
}

class _DebugHud extends StatelessWidget {
  const _DebugHud();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 16,
      left: 16,
      child: ValueListenableBuilder<Vector2>(
        valueListenable: CustomPlayer.positionNotifier,
        builder: (_, pos, __) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            border: Border.all(color: const Color(0xFF00FF88), width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'x: ${pos.x.toStringAsFixed(1)}  y: ${pos.y.toStringAsFixed(1)}',
            style: const TextStyle(
                color: Color(0xFF00FF88),
                fontSize: 13,
                fontFamily: 'monospace',
                letterSpacing: 1),
          ),
        ),
      ),
    );
  }
}

class _PortalOverlay extends StatelessWidget {
  final BonfireGame game;
  final VoidCallback onEnter;
  final String label;
  final String subtitle;
  const _PortalOverlay({
    required this.game,
    required this.onEnter,
    this.label = 'AETHERIAN GATE',
    this.subtitle = 'A resonance field from the lost civilisation.\nThe Aetherian echoes grow stronger beyond.',
  });

  @override
  Widget build(BuildContext context) {
    // Scrollable + scaled title so it never overflows a phone in landscape.
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.88),
              border: Border.all(color: const Color(0xFF00FFFF), width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFF00FFFF),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 5)),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    TextButton(
                      onPressed: () => game.overlays.remove('portalReached'),
                      style: TextButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10)),
                      child: const Text('NOT YET',
                          style: TextStyle(color: Colors.white38)),
                    ),
                    _CyberButton(label: 'ENTER', onTap: onEnter),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VictoryScreen extends StatelessWidget {
  const _VictoryScreen();

  static const _story =
      'You reached the Core and activated the Aetherian resonance.\n\n'
      'Gaia\'s memory floods back — ten thousand years of harmony, of a civilization that chose '
      'to become one with their world rather than consume it.\n\n'
      'The UEC drones go silent. Commander Voss withdraws.\n\n'
      'Elysium breathes again.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          // Same approach as IntroScreen: phones in landscape are only ~400
          // logical px tall, so shrink and put the story beside the title and
          // buttons; always scrollable as a fallback.
          final compact = box.maxHeight < 600;
          final wide = box.maxWidth >= 700;
          final pad = compact ? 16.0 : 40.0;

          final title = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('GAIA REMEMBERS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: const Color(0xFF00FFCC),
                        fontSize: compact ? 24 : 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: compact ? 4 : 5)),
              ),
              SizedBox(height: compact ? 8 : 12),
              const Text(GameState.endingText,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 14, letterSpacing: 1)),
            ],
          );

          final story = Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: EdgeInsets.all(compact ? 16 : 24),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF00FFCC).withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white.withOpacity(0.03),
            ),
            child: Text(_story,
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: compact ? 13 : 14,
                    height: compact ? 1.5 : 1.75)),
          );

          final actions = Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: compact ? 12 : 16,
            children: [
              _CyberButton(
                label: 'PLAY AGAIN',
                onTap: () => _beginNewGame(context),
              ),
              _CyberButton(
                label: 'MAIN MENU',
                color: Colors.white38,
                onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const IntroScreen())),
              ),
            ],
          );

          final Widget content = (compact && wide)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [title, const SizedBox(height: 24), actions],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(child: story),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title,
                    SizedBox(height: compact ? 20 : 36),
                    story,
                    SizedBox(height: compact ? 20 : 36),
                    actions,
                  ],
                );

          return SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - pad * 2),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: content,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _CyberButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  /// Primary action: stronger fill.
  final bool filled;
  const _CyberButton({
    required this.label,
    required this.onTap,
    this.color = const Color(0xFF00FFCC),
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: color.withOpacity(filled ? 0.28 : 0.12),
        side: BorderSide(color: color, width: filled ? 2 : 1),
        padding: EdgeInsets.symmetric(horizontal: filled ? 40 : 28, vertical: filled ? 14 : 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontSize: filled ? 15 : 13)),
    );
  }
}

// ---------------------------------------------------------------------------
// Calm gameplay UI: respawn fade, checkpoint toast, pause + Story Mode
// ---------------------------------------------------------------------------

class _StoryModeToggle extends StatelessWidget {
  const _StoryModeToggle();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GameSettings.storyMode,
      builder: (_, on, __) => InkWell(
        onTap: () => GameSettings.setStoryMode(!on),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(
              value: on,
              onChanged: GameSettings.setStoryMode,
              activeColor: const Color(0xFF66FFAA),
            ),
            const SizedBox(width: 6),
            Flexible(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('STORY MODE  ${on ? 'ON' : 'OFF'}',
                    style: TextStyle(
                        color: on ? const Color(0xFF66FFAA) : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2)),
                const SizedBox(height: 2),
                const Text('Enemies stay calm and can\'t hurt you. Just enjoy the story.',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            )),
          ]),
        ),
      ),
    );
  }
}

class _CalmLayer extends StatelessWidget {
  const _CalmLayer();

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Pause button + Story Mode tag, under the health bar
      Positioned(
        top: 62,
        left: 12,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () => _setPaused(true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('II  PAUSE',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5)),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<bool>(
            valueListenable: GameSettings.storyMode,
            builder: (_, on, __) => on
                ? const Text('STORY MODE',
                    style: TextStyle(
                        color: Color(0xFF66FFAA), fontSize: 10, letterSpacing: 1.5))
                : const SizedBox.shrink(),
          ),
        ]),
      ),
      // Checkpoint toast
      ValueListenableBuilder<String?>(
        valueListenable: Checkpoint.toast,
        builder: (_, text, __) => Positioned(
          top: 56,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: text == null ? 0 : 1,
                duration: const Duration(milliseconds: 500),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    border: Border.all(color: const Color(0xFF66FFAA).withValues(alpha: 0.6)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(text ?? '',
                      style: const TextStyle(
                          color: Color(0xFF66FFAA), fontSize: 12, letterSpacing: 1.5)),
                ),
              ),
            ),
          ),
        ),
      ),
      // "Gaia pulls you back" respawn fade (replaces the old game over)
      ValueListenableBuilder<bool>(
        valueListenable: CustomPlayer.respawnFade,
        builder: (_, fading, __) => IgnorePointer(
          ignoring: !fading,
          child: AnimatedOpacity(
            opacity: fading ? 1 : 0,
            duration: Duration(
                milliseconds: ((fading
                            ? CustomPlayer.fadeOutSeconds
                            : CustomPlayer.fadeInSeconds) *
                        1000)
                    .round()),
            curve: Curves.easeInOut,
            child: Container(
              color: const Color(0xFF020A08),
              alignment: Alignment.center,
              child: const Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Gaia pulls you back…',
                    style: TextStyle(
                        color: Color(0xFF66FFAA),
                        fontSize: 22,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 2)),
                SizedBox(height: 10),
                Text('returning to the last checkpoint',
                    style: TextStyle(color: Colors.white30, fontSize: 11, letterSpacing: 1.5)),
              ]),
            ),
          ),
        ),
      ),
      // Pause menu (scrollable so it fits a phone in landscape)
      ValueListenableBuilder<bool>(
        valueListenable: _paused,
        builder: (ctx, paused, __) => paused
            ? Container(
                color: Colors.black.withValues(alpha: 0.7),
                alignment: Alignment.center,
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06060F).withValues(alpha: 0.96),
                        border: Border.all(
                            color: const Color(0xFF00FFCC).withValues(alpha: 0.6)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('PAUSED',
                            style: TextStyle(
                                color: Color(0xFF00FFCC),
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 5)),
                        const SizedBox(height: 14),
                        const _StoryModeToggle(),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _CyberButton(label: 'RESUME', onTap: () => _setPaused(false)),
                            _CyberButton(
                              label: 'MAIN MENU',
                              color: Colors.white38,
                              onTap: () async {
                                final nav = Navigator.of(ctx);
                                _setPaused(false);
                                await _leaveMap();
                                nav.pushReplacement(
                                    MaterialPageRoute(builder: (_) => const IntroScreen()));
                              },
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    ]);
  }
}


// ---------------------------------------------------------------------------
// Interact prompt: shown near an NPC or AI fragment. Tappable (phones have no
// E key); on desktop E still works through CustomPlayer.
// ---------------------------------------------------------------------------

bool get _isTouch =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

class _InteractPrompt extends StatelessWidget {
  const _InteractPrompt();

  void _interact() {
    AIFragment.nearbyFragment?.interact();
    NpcCharacter.nearbyNpc?.interact();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        NpcCharacter.showPrompt,
        AIFragment.showPrompt,
        NpcCharacter.activeDialogue,
        AIFragment.activeDialogue,
      ]),
      builder: (_, __) {
        final npc = NpcCharacter.showPrompt.value;
        final frag = AIFragment.showPrompt.value;
        final talking = NpcCharacter.activeDialogue.value != null ||
            AIFragment.activeDialogue.value != null;
        if (talking || (!npc && !frag)) return const SizedBox.shrink();
        final action = npc ? 'TALK' : 'INTERACT';
        final label = _isTouch ? action : 'E  $action';
        return Positioned(
          bottom: 80, left: 0, right: 0,
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _interact,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: _isTouch ? 28 : 14, vertical: _isTouch ? 14 : 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  border: Border.all(color: const Color(0xFF00FFCC)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(label,
                    style: TextStyle(
                        color: const Color(0xFF00FFCC),
                        fontSize: _isTouch ? 16 : 12,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        );
      },
    );
  }
}
