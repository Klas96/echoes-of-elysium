import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'custom_player.dart';
import 'drone_bounds.dart';
import 'enemy_bullet.dart';
import 'explosion_effect.dart';
import '../game/progression.dart';
import '../game/quests.dart';

enum DroneKind {
  /// Balanced melee chase — the original UEC drone.
  scout,

  /// Keeps distance and fires pulses.
  sniper,

  /// Slow tank with a regenerating frontal shield.
  shield,

  /// Small, fast, fragile pack hunter.
  swarm,
}

extension DroneKindParse on DroneKind {
  static DroneKind from(String? raw) {
    switch ((raw ?? 'scout').toLowerCase().trim()) {
      case 'sniper':
        return DroneKind.sniper;
      case 'shield':
        return DroneKind.shield;
      case 'swarm':
        return DroneKind.swarm;
      default:
        return DroneKind.scout;
    }
  }
}

enum _DroneState { patrol, chase, attack, retreat }

class _DroneStats {
  final double detectionRadius;
  final double attackRadius;
  final double preferMin;
  final double preferMax;
  final double speed;
  final int damage;
  final double attackCooldown;
  final int maxHealth;
  final int shieldMax;
  final double size;
  final Color idleColor;
  final Color aggroColor;
  final String spritePath;

  const _DroneStats({
    required this.detectionRadius,
    required this.attackRadius,
    required this.preferMin,
    required this.preferMax,
    required this.speed,
    required this.damage,
    required this.attackCooldown,
    required this.maxHealth,
    required this.shieldMax,
    required this.size,
    required this.idleColor,
    required this.aggroColor,
    required this.spritePath,
  });

  static _DroneStats forKind(DroneKind kind) => switch (kind) {
        DroneKind.scout => const _DroneStats(
            detectionRadius: 220,
            attackRadius: 36,
            preferMin: 0,
            preferMax: 0,
            speed: 64,
            damage: 12,
            attackCooldown: 1.0,
            maxHealth: 85,
            shieldMax: 0,
            size: 24,
            idleColor: Color(0xFF6688AA),
            aggroColor: Color(0xFFFF4444),
            spritePath: 'sprites/uec_drone.png',
          ),
        DroneKind.sniper => const _DroneStats(
            detectionRadius: 300,
            attackRadius: 260,
            preferMin: 140,
            preferMax: 240,
            speed: 44,
            damage: 11,
            attackCooldown: 1.5,
            maxHealth: 60,
            shieldMax: 0,
            size: 22,
            idleColor: Color(0xFF8866AA),
            aggroColor: Color(0xFFFF6622),
            spritePath: 'sprites/enemy_ship.png',
          ),
        DroneKind.shield => const _DroneStats(
            detectionRadius: 190,
            attackRadius: 42,
            preferMin: 0,
            preferMax: 0,
            speed: 38,
            damage: 15,
            attackCooldown: 1.2,
            maxHealth: 140,
            shieldMax: 65,
            size: 30,
            idleColor: Color(0xFF4488CC),
            aggroColor: Color(0xFF33AAFF),
            spritePath: 'sprites/uec_drone.png',
          ),
        DroneKind.swarm => const _DroneStats(
            detectionRadius: 240,
            attackRadius: 30,
            preferMin: 0,
            preferMax: 0,
            speed: 90,
            damage: 8,
            attackCooldown: 0.65,
            maxHealth: 35,
            shieldMax: 0,
            size: 16,
            idleColor: Color(0xFF88AA66),
            aggroColor: Color(0xFFFFCC33),
            spritePath: 'sprites/enemy_ship.png',
          ),
      };
}

class UECDrone extends GameDecoration {
  static final List<UECDrone> active = [];

  final DroneKind kind;
  /// When set, death counts toward that job board nest quest.
  final String? nestQuestId;
  final _DroneStats _stats;
  final Vector2 _origin;
  _DroneState _state = _DroneState.patrol;
  double _patrolAngle;
  double _attackTimer = 0;
  double _pulse = 0;
  late int _health;
  late int _shield;
  double _shieldRegen = 0;
  double _shieldRegenAcc = 0;
  bool _rewarded = false;
  /// Residual shove from player shots (px/s), decays each frame.
  Vector2 _knockback = Vector2.zero();
  bool get isDead => _health <= 0;
  int get maxHealth => _stats.maxHealth;

