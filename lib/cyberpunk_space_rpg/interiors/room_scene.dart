import 'dart:math';
import 'dart:ui' as ui;

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
import '../creatures/gates.dart';
import '../creatures/interaction.dart';
import '../creatures/journal_ui.dart';
import '../game/adventure.dart';
import '../game/game_input.dart';
import '../game/keyboard_guard.dart';
import '../game/save_service.dart';
import '../ui/hud_layout.dart';
import 'meal_chip.dart';
import 'room_actions.dart';
import 'room_data.dart';
import 'room_panel.dart';
import 'room_services.dart';

/// Enterable building interiors (#31).
///
/// E at an enterable building's door fades to a small tiled room (12×8 of
/// 32 px, same density as Kaela) built from the JSON floor/props layers
/// (collision rects, doormat, spawn, NPCs, interact spots, lights). Stepping
/// onto the doormat fades back out
/// and puts Kaela one step in front of the same exterior door, facing down.
///
/// The room is its own [BonfireWidget] pushed over the paused overworld, so
/// the exterior map keeps all its state. Saving while inside stores the
/// exterior position in front of the door (CONTINUE resumes there).
class Interiors {
  Interiors._();

  /// Bonfire focus inside a room (separate from [GameInput.focusNode]).
  static final roomFocus = FocusNode(debugLabel: 'roomInput');

  /// Live room Bonfire (for resume after archive_ash / memory overlays).
  static BonfireGameInterface? roomGame;

  static const rooms = [
    'tea_house',
    'noodle_shop',
    'archive_library',
    'ranger_cabin',
    'pond_grotto',
  ];

  /// Click talk/examine indoors, or click-move on the floor (same as overworld).
  static void handleRoomClick(BonfireGameInterface game, Vector2 screen) {
    final player = RoomPlayer.current;
    if (player == null || !player.isMounted || !player.hasGameRef) return;
    // Panels/cutscenes can leave the room engine paused — wake it for moves.
    if (game.paused && !RoomPanel.isOpen && !Journal.open.value) {
      game.resumeEngine();
    }
    final cam = game.camera.viewfinder.position;
    final center = game.size / 2;
    final zoom = game.camera.viewfinder.zoom;
    final world = cam + (screen - center) / zoom;
    final flame = player.findGame();
    if (flame == null) return;
    final hit = Interaction.atWorld(world, game: flame, clickRadius: 48);
    if (hit != null && hit.prompt.enabled) {
      final dest = hit.interactPoint - player.size / 2;
      final dist = player.position.distanceTo(dest);
      if (dist <= hit.interactRadius + 8) {
        hit.interact();
      } else {
        player.walkTo(hit.interactPoint, onArrive: () {
          if (hit.isMounted) hit.interact();
        });
      }
      return;
    }
    for (final n in player.gameRef.query<RoomNpcSprite>()) {
      if (!n.isMounted) continue;
      final c = n.position + n.size / 2;
      if (c.distanceTo(world) > 40) continue;
      final dest = c;
      if (player.position.distanceTo(dest - player.size / 2) <= 36) {
        n.interact();
      } else {
        player.walkTo(dest, onArrive: () {
          if (n.isMounted) n.interact();
        });
      }
      return;
    }
    // Empty floor / furniture: path around solids to the click.
    player.walkTo(world);
  }

