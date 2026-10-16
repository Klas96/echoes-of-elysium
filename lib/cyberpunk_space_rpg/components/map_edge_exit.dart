import 'dart:math' as math;

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../creatures/interaction.dart';
import '../game/travel.dart';

/// Invisible strip on a map border: walk into it to leave for [destLevel].
/// No portal glow — adjacent maps should feel like roads, not warp pads.
///
/// While [canExit] is false the strip is a solid thicket so the punched map
/// edge does not look (or play) like an open road. Designer sheets (#55)
/// replace that paint: a locked treeline y-sorts in front of the meadow, and
/// an open road sheet is a ground decal (under Kaela and the boulder). The
/// open sheet may be taller than the strip so it can join the path one tile
/// north without growing the solid hitbox.
class MapEdgeExit extends GameComponent {
  final int destLevel;
  final String entrySide;
  final bool Function() canExit;
  final String lockedTitle;
  final String lockedBody;

  /// A beat to play before leaving (the region farewell); null = none now.
  final Future<void> Function()? Function()? beforeExit;

  /// Optional designer art for locked / open states (#55). Paths relative to
  /// `assets/images/` (Bonfire [Sprite.load] convention).
  final String? lockedSpritePath;
  final String? openSpritePath;

  bool _fired = false;
  bool _beat = false;
  bool _lockedHint = false;
  bool? _sealed;
  RectangleHitbox? _block;
  Sprite? _lockedSprite;
  Sprite? _openSprite;

  MapEdgeExit(
    Vector2 position,
    Vector2 size, {
    required this.destLevel,
    required this.entrySide,
    bool Function()? canExit,
    this.lockedTitle = 'PATH CLOSED',
    this.lockedBody = 'Not yet.',
    this.beforeExit,
    this.lockedSpritePath,
    this.openSpritePath,
  }) : canExit = canExit ?? (() => true) {
    this.position = position;
    this.size = size;
    _applyPriority(!this.canExit());
  }

  /// Open road art sits with the ground. A sealed treeline sorts by its foot.
  void _applyPriority(bool sealed) {
    final groundRoad = !sealed && _openSprite != null;
    final next = groundRoad
        ? LayerPriority.MAP + 1
        : LayerPriority.getComponentPriority(
            (position.y + size.y * 0.85).floor(),
          );
    if (priority != next) priority = next;
  }

  void _syncSeal() {
    final sealed = !canExit();
    _applyPriority(sealed);
    if (_sealed == sealed) return;
    _sealed = sealed;
    if (sealed) {
      if (_block == null) {
        add(_block = RectangleHitbox(size: size, isSolid: true));
      }
    } else {
      _block?.removeFromParent();
      _block = null;
    }
  }

  @override
  Future<void> onLoad() async {
    if (lockedSpritePath != null) {
      try {
        _lockedSprite = await Sprite.load(lockedSpritePath!);
      } catch (_) {}
    }
    if (openSpritePath != null) {
      try {
        _openSprite = await Sprite.load(openSpritePath!);
      } catch (_) {}
    }
    _syncSeal();
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _syncSeal();
    final player = gameRef.player;
    if (player == null || _beat) return;
    final pc = player.position + player.size / 2;
    // Slightly taller than the strip so a sealed hitbox still triggers the hint.
    final zone = Rect.fromLTWH(
      position.x,
      position.y - 28,
      size.x,
      size.y + 28,
    );
    final inside = zone.contains(Offset(pc.x, pc.y));

    if (!inside) {
      _fired = false;
      _lockedHint = false;
      return;
    }
    if (_fired) return;

    if (!canExit()) {
      if (!_lockedHint) {
        _lockedHint = true;
        GameToast.show(lockedTitle,
            body: lockedBody, color: const Color(0xFFFFAABB), compact: true);
      }
      return;
    }

    // Must stand in the real exit strip to leave (not only the hint pad).
    final inStrip = pc.x >= position.x &&
        pc.x <= position.x + size.x &&
        pc.y >= position.y &&
        pc.y <= position.y + size.y;
    if (!inStrip) return;

    _fired = true;
    final beat = beforeExit?.call();
    if (beat != null) {
      _beat = true;
      beat().then((_) {
        _beat = false;
        if (isMounted) _travel();
      });
      return;
    }
    _travel();
  }

  void _travel() {
    Travel.requestEdge(destLevel, entrySide: entrySide);
    if (!gameRef.overlays.isActive('edgeTravel')) {
      gameRef.overlays.add('edgeTravel');
    }
  }

  /// Native pixels, bottom-aligned on the strip. Extra height overhangs north.
  void _paintSprite(Canvas canvas, Sprite sprite) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    sprite.render(
      canvas,
      position: Vector2(0, size.y - sprite.srcSize.y),
      size: Vector2(sprite.srcSize.x, sprite.srcSize.y),
      overridePaint: paint,
    );
  }

  @override
  void render(Canvas canvas) {
    if (_sealed ?? !canExit()) {
      final locked = _lockedSprite;
      if (locked != null) {
        _paintSprite(canvas, locked);
        return;
      }
      _paintThicket(canvas);
      return;
    }
    final open = _openSprite;
    if (open != null) {
      _paintSprite(canvas, open);
      return;
    }
    // Soft dust line so the opening reads as a road, not a void.
    final midY = size.y * 0.55;
    canvas.drawRect(
      Rect.fromLTWH(2, midY, size.x - 4, 2),
      Paint()..color = const Color(0xFF88AACC).withValues(alpha: 0.18),
    );
  }

  /// Dense treeline so a locked south road does not read as walkable grass.
  void _paintThicket(Canvas canvas) {
    final rng = math.Random(destLevel * 97 + size.x.toInt());
    canvas.drawRect(
      Rect.fromLTWH(0, size.y * 0.12, size.x, size.y * 0.88),
      Paint()..color = const Color(0xFF0A140C).withValues(alpha: 0.92),
    );

    final dark = Paint()..color = const Color(0xFF142818);
    final mid = Paint()..color = const Color(0xFF1E3A24);
    final tip = Paint()..color = const Color(0xFF2A4E30).withValues(alpha: 0.85);
    for (var i = 0; i < 9; i++) {
      final cx = size.x * (0.06 + i * 0.11) + (rng.nextDouble() - 0.5) * 6;
      final base = size.y * (0.72 + rng.nextDouble() * 0.12);
      final h = size.y * (0.55 + rng.nextDouble() * 0.35);
      final w = 10.0 + rng.nextDouble() * 14;
      final path = Path()
        ..moveTo(cx - w * 0.55, base)
        ..lineTo(cx, base - h)
        ..lineTo(cx + w * 0.55, base)
        ..close();
      canvas.drawPath(path, i.isEven ? dark : mid);
      canvas.drawCircle(Offset(cx, base - h * 0.35), w * 0.42, tip);
    }
    // Soft vignette so it blends into the bordering forest tiles.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y * 0.2),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0A140C).withValues(alpha: 0),
            const Color(0xFF0A140C).withValues(alpha: 0.55),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.x, size.y * 0.2)),
    );
  }
}

/// Marks where Kaela appears when arriving from [side] (north/south/east/west).
class MapEntryPoint extends GameComponent {
  static final Map<String, Vector2> bySide = {};

  final String side;

  MapEntryPoint(Vector2 position, {required this.side}) {
    this.position = position;
    size = Vector2.all(32);
  }

  @override
  Future<void> onLoad() async {
    bySide[side] = position.clone();
    return super.onLoad();
  }

  @override
  void onRemove() {
    if (bySide[side] == position) bySide.remove(side);
    super.onRemove();
  }
}
