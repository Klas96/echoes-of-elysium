import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:bonfire/util/collision_game_component.dart';
import 'uec_drone.dart';
import 'sentinel_drone.dart';
import '../game/progression.dart';
import '../game/well_rested.dart';

class PlayerBullet extends GameDecoration {
  static const double _speed = 420;
  static const double _maxDistance = 540;
  static const int _baseDamage = 18;
  static int get _damage => WellRested.applyDamage(_baseDamage + Progression.bonusDamage);
  /// Half-extent used when centering the spawn on Kaela.
  static const double bulletSize = 14;
  static final Vector2 spriteSize = Vector2(28, 12);

  final Vector2 _velocity;
  final double _angle;
  double _traveled = 0;
  bool _hit = false;

  PlayerBullet(Vector2 position, Vector2 direction)
      : _velocity = direction * _speed,
        // Bolt is drawn along +X; screenAngle treats "up" as 0° (90° off).
        _angle = atan2(direction.y, direction.x),
        super(position: position, size: spriteSize.clone());

  @override
  Future<void> onLoad() async {
    paint.filterQuality = FilterQuality.none;
    add(CircleHitbox(radius: 6, position: size / 2, anchor: Anchor.center));
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hit) return;
    final step = _velocity * min(dt, 1 / 30);
    position += step;
    _traveled += step.length;

    if (_traveled > _maxDistance) {
      removeFromParent();
      return;
    }
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    if (!_hit) {
      if (other is UECDrone && !other.isDead) {
        _hit = true;
        other.takeDamage(_damage, knockbackDir: _velocity);
        removeFromParent();
      } else if (other is SentinelDrone && !other.isDead) {
        _hit = true;
        other.takeDamage(_damage, knockbackDir: _velocity);
        removeFromParent();
      } else if (other is TileWithCollision ||
          other is CollisionMapComponent ||
          other is GameDecorationWithCollision) {
        _hit = true;
        removeFromParent();
      }
    }
    super.onCollisionStart(intersectionPoints, other);
  }

  @override
  void render(Canvas canvas) {
    final fade = (1.0 - (_traveled / _maxDistance) * 0.4).clamp(0.0, 1.0);
    final cx = size.x / 2;
    final cy = size.y / 2;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(_angle);
    canvas.translate(-cx, -cy);

    // Outer bloom — same treatment as UEC pulses, cyan for Kaela.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: size.x * 1.05, height: 10),
        const Radius.circular(5),
      ),
      Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.38 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Soft body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: size.x * 0.88, height: 5.5),
        const Radius.circular(2.5),
      ),
      Paint()..color = const Color(0xFF66F0FF).withValues(alpha: 0.85 * fade),
    );

    // Bright core streak.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + 1, cy), width: size.x * 0.62, height: 2.4),
        const Radius.circular(1.2),
      ),
      Paint()..color = Color.fromRGBO(255, 255, 255, fade),
    );

    // Tip flare so travel direction reads at a glance.
    canvas.drawCircle(
      Offset(size.x - 4, cy),
      3.2,
      Paint()
        ..color = const Color(0xFF00FFFF).withValues(alpha: 0.45 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      Offset(size.x - 4, cy),
      1.8,
      Paint()..color = Color.fromRGBO(255, 255, 255, fade),
    );

    canvas.restore();
  }
}
