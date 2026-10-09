import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../game/adventure.dart';

/// Solid barricade that vanishes when [openFlag] is set (keyed ruins wing).
class StoryGate extends GameComponent {
  final String openFlag;
  double _pulse = 0;

  StoryGate(Vector2 position, Vector2 size, {required this.openFlag}) {
    this.position = position;
    this.size = size;
  }

  bool get _open => Adventure.flag(openFlag);

  @override
  Future<void> onLoad() async {
    if (_open) {
      removeFromParent();
      return;
    }
    add(RectangleHitbox(size: size, isSolid: true));
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 2;
    if (_open && isMounted) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    if (_open) return;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.x, size.y),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      r,
      Paint()..color = const Color(0xFF2A2030).withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..color = const Color(0xFFFF6688).withValues(alpha: 0.45 + 0.15 * (0.5 + 0.5 * (1 - (_pulse % 1))))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'LOCKED',
        style: TextStyle(color: Color(0xFFFFAABB), fontSize: 9, letterSpacing: 1.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.x - tp.width) / 2, (size.y - tp.height) / 2));
  }
}
