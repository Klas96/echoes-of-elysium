import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:bonfire/map/empty_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/sfx_manager.dart';
import '../components/building.dart';
import '../components/custom_player.dart';
import '../components/lamp_light.dart';
import '../components/npc_character.dart';
import '../components/walk_sheet.dart';
import '../creatures/creature_components.dart' show DayClock;
import '../creatures/interaction.dart';
import '../creatures/journal_ui.dart';
import '../game/adventure.dart';
import '../game/save_service.dart';
import 'meal_chip.dart';
import 'room_actions.dart';
import 'room_data.dart';
import 'room_panel.dart';
import 'room_services.dart';
import '../ui/hud_layout.dart';

/// Enterable building interiors (#31).
///
/// E at an enterable building's door fades to a small room scene built from
/// the room's 512x288 background + JSON (collision rects, doormat, spawn,
/// NPCs, interact spots, lights). Stepping onto the doormat fades back out
/// and puts Kaela one step in front of the same exterior door, facing down.
///
/// The room is its own [BonfireWidget] pushed over the paused overworld, so
/// the exterior map keeps all its state. Saving while inside stores the
/// exterior position in front of the door (CONTINUE resumes there).
class Interiors {
  Interiors._();

  static const rooms = ['tea_house', 'noodle_shop', 'archive_library', 'ranger_cabin'];

  /// The archive opens only after the Archivist's seal.
  static bool canEnter(String buildingId) {
    if (!rooms.contains(buildingId)) return false;
    if (buildingId == 'archive_library') return Adventure.flag('archive_opened');
    return true;
  }

  static final _cache = <String, RoomData>{};

  static Future<RoomData> load(String id) async =>
      _cache[id] ??= RoomData.parse(await rootBundle.loadString(RoomData.assetFor(id)));

  static bool _busy = false;

  /// The room currently shown, if any.
  static final current = ValueNotifier<RoomData?>(null);

  /// Top-left for a 32 px player standing one step in front of a building's
  /// door: centred on the door, feet just below the wall base, which is
  /// where the door prompt sits.
  static Vector2 doorFrontFor(Vector2 buildingTopLeft, BuildingDef def) =>
      buildingTopLeft + Vector2(def.door.dx - CustomPlayer.sizePlayer / 2, def.door.dy - 8);

  static Vector2 doorFront(Building b) => doorFrontFor(b.position, b.def);

  static void _placeOutside(Player? p, Vector2 at) {
    if (p == null) return;
    p.position = at.clone();
    p.lastDirection = Direction.down;
    if (p.isMounted) p.stopMove(forceIdle: true);
  }

  static VoidCallback? _leaveRoom;

  /// Leave the current room (the doormat does this).
  static void leave() => _leaveRoom?.call();

  /// Walk into [b]. Safe to call from [Building.interact].
  static Future<void> enter(Building b) =>
      enterAt(b.gameRef, b.id, doorFront(b));

  /// Pause [game], fade into room [id], and on the way out put the player at
  /// [front] (one step before the exterior door) facing down.
  static Future<void> enterAt(BonfireGameInterface game, String id, Vector2 front) async {
    if (_busy || !canEnter(id)) return;
    _busy = true;
    try {
      final room = await load(id);
      final context = game.context;
      if (!context.mounted) return;
      final outside = game.player;
      _placeOutside(outside, front);
      CustomPlayer.pendingShot.value = null;
      NpcCharacter.nearbyNpc = null;
      NpcCharacter.showPrompt.value = false;
      // Saved in front of the door: CONTINUE from inside resumes there.
      await SaveService.saveNow();
      final wasPaused = game.paused;
      if (!wasPaused) game.pauseEngine();
      Interaction.reset();

      // Overlays opened inside (journal) must pause the room, not resume the
      // overworld behind it.
      final journalHook = Journal.onOpenChanged;
      InnRest.setCheckpoint = () {
        if (outside is CustomPlayer) outside.respawnPoint = front.clone();
        SaveService.data.checkpoint = SavePoint(front.x, front.y);
      };
      SfxManager().playFootstep();
      current.value = room;
      try {
        if (!context.mounted) return;
        await Navigator.of(context).push(_route(room));
      } finally {
        current.value = null;
        _leaveRoom = null;
        Journal.onOpenChanged = journalHook;
        InnRest.setCheckpoint = null;
        RoomPanel.onOpenChanged = null;
        RoomPanel.close();
        Interaction.reset();
        _placeOutside(outside, front);
        if (game.context.mounted) {
          if (outside != null && outside.isMounted) game.camera.moveToPlayer();
          if (!wasPaused) game.resumeEngine();
        }
        SaveService.requestAutosave();
      }
    } finally {
      _busy = false;
    }
  }

