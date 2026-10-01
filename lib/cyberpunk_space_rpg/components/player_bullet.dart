import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:bonfire/util/collision_game_component.dart';
import 'uec_drone.dart';
import 'sentinel_drone.dart';

class PlayerBullet extends GameDecoration {
  static const double _speed = 380;
  static const double _maxDistance = 520;
  static const int _damage = 30;
  static const double bulletSize = 16;

  final Vector2 _velocity;
  final double _angle;
  double _traveled = 0;
  bool _hit = false;
  Sprite? _sprite;

  PlayerBullet(Vector2 position, Vector2 direction)
      : _velocity = direction * _speed,
        _angle = direction.screenAngle(),
        super(position: position, size: Vector2.all(bulletSize));

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load('sprites/bullet.png');
    add(CircleHitbox(radius: 4, position: size / 2, anchor: Anchor.center));
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hit) return;
    // Clamp dt so a frame spike can't make the bullet skip over a drone.
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
        other.takeDamage(_damage);
        removeFromParent();
      } else if (other is SentinelDrone && !other.isDead) {
        _hit = true;
        other.takeDamage(_damage);
        removeFromParent();
      } else if (other is TileWithCollision ||
          other is CollisionMapComponent ||
          other is GameDecorationWithCollision) {
        // Tiled walls (collision tiles / collision objects)
        _hit = true;
        removeFromParent();
      }
    }
    super.onCollisionStart(intersectionPoints, other);
  }

  @override
  void render(Canvas canvas) {
    final fade = (1.0 - (_traveled / _maxDistance) * 0.45).clamp(0.0, 1.0);
    if (_sprite != null) {
      canvas.save();
      canvas.translate(size.x / 2, size.y / 2);
      canvas.rotate(_angle);
      canvas.translate(-size.x / 2, -size.y / 2);
      _sprite!.render(
        canvas,
        size: size,
        overridePaint: Paint()..color = const Color(0xFFFFFFFF).withOpacity(fade),
      );
      canvas.restore();
    } else {
      // fallback if sprite not loaded yet
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        3.5,
        Paint()..color = const Color(0xFF00FFFF).withOpacity(fade),
      );
    }
  }
}
