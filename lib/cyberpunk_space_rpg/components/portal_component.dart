import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import '../audio/sfx_manager.dart';
import '../game/game_state.dart';
import '../game/travel.dart';
import 'lamp_light.dart';

/// Map travel gate — a flat cyan ring on the ground (not a crystal shard).
/// Walk into the glow to travel. Amber tint for Lantern Town side hubs.
///
/// Drawn at map-floor priority so Kaela always paints over it.
class PortalComponent extends GameDecoration {
  static const double lightW = 48;
  static const double lightH = 48;

  static const double _activateRadius = 26;
  static const Color _townAmber = Color(0xFFFFE08A);

  static const _flickerPath = 'sprites/fx/portal_light_flicker.png';
  static const _stillPath = 'sprites/fx/portal_light.png';

  final bool Function() canActivate;
  final String overlayId;
  final Color accent;
  double _pulse = 0.0;
  bool _triggered = false;
  bool _near = false;
  static const double _nearRadius = 320.0;
  Sprite? _frameA;
  Sprite? _frameB;
  LampLight? _glow;

  PortalComponent(
    Vector2 mapTopLeft, {
    bool Function()? canActivate,
    this.overlayId = 'portalReached',
    this.accent = const Color(0xFF00FFFF),
  })  : canActivate = canActivate ??
            (() => Travel.portalUsable(GameState.level)),
        super(position: mapTopLeft, size: Vector2(lightW, lightH));

  Vector2 get _centre => position + size / 2;

  bool get _town => accent == _townAmber;

  /// Floor pad: always under Y-sorted actors (Kaela, NPCs, props).
  @override
  int get priority => LayerPriority.MAP + 1;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      final flick = await Flame.images.load(_flickerPath);
      final fw = flick.width / 2;
      _frameA = Sprite(flick,
          srcPosition: Vector2.zero(),
          srcSize: Vector2(fw, flick.height.toDouble()));
      _frameB = Sprite(flick,
          srcPosition: Vector2(fw, 0),
          srcSize: Vector2(fw, flick.height.toDouble()));
    } catch (_) {
      try {
        _frameA = await Sprite.load(_stillPath);
        _frameB = _frameA;
      } catch (_) {
        _frameA = _frameB = null;
      }
    }
    final c = _centre;
    _glow = LampLight(
      Vector2(c.x - 8, c.y - 8),
      Vector2.all(16),
      kind: _town ? LightKind.lamp : LightKind.energy,
      radius: 160,
      style: _town ? 'warm' : 'neon',
    );
    await gameRef.add(_glow!);
  }

  @override
  void onRemove() {
    _glow?.removeFromParent();
    _glow = null;
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 3.0;

    final player = gameRef.player;
    if (player == null) return;
    final pc = player.position + player.size / 2;
    final dist = (pc - _centre).length;
    if (!_near && dist < _nearRadius) {
      _near = true;
      GameState.onNearPortal();
    }
    if (_triggered) {
      final overlayOpen = gameRef.overlays.isActive(overlayId);
      if (!overlayOpen && dist >= _activateRadius * 1.2) {
        _triggered = false;
      }
      return;
    }
    if (!canActivate()) return;
    if (dist < _activateRadius) {
      _triggered = true;
      SfxManager().playPortal();
      gameRef.overlays.add(overlayId);
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    if (_town) {
      paint.colorFilter = ColorFilter.mode(
        accent.withValues(alpha: 0.55),
        BlendMode.modulate,
      );
    }
    final spr = (sin(_pulse * 1.6) > 0) ? _frameA : _frameB;
    if (spr != null) {
      spr.render(
        canvas,
        position: Vector2.zero(),
        size: size,
        overridePaint: paint,
      );
    } else {
      // Fallback: flat ring (never a diamond).
      final c = Offset(size.x / 2, size.y * 0.65);
      for (final r in [18.0, 12.0, 6.0]) {
        canvas.drawOval(
          Rect.fromCenter(center: c, width: r * 2, height: r * 1.2),
          Paint()
            ..color = accent.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(size.x / 2, size.y * 0.35),
          width: 6,
          height: size.y * 0.45,
        ),
        Paint()..color = accent.withValues(alpha: 0.55),
      );
    }
  }
}