  static PageRoute<void> _route(RoomData room) => PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 650),
        reverseTransitionDuration: const Duration(milliseconds: 650),
        pageBuilder: (_, __, ___) => RoomScreen(room: room),
        // Fade the overworld to black, then the room in (and back on exit).
        transitionsBuilder: (_, anim, __, child) => Stack(fit: StackFit.expand, children: [
          FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: const Interval(0, 0.45)),
            child: const ColoredBox(color: Colors.black),
          ),
          FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: const Interval(0.55, 1)),
            child: child,
          ),
        ]),
      );
}

/// Tile helpers shared by the room components.
extension _RoomPx on RoomData {
  Vector2 tilePx(int tx, int ty) => Vector2((tx * tile).toDouble(), (ty * tile).toDouble());
}

/// Kaela's feet centre, relative to her 32x32 top-left (feet hitbox centre).
final _feet = Vector2(CustomPlayer.sizePlayer / 2, CustomPlayer.sizePlayer * 0.82);

/// The room scene. Its own small Bonfire game: background, walls, NPCs,
/// spots, lights and a plain walking Kaela (no shooting indoors).
class RoomScreen extends StatefulWidget {
  final RoomData room;
  const RoomScreen({super.key, required this.room});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  BonfireGameInterface? _game;
  bool _leaving = false;

  RoomData get room => widget.room;

  void _hold(bool open) {
    final g = _game;
    if (g == null) return;
    if (open) {
      g.pauseEngine();
    } else if (!RoomPanel.isOpen && !Journal.open.value) {
      g.resumeEngine();
    }
  }

  @override
  void initState() {
    super.initState();
    RoomPanel.onOpenChanged = _hold;
    Journal.onOpenChanged = _hold;
    Interiors._leaveRoom = _leave;
  }

  void _leave() {
    if (_leaving || !mounted) return;
    _leaving = true;
    RoomPanel.close();
    Journal.hide();
    SfxManager().playFootstep();
    Navigator.of(context).pop();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (RoomPanel.isOpen) return RoomPanel.handleKey(e);
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape && Journal.open.value) {
      Journal.hide();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyJ) {
      Journal.toggle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(builder: (context, box) {
          // Fit the whole room when the screen allows, never smaller than
          // 1.5x (pixel art stays readable; portrait scrolls with Kaela).
          final fit = min(box.maxWidth / room.widthPx, box.maxHeight / room.heightPx);
          final zoom = fit.clamp(1.5, 3.0).toDouble();
          return Stack(children: [
            BonfireWidget(
              map: EmptyWorldMap(size: Vector2(room.widthPx - 1, room.heightPx - 1)),
              player: RoomPlayer(room, onDoormat: _leave),
              components: [
                RoomBackground(room),
                for (final r in room.collision) RoomWall(room, r),
                for (final n in room.npcs) RoomNpcSprite(room, n),
                for (final n in room.npcs) RoomWall(room, RoomRect(n.tx, n.ty, 1, 1)),
                for (final l in room.lights) RoomGlow(room, l),
                for (final s in _usableSpots(room)) RoomSpotComponent(room, s),
                InteractionManager(),
                DayClock(),
              ],
              playerControllers: [
                Joystick(directional: JoystickDirectional(size: HudLayout.joystickSize, margin: HudLayout.joystickMargin)),
                Keyboard(
                  config: KeyboardConfig(
                    directionalKeys: [KeyboardDirectionalKeys.arrows(), KeyboardDirectionalKeys.wasd()],
                    acceptedKeys: [],
                  ),
                ),
              ],
              backgroundColor: Colors.black,
              cameraConfig: CameraConfig(moveOnlyMapArea: true, zoom: zoom),
              onReady: (g) {
                _game = g;
                g.camera.moveToPlayer();
              },
            ),
            const _WarmVignette(),
            Positioned(
              top: 12,
              left: 12,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _RoomTitle(room.title),
                const MealChip(), // Dao's bowl is still ticking indoors
              ]),
            ),
            const InteractPromptLayer(),
            const ToastLayer(),
            const RoomPanelLayer(),
            const JournalOverlay(),
          ]);
        }),
      ),
    );
  }
}

