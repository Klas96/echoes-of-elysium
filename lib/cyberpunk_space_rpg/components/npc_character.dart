import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

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

class NpcCharacter extends GameDecoration {
  static NpcCharacter? nearbyNpc;
  static final ValueNotifier<NpcDialogue?> activeDialogue = ValueNotifier(null);
  static final ValueNotifier<bool> showPrompt = ValueNotifier(false);

  final NpcDialogue dialogue;
  final String spritePath;
  double _pulse = 0;
  Sprite? _sprite;
  static const double _interactRadius = 72;

  NpcCharacter(Vector2 position, {required this.dialogue, required this.spritePath})
      : super(position: position, size: Vector2.all(30));

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load(spritePath);
    return super.onLoad();
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
    final dist = ((player.position + player.size / 2) - (position + size / 2)).length;
    final near = dist < _interactRadius;

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

    // Sprite
    if (_sprite != null) {
      _sprite!.render(canvas, size: size);
    }

    // Floating chat bubble indicator
    final by = cy - r - 10 + p * 2.5;
    canvas.drawCircle(Offset(cx, by), 4.0, Paint()..color = col);
    canvas.drawCircle(Offset(cx - 5, by + 6), 2.5, Paint()..color = col.withOpacity(0.55));
    canvas.drawCircle(Offset(cx - 9, by + 10), 1.5, Paint()..color = col.withOpacity(0.3));
  }
}
