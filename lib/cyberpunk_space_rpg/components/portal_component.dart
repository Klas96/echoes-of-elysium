import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import '../audio/music_manager.dart';
import '../game/game_state.dart';

class PortalComponent extends GameDecoration {
  static const double _radius = 28.0;
  final bool Function() canActivate;
  double _pulse = 0.0;
  bool _triggered = false;

  PortalComponent(Vector2 position, {bool Function()? canActivate})
      : canActivate = canActivate ?? (() => GameState.portalUnlocked.value),
        super(position: position, size: Vector2.all(_radius * 2));

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 3.0;

    if (_triggered) return;
    if (!canActivate()) return;
    final player = gameRef.player;
    if (player == null) return;
    final dist = ((player.position + player.size / 2) - (position + size / 2)).length;
    if (dist < _radius) {
      _triggered = true;
      SfxManager().playPortal();
      gameRef.overlays.add('portalReached');
    }
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    final outerRadius = _radius + sin(_pulse) * 4;

    // Outer glow rings
    for (int i = 3; i >= 1; i--) {
      canvas.drawCircle(
        center,
        outerRadius + i * 5,
        Paint()
          ..color = const Color(0xFF00FFFF).withOpacity(0.06 * i)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Portal body
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()..color = const Color(0xFF001F3F).withOpacity(0.85),
    );
    canvas.drawCircle(
      center,
      outerRadius * 0.65,
      Paint()..color = const Color(0xFF00FFFF).withOpacity(0.25 + sin(_pulse) * 0.1),
    );

    // Spinning arc ring
    final arcPaint = Paint()
      ..color = const Color(0xFF00FFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      _pulse,
      pi * 1.4,
      false,
      arcPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      _pulse + pi,
      pi * 1.4,
      false,
      arcPaint..color = const Color(0xFF7F00FF),
    );

    // Inner bright core
    canvas.drawCircle(
      center,
      6 + sin(_pulse * 2) * 2,
      Paint()..color = Colors.white.withOpacity(0.9),
    );
  }
}
