import 'dart:math';
import 'dart:ui';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

/// Short cyan flare at the shot origin — juice without a fake shoot sheet.
class MuzzleFlash extends GameComponent {
  final Vector2 dir;
  double _age = 0;
  static const _life = 0.11;
  final _rng = Random();
  late final List<Offset> _sparks;

  MuzzleFlash(Vector2 center, this.dir) {
    position = center - Vector2.all(12);
    size = Vector2.all(24);
    _sparks = List.generate(5, (_) {
      final spread = (_rng.nextDouble() - 0.5) * 0.9;
      final len = 4.0 + _rng.nextDouble() * 7;
      final ang = atan2(dir.y, dir.x) + spread;
      return Offset(cos(ang) * len, sin(ang) * len);
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_age >= _life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final u = (_age / _life).clamp(0.0, 1.0);
    final fade = (1.0 - u);
    final stretch = 1.0 + u * 1.8;
    final cx = size.x / 2;
    final cy = size.y / 2;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(atan2(dir.y, dir.x));

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(5 * stretch, 0),
        width: 16 * stretch,
        height: 9 * fade,
      ),
      Paint()
        ..color = const Color(0xFF44DDEE).withValues(alpha: 0.4 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(4 * stretch, 0),
        width: 8 * stretch,
        height: 3.5,
      ),
      Paint()..color = const Color(0xFFE8FFFF).withValues(alpha: 0.95 * fade),
    );
    canvas.drawCircle(
      const Offset(2, 0),
      2.0 * (1.1 - u * 0.4),
      Paint()..color = Colors.white.withValues(alpha: fade),
    );

    // Tiny sparks along the aim cone
    final sparkPaint = Paint()
      ..color = const Color(0xFF66F0FF).withValues(alpha: 0.7 * fade)
      ..strokeWidth = 1;
    for (final s in _sparks) {
      canvas.drawLine(Offset.zero, s * (0.6 + u), sparkPaint);
    }
    canvas.restore();
  }
}
