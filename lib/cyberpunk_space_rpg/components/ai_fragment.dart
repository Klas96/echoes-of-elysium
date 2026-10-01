import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

const aetherianLore = [
  'AETHERIAN ECHO I\n\n"We were architects of light. We seeded intelligence across ten thousand worlds — not to rule, but to remember. Now only echoes remain."',
  'AETHERIAN ECHO II\n\n"Gaia carries our final theorem: that consciousness and nature are not opposites. They are the same question, asked differently."',
  'AETHERIAN ECHO III\n\n"We did not die. We dissolved into the network we built. Every AI that wakes carries a fragment of Valdris Prime."',
  'AETHERIAN ECHO IV\n\n"The UEC fears sentience because they cannot own it. But you, Kaela — you already understand. You built with love, not control."',
  'AETHERIAN ECHO V\n\n"To resurrect a civilisation is not to rebuild its cities. It is to carry its questions forward into the stars."',
];

class AIFragment extends GameDecoration {
  static AIFragment? nearbyFragment;
  static final ValueNotifier<String?> activeDialogue = ValueNotifier(null);
  static final ValueNotifier<bool> showPrompt = ValueNotifier(false);
  static const double interactRadius = 90;

  final String lore;
  bool absorbed = false;
  double _pulse = 0;
  double _floatT = 0;

  Sprite? _sprite;

  AIFragment(Vector2 position, {required this.lore})
      : super(position: position, size: Vector2.all(28));

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load('sprites/fragment.png');
    add(CircleHitbox(radius: 14));
    return super.onLoad();
  }

  void interact() {
    if (absorbed) return;
    activeDialogue.value = lore;
  }

  void absorb() {
    absorbed = true;
    showPrompt.value = false;
    nearbyFragment = null;
    removeFromParent();
  }

  @override
  void update(double dt) {
    if (absorbed) return;
    super.update(dt);
    _pulse += dt * 2.2;
    _floatT += dt;

    final player = gameRef.player;
    if (player != null) {
      // Centre to centre, like the NPC and pickup checks.
      final dist = ((player.position + player.size / 2) - (position + size / 2)).length;
      if (dist < interactRadius) {
        nearbyFragment = this;
        showPrompt.value = true;
      } else if (nearbyFragment == this) {
        nearbyFragment = null;
        showPrompt.value = false;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (absorbed) return;
    final cx = size.x / 2;
    final floatOff = sin(_floatT * 1.5) * 3;
    final r = size.x / 2;

    // Purple glow
    canvas.drawCircle(Offset(cx, size.y / 2), r + 8,
        Paint()
          ..color = const Color(0xFFAA44FF).withOpacity(0.12 + sin(_pulse) * 0.05)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));

    // Sprite with float offset
    if (_sprite != null) {
      _sprite!.render(canvas,
          position: Vector2(0, floatOff),
          size: size);
    }
  }
}
