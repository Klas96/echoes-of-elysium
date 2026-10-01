import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'walk_sheet.dart';

class NpcDialogue {
  final String name;
  final Color color;
  final List<String> lines;
  final List<String> voicePaths;

  const NpcDialogue({
    required this.name,
    required this.color,
    required this.lines,
    required this.voicePaths,
  });
}

/// Animated NPC. Uses the walk sheet 'sprites/<name>_walk.png' (derived from
/// [spritePath] 'sprites/npc_<name>.png'); falls back to the static sprite
/// if there is no sheet. Idles facing down and turns to face the player when
/// they are within talk range.
class NpcCharacter extends SimpleNpc {
  static NpcCharacter? nearbyNpc;
  static final ValueNotifier<NpcDialogue?> activeDialogue = ValueNotifier(null);
  static final ValueNotifier<bool> showPrompt = ValueNotifier(false);

  static const double npcSize = 32;

  final NpcDialogue dialogue;
  final String spritePath;
  double _pulse = 0;
  static const double _interactRadius = 72;

  // The Tiled objects are 30x30; keep the same centre at 32x32.
  NpcCharacter(Vector2 position, {required this.dialogue, required this.spritePath})
      : super(
          position: position - Vector2.all(1),
          size: Vector2.all(npcSize),
          initDirection: Direction.down,
        );

  String get walkSheetPath =>
      spritePath.replaceFirstMapped(RegExp(r'npc_(\w+)\.png$'), (m) => '${m[1]}_walk.png');

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
    activeDialogue.value = dialogue;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 2.0;

    final player = gameRef.player;
    if (player == null) return;
    final playerCenter = player.position + player.size / 2;
    final center = position + size / 2;
    final near = (playerCenter - center).length < _interactRadius;
    _face(near ? WalkSheet.facing(center, playerCenter) : Direction.down);

    if (near) {
      nearbyNpc = this;
      if (!showPrompt.value) showPrompt.value = true;
    } else if (nearbyNpc == this) {
      nearbyNpc = null;
      showPrompt.value = false;
    }
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;
    final col = dialogue.color;
    final p = sin(_pulse);

    // Soft glow aura
    canvas.drawCircle(
      Offset(cx, cy),
      r + 6 + p * 2,
      Paint()
        ..color = col.withOpacity(0.12 + p * 0.04)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
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
