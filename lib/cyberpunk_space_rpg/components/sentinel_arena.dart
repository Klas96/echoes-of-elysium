import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

/// Temporary lockdown ring around the City Sentinel plaza.
///
/// Hard-pixel UEC energy fence + corner pylons + floor rim while the fight is
/// active. Cleared on Sentinel death so the plaza opens again for the
/// Archivist beat.
class SentinelArena extends GameComponent {
  static SentinelArena? instance;

  /// Half-width of the square arena (world px) from [arenaCenter].
  static const double halfExtent = 11 * 32; // ~11 tiles
  static const double wallThick = 14;
  static const double _tile = 32;

  final Vector2 arenaCenter;
  bool sealed = false;
  double _pulse = 0;
  final List<_ArenaWall> _walls = [];
  final List<GameComponent> _decor = [];

  Sprite? _fence;
  Sprite? _pylon;
  Sprite? _rim;

  SentinelArena(this.arenaCenter);

  @override
  Future<void> onLoad() async {
    instance = this;
    try {
      _fence = await Sprite.load('sprites/sentinel_fence.png');
      _pylon = await Sprite.load('sprites/sentinel_pylon.png');
      _rim = await Sprite.load('sprites/sentinel_rim.png');
    } catch (_) {
      // Missing art falls back to procedural neon slabs in [_ArenaWall].
    }
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
        fence: _fence,
      );
      _walls.add(w);
      gameRef.add(w);
    }

    // Corner pylons sit outside the walkable square.
    final pylon = _pylon;
    if (pylon != null) {
      for (final offset in [
        Vector2(-h - _tile * 0.55, -h - _tile * 0.55),
        Vector2(h - _tile * 0.45, -h - _tile * 0.55),
        Vector2(-h - _tile * 0.55, h - _tile * 0.45),
        Vector2(h - _tile * 0.45, h - _tile * 0.45),
      ]) {
        final d = _ArenaPylon(c + offset, pylon);
        _decor.add(d);
        gameRef.add(d);
      }
    }

    // Floor rim decals along the inner edge (activate on engage).
    final rim = _rim;
    if (rim != null) {
      const step = _tile;
      final n = ((h * 2) / step).floor();
      for (var i = 0; i < n; i++) {
        final along = -h + i * step + step / 2;
        for (final pos in [
          Vector2(c.x + along - step / 2, c.y - h), // north
          Vector2(c.x + along - step / 2, c.y + h - step), // south
          Vector2(c.x - h, c.y + along - step / 2), // west
          Vector2(c.x + h - step, c.y + along - step / 2), // east
        ]) {
          final d = _ArenaRim(pos, rim);
          _decor.add(d);
          gameRef.add(d);
        }
      }
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
    for (final d in _decor) {
      if (d.isMounted) d.removeFromParent();
    }
    _decor.clear();
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
    // Soft floor wash under the hard-pixel rim (kept quiet so tiles read).
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(c.x, c.y),
        width: h * 2,
        height: h * 2,
      ),
      Paint()..color = Color.fromRGBO(255, 80, 20, 0.04 + p * 0.015),
    );
    super.render(canvas);
  }

  @override
  int get priority => LayerPriority.MAP + 1;
}

/// Solid slab — player [BlockMovementCollision] treats solid hitboxes as walls.
class _ArenaWall extends GameDecoration {
  final Sprite? fence;

  _ArenaWall(Vector2 position, Vector2 size, {this.fence})
      : super(position: position, size: size);

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox(size: size, isSolid: true));
    return super.onLoad();
  }

  @override
  void render(Canvas canvas) {
    final sprite = fence;
    if (sprite == null) {
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
      return super.render(canvas);
    }

    final paint = Paint()..filterQuality = FilterQuality.none;
    final horizontal = size.x >= size.y;
    if (horizontal) {
      // Tile fence segments along the long axis; stretch height to the slab.
      var x = 0.0;
      while (x < size.x) {
        final w = min(32.0, size.x - x);
        sprite.render(
          canvas,
          position: Vector2(x, 0),
          size: Vector2(w, size.y),
          overridePaint: paint,
        );
        x += 32;
      }
    } else {
      // Vertical walls: rotate each segment 90°.
      var y = 0.0;
      while (y < size.y) {
        final h = min(32.0, size.y - y);
        canvas.save();
        canvas.translate(size.x / 2, y + h / 2);
        canvas.rotate(pi / 2);
        sprite.render(
          canvas,
          position: Vector2(-h / 2, -size.x / 2),
          size: Vector2(h, size.x),
          overridePaint: paint,
        );
        canvas.restore();
        y += 32;
      }
    }
    super.render(canvas);
  }
}

class _ArenaPylon extends GameDecoration {
  final Sprite art;

  _ArenaPylon(Vector2 position, this.art)
      : super(position: position, size: Vector2.all(32));

  @override
  void render(Canvas canvas) {
    art.render(
      canvas,
      size: size,
      overridePaint: Paint()..filterQuality = FilterQuality.none,
    );
    super.render(canvas);
  }

  @override
  int get priority => LayerPriority.MAP + 2;
}

class _ArenaRim extends GameDecoration {
  final Sprite art;

  _ArenaRim(Vector2 position, this.art)
      : super(position: position, size: Vector2.all(32));

  @override
  void render(Canvas canvas) {
    art.render(
      canvas,
      size: size,
      overridePaint: Paint()
        ..filterQuality = FilterQuality.none
        ..color = const Color(0xDDFFFFFF),
    );
    super.render(canvas);
  }

  @override
  int get priority => LayerPriority.MAP + 1;
}
