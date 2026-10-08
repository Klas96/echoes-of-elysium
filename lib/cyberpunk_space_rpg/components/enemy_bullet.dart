import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'custom_player.dart';

/// Orange UEC pulse fired by sniper drones.
class EnemyBullet extends GameDecoration {
  static const double _speed = 260;
  static const double _maxDistance = 480;
  static const double _hitRadius = 14;
  static const double bulletSize = 10;

  final Vector2 _velocity;
  final int damage;
  double _traveled = 0;
  bool _hit = false;

  EnemyBullet(Vector2 position, Vector2 direction, {this.damage = 14})
      : _velocity = direction.normalized() * _speed,
        super(position: position, size: Vector2.all(bulletSize));

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

    final player = gameRef.player;
    if (player == null) return;
    final toPlayer =
        (player.position + player.size / 2) - (position + size / 2);
    if (toPlayer.length < _hitRadius) {
      _hit = true;
      CustomPlayer.applyDamage(damage);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final fade = (1.0 - (_traveled / _maxDistance) * 0.5).clamp(0.0, 1.0);
    final cx = size.x / 2;
    final cy = size.y / 2;
    canvas.drawCircle(
      Offset(cx, cy),
      5,
      Paint()
        ..color = const Color(0xFFFF6622).withOpacity(0.35 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      2.8,
      Paint()..color = const Color(0xFFFFAA44).withOpacity(fade),
    );
  }
}
