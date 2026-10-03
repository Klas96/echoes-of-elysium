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
Map<String, ObjectBuilder> _mapObjects() => {
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
      'fragment': (p) => FragmentPickup(p.position),
      'health': (p) => HealthPickup(p.position),
      'drone': (p) => UECDrone(p.position, startAngle: _numProp(p, 'startAngle')),
      'sentinel': (p) => SentinelDrone(p.position, onDefeated: GameState.onSentinelDefeated),
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

/// Moves the player to the map's spawn object once the map is loaded, then
/// removes itself.
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
    player.position = position.clone();
    // Until a checkpoint is touched, Gaia pulls Kaela back to the spawn.
    if (player is CustomPlayer) player.respawnPoint ??= position.clone();
    gameRef.camera.moveToPlayer();
    removeFromParent();
  }
}

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------

class CustomMapGame extends StatelessWidget {
  const CustomMapGame({super.key});

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
              _CyberButton(
                label: 'BEGIN MISSION',
                onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const CustomMapGameScreen())),
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
            map: CustomMap('maps/world.tmj', objectsBuilder: _mapObjects()),
            cameraConfig: CameraConfig(moveOnlyMapArea: true, zoom: 2.0),
            overlayBuilderMap: {
              'portalReached': (ctx, game) => _PortalOverlay(
                    game: game,
                    onEnter: () => Navigator.of(ctx).pushReplacement(
                      MaterialPageRoute(builder: (_) => const Map2GameScreen()),
                    ),
                  ),
            },
            onReady: (game) {
              _onMapReady(game);
              GameState.resetMap1();
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
            map: CustomMap('maps/world2.tmj', objectsBuilder: _mapObjects()),
            cameraConfig: CameraConfig(moveOnlyMapArea: true, zoom: 2.0),
            overlayBuilderMap: {
              'portalReached': (ctx, game) => _PortalOverlay(
                    game: game,
                    label: 'THE CORE',
                    subtitle: 'Gaia\'s memory is restored. Elysium lives.',
                    onEnter: () => Navigator.of(ctx).pushReplacement(
                      MaterialPageRoute(builder: (_) => const Map3GameScreen()),
                    ),
                  ),
            },
            onReady: (game) {
              _onMapReady(game);
              GameState.resetMap2();
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
              map: CustomMap('maps/world3.tmj', objectsBuilder: _mapObjects()),
              cameraConfig: CameraConfig(moveOnlyMapArea: true, zoom: 2.0),
              overlayBuilderMap: {
                'portalReached': (ctx, game) => _PortalOverlay(
                      game: game,
                      label: 'EXTRACTION POINT',
                      subtitle: 'The ruins hold the final truth.\nElysium\'s fate is decided here.',
                      onEnter: () => Navigator.of(ctx).pushReplacement(
                        MaterialPageRoute(builder: (_) => const _VictoryScreen()),
                      ),
                    ),
              },
              onReady: (game) {
                _onMapReady(game);
                GameState.resetMap3();
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
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.88),
          border: Border.all(color: const Color(0xFF00FFFF), width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF00FFFF),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 5)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(width: 12),
                _CyberButton(label: 'ENTER', onTap: onEnter),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VictoryScreen extends StatelessWidget {
  const _VictoryScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('MISSION COMPLETE',
                  style: TextStyle(
                      color: Color(0xFF00FFCC),
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 5)),
              const SizedBox(height: 12),
              const Text(GameState.endingText,
                  style: TextStyle(color: Colors.white38, fontSize: 14, letterSpacing: 1)),
              const SizedBox(height: 36),
              Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF00FFCC).withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white.withOpacity(0.03),
                ),
                child: const Text(
                  'You reached the Core and activated the Aetherian resonance.\n\n'
                  'Gaia\'s memory floods back — ten thousand years of harmony, of a civilization that chose '
                  'to become one with their world rather than consume it.\n\n'
                  'The UEC drones go silent. Commander Voss withdraws.\n\n'
                  'Elysium breathes again.',
                  style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.75),
                ),
              ),
              const SizedBox(height: 36),
              _CyberButton(
                label: 'PLAY AGAIN',
                onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const CustomMapGameScreen())),
              ),
              const SizedBox(height: 16),
              _CyberButton(
                label: 'MAIN MENU',
                color: Colors.white38,
                onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const IntroScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CyberButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _CyberButton({
    required this.label,
    required this.onTap,
    this.color = const Color(0xFF00FFCC),
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: color.withOpacity(0.12),
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontSize: 13)),
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
                Text('signal lost · returning to the last checkpoint',
                    style: TextStyle(color: Colors.white30, fontSize: 11, letterSpacing: 1.5)),
              ]),
            ),
          ),
        ),
      ),
      // Pause menu
      ValueListenableBuilder<bool>(
        valueListenable: _paused,
        builder: (ctx, paused, __) => paused
            ? Container(
                color: Colors.black.withValues(alpha: 0.7),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06060F).withValues(alpha: 0.96),
                    border: Border.all(color: const Color(0xFF00FFCC).withValues(alpha: 0.6)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('PAUSED',
                        style: TextStyle(
                            color: Color(0xFF00FFCC),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 5)),
                    const SizedBox(height: 18),
                    const _StoryModeToggle(),
                    const SizedBox(height: 18),
                    _CyberButton(label: 'RESUME', onTap: () => _setPaused(false)),
                    const SizedBox(height: 12),
                    _CyberButton(
                      label: 'MAIN MENU',
                      color: Colors.white38,
                      onTap: () {
                        _setPaused(false);
                        Navigator.of(ctx).pushReplacement(
                            MaterialPageRoute(builder: (_) => const IntroScreen()));
                      },
                    ),
                  ]),
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