  static void _reclaimRoomKeys() {
    KeyboardGuard.releaseAll();
    void apply() {
      if (roomFocus.context != null && roomFocus.canRequestFocus) {
        roomFocus.requestFocus();
      }
      final g = roomGame;
      // Cutscenes leave the room paused under an open panel; if nothing is
      // holding it, start ticking again so WASD can move Kaela.
      if (g != null && g.paused && !RoomPanel.isOpen && !Journal.open.value) {
        g.resumeEngine();
      }
      RoomPlayer.current?.syncMovementFromKeyboard();
    }

    apply();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      apply();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        apply();
        Future<void>.delayed(const Duration(milliseconds: 500), apply);
      });
    });
  }

  /// The archive opens only after the Archivist's seal; the pond grotto only
  /// after LIGHT (`woods_grotto`).
  static bool canEnter(String buildingId) {
    if (!rooms.contains(buildingId)) return false;
    // Door unlock (seal) or already read the draft on an older save.
    if (buildingId == 'archive_library') {
      return Adventure.flag('archive_opened') || Adventure.openedArchive;
    }
    if (buildingId == 'pond_grotto') return Gates.isOpen('woods_grotto');
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
    // Enter a touch slower than exit — walking out used to feel laggy because
    // we waited a full second fade twice (route reverse + an extra delay).
    const fadeIn = Duration(milliseconds: 380);
    const fadeOut = Duration(milliseconds: 260);
    try {
      final room = await load(id);
      final context = game.context;
      if (!context.mounted) return;
      final outside = game.player;
      _placeOutside(outside, front);
      CustomPlayer.pendingShot.value = null;
      NpcCharacter.nearbyNpc = null;
      NpcCharacter.showPrompt.value = false;
      // Door-front checkpoint for CONTINUE; don't block the fade on disk I/O.
      SaveService.requestAutosave();
      final wasPaused = game.paused;
      final wePaused = !wasPaused;
      if (wePaused) game.pauseEngine();
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
      GameInput.overworldKeysEnabled = false;
      GameInput.reclaimAlternate = _reclaimRoomKeys;
      GameInput.syncAlternateKeys = () => RoomPlayer.current?.syncMovementFromKeyboard();
      try {
        if (!context.mounted) return;
        // Completes after the reverse (exit) transition finishes — no second wait.
        await Navigator.of(context).push(_route(room, fadeIn, fadeOut));
      } finally {
        current.value = null;
        _leaveRoom = null;
        Journal.onOpenChanged = journalHook;
        InnRest.setCheckpoint = null;
        RoomPanel.onOpenChanged = null;
        RoomPanel.close();
        Interaction.reset();
        _placeOutside(outside, front);
        roomGame = null;
        GameInput.overworldKeysEnabled = true;
        GameInput.reclaimAlternate = null;
        GameInput.syncAlternateKeys = null;
        if (game.context.mounted) {
          if (outside != null && outside.isMounted) game.camera.moveToPlayer();
          // Always unpause if we paused on the way in (a memory played inside
          // may have left the overworld paused).
          if (wePaused) game.resumeEngine();
          GameInput.reclaim();
        }
        SaveService.requestAutosave();
      }
    } finally {
      roomGame = null;
      GameInput.overworldKeysEnabled = true;
      GameInput.reclaimAlternate = null;
      GameInput.syncAlternateKeys = null;
      _busy = false;
    }
  }

  static PageRoute<void> _route(RoomData room, Duration fadeIn, Duration fadeOut) =>
      PageRouteBuilder<void>(
        transitionDuration: fadeIn,
        reverseTransitionDuration: fadeOut,
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
    // Stop the indoor Bonfire before the fade-out so teardown work does not
    // hitch the reverse transition (and the overworld resume after it).
    _game?.pauseEngine();
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
      canRequestFocus: false,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(builder: (context, box) {
          // Fit the whole room when the screen allows; desktop needs a higher
          // floor so interiors match the closer overworld view.
          final fit = min(box.maxWidth / room.widthPx, box.maxHeight / room.heightPx);
          final minZ = HudLayout.isTouch ? 1.5 : 2.0;
          final maxZ = HudLayout.isTouch ? 3.0 : 3.5;
          final zoom = fit.clamp(minZ, maxZ).toDouble();
          return Stack(children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (d) {
                if (RoomPanel.isOpen || Journal.open.value) return;
                final g = _game;
                if (g == null) return;
                Interiors.handleRoomClick(g, Vector2(d.localPosition.dx, d.localPosition.dy));
              },
              child: BonfireWidget(
              focusNode: Interiors.roomFocus,
              autofocus: true,
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
                Interiors.roomGame = g;
                g.camera.moveToPlayer();
              },
            )),
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
  ui.Image? _baked;
  Sprite? _sprite;
  final _paint = Paint()..filterQuality = FilterQuality.none;

  RoomBackground(this.room) {
    position = Vector2.zero();
    size = Vector2(room.widthPx, room.heightPx);
  }

  @override
  int get priority => LayerPriority.MAP + 1;

  bool get _tiled => room.floor.isNotEmpty;

  @override
  Future<void> onLoad() async {
    if (_tiled) {
      // Compose once: per-frame blit of 12×8 floor+props was a hitch indoors.
      final sheet = await Flame.images.load('interiors/${room.tileset}');
      _baked = await _bake(sheet);
    } else {
      _sprite = await Sprite.load(room.imagePath);
    }
    return super.onLoad();
  }

  Future<ui.Image> _bake(ui.Image sheet) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final s = room.tile.toDouble();
    void blit(int id, int tx, int ty) {
      final src = Rect.fromLTWH(
        ((id % room.sheetCols) * room.tile).toDouble(),
        ((id ~/ room.sheetCols) * room.tile).toDouble(),
        s,
        s,
      );
      canvas.drawImageRect(sheet, src, Rect.fromLTWH(tx * s, ty * s, s, s), _paint);
    }

    bool isWall(int id) => (id >= 16 && id < 36) || (id >= 70 && id < 80);

    for (var y = 0; y < room.rows; y++) {
      final floor = room.floor[y];
      final props = y < room.props.length ? room.props[y] : const <int>[];
      for (var x = 0; x < room.cols; x++) {
        blit(floor[x], x, y);
        if (x < props.length && props[x] > 0) blit(props[x], x, y);
      }
    }

    // Floor contact shadow where walkable tiles meet walls.
    final shade = Paint()
      ..color = const Color(0x55000000)
      ..blendMode = BlendMode.srcOver;
    for (var y = 0; y < room.rows; y++) {
      final row = room.floor[y];
      for (var x = 0; x < room.cols; x++) {
        if (isWall(row[x])) continue;
        final px = x * s;
        final py = y * s;
        if (x > 0 && isWall(row[x - 1])) {
          canvas.drawRect(Rect.fromLTWH(px, py, 4, s), shade);
        }
        if (x < room.cols - 1 && isWall(row[x + 1])) {
          canvas.drawRect(Rect.fromLTWH(px + s - 4, py, 4, s), shade);
        }
        if (y > 0 && isWall(room.floor[y - 1][x])) {
          canvas.drawRect(Rect.fromLTWH(px, py, s, 5), shade);
        }
        if (y < room.rows - 1 && isWall(room.floor[y + 1][x])) {
          canvas.drawRect(Rect.fromLTWH(px, py + s - 3, s, 3), shade);
        }
      }
    }

    // Soft outer rim against letterbox black.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF100806);
    canvas.drawRect(Rect.fromLTWH(0.5, 0.5, room.widthPx - 1, room.heightPx - 1), rim);
    final rim2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x66000000);
    canvas.drawRect(Rect.fromLTWH(1.5, 1.5, room.widthPx - 3, room.heightPx - 3), rim2);

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(room.widthPx.round(), room.heightPx.round());
    } finally {
      picture.dispose();
    }
  }

  @override
  void onRemove() {
    final img = _baked;
    _baked = null;
    // Defer GPU dispose so it does not stall the exit fade / overworld resume.
    if (img != null) {
      Future<void>.microtask(img.dispose);
    }
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    final baked = _baked;
    if (baked != null) {
      canvas.drawImage(baked, Offset.zero, _paint);
    } else {
      _sprite?.render(canvas, size: size, overridePaint: _paint);
    }
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
class RoomPlayer extends SimplePlayer with BlockMovementCollision, InstantFacing {
  final RoomData room;
  final VoidCallback onDoormat;
  bool _armed = false;
  bool _left = false;
  double _step = 0;
  JogSheet? _jog;
  final List<Vector2> _waypoints = [];
  int _wpIndex = 0;
  VoidCallback? _onArrive;

  /// Indoors Kaela — [GameInput] steers her when Bonfire loses focus.
  static RoomPlayer? current;

  static const baseSpeed = CustomPlayer.sizePlayer * 2.5;
  static const _arrive = 10.0;

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

  Vector2 _positionForTile((int, int) t) =>
      room.tilePx(t.$1, t.$2) + Vector2(room.tile / 2, room.tile / 2) - _feet;

  @override
  Future<void> onLoad() async {
    current = this;
    setupMovementByJoystick(enabled: true);
    paint.filterQuality = FilterQuality.none;
    _jog = await JogSheet.load();
    animation = _jog!.animation;
    // Same feet box as overworld Kaela so indoor gaps match outdoor feel.
    add(RectangleHitbox(
      size: Vector2(CustomPlayer.feetWidth, CustomPlayer.feetHeight),
      position: Vector2(
        (CustomPlayer.sizePlayer - CustomPlayer.feetWidth) / 2,
        CustomPlayer.feetTop,
      ),
    ));
    return super.onLoad();
  }

  @override
  void onRemove() {
    if (identical(current, this)) current = null;
    super.onRemove();
  }

  /// League-style click path on the room grid (around tables/counters).
  void walkTo(Vector2 worldPoint, {VoidCallback? onArrive}) {
    if (RoomPanel.isOpen || Journal.open.value) return;
    if (hasGameRef && gameRef.paused) gameRef.resumeEngine();
    final to = (
      (worldPoint.x / room.tile).floor().clamp(0, room.cols - 1),
      (worldPoint.y / room.tile).floor().clamp(0, room.rows - 1),
    );
    final cells = room.path(tile, to);
    _onArrive = onArrive;
    _waypoints
      ..clear()
      ..addAll(cells.map(_positionForTile));
    _wpIndex = 0;
    if (_waypoints.isEmpty) {
      _finishWalk();
      return;
    }
  }

  void _clearWalk({bool runArrive = false}) {
    _waypoints.clear();
    _wpIndex = 0;
    final cb = _onArrive;
    _onArrive = null;
    if (runArrive) cb?.call();
  }

  void _finishWalk() {
    stopMove(forceIdle: true);
    _clearWalk(runArrive: true);
  }

  void _followWalk() {
    while (_wpIndex < _waypoints.length &&
        position.distanceTo(_waypoints[_wpIndex]) <= _arrive) {
      _wpIndex++;
    }
    if (_wpIndex >= _waypoints.length) {
      _finishWalk();
      return;
    }
    final dest = _waypoints[_wpIndex];
    final d = dest - position;
    if (d.length < 1) {
      _wpIndex++;
      return;
    }
    final n = d.normalized();
    final JoystickMoveDirectional dir;
    if (n.y < -0.4 && n.x < -0.4) {
      dir = JoystickMoveDirectional.MOVE_UP_LEFT;
    } else if (n.y < -0.4 && n.x > 0.4) {
      dir = JoystickMoveDirectional.MOVE_UP_RIGHT;
    } else if (n.y > 0.4 && n.x < -0.4) {
      dir = JoystickMoveDirectional.MOVE_DOWN_LEFT;
    } else if (n.y > 0.4 && n.x > 0.4) {
      dir = JoystickMoveDirectional.MOVE_DOWN_RIGHT;
    } else if (n.y < -0.4) {
      dir = JoystickMoveDirectional.MOVE_UP;
    } else if (n.y > 0.4) {
      dir = JoystickMoveDirectional.MOVE_DOWN;
    } else if (n.x < -0.4) {
      dir = JoystickMoveDirectional.MOVE_LEFT;
    } else if (n.x > 0.4) {
      dir = JoystickMoveDirectional.MOVE_RIGHT;
    } else {
      dir = JoystickMoveDirectional.IDLE;
    }
    onJoystickChangeDirectional(JoystickDirectionalEvent(
      directional: dir,
      intensity: 1.0,
      isKeyboard: true,
    ));
  }

  /// Focus-independent WASD (same mapping as overworld [CustomPlayer]).
  /// Returns true when a move key is held.
  bool syncMovementFromKeyboard() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final up = keys.contains(LogicalKeyboardKey.keyW) ||
        keys.contains(LogicalKeyboardKey.arrowUp);
    final down = keys.contains(LogicalKeyboardKey.keyS) ||
        keys.contains(LogicalKeyboardKey.arrowDown);
    final left = keys.contains(LogicalKeyboardKey.keyA) ||
        keys.contains(LogicalKeyboardKey.arrowLeft);
    final right = keys.contains(LogicalKeyboardKey.keyD) ||
        keys.contains(LogicalKeyboardKey.arrowRight);
    final held = up || down || left || right;
    if (held) _clearWalk();

    final JoystickMoveDirectional dir;
    if (up && left) {
      dir = JoystickMoveDirectional.MOVE_UP_LEFT;
    } else if (up && right) {
      dir = JoystickMoveDirectional.MOVE_UP_RIGHT;
    } else if (down && left) {
      dir = JoystickMoveDirectional.MOVE_DOWN_LEFT;
    } else if (down && right) {
      dir = JoystickMoveDirectional.MOVE_DOWN_RIGHT;
    } else if (up) {
      dir = JoystickMoveDirectional.MOVE_UP;
    } else if (down) {
      dir = JoystickMoveDirectional.MOVE_DOWN;
    } else if (left) {
      dir = JoystickMoveDirectional.MOVE_LEFT;
    } else if (right) {
      dir = JoystickMoveDirectional.MOVE_RIGHT;
    } else {
      dir = JoystickMoveDirectional.IDLE;
    }

    // Don't IDLE over an active click-path — follower owns the stick.
    if (dir == JoystickMoveDirectional.IDLE && _waypoints.isNotEmpty) {
      return false;
    }

    onJoystickChangeDirectional(JoystickDirectionalEvent(
      directional: dir,
      intensity: dir == JoystickMoveDirectional.IDLE ? 0.0 : 1.0,
      isKeyboard: true,
    ));
    return held;
  }

  @override
  void update(double dt) {
    speed = baseSpeed * Meals.speedMultiplier;
    if (!RoomPanel.isOpen && !Journal.open.value) {
      if (hasGameRef && gameRef.paused) gameRef.resumeEngine();
      final held = syncMovementFromKeyboard();
      if (!held && _waypoints.isNotEmpty) _followWalk();
    }
    super.update(dt);
    _jog?.setSpeed(velocity.length);
    Meals.tick(dt);
    final (tx, ty) = tile;
    final onMat = room.door.contains(tx, ty);
    if (!onMat) _armed = true;
    if (onMat && _armed && !_left) {
      _left = true;
      _clearWalk();
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
  final RoomData room;
  final RoomNpc npc;
  RoomNpcSprite(this.room, this.npc)
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

  /// Click-to-talk: run the matching interact spot (id = name / role).
  void interact() {
    if (RoomPanel.isOpen) return;
    for (final s in room.spots) {
      if (s.id == npc.name || s.id == npc.role) {
        useSpot(room, s);
        return;
      }
    }
    for (final s in room.spots) {
      if (s.kind == 'npc' || s.kind == 'errand') {
        useSpot(room, s);
        return;
      }
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
  final Paint _paint = Paint()..blendMode = BlendMode.plus;

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
    // Reuse paint; rebuild only the gradient (cheap vs recreating Paint).
    _paint.shader = RadialGradient(colors: [
      c.withValues(alpha: a),
      c.withValues(alpha: a * 0.35),
      c.withValues(alpha: 0),
    ], stops: const [0, 0.45, 1])
        .createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    canvas.drawCircle(Offset.zero, radius, _paint);
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
    // Distance is handled by InteractionManager / click radius — no facing gate.
    return _player != null && !RoomPanel.isOpen;
  }

  @override
  Vector2 get interactPoint => absoluteCenter;

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