/// Spots that get an interactable: when two share a rect (Dao's menu and
/// errand), the first one handles both.
List<RoomSpot> _usableSpots(RoomData room) {
  final seen = <String>{};
  return [
    for (final s in room.spots)
      if (seen.add(s.rect.toString())) s,
  ];
}

class RoomBackground extends GameComponent {
  final RoomData room;
  Sprite? _sprite;
  final _paint = Paint()..filterQuality = FilterQuality.none;

  RoomBackground(this.room) {
    position = Vector2.zero();
    size = Vector2(room.widthPx, room.heightPx);
  }

  @override
  int get priority => LayerPriority.MAP + 1;

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load(room.imagePath);
    return super.onLoad();
  }

  @override
  void render(Canvas canvas) {
    _sprite?.render(canvas, size: size, overridePaint: _paint);
    super.render(canvas);
  }
}

/// An invisible solid tile rect.
class RoomWall extends GameDecorationWithCollision {
  RoomWall(RoomData room, RoomRect r)
      : super(
          position: room.tilePx(r.x, r.y),
          size: Vector2((r.w * room.tile).toDouble(), (r.h * room.tile).toDouble()),
          collisions: [
            RectangleHitbox(size: Vector2((r.w * room.tile).toDouble(), (r.h * room.tile).toDouble()), isSolid: true),
          ],
        );
}

/// Kaela indoors: walks, no gun. Steps onto the doormat to leave (only after
/// she has been off it, never on the frame she appears).
class RoomPlayer extends SimplePlayer with BlockMovementCollision {
  final RoomData room;
  final VoidCallback onDoormat;
  bool _armed = false;
  bool _left = false;
  double _step = 0;
  JogSheet? _jog;

  static const baseSpeed = CustomPlayer.sizePlayer * 2.5;

  RoomPlayer(this.room, {required this.onDoormat})
      : super(
          position: room.tilePx(room.spawn.$1, room.spawn.$2) +
              Vector2(room.tile / 2, room.tile / 2) -
              _feet,
          size: Vector2.all(CustomPlayer.sizePlayer),
          speed: baseSpeed,
          initDirection: Direction.up,
        );

  /// Tile under Kaela's feet.
  (int, int) get tile {
    final f = position + _feet;
    return ((f.x / room.tile).floor(), (f.y / room.tile).floor());
  }

  @override
  Future<void> onLoad() async {
    paint.filterQuality = FilterQuality.none;
    _jog = await JogSheet.load();
    animation = _jog!.animation;
    add(RectangleHitbox(
      size: Vector2(CustomPlayer.feetWidth, CustomPlayer.sizePlayer / 3),
      position: Vector2(CustomPlayer.sizePlayer * 0.25, CustomPlayer.sizePlayer * 0.65),
    ));
    return super.onLoad();
  }

  @override
  void update(double dt) {
    speed = baseSpeed * Meals.speedMultiplier;
    super.update(dt);
    _jog?.setSpeed(velocity.length);
    Meals.tick(dt);
    final (tx, ty) = tile;
    final onMat = room.door.contains(tx, ty);
    if (!onMat) _armed = true;
    if (onMat && _armed && !_left) {
      _left = true;
      stopMove(forceIdle: true);
      onDoormat();
    }
    if (!velocity.isZero()) {
      _step -= dt;
      if (_step <= 0) {
        SfxManager().playFootstep();
        _step = 0.38;
      }
    } else {
      _step = 0;
    }
  }
}

/// A room NPC standing idle (faces Kaela when she is close).
class RoomNpcSprite extends SimpleNpc {
  final RoomNpc npc;
  RoomNpcSprite(RoomData room, this.npc)
      : super(
          position: room.tilePx(npc.tx, npc.ty),
          size: Vector2.all(NpcCharacter.npcSize),
          initDirection: Direction.down,
        );

  @override
  Future<void> onLoad() async {
    paint.filterQuality = FilterQuality.none;
    try {
      animation = await WalkSheet.load('sprites/${npc.sprite}_walk.png');
    } catch (_) {
      final still = SpriteAnimation.spriteList([await Sprite.load('sprites/npc_${npc.sprite}.png')], stepTime: 1);
      animation = SimpleDirectionAnimation(idleRight: still, runRight: still);
    }
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    final p = gameRef.player;
    if (p == null) return;
    final pc = p.position + p.size / 2;
    final c = position + size / 2;
    final d = pc.distanceTo(c) < 56 ? WalkSheet.facing(c, pc) : Direction.down;
    if (lastDirection != d) {
      lastDirection = d;
      if (d == Direction.left || d == Direction.right) lastDirectionHorizontal = d;
      idle();
    }
  }
}

