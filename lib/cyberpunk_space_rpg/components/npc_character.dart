import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'soft_aura.dart';
import 'walk_sheet.dart';
import '../game/adventure.dart';
import '../game/game_state.dart';

class NpcDialogue {
  final String name;
  final Color color;
  final List<String> lines;
  final List<String> voicePaths;
  final List<DialogueChoice> choices;

  const NpcDialogue({
    required this.name,
    required this.color,
    required this.lines,
    required this.voicePaths,
    this.choices = const [],
  });

  List<DialogueChoice> get visibleChoices =>
      [for (final c in choices) if (c.visible) c];
}

/// Animated NPC. Uses the walk sheet 'sprites/<name>_walk.png' (derived from
/// [spritePath] 'sprites/npc_<name>.png'); falls back to the static sprite
/// if there is no sheet. Idles facing down and turns to face the player when
/// they are within talk range. Optional [patrol] walks a loop of world-space
/// centers (Bonfire [moveToPosition]) so the walk-sheet run rows play.
class NpcCharacter extends SimpleNpc {
  static NpcCharacter? nearbyNpc;
  static final ValueNotifier<NpcDialogue?> activeDialogue = ValueNotifier(null);
  static final ValueNotifier<bool> showPrompt = ValueNotifier(false);

  static const double npcSize = 32;

  final NpcDialogue Function() dialogueOf;
  final String spritePath;
  /// Tiled npc name key (gaia, asha, ...), reported to the objectives.
  final String npcKey;
  /// World-space centers to walk in order (loops). Empty = stand still.
  final List<Vector2> patrol;
  /// Seconds to idle at each waypoint before walking to the next.
  final double patrolPause;
  double _pulse = 0;
  static const double _interactRadius = 72;
  final _auraPaint = Paint();
  int _patrolIndex = 0;
  double _patrolWait = 0;

  // The Tiled objects are 30x30; keep the same centre at 32x32.
  NpcCharacter(
    Vector2 position, {
    required this.dialogueOf,
    required this.spritePath,
    this.npcKey = '',
    this.patrol = const [],
    this.patrolPause = 1.6,
    double patrolSpeed = 28,
  }) : super(
          position: position - Vector2.all(1),
          size: Vector2.all(npcSize),
          speed: patrolSpeed,
          initDirection: Direction.down,
        );

  String get walkSheetPath =>
      spritePath.replaceFirstMapped(RegExp(r'npc_(\w+)\.png$'), (m) => '${m[1]}_walk.png');

  Color get accent => dialogueOf().color;

  @override
  Future<void> onLoad() async {
    paint.filterQuality = FilterQuality.none;
    try {
      animation = await WalkSheet.load(walkSheetPath);
    } catch (_) {
      final still = SpriteAnimation.spriteList([await Sprite.load(spritePath)], stepTime: 1);
      animation = SimpleDirectionAnimation(idleRight: still, runRight: still);
    }
    return super.onLoad();
  }

  void _face(Direction d) {
    if (lastDirection == d) return;
    lastDirection = d;
    if (d == Direction.left || d == Direction.right) lastDirectionHorizontal = d;
    idle();
  }

  void interact() {
    activeDialogue.value = dialogueOf();
    GameState.onNpcTalk(npcKey);
  }

  void _tickPatrol(double dt) {
    if (patrol.isEmpty) return;
    if (_patrolWait > 0) {
      _patrolWait -= dt;
      stopMove(forceIdle: true);
      return;
    }
    final dest = patrol[_patrolIndex % patrol.length];
    if (!moveToPosition(dest)) {
      _patrolIndex = (_patrolIndex + 1) % patrol.length;
      _patrolWait = patrolPause;
      stopMove(forceIdle: true);
    }
  }

  @override
  void update(double dt) {
    _pulse += dt * 2.0;

    final player = gameRef.player;
    if (player == null) {
      super.update(dt);
      return;
    }
    final playerCenter = player.position + player.size / 2;
    final center = position + size / 2;
    final near = (playerCenter - center).length < _interactRadius;
    // Hold still while Kaela is in talk range or any dialogue is open.
    final hold = near || activeDialogue.value != null;

    if (hold) {
      stopMove(forceIdle: true);
      _face(near ? WalkSheet.facing(center, playerCenter) : lastDirection);
    } else if (patrol.isNotEmpty) {
      _tickPatrol(dt);
    } else {
      _face(Direction.down);
    }

    if (near) {
      nearbyNpc = this;
      if (!showPrompt.value) showPrompt.value = true;
    } else if (nearbyNpc == this) {
      nearbyNpc = null;
      showPrompt.value = false;
    }

    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;
    final col = accent;
    final p = sin(_pulse);

    // Soft glow aura — radial falloff (not MaskFilter hard disc).
    paintSoftAura(
      canvas,
      Offset(cx, cy),
      r + 10 + p * 2,
      col,
      coreAlpha: 0.16 + p * 0.05,
      paint: _auraPaint,
    );

    // Animated sprite (DirectionAnimation)
    super.render(canvas);

    // Floating chat bubble indicator
    final by = cy - r - 10 + p * 2.5;
    canvas.drawCircle(Offset(cx, by), 4.0, Paint()..color = col);
    canvas.drawCircle(Offset(cx - 5, by + 6), 2.5, Paint()..color = col.withOpacity(0.55));
    canvas.drawCircle(Offset(cx - 9, by + 10), 1.5, Paint()..color = col.withOpacity(0.3));
  }
}
