import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'custom_player.dart';
import 'damage_number.dart';
import 'drone_bounds.dart';
import 'enemy_bullet.dart';
import 'explosion_effect.dart';
import '../game/game_debug.dart';
import '../game/game_state.dart';
import '../game/progression.dart';
import '../game/quests.dart';
import '../game/save_service.dart';

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

  /// Danger rank before map tier (swarm weakest → shield toughest).
  int get baseLevel => switch (this) {
        DroneKind.swarm => 1,
        DroneKind.scout => 2,
        DroneKind.sniper => 3,
        DroneKind.shield => 4,
      };
}

/// Enemy levels: kind danger + map tier (woods soft → core hard).
class EnemyLevels {
  EnemyLevels._();

  static int mapBonus([int? gameLevel]) {
    final g = gameLevel ?? GameState.level;
    return switch (g) {
      1 => 0, // woods
      2 => 1, // city
      5 => 1, // lantern town
      3 => 2, // ruins
      4 => 3, // core
      _ => 0,
    };
  }

  static int forDrone(DroneKind kind, {int? overrideLevel, int? gameLevel}) =>
      overrideLevel ?? (kind.baseLevel + mapBonus(gameLevel));

  /// Sentinel is the city apex threat.
  static int forSentinel({int? gameLevel}) => 7 + mapBonus(gameLevel);

  /// Stat multiplier so base-level drones keep today's numbers.
  static double scale(int level, int baseLevel) =>
      (1.0 + 0.1 * (level - baseLevel)).clamp(0.7, 2.2);
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
  /// Static 32x32 art (`sprites/uec_<kind>.png`). A 2-frame hover sheet
  /// `<name>_hover.png` next to it is preferred when present.
  final String spritePath;

  /// Drawn size of the sprite (centred); can exceed the hitbox [size] so
  /// small, fast kinds stay readable.
  final double spriteSize;

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
    required this.spriteSize,
  });

  String get hoverPath => spritePath.replaceFirst(RegExp(r'\.png$'), '_hover.png');

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
            spritePath: 'sprites/uec_scout.png',
            spriteSize: 28,
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
            spritePath: 'sprites/uec_sniper.png',
            spriteSize: 28,
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
            spritePath: 'sprites/uec_shield.png',
            spriteSize: 32,
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
            spritePath: 'sprites/uec_swarm.png',
            // Three ships in one sprite: below ~24px they turn to mush.
            spriteSize: 26,
          ),
      };
}

class UECDrone extends GameDecoration {
  static final List<UECDrone> active = [];

  final DroneKind kind;
  /// Combat level shown above the HP bar (kind danger + map tier).
  final int enemyLevel;
  /// When set, death counts toward that job board nest quest.
  final String? nestQuestId;
  final _DroneStats _stats;
  final Vector2 _origin;
  final int _maxHp;
  final int _maxShield;
  final int _damage;
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
  /// Puffcap HUSH: seconds left calmed (no chase / attack).
  double _hushed = 0;
  bool get isDead => _health <= 0;
  int get maxHealth => _maxHp;
  bool get isHushed => _hushed > 0;

  void applyHush(double seconds) {
    if (isDead) return;
    _hushed = max(_hushed, seconds);
    _state = _DroneState.patrol;
  }

  factory UECDrone(
    Vector2 position, {
    double startAngle = 0,
    DroneKind kind = DroneKind.scout,
    String? nestQuestId,
    int? level,
  }) {
    final stats = _DroneStats.forKind(kind);
    final lv = EnemyLevels.forDrone(kind, overrideLevel: level);
    final s = EnemyLevels.scale(lv, kind.baseLevel);
    return UECDrone._(
      position,
      startAngle: startAngle,
      kind: kind,
      nestQuestId: nestQuestId,
      enemyLevel: lv,
      stats: stats,
      maxHp: max(1, (stats.maxHealth * s).round()),
      maxShield: (stats.shieldMax * s).round(),
      damage: max(1, (stats.damage * s).round()),
    );
  }

  UECDrone._(
    Vector2 position, {
    double startAngle = 0,
    required this.kind,
    required this.nestQuestId,
    required this.enemyLevel,
    required _DroneStats stats,
    required int maxHp,
    required int maxShield,
    required int damage,
  })  : _stats = stats,
        _origin = position.clone(),
        _patrolAngle = startAngle,
        _maxHp = maxHp,
        _maxShield = maxShield,
        _damage = damage,
        super(position: position, size: Vector2.all(stats.size)) {
    _health = _maxHp;
    _shield = _maxShield;
  }

  Sprite? _sprite;
  SpriteAnimationTicker? _hover;

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load(_stats.spritePath);
    try {
      // Frame 2 bobs up 1px and brightens the eye (uec_*_hover.json).
      final img = await Flame.images.load(_stats.hoverPath);
      _hover = SpriteAnimation.fromFrameData(
        img,
        SpriteAnimationData.sequenced(
          amount: max(1, img.width ~/ 32),
          stepTime: kind == DroneKind.swarm ? 0.2 : 0.3,
          textureSize: Vector2.all(32),
        ),
      ).createTicker();
    } catch (_) {
      _hover = null;
    }
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
    final top = position + Vector2(size.x / 2, 0);
    if (_shield > 0) {
      final absorbed = min(_shield, amount);
      _shield -= absorbed;
      amount -= absorbed;
      if (amount <= 0) {
        DamageNumber.spawn(this, top, absorbed, DamageNumberStyle.shield);
        return;
      }
    }
    _health -= amount;
    DamageNumber.spawn(this, top, amount, DamageNumberStyle.dealt);
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

