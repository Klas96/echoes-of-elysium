import 'package:flutter/material.dart';

/// Soft body glow without [MaskFilter.blur] (hard circle on web / laggy).
/// Radial falloff reads as a halo; draw under the sprite.
void paintSoftAura(
  Canvas canvas,
  Offset center,
  double radius,
  Color color, {
  double coreAlpha = 0.28,
  Paint? paint,
}) {
  final p = paint ?? Paint();
  p
    ..maskFilter = null
    ..shader = RadialGradient(
      colors: [
        color.withValues(alpha: coreAlpha),
        color.withValues(alpha: coreAlpha * 0.45),
        color.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
  canvas.drawCircle(center, radius, p);
  p.shader = null;
}
