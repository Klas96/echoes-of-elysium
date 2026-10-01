import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'uec_drone.dart';
import 'sentinel_drone.dart';

class PlayerBullet extends GameDecoration {
  static const double _speed = 380;
  static const double _maxDistance = 520;
  static const int _damage = 30;

  final Vector2 _velocity;
  final double _angle;
  double _traveled = 0;
  Sprite? _sprite;

  PlayerBullet(Vector2 position, Vector2 direction)
      : _velocity = direction * _speed,
        _angle = direction.screenAngle(),
        super(position: position, size: Vector2.all(16));

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load('sprites/bullet.png');
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    final step = _velocity * dt;
    position += step;
    _traveled += step.length;

    if (_traveled > _maxDistance) {
      removeFromParent();
      return;
    }

    final center = position + size / 2;
    for (final drone in List.of(UECDrone.active)) {
      if (drone.isDead) continue;
      if ((center - (drone.position + drone.size / 2)).length < 18) {
        drone.takeDamage(_damage);
        removeFromParent();
        return;
      }
    }
    final sentinel = SentinelDrone.instance;
    if (sentinel != null && !sentinel.isDead) {
      if ((center - (sentinel.position + sentinel.size / 2)).length < 30) {
        sentinel.takeDamage(_damage);
        removeFromParent();
        return;
      }
    }
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