/// A subtle warm pool for each room light (#35 colours; additive, slow
/// flicker on fires). Indoors there is no night tint, so this is just glow.
class RoomGlow extends GameComponent {
  final RoomLight light;
  final LightKind kind;
  final double radius;
  double _t;

  RoomGlow(RoomData room, this.light)
      : kind = switch (light.kind) {
          'fire' => LightKind.fire,
          'neon' => LightKind.neon,
          'cyan' => LightKind.energy,
          _ => LightKind.lamp,
        },
        radius = light.kind == 'fire' ? 52 : 40,
        _t = (light.tx * 1.7 + light.ty * 2.3) {
    position = room.tilePx(light.tx, light.ty) + Vector2.all(room.tile / 2);
    size = Vector2.zero();
  }

  @override
  int get priority => LayerPriority.MAP + 2;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void render(Canvas canvas) {
    final f = kind.flicker;
    final wobble = 1 - f + f * (0.5 + 0.5 * sin(_t * (kind == LightKind.fire ? 7.3 : 1.3)));
    final a = 0.2 * wobble;
    final c = kind.color;
    final shader = RadialGradient(colors: [
      c.withValues(alpha: a),
      c.withValues(alpha: a * 0.35),
      c.withValues(alpha: 0),
    ], stops: const [0, 0.45, 1])
        .createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    canvas.drawCircle(Offset.zero, radius, Paint()
      ..shader = shader
      ..blendMode = BlendMode.plus);
    super.render(canvas);
  }
}

/// An E-press spot. Focusable when Kaela stands on or 4-next to its rect and
/// faces it.
class RoomSpotComponent extends GameComponent with Interactable {
  final RoomData room;
  final RoomSpot spot;

  RoomSpotComponent(this.room, this.spot) {
    position = room.tilePx(spot.rect.x, spot.rect.y);
    size = Vector2((spot.rect.w * room.tile).toDouble(), (spot.rect.h * room.tile).toDouble());
  }

  RoomPlayer? get _player => gameRef.player as RoomPlayer?;

  static bool facing(Direction d, (int, int) step) => switch (step) {
        (0, 0) => true,
        (0, -1) => d == Direction.up || d == Direction.upLeft || d == Direction.upRight,
        (0, 1) => d == Direction.down || d == Direction.downLeft || d == Direction.downRight,
        (-1, 0) => d == Direction.left || d == Direction.upLeft || d == Direction.downLeft,
        (1, 0) => d == Direction.right || d == Direction.upRight || d == Direction.downRight,
        _ => false,
      };

  @override
  bool get canFocus {
    final p = _player;
    if (p == null || RoomPanel.isOpen) return false;
    final (tx, ty) = p.tile;
    final step = room.stepInto(spot.rect, tx, ty);
    return step != null && facing(p.lastDirection, step);
  }

  /// Closest point of the rect to Kaela, so the nearest spot wins.
  @override
  Vector2 get interactPoint {
    final p = _player;
    if (p == null) return absoluteCenter;
    final f = p.position + p.size / 2;
    return Vector2(f.x.clamp(position.x, position.x + size.x), f.y.clamp(position.y, position.y + size.y));
  }

  @override
  double get interactRadius => room.tile * 2.0;

  @override
  PromptInfo get prompt => PromptInfo(promptFor(spot));

  @override
  void interact() => useSpot(room, spot);
}

class _RoomTitle extends StatelessWidget {
  final String title;
  const _RoomTitle(this.title);

  @override
  Widget build(BuildContext context) {
    final name = title.split(':').first.trim();
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          border: Border.all(color: const Color(0x55FFC27A)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(name.toUpperCase(),
              style: const TextStyle(
                  color: Color(0xFFFFC27A), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 2),
          const Text('Step on the doormat to leave',
              style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 0.5)),
        ]),
      ),
    );
  }
}

class _WarmVignette extends StatelessWidget {
  const _WarmVignette();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.1,
              colors: [Color(0x00000000), Color(0x00000000), Color(0x66000000)],
              stops: [0, 0.6, 1],
            ),
          ),
          child: SizedBox.expand(),
        ),
      );
}
