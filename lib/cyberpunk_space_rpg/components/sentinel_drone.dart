import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../creatures/interaction.dart';
import '../game/game_debug.dart';
import '../game/game_state.dart';
import '../game/progression.dart';
import 'custom_player.dart';
import 'damage_number.dart';
import 'drone_bounds.dart';
import 'enemy_bullet.dart';
import 'explosion_effect.dart';
import 'sentinel_arena.dart';
import 'uec_drone.dart';

enum _SState { idle, fight }

enum _Atk { none, slamTele, ring, sweepTele }

/// City apex boss: sealed plaza arena + three HP phases with telegraphs/adds.
class SentinelDrone extends GameDecoration {
  static SentinelDrone? instance;
  static const int baseMaxHealth = 360;
  static const int baseLevel = 7;
  static const double spriteSize = 64;
  static const double _detectR = 280;
  static const double _meleeR = 44;
  static const double _speed = 62;
  static const double _rageSpeed = 96;
  static const double _meleeCd = 1.15;
  static const double _rageMeleeCd = 0.7;
  static const int _baseDamage = 16;
  static const int _baseRageDamage = 24;
  static const double _slamR = 78;
  static const double _slamTele = 0.75;
  static const double _sweepTele = 0.65;
  static const double _sweepRange = 110;
  static const double _sweepHalfRad = pi / 3; // 60° half-angle

  final int enemyLevel;
  final int maxHealth;
  final int _damage;
  final int _rageDamage;
  late int _health;
  bool get isDead => _health <= 0;
  _SState _state = _SState.idle;
  double _meleeTimer = 0;
  double _patternTimer = 1.2;
  double _pulse = 0;
  bool _deathFired = false;
  Vector2 _knockback = Vector2.zero();
  double _hushed = 0;
  double _stuckFor = 0;
  late final Vector2 _origin;
  late final Vector2 _arenaCenter;
  final VoidCallback onDefeated;
  final Random _rng = Random();

  _Atk _atk = _Atk.none;
  double _atkT = 0;
  double _sweepFacing = 0;
  int _phase = 1;
  bool _spawnedP2 = false;
  bool _spawnedP3 = false;
  bool _arenaReady = false;
  final List<UECDrone> _adds = [];

  bool get isHushed => _hushed > 0;
  double _slowT = 0;
  double _slowFactor = 0.45;
  double get _speedMult => _slowT > 0 ? _slowFactor : 1.0;

  void applyHush(double seconds) {
    if (isDead) return;
    _hushed = max(_hushed, seconds);
    _atk = _Atk.none;
    _atkT = 0;
  }

  void applySlow(double seconds, {double factor = 0.45}) {
    if (isDead || seconds <= 0) return;
    _slowT = max(_slowT, seconds);
    _slowFactor = min(_slowFactor, factor.clamp(0.1, 1.0));
  }

  factory SentinelDrone(Vector2 position,
      {required VoidCallback onDefeated, int? level}) {
    final lv = level ?? EnemyLevels.forSentinel();
    final s = EnemyLevels.scale(lv, baseLevel);
    return SentinelDrone._(
      position,
      onDefeated: onDefeated,
      enemyLevel: lv,
      maxHealth: max(1, (baseMaxHealth * s).round()),
      damage: max(1, (_baseDamage * s).round()),
      rageDamage: max(1, (_baseRageDamage * s).round()),
    );
  }

  SentinelDrone._(
    Vector2 position, {
    required this.onDefeated,
    required this.enemyLevel,
    required this.maxHealth,
    required int damage,
    required int rageDamage,
  })  : _damage = damage,
        _rageDamage = rageDamage,
        _origin = position.clone(),
        _arenaCenter = position + Vector2.all(24),
        super(position: position, size: Vector2.all(48)) {
    _health = maxHealth;
  }

  /// HP ratio → phase (1 above 60%, 2 above 30%, else 3).
  static int phaseForHpRatio(double ratio) {
    if (ratio > 0.6) return 1;
    if (ratio > 0.3) return 2;
    return 3;
  }

  Sprite? _sprite;