  UECDrone(
    Vector2 position, {
    double startAngle = 0,
    this.kind = DroneKind.scout,
    this.nestQuestId,
  })  : _stats = _DroneStats.forKind(kind),
        _origin = position.clone(),
        _patrolAngle = startAngle,
        super(position: position, size: Vector2.all(_DroneStats.forKind(kind).size)) {
    _health = _stats.maxHealth;
    _shield = _stats.shieldMax;
  }

  Sprite? _sprite;

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load(_stats.spritePath);
    active.add(this);
    add(CircleHitbox(
      radius: size.x * 0.5,
      isSolid: true,
      collisionType: CollisionType.passive,
    ));
    return super.onLoad();
  }

  @override
  void onRemove() {
    active.remove(this);
    super.onRemove();
  }

  void takeDamage(int amount, {Vector2? knockbackDir}) {
    if (isDead || amount <= 0) return;
    _shieldRegen = 0;
    _shieldRegenAcc = 0;
    if (knockbackDir != null) _applyKnockback(knockbackDir);
    if (_shield > 0) {
      final absorbed = min(_shield, amount);
      _shield -= absorbed;
      amount -= absorbed;
      if (amount <= 0) return;
    }
    _health -= amount;
  }

  void _applyKnockback(Vector2 dir) {
    if (dir.length2 < 1e-8) return;
    final mult = switch (kind) {
      DroneKind.swarm => 1.25,
      DroneKind.scout => 1.0,
      DroneKind.sniper => 0.9,
      DroneKind.shield => 0.4,
    };
    // Replace rather than stack so rapid fire feels snappy, not rocket-launch.
    _knockback = dir.normalized() * (140 * mult);
  }

  double get _leash => max(120.0, _stats.detectionRadius * 0.75);

  void _move(Vector2 delta) {
    final before = position.clone();
    final ok = DroneBounds.moveBy(this, delta, origin: _origin, leash: _leash);
    if (!ok) {
      _knockback.setZero();
      return;
    }
    // Partial slide into a wall/leash — stop the shove.
    if ((position - (before + delta)).length2 > 1) {
      _knockback.setZero();
    }
  }

  @override
  void update(double dt) {
    if (isDead) {
      if (!_rewarded) {
        _rewarded = true;
        Progression.onDroneKilled(kind);
        final nest = nestQuestId;
        if (nest != null && nest.isNotEmpty) Quests.onNestDroneKilled(nest);
      }
      gameRef.add(ExplosionEffect(position.clone()));
      removeFromParent();
      return;
    }
    super.update(dt);
    _pulse += dt * (kind == DroneKind.swarm ? 5.0 : 3.5);
    _attackTimer = max(0, _attackTimer - dt);

    if (_stats.shieldMax > 0 && _shield < _stats.shieldMax) {
      _shieldRegen += dt;
      if (_shieldRegen >= 3.0) {
        _shieldRegenAcc += 25 * dt;
        final add = _shieldRegenAcc.floor();
        if (add > 0) {
          _shield = (_shield + add).clamp(0, _stats.shieldMax);
          _shieldRegenAcc -= add;
        }
      }
    }

    DroneBounds.rescue(this, origin: _origin, leash: _leash);

    final player = gameRef.player;
    if (player == null) return;

    final toPlayer =
        (player.position + player.size / 2) - (position + size / 2);
    final dist = toPlayer.length;

    _updateState(dist);
    // Strong shove briefly overrides chase so hits read clearly.
    if (_knockback.length < 50) {
      _act(dt, toPlayer, dist);
    }
    if (_knockback.length2 > 0.25) {
      _move(_knockback * dt);
      _knockback.scale(exp(-14 * dt));
      if (_knockback.length2 < 4) _knockback.setZero();
    }
  }

  void _updateState(double dist) {
    switch (kind) {
      case DroneKind.sniper:
        if (dist > _stats.detectionRadius) {
          _state = _DroneState.patrol;
        } else if (dist < _stats.preferMin) {
          _state = _DroneState.retreat;
        } else if (dist > _stats.preferMax) {
          _state = _DroneState.chase;
        } else {
          _state = _DroneState.attack;
        }
      case DroneKind.scout:
      case DroneKind.shield:
      case DroneKind.swarm:
        if (dist < _stats.attackRadius) {
          _state = _DroneState.attack;
        } else if (dist < _stats.detectionRadius) {
          _state = _DroneState.chase;
        } else {
          _state = _DroneState.patrol;
        }
    }
  }

  void _act(double dt, Vector2 toPlayer, double dist) {
    switch (_state) {
      case _DroneState.patrol:
        _patrolAngle += dt * (kind == DroneKind.swarm ? 1.2 : 0.7);
        final radius = kind == DroneKind.swarm ? 40.0 : 70.0;
        final target = _origin +
            Vector2(cos(_patrolAngle) * radius, sin(_patrolAngle) * radius);
        final step = target - position;
        if (step.length > 1) {
          _move(step.normalized() * min(_stats.speed * dt, step.length));
        }
      case _DroneState.chase:
        if (toPlayer.length > 1) {
          _move(toPlayer.normalized() * _stats.speed * dt);
        }
      case _DroneState.retreat:
        if (toPlayer.length > 1) {
          _move(-toPlayer.normalized() * _stats.speed * 1.1 * dt);
        }
        if (_attackTimer <= 0 && dist <= _stats.attackRadius) {
          _fireOrMelee(toPlayer);
        }
      case _DroneState.attack:
        if (kind == DroneKind.sniper) {
          // Hold position and fire.
          if (_attackTimer <= 0) _fireOrMelee(toPlayer);
        } else if (_attackTimer <= 0) {
          _fireOrMelee(toPlayer);
        }
    }
  }

  void _fireOrMelee(Vector2 toPlayer) {
    if (kind == DroneKind.sniper) {
      if (toPlayer.length < 1) return;
      final origin = position + size / 2 - Vector2.all(EnemyBullet.bulletSize / 2);
      gameRef.add(EnemyBullet(origin, toPlayer, damage: _stats.damage));
      _attackTimer = _stats.attackCooldown;
      return;
    }
    CustomPlayer.applyDamage(_stats.damage);
    _attackTimer = _stats.attackCooldown;
  }

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;
    final aggro = _state != _DroneState.patrol;
    final col = aggro ? _stats.aggroColor : _stats.idleColor;

    // Kind-coloured aura
    canvas.drawCircle(
      Offset(cx, cy),
      r + (kind == DroneKind.shield && _shield > 0 ? 8 : 5),
      Paint()
        ..color = col.withOpacity(0.18 + sin(_pulse) * 0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // Shield ring
    if (_shield > 0) {
      canvas.drawCircle(
        Offset(cx, cy),
        r + 3,
        Paint()
          ..color = const Color(0xFF66CCFF)
              .withOpacity(0.35 + sin(_pulse) * 0.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    }

    if (_sprite != null) {
      _sprite!.render(
        canvas,
        size: size,
        overridePaint: Paint()
          ..colorFilter = ColorFilter.mode(
            Color.lerp(Colors.white, col, aggro ? 0.35 : 0.15)!,
            BlendMode.modulate,
          ),
      );
    }

    // HP bar
    const barW = 22.0;
    const barH = 3.0;
    final barX = cx - barW / 2;
    final barY = cy - r - 8;
    canvas.drawRect(
      Rect.fromLTWH(barX, barY, barW, barH),
      Paint()..color = Colors.black54,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        barX,
        barY,
        barW * (_health / _stats.maxHealth).clamp(0, 1),
        barH,
      ),
      Paint()..color = _stats.aggroColor,
    );

    // Shield bar (above HP)
    if (_stats.shieldMax > 0) {
      canvas.drawRect(
        Rect.fromLTWH(barX, barY - 4, barW, 2),
        Paint()..color = Colors.black54,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          barX,
          barY - 4,
          barW * (_shield / _stats.shieldMax).clamp(0, 1),
          2,
        ),
        Paint()..color = const Color(0xFF66CCFF),
      );
    }
  }
}