  /// Patrol stays near spawn; once aggro'd, allow a longer chase so they don't
  /// freeze on the leash while still glowing red at the player.
  double get _leash {
    final base = max(120.0, _stats.detectionRadius * 0.75);
    return _state == _DroneState.patrol ? base : base * 1.85;
  }

  void _move(Vector2 delta) {
    final before = position.clone();
    var ok = DroneBounds.moveBy(this, delta, origin: _origin, leash: _leash);
    if (!ok && delta.length2 > 1e-8) {
      // Head-on into a prop/corner: step sideways so chase doesn't hard-stop.
      final n = delta.normalized();
      final len = delta.length;
      final left = Vector2(-n.y, n.x) * len;
      final right = Vector2(n.y, -n.x) * len;
      ok = DroneBounds.moveBy(this, left, origin: _origin, leash: _leash) ||
          DroneBounds.moveBy(this, right, origin: _origin, leash: _leash);
    }
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
        Progression.onDroneKilled(kind, enemyLevel: enemyLevel);
        final nest = nestQuestId;
        if (nest != null && nest.isNotEmpty) Quests.onNestDroneKilled(nest);
        Quests.onDroneKilled(SaveService.data.regionId);
      }
      gameRef.add(ExplosionEffect(position.clone()));
      removeFromParent();
      return;
    }
    super.update(dt);
    _hover?.update(dt);
    _pulse += dt * (kind == DroneKind.swarm ? 5.0 : 3.5);
    _attackTimer = max(0, _attackTimer - dt);
    _hushed = max(0, _hushed - dt);

    if (_maxShield > 0 && _shield < _maxShield) {
      _shieldRegen += dt;
      if (_shieldRegen >= 3.0) {
        _shieldRegenAcc += 25 * dt;
        final add = _shieldRegenAcc.floor();
        if (add > 0) {
          _shield = (_shield + add).clamp(0, _maxShield);
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

    if (isHushed) {
      _state = _DroneState.patrol;
      if (_knockback.length < 50) _act(dt, toPlayer, dist);
    } else {
      _updateState(dist);
      // Strong shove briefly overrides chase so hits read clearly.
      if (_knockback.length < 50) {
        _act(dt, toPlayer, dist);
      }
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
        } else {
          // Keep closing during cooldown — standing still at attackRadius looks
          // like the AI stalled mid-charge.
          const strikeRange = 20.0;
          if (dist > strikeRange && toPlayer.length > 1) {
            _move(toPlayer.normalized() * _stats.speed * dt);
          }
          if (_attackTimer <= 0) _fireOrMelee(toPlayer);
        }
    }
  }

  void _fireOrMelee(Vector2 toPlayer) {
    if (kind == DroneKind.sniper) {
      if (toPlayer.length < 1) return;
      final origin = position + size / 2 - Vector2.all(EnemyBullet.bulletSize / 2);
      gameRef.add(EnemyBullet(origin, toPlayer, damage: _damage));
      _attackTimer = _stats.attackCooldown;
      return;
    }
    CustomPlayer.applyDamage(_damage);
    _attackTimer = _stats.attackCooldown;
  }

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;
    final aggro = !isHushed && _state != _DroneState.patrol;
    final col = isHushed
        ? const Color(0xFF88CC88)
        : (aggro ? _stats.aggroColor : _stats.idleColor);

    // Kind-coloured aura (soft green while HUSHed)
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

    final sprite = _hover?.getSprite() ?? _sprite;
    if (sprite != null) {
      final s = _stats.spriteSize;
      sprite.render(
        canvas,
        position: Vector2(cx - s / 2, cy - s / 2),
        size: Vector2.all(s),
        overridePaint: Paint()
          ..filterQuality = FilterQuality.none
          // Light tint only: the per-kind art already carries the identity.
          ..colorFilter = ColorFilter.mode(
            Color.lerp(Colors.white, col, aggro ? 0.25 : 0.0)!,
            BlendMode.modulate,
          ),
      );
    }

    // Level + HP bar
    const barW = 22.0;
    const barH = 3.0;
    final barX = cx - barW / 2;
    final barY = cy - max(r, _stats.spriteSize / 2) - 6;
    canvas.drawRect(
      Rect.fromLTWH(barX, barY, barW, barH),
      Paint()..color = Colors.black54,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        barX,
        barY,
        barW * (_health / _maxHp).clamp(0, 1),
        barH,
      ),
      Paint()..color = _stats.aggroColor,
    );

    // Shield bar (above HP)
    if (_maxShield > 0) {
      canvas.drawRect(
        Rect.fromLTWH(barX, barY - 4, barW, 2),
        Paint()..color = Colors.black54,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          barX,
          barY - 4,
          barW * (_shield / _maxShield).clamp(0, 1),
          2,
        ),
        Paint()..color = const Color(0xFF66CCFF),
      );
    }

    final lvTp = TextPainter(
      text: TextSpan(
        text: 'LV$enemyLevel',
        style: TextStyle(
          color: Colors.white.withOpacity(0.9),
          fontSize: 8,
          fontWeight: FontWeight.w700,
          shadows: const [
            Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final lvTop = _maxShield > 0 ? barY - 4 : barY;
    lvTp.paint(canvas, Offset(cx - lvTp.width / 2, lvTop - lvTp.height - 1));

    if (GameDebug.isOn) {
      final tileX = (absolutePosition.x / 32).toStringAsFixed(0);
      final tileY = (absolutePosition.y / 32).toStringAsFixed(0);
      GameDebug.paintLabel(
        canvas,
        '${kind.name} @$tileX,$tileY',
        Offset(cx, lvTop - lvTp.height - 12),
      );
    }
  }
}