  Vector2 get _centre => position + size / 2;

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load('sprites/sentinel_boss.png');
    instance = this;
    add(CircleHitbox(
        radius: 24, isSolid: true, collisionType: CollisionType.passive));
    // Arena lives under the boss; sealed on first engage.
    if (SentinelArena.instance == null) {
      gameRef.add(SentinelArena(_arenaCenter.clone()));
    }
    return super.onLoad();
  }

  @override
  void onRemove() {
    if (instance == this) instance = null;
    _clearAdds();
    SentinelArena.instance?.open();
    super.onRemove();
  }

  Vector2 get _leashOrigin =>
      _state == _SState.fight ? _arenaCenter : _origin;

  double get _leash {
    if (_state == _SState.idle) return 260;
    // Stay inside the arena while fighting.
    return SentinelArena.halfExtent - 24;
  }

  void _engage() {
    if (_arenaReady) return;
    _arenaReady = true;
    _state = _SState.fight;
    GameState.onSentinelEngaged();
    _trySeal();
  }

  /// Fence only when Kaela is inside — ranged openers must not lock her out.
  void _trySeal() {
    final arena = SentinelArena.instance;
    if (arena == null || arena.sealed || !hasGameRef) return;
    final player = gameRef.player;
    if (player == null) return;
    final p = player.position + player.size / 2;
    if (!arena.containsWorld(p)) return;
    arena.seal();
    GameToast.show('SENTINEL LOCKDOWN',
        body: 'Plaza sealed · watch the ground',
        color: const Color(0xFFFF6622),
        compact: true);
  }

  void _setPhase(int p) {
    if (p == _phase) return;
    _phase = p;
    GameToast.show('PHASE $p',
        color: const Color(0xFFFF8844), compact: true, seconds: 1.6);
    if (p == 2 && !_spawnedP2) {
      _spawnedP2 = true;
      _spawnAdds(DroneKind.swarm, 2);
    } else if (p == 3 && !_spawnedP3) {
      _spawnedP3 = true;
      _spawnAdds(DroneKind.sniper, 1);
    }
  }

  void _spawnAdds(DroneKind kind, int count) {
    if (!hasGameRef) return;
    final c = _arenaCenter;
    for (var i = 0; i < count; i++) {
      final ang = (i / max(1, count)) * pi * 2 + _pulse;
      final pos = c + Vector2(cos(ang), sin(ang)) * 90 - Vector2.all(16);
      final d = UECDrone(pos, kind: kind, startAngle: ang, level: 3);
      _adds.add(d);
      gameRef.add(d);
    }
  }

  void _clearAdds() {
    for (final d in _adds) {
      if (d.isMounted && !d.isDead) d.removeFromParent();
    }
    _adds.clear();
  }

  void _move(Vector2 delta) {
    final before = position.clone();
    final ok = DroneBounds.chaseStep(
      this,
      delta,
      origin: _leashOrigin,
      leash: _leash,
      pad: 28,
    );
    if (!ok) {
      _knockback.setZero();
      return;
    }
    if ((position - (before + delta)).length2 > 1) {
      _knockback.setZero();
    }
  }

  void _unstuckToward(Vector2 toPlayer) {
    if (toPlayer.length2 < 1e-6) return;
    final dir = toPlayer.normalized();
    final centre = _centre;
    for (final dist in [48.0, 80.0, 120.0]) {
      for (final angle in [0.0, 0.55, -0.55, 1.1, -1.1]) {
        final c = cos(angle);
        final s = sin(angle);
        final step =
            Vector2(dir.x * c - dir.y * s, dir.x * s + dir.y * c) * dist;
        final next = centre + step - size / 2;
        if (DroneBounds.moveBy(
          this,
          next - position,
          origin: _leashOrigin,
          leash: _leash,
          pad: 28,
        )) {
          _stuckFor = 0;
          return;
        }
      }
    }
  }

  void takeDamage(int amount,
      {Vector2? knockbackDir, double knockbackScale = 1.0}) {
    if (isDead) return;
    _engage();
    if (knockbackDir != null && knockbackDir.length2 > 1e-8) {
      _knockback = knockbackDir.normalized() * (70 * knockbackScale);
    }
    _health = (_health - amount).clamp(0, maxHealth);
    DamageNumber.spawn(
        this, position + Vector2(size.x / 2, 0), amount, DamageNumberStyle.dealt);
    _setPhase(phaseForHpRatio(_health / maxHealth));
    if (_health <= 0 && !_deathFired) {
      _deathFired = true;
      _clearAdds();
      SentinelArena.instance?.open();
      Progression.onSentinelKilled(enemyLevel: enemyLevel);
      gameRef.add(ExplosionEffect(position.clone()));
      Future.microtask(onDefeated);
      removeFromParent();
    }
  }

  void _startSlam() {
    _atk = _Atk.slamTele;
    _atkT = _slamTele;
  }

  void _startRing() {
    _atk = _Atk.ring;
    _atkT = 0.05;
  }

  void _startSweep(Vector2 toPlayer) {
    _atk = _Atk.sweepTele;
    _atkT = _sweepTele;
    _sweepFacing = atan2(toPlayer.y, toPlayer.x);
  }

  void _resolveSlam() {
    final player = gameRef.player;
    if (player == null) return;
    final to = (player.position + player.size / 2) - _centre;
    if (to.length <= _slamR) {
      CustomPlayer.applyDamage(_phase >= 3 ? _rageDamage : _damage + 4);
    }
  }

  void _resolveRing() {
    if (!hasGameRef) return;
    final dmg = max(8, (_damage * 0.7).round());
    for (var i = 0; i < 8; i++) {
      final a = i * pi / 4 + _pulse * 0.2;
      final dir = Vector2(cos(a), sin(a));
      gameRef.add(EnemyBullet(
        _centre - Vector2.all(EnemyBullet.bulletSize / 2),
        dir,
        damage: dmg,
      ));
    }
  }

  void _resolveSweep() {
    final player = gameRef.player;
    if (player == null) return;
    final to = (player.position + player.size / 2) - _centre;
    if (to.length > _sweepRange || to.length2 < 1e-6) return;
    final ang = atan2(to.y, to.x);
    var d = (ang - _sweepFacing);
    while (d > pi) {
      d -= 2 * pi;
    }
    while (d < -pi) {
      d += 2 * pi;
    }
    if (d.abs() <= _sweepHalfRad) {
      CustomPlayer.applyDamage(_rageDamage);
    }
  }

  void _tickPatterns(double dt, Vector2 toPlayer, double dist) {
    if (isHushed) {
      _atk = _Atk.none;
      return;
    }
    if (_atk != _Atk.none) {
      _atkT -= dt;
      if (_atkT > 0) return;
      switch (_atk) {
        case _Atk.slamTele:
          _resolveSlam();
          break;
        case _Atk.ring:
          _resolveRing();
          break;
        case _Atk.sweepTele:
          _resolveSweep();
          break;
        case _Atk.none:
          break;
      }
      _atk = _Atk.none;
      _patternTimer = _phase == 1 ? 2.4 : (_phase == 2 ? 2.0 : 1.55);
      return;
    }

    _patternTimer -= dt;
    if (_patternTimer > 0) return;

    // Pick next attack by phase.
    if (_phase == 1) {
      _startSlam();
    } else if (_phase == 2) {
      if (_rng.nextBool()) {
        _startRing();
      } else {
        _startSlam();
      }
    } else {
      final r = _rng.nextDouble();
      if (r < 0.4) {
        _startSweep(toPlayer);
      } else if (r < 0.7) {
        _startRing();
      } else {
        _startSlam();
      }
    }
  }

  @override
  void update(double dt) {
    if (isDead) return;
    super.update(dt);
    _pulse += dt * 4.5;
    _meleeTimer = max(0, _meleeTimer - dt);
    _hushed = max(0, _hushed - dt);
    _slowT = max(0, _slowT - dt);
    if (_slowT <= 0) _slowFactor = 0.45;

    final player = gameRef.player;
    if (player == null) return;
    final toPlayer = (player.position + player.size / 2) - _centre;
    final dist = toPlayer.length;

    if (dist < _detectR || _arenaReady) {
      _engage();
    }
    if (_state == _SState.idle) return;
    if (_arenaReady) _trySeal();

    _setPhase(phaseForHpRatio(_health / maxHealth));
    final rage = _phase >= 3;
    final spd = (rage ? _rageSpeed : _speed) * _speedMult;

    DroneBounds.rescue(this, origin: _leashOrigin, leash: _leash, pad: 28);
    _tickPatterns(dt, toPlayer, dist);

    // Movement: orbit / chase between telegraphs (freeze during slam/sweep tele).
    final freezing = _atk == _Atk.slamTele || _atk == _Atk.sweepTele;
    if (!isHushed &&
        !freezing &&
        _knockback.length < 40 &&
        dist > _meleeR * 0.85) {
      Vector2 desire;
      if (_phase == 1 && dist < 120) {
        // Orbit clockwise.
        final n = toPlayer.normalized();
        desire = Vector2(-n.y, n.x) * spd * dt;
      } else {
        desire = toPlayer.normalized() * spd * dt;
      }
      final before = position.clone();
      _move(desire);
      if ((position - before).length2 < 0.25) {
        _stuckFor += dt;
        if (_stuckFor > 0.35) _unstuckToward(toPlayer);
      } else {
        _stuckFor = 0;
      }
    } else {
      _stuckFor = 0;
    }

    if (_knockback.length2 > 0.25) {
      _move(_knockback * dt);
      _knockback.scale(exp(-12 * dt));
      if (_knockback.length2 < 4) _knockback.setZero();
    }

    // Backup melee if Kaela hugs the body.
    if (!isHushed &&
        !freezing &&
        dist < _meleeR * 1.35 &&
        _meleeTimer <= 0) {
      CustomPlayer.applyDamage(rage ? _rageDamage : _damage);
      _meleeTimer = rage ? _rageMeleeCd : _meleeCd;
    }
  }

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;
    final rage = _phase >= 3;
    final col = rage ? const Color(0xFFFF2200) : const Color(0xFFFF6600);
    final p = sin(_pulse);

    // Outer pulsing aura
    canvas.drawCircle(
        Offset(cx, cy),
        r + 12 + p * 5,
        Paint()
          ..color = col.withValues(alpha: 0.14 + p * 0.06)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));

    if (_sprite != null) {
      const s = spriteSize;
      _sprite!.render(
        canvas,
        position: Vector2(cx - s / 2, cy - s / 2),
        size: Vector2.all(s),
        overridePaint: Paint()..filterQuality = FilterQuality.none,
      );
    }

    if (rage) {
      canvas.drawCircle(Offset(cx, cy), r * 0.1,
          Paint()..color = Colors.white.withValues(alpha: 0.5 + p * 0.3));
    }

    _paintTelegraphs(canvas, cx, cy, col);

    // Level + HP bar
    const barW = 52.0, barH = 5.0;
    final barX = cx - barW / 2;
    final barY = cy - spriteSize / 2 - 8;
    canvas.drawRect(
        Rect.fromLTWH(barX, barY, barW, barH), Paint()..color = Colors.black54);
    canvas.drawRect(
        Rect.fromLTWH(
            barX, barY, barW * (_health / maxHealth).clamp(0, 1), barH),
        Paint()..color = col);
    canvas.drawRect(
        Rect.fromLTWH(barX, barY, barW, barH),
        Paint()
          ..color = col.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);

    final lvTp = TextPainter(
      text: TextSpan(
        text: 'LV$enemyLevel  P$_phase',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.95),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          shadows: const [
            Shadow(
                color: Colors.black87,
                blurRadius: 2,
                offset: Offset(0, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    lvTp.paint(canvas, Offset(cx - lvTp.width / 2, barY - lvTp.height - 2));

    if (GameDebug.isOn) {
      final tileX = (absolutePosition.x / 32).toStringAsFixed(0);
      final tileY = (absolutePosition.y / 32).toStringAsFixed(0);
      GameDebug.paintLabel(
        canvas,
        'sentinel @$tileX,$tileY p$_phase',
        Offset(cx, barY - lvTp.height - 13),
      );
    }
  }

  void _paintTelegraphs(Canvas canvas, double cx, double cy, Color col) {
    if (_atk == _Atk.slamTele) {
      final t = (1 - _atkT / _slamTele).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(cx, cy),
        _slamR,
        Paint()
          ..color = Color.fromRGBO(255, 200, 40, 0.15 + t * 0.25)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(cx, cy),
        _slamR,
        Paint()
          ..color = Color.fromRGBO(255, 180, 20, 0.55 + t * 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      canvas.drawCircle(
        Offset(cx, cy),
        _slamR * t,
        Paint()
          ..color = const Color(0x88FFEE66)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    } else if (_atk == _Atk.sweepTele) {
      final t = (1 - _atkT / _sweepTele).clamp(0.0, 1.0);
      final path = Path()
        ..moveTo(cx, cy)
        ..arcTo(
          Rect.fromCircle(center: Offset(cx, cy), radius: _sweepRange),
          _sweepFacing - _sweepHalfRad,
          _sweepHalfRad * 2,
          false,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = Color.fromRGBO(255, 60, 40, 0.18 + t * 0.28),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.fromRGBO(255, 80, 40, 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }
}
