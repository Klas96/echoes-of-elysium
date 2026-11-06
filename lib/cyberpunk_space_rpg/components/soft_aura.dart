import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class _AuraCache {
  ui.Shader? shader;
  Offset? center;
  int rKey = -1;
  int aKey = -1;
  int cKey = -1;
}

final _scratch = Paint();
final _caches = Expando<_AuraCache>('softAura');

/// Soft body glow without [MaskFilter.blur] (hard circle on web / laggy).
/// Radial falloff reads as a halo; draw under the sprite.
///
/// Caches the radial shader on the caller's [paint] (or a shared scratch)
/// so night walk/combat with many auras does not allocate a Gradient every
/// frame. Pulse alpha is quantized so small sin() wobble keeps the cache.
void paintSoftAura(
  Canvas canvas,
  Offset center,
  double radius,
  Color color, {
  double coreAlpha = 0.28,
  Paint? paint,
}) {
  final p = paint ?? _scratch;
  final cache = _caches[p] ??= _AuraCache();
  final aKey = (coreAlpha * 40).round();
  final rKey = (radius * 2).round();
  final cKey = Object.hash(color.r, color.g, color.b);
  if (cache.shader == null ||
      cache.center != center ||
      cache.rKey != rKey ||
      cache.aKey != aKey ||
      cache.cKey != cKey) {
    cache
      ..center = center
      ..rKey = rKey
      ..aKey = aKey
      ..cKey = cKey
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: coreAlpha),
          color.withValues(alpha: coreAlpha * 0.45),
          color.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
  }
  p
    ..maskFilter = null
    ..shader = cache.shader;
  canvas.drawCircle(center, radius, p);
  p.shader = null;
}
