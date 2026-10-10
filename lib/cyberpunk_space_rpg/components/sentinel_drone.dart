import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'damage_number.dart';
import 'custom_player.dart';
import 'drone_bounds.dart';
import 'explosion_effect.dart';
import '../game/game_state.dart';
import '../game/progression.dart';

enum _SState { idle, chase, attack, rage }

class SentinelDrone extends GameDecoration {
  static SentinelDrone? instance;
  static const int maxHealth = 360;
  static const double spriteSize = 64;
  static const double _detectR = 300;
  static const double _attackR = 50;
  static const double _speed = 68;
  static const double _rageSpeed = 105;
  static const double _cooldown = 1.0;
  static const double _rageCooldown = 0.55;
  static const int _damage = 18;
  static const int _rageDamage = 28;

  int _health = maxHealth;
  bool get isDead => _health <= 0;
  _SState _state = _SState.idle;
  double _attackTimer = 0;
  double _pulse = 0;
  bool _deathFired = false;
  Vector2 _knockback = Vector2.zero();
  late final Vector2 _origin;
  final VoidCallback onDefeated;

  SentinelDrone(Vector2 position, {required this.onDefeated})
      : _origin = position.clone(),
        super(position: position, size: Vector2.all(48));

  Sprite? _sprite;

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load('sprites/sentinel_boss.png');
    instance = this;
    add(CircleHitbox(radius: 24, isSolid: true, collisionType: CollisionType.passive));
    return super.onLoad();
  }

  @override
  void onRemove() {
    if (instance == this) instance = null;
    super.onRemove();
  }

  static const double _leash = 220;

  void _move(Vector2 delta) {
    final ok = DroneBounds.moveBy(
      this,
      delta,
      origin: _origin,
      leash: _leash,
      pad: 32,
    );
    if (!ok) _knockback.setZero();
  }

  void takeDamage(int amount, {Vector2? knockbackDir}) {
    if (isDead) return;
    GameState.onSentinelEngaged();
    if (knockbackDir != null && knockbackDir.length2 > 1e-8) {
      // Heavy boss: short flinch, not a shove across the plaza.
      _knockback = knockbackDir.normalized() * 70;
    }
    _health = (_health - amount).clamp(0, maxHealth);
    DamageNumber.spawn(this, position + Vector2(size.x / 2, 0), amount, DamageNumberStyle.dealt);
    if (_health <= 0 && !_deathFired) {
      _deathFired = true;
      Progression.onSentinelKilled();
      gameRef.add(ExplosionEffect(position.clone()));
      Future.microtask(onDefeated);
      removeFromParent();
    }
  }

  @override
  void update(double dt) {
    if (isDead) return;
    super.update(dt);
    _pulse += dt * 4.5;
    _attackTimer = max(0, _attackTimer - dt);

    final player = gameRef.player;
    if (player == null) return;
    // Centre to centre, so ranges don't drift with the size difference.
    final toPlayer = (player.position + player.size / 2) - (position + size / 2);
    // Objective: the player went for the Sentinel.
    if (toPlayer.length < _detectR) GameState.onSentinelEngaged();
    final dist = toPlayer.length;
    final rage = _health < maxHealth * 0.3;

    if (dist < _attackR) {
      _state = rage ? _SState.rage : _SState.attack;
    } else if (dist < _detectR) {
      _state = rage ? _SState.rage : _SState.chase;
    } else {
      _state = _SState.idle;
    }

    final spd = (rage && _state != _SState.idle) ? _rageSpeed : _speed;

    DroneBounds.rescue(this, origin: _origin, leash: _leash, pad: 32);

    if (_knockback.length < 40 &&
        (_state == _SState.chase || _state == _SState.rage) &&
        dist > _attackR) {
      _move(toPlayer.normalized() * spd * dt);
    }
    if (_knockback.length2 > 0.25) {
      _move(_knockback * dt);
      _knockback.scale(exp(-12 * dt));
      if (_knockback.length2 < 4) _knockback.setZero();
    }
    if (dist < _attackR * 1.5 && _attackTimer <= 0) {
      final dmg = rage ? _rageDamage : _damage;
      CustomPlayer.applyDamage(dmg);
      _attackTimer = rage ? _rageCooldown : _cooldown;
    }
  }

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;
    final rage = _health < maxHealth * 0.3;
    final col = rage ? const Color(0xFFFF2200) : const Color(0xFFFF6600);
    final p = sin(_pulse);

    // Outer pulsing aura
    canvas.drawCircle(Offset(cx, cy), r + 12 + p * 5,
        Paint()
          ..color = col.withOpacity(0.14 + p * 0.06)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));

    // Sprite
    // 64x64 art drawn at 1:1 over the 48px body so the boss reads bigger
    // than its hitbox.
    if (_sprite != null) {
      const s = spriteSize;
      _sprite!.render(
        canvas,
        position: Vector2(cx - s / 2, cy - s / 2),
        size: Vector2.all(s),
        overridePaint: Paint()..filterQuality = FilterQuality.none,
      );
    }

    // Rage white core flash
    if (rage) canvas.drawCircle(Offset(cx, cy), r * 0.1,
        Paint()..color = Colors.white.withOpacity(0.5 + p * 0.3));

    // HP bar
    const barW = 52.0, barH = 5.0;
    final barX = cx - barW / 2;
    final barY = cy - spriteSize / 2 - 8;
    canvas.drawRect(Rect.fromLTWH(barX, barY, barW, barH), Paint()..color = Colors.black54);
    canvas.drawRect(
        Rect.fromLTWH(barX, barY, barW * (_health / maxHealth).clamp(0, 1), barH),
        Paint()..color = col);
    canvas.drawRect(
        Rect.fromLTWH(barX, barY, barW, barH),
        Paint()
          ..color = col.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);

    // "SENTINEL" label
    // (can't draw text in Canvas here without TextPainter; skip label)
  }
}
