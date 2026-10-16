import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:bonfire/util/collision_game_component.dart';
import 'drone_spawn.dart';
import 'uec_drone.dart';
import 'sentinel_drone.dart';
import '../game/progression.dart';
import '../game/well_rested.dart';

enum BulletKind { auto, pulse }

class PlayerBullet extends GameDecoration {
  static const double _autoSpeed = 420;
  static const double _pulseSpeed = 520;
  static const double _autoRange = 540;
  static const double _pulseRange = 240;
  static const int _autoDamage = 18;
  static const int _pulseDamage = 28;
  /// Half-extent used when centering the spawn on Kaela.
  static const double bulletSize = 14;
  static final Vector2 spriteSize = Vector2(28, 12);
  static final Vector2 pulseSpriteSize = Vector2(36, 16);

  final Vector2 _velocity;
  final double _angle;
  final BulletKind kind;
  final double _maxDistance;
  final int _damage;
  final double _slowSeconds;
  int _pierceLeft;
  double _traveled = 0;
  bool _done = false;
  final Set<int> _hitIds = {};

  PlayerBullet(
    Vector2 position,
    Vector2 direction, {
    this.kind = BulletKind.auto,
  })  : _velocity = direction *
            (kind == BulletKind.pulse ? _pulseSpeed : _autoSpeed),
        _angle = atan2(direction.y, direction.x),
        _maxDistance = kind == BulletKind.pulse ? _pulseRange : _autoRange,
        _damage = WellRested.applyDamage(
          (kind == BulletKind.pulse ? _pulseDamage : _autoDamage) +
              Progression.bonusDamage,
        ),
        _slowSeconds = kind == BulletKind.pulse ? 1.4 : 0,
        _pierceLeft = kind == BulletKind.pulse ? 3 : 0,
        super(
          position: position,
          size: (kind == BulletKind.pulse ? pulseSpriteSize : spriteSize)
              .clone(),
        );

  @override
  Future<void> onLoad() async {
    paint.filterQuality = FilterQuality.none;
    final r = kind == BulletKind.pulse ? 8.0 : 6.0;
    add(CircleHitbox(radius: r, position: size / 2, anchor: Anchor.center));
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_done) return;
    final step = _velocity * min(dt, 1 / 30);
    position += step;
    _traveled += step.length;

    if (_traveled > _maxDistance) {
      removeFromParent();
    }
  }

  void _finish() {
    _done = true;
    removeFromParent();
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    if (!_done) {
      if (other is UECDrone && !other.isDead) {
        _hitHostile(other, () {
          other.takeDamage(_damage, knockbackDir: _velocity);
          if (_slowSeconds > 0) other.applySlow(_slowSeconds);
        });
      } else if (other is SentinelDrone && !other.isDead) {
        _hitHostile(other, () {
          other.takeDamage(_damage, knockbackDir: _velocity);
          if (_slowSeconds > 0) other.applySlow(_slowSeconds);
        });
      } else if (other is DroneSpawnPoint && !other.isDead) {
        _hitHostile(other, () {
          other.takeDamage(_damage, knockbackDir: _velocity);
        });
      } else if (other is TileWithCollision ||
          other is CollisionMapComponent ||
          other is GameDecorationWithCollision) {
        _finish();
      }
    }
    super.onCollisionStart(intersectionPoints, other);
  }

  void _hitHostile(PositionComponent other, void Function() apply) {
    final id = identityHashCode(other);
    if (!_hitIds.add(id)) return;
    apply();
    if (kind == BulletKind.pulse && _pierceLeft > 1) {
      _pierceLeft--;
      return;
    }
    _finish();
  }

  @override
  void render(Canvas canvas) {
    final fade = (1.0 - (_traveled / _maxDistance) * 0.4).clamp(0.0, 1.0);
    final cx = size.x / 2;
    final cy = size.y / 2;
    final pulse = kind == BulletKind.pulse;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(_angle);
    canvas.translate(-cx, -cy);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, cy),
            width: size.x * (pulse ? 1.15 : 1.05),
            height: pulse ? 14 : 10),
        Radius.circular(pulse ? 7 : 5),
      ),
      Paint()
        ..color = Color(pulse ? 0xFF66FFEE : 0xFF00E5FF)
            .withValues(alpha: (pulse ? 0.5 : 0.38) * fade)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, pulse ? 7 : 5),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, cy),
            width: size.x * 0.88,
            height: pulse ? 7 : 5.5),
        Radius.circular(pulse ? 3.5 : 2.5),
      ),
      Paint()
        ..color = Color(pulse ? 0xFFAAFFF8 : 0xFF66F0FF)
            .withValues(alpha: 0.9 * fade),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx + 1, cy),
            width: size.x * 0.62,
            height: pulse ? 3.2 : 2.4),
        Radius.circular(pulse ? 1.6 : 1.2),
      ),
      Paint()..color = Color.fromRGBO(255, 255, 255, fade),
    );

    canvas.drawCircle(
      Offset(size.x - 4, cy),
      pulse ? 4.2 : 3.2,
      Paint()
        ..color = const Color(0xFF00FFFF).withValues(alpha: 0.45 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      Offset(size.x - 4, cy),
      pulse ? 2.2 : 1.8,
      Paint()..color = Color.fromRGBO(255, 255, 255, fade),
    );

    canvas.restore();
  }
}
