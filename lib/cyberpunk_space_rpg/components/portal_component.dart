import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import '../audio/sfx_manager.dart';
import '../game/game_state.dart';
import '../game/travel.dart';

/// Map travel portal — circular Aetherian ring ([sprites/portal.png]) with a
/// soft pulse. Cyan for story routes; amber for side hubs (Lantern Town).
class PortalComponent extends GameDecoration {
  /// Footprint matches the woods `portal_platform` (3×3 tiles).
  static const double padSize = 96;
  static const double _radius = 36;
  final bool Function() canActivate;
  final String overlayId;
  /// Story portals stay cyan; side hubs (Lantern Gate) use amber.
  final Color accent;
  double _pulse = 0.0;
  bool _triggered = false;
  bool _near = false;
  static const double _nearRadius = 320.0;
  Sprite? _sprite;

  PortalComponent(
    Vector2 position, {
    bool Function()? canActivate,
    this.overlayId = 'portalReached',
    this.accent = const Color(0xFF00FFFF),
  })  : canActivate = canActivate ??
            (() => Travel.portalUsable(GameState.level)),
        super(position: position, size: Vector2.all(padSize));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      _sprite = await Sprite.load('sprites/portal.png');
    } catch (_) {
      _sprite = null;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 3.0;

    final player = gameRef.player;
    if (player == null) return;
    final dist = ((player.position + player.size / 2) - (position + size / 2)).length;
    if (!_near && dist < _nearRadius) {
      _near = true;
      GameState.onNearPortal();
    }
    // Allow re-entry after the player leaves (or closes the overlay).
    if (_triggered) {
      final overlayOpen = gameRef.overlays.isActive(overlayId);
      if (!overlayOpen && dist >= _radius * 1.15) {
        _triggered = false;
      }
      return;
    }
    if (!canActivate()) return;
    if (dist < _radius) {
      _triggered = true;
      SfxManager().playPortal();
      gameRef.overlays.add(overlayId);
    }
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    final breath = 0.5 + 0.5 * sin(_pulse);
    final scale = 1.0 + sin(_pulse) * 0.035;
    final draw = padSize * scale;
    final origin = Vector2(center.dx - draw / 2, center.dy - draw / 2);

    // Soft ground bloom under the pad.
    canvas.drawCircle(
      center,
      draw * 0.42,
      Paint()
        ..color = accent.withValues(alpha: 0.10 + breath * 0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    final sprite = _sprite;
    if (sprite != null) {
      final paint = Paint()..filterQuality = FilterQuality.none;
      // Amber hubs: warm tint over the cyan hexpad.
      if (accent != const Color(0xFF00FFFF)) {
        paint.colorFilter = ColorFilter.mode(
          accent.withValues(alpha: 0.55),
          BlendMode.modulate,
        );
      }
      sprite.render(
        canvas,
        position: origin,
        size: Vector2.all(draw),
        overridePaint: paint,
      );
    } else {
      _renderFallback(canvas, center, draw / 2);
    }

    // Thin spinning rim so the pad still reads as "live".
    final rim = Paint()
      ..color = accent.withValues(alpha: 0.35 + breath * 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: draw * 0.28),
      _pulse,
      pi * 1.2,
      false,
      rim,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: draw * 0.28),
      _pulse + pi,
      pi * 1.2,
      false,
      rim..color = Color.lerp(accent, const Color(0xFFAA44FF), 0.5)!
          .withValues(alpha: 0.4),
    );
  }

  void _renderFallback(Canvas canvas, Offset center, double outerRadius) {
    final deep = Color.lerp(const Color(0xFF001F3F), accent, 0.35)!;
    canvas.drawCircle(center, outerRadius, Paint()..color = deep.withValues(alpha: 0.85));
    canvas.drawCircle(
      center,
      outerRadius * 0.65,
      Paint()..color = accent.withValues(alpha: 0.25 + sin(_pulse) * 0.1),
    );
    canvas.drawCircle(
      center,
      6 + sin(_pulse * 2) * 2,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }
}
