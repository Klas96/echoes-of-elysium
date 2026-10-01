import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'custom_player.dart';
import 'explosion_effect.dart';
import '../game/settings.dart';

enum _DroneState { patrol, chase, attack }

class UECDrone extends GameDecoration {
  static final List<UECDrone> active = [];

  // Calm tuning (brief v2): slower scout, 8 contact damage, shorter notice
  // range and a gentler attack rhythm. Was 220 / 55 / 12 / 1.2.
  static const double _detectionRadius = 160;
  static const double _attackRadius = 36;
  static const double _speed = 40;
  static const int _damage = 8;
  static const double _attackCooldown = 1.5;

  final Vector2 _origin;
  _DroneState _state = _DroneState.patrol;
  double _patrolAngle;
  double _attackTimer = 0;
  double _pulse = 0;
  int _health = 60;
  bool get isDead => _health <= 0;

  UECDrone(Vector2 position, {double startAngle = 0})
      : _origin = position.clone(),
        _patrolAngle = startAngle,
        super(position: position, size: Vector2.all(24));

  Sprite? _sprite;

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load('sprites/enemy_ship.png');
    active.add(this);
    add(CircleHitbox(radius: 12, isSolid: true, collisionType: CollisionType.passive));
    return super.onLoad();
  }

  @override
  void onRemove() {
    active.remove(this);
    super.onRemove();
  }

  void takeDamage(int amount) {
    _health -= amount;
  }

  @override
  void update(double dt) {
    if (isDead) {
      gameRef.add(ExplosionEffect(position.clone()));
      removeFromParent();
      return;
    }
    super.update(dt);
    _pulse += dt * 3.5;
    _attackTimer = max(0, _attackTimer - dt);

    final player = gameRef.player;
    if (player == null) return;

    // Centre to centre, so ranges don't drift with the size difference.
    final toPlayer = (player.position + player.size / 2) - (position + size / 2);
    // Story Mode: drones are passive and just keep patrolling.
    final dist = GameSettings.storyMode.value ? double.infinity : toPlayer.length;

    if (dist < _attackRadius) {
      _state = _DroneState.attack;
    } else if (dist < _detectionRadius) {
      _state = _DroneState.chase;
    } else {
      _state = _DroneState.patrol;
    }

    switch (_state) {
      case _DroneState.patrol:
        _patrolAngle += dt * 0.7;
        final target = _origin + Vector2(cos(_patrolAngle) * 70, sin(_patrolAngle) * 70);
        final step = (target - position);
        if (step.length > 1) position += step.normalized() * min(_speed * dt, step.length);
        break;
      case _DroneState.chase:
        position += toPlayer.normalized() * _speed * dt;
        break;
      case _DroneState.attack:
        if (_attackTimer <= 0) {
          CustomPlayer.applyDamage(_damage);
          _attackTimer = _attackCooldown;
        }
        break;
    }
  }

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;
    final aggro = _state != _DroneState.patrol;
    final col = aggro ? const Color(0xFFFF4444) : const Color(0xFF6688AA);

    // Glow
    canvas.drawCircle(Offset(cx, cy), r + 5,
        Paint()
          ..color = col.withOpacity(0.18 + sin(_pulse) * 0.07)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));

    // Sprite
    if (_sprite != null) {
      _sprite!.render(canvas, size: size);
    }

    // Health bar
    const barW = 20.0; const barH = 3.0;
    final barX = cx - barW / 2;
    final barY = cy - r - 6;
    canvas.drawRect(Rect.fromLTWH(barX, barY, barW, barH),
        Paint()..color = Colors.black54);
    canvas.drawRect(
        Rect.fromLTWH(barX, barY, barW * (_health / 60).clamp(0, 1), barH),
        Paint()..color = const Color(0xFFFF4444));
  }
}
