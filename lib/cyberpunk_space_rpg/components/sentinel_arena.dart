import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

/// Temporary lockdown ring around the City Sentinel plaza.
///
/// Thin solid walls + a dim vignette while the fight is active. Cleared on
/// Sentinel death so the plaza opens again for the Archivist beat.
class SentinelArena extends GameComponent {
  static SentinelArena? instance;

  /// Half-width of the square arena (world px) from [arenaCenter].
  static const double halfExtent = 11 * 32; // ~11 tiles
  static const double wallThick = 14;

  final Vector2 arenaCenter;
  bool sealed = false;
  double _pulse = 0;
  final List<_ArenaWall> _walls = [];

  SentinelArena(this.arenaCenter);

  @override
  Future<void> onLoad() async {
    instance = this;
    return super.onLoad();
  }

  @override
  void onRemove() {
    if (instance == this) instance = null;
    super.onRemove();
  }

  /// Raise the fence (idempotent).
  void seal() {
    if (sealed || !hasGameRef) return;
    sealed = true;
    const h = halfExtent;
    const t = wallThick;
    final c = arenaCenter;
    // Top / bottom / left / right slabs just outside the walkable square.
    final rects = <Rect>[
      Rect.fromLTWH(c.x - h - t, c.y - h - t, h * 2 + t * 2, t), // north
      Rect.fromLTWH(c.x - h - t, c.y + h, h * 2 + t * 2, t), // south
      Rect.fromLTWH(c.x - h - t, c.y - h, t, h * 2), // west
      Rect.fromLTWH(c.x + h, c.y - h, t, h * 2), // east
    ];
    for (final r in rects) {
      final w = _ArenaWall(
        Vector2(r.left, r.top),
        Vector2(r.width, r.height),
      );
      _walls.add(w);
      gameRef.add(w);
    }
  }

  /// Drop the fence (idempotent).
  void open() {
    if (!sealed) return;
    sealed = false;
    for (final w in _walls) {
      if (w.isMounted) w.removeFromParent();
    }
    _walls.clear();
  }

  bool containsWorld(Vector2 world) {
    final dx = (world.x - arenaCenter.x).abs();
    final dy = (world.y - arenaCenter.y).abs();
    return dx <= halfExtent && dy <= halfExtent;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (sealed) _pulse += dt * 3;
  }

  @override
  void render(Canvas canvas) {
    if (!sealed) return;
    const h = halfExtent;
    final p = sin(_pulse);
    final c = arenaCenter;
    // Floor wash
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(c.x, c.y),
        width: h * 2,
        height: h * 2,
      ),
      Paint()..color = Color.fromRGBO(255, 80, 20, 0.06 + p * 0.02),
    );
    // Inner rim
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(c.x, c.y),
        width: h * 2,
        height: h * 2,
      ),
      Paint()
        ..color = Color.fromRGBO(255, 100, 40, 0.35 + p * 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    super.render(canvas);
  }

  @override
  int get priority => LayerPriority.MAP + 1;
}

/// Solid slab — player [BlockMovementCollision] treats solid hitboxes as walls.
class _ArenaWall extends GameDecoration {
  _ArenaWall(Vector2 position, Vector2 size)
      : super(position: position, size: size);

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox(size: size, isSolid: true));
    return super.onLoad();
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()..color = const Color(0xCCFF4422),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()
        ..color = const Color(0x88FFAA66)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    super.render(canvas);
  }
}
