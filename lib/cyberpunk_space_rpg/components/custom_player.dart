import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bonfire/util/collision_game_component.dart';
import 'dart:math';
import 'ai_fragment.dart';
import 'npc_character.dart';
import 'player_bullet.dart';
import 'sentinel_drone.dart';
import 'uec_drone.dart';
import 'walk_sheet.dart';
import 'building.dart';
import 'muzzle_flash.dart';
import '../audio/music_manager.dart';
import '../game/progression.dart';
import '../game/well_rested.dart';
import 'damage_number.dart';

class CustomPlayer extends SimplePlayer with BlockMovementCollision {
  static const double sizePlayer = 32;
  /// Width of the feet hitbox that collides with the world.
  static const double feetWidth = sizePlayer * 0.5;
  static const int baseMaxHealth = 100;
  /// Base HP plus level/gear bonuses (Runescape-lite progression).
  static int get maxHealth => baseMaxHealth + Progression.bonusHealth;
  static final ValueNotifier<Vector2> positionNotifier = ValueNotifier(Vector2.zero());
  static final ValueNotifier<int> healthNotifier = ValueNotifier(baseMaxHealth);
  static final ValueNotifier<bool> damageFlash = ValueNotifier(false);
  static final ValueNotifier<Vector2?> pendingShot = ValueNotifier(null);
  /// Shots fired so far and where the last one left from: creatures listen
  /// for noise (quiet approach).
  static int shotCount = 0;
  static Vector2? lastShotFrom;

  // --- Calm gameplay: no game over, gentle regen -------------------------
  /// Seconds without taking damage before health starts coming back.
  static const double regenDelay = 4.0;
  /// HP per second while regenerating (0 -> 100 in 20 s).
  static const double regenPerSecond = 5.0;
  /// Respawn fade: fade to black, hold (teleport happens here), fade back.
  static const double fadeOutSeconds = 0.8;
  static const double fadeHoldSeconds = 0.9;
  static const double fadeInSeconds = 0.8;
  /// Extra no-damage time after the fade so Kaela can get her bearings.
  static const double respawnGraceSeconds = 1.5;

  /// True while the "Gaia pulls you back" fade should be shown.
  static final ValueNotifier<bool> respawnFade = ValueNotifier(false);
  /// The player on the current map (null between maps).
  static CustomPlayer? current;

  /// Top-left position to respawn at: the last checkpoint touched, or the
  /// map's spawn until one is reached.
  Vector2? respawnPoint;
  double _sinceDamage = regenDelay;
  double _regenAcc = 0;
  double _respawnT = -1; // >= 0 while the respawn sequence runs
  double _grace = 0;
  bool _teleported = false;
  bool get isRespawning => _respawnT >= 0;
  bool get isInvulnerable => isRespawning || _grace > 0;

  /// All enemy damage goes through here. The respawn fade and the short
  /// grace period after it ignore damage. At 0 HP Kaela is pulled back to
  /// the last checkpoint instead of a game over.
  static void applyDamage(int amount) {
    // Talk / absorb overlays freeze combat; ignore stray hits too.
    if (NpcCharacter.activeDialogue.value != null ||
        AIFragment.activeDialogue.value != null) {
      return;
    }
    final p = current;
    if (p != null && p.isInvulnerable) return;
    final hp = (healthNotifier.value - amount).clamp(0, maxHealth);
    healthNotifier.value = hp;
    damageFlash.value = true;
    SfxManager().playDamage();
    if (p == null) return;
    DamageNumber.spawn(p, p.position + Vector2(p.size.x / 2, 0), amount, DamageNumberStyle.taken);
    p._sinceDamage = 0;
    p._regenAcc = 0;
    if (hp <= 0) p._startRespawn();
  }

  void _startRespawn() {
    _respawnT = 0;
    _teleported = false;
    pendingShot.value = null;
    setupMovementByJoystick(enabled: false);
    stopMove(forceIdle: true);
    respawnFade.value = true;
  }

  void _updateRespawn(double dt) {
    _respawnT += dt;
    stopMove(forceIdle: true);
    if (!_teleported && _respawnT >= fadeOutSeconds) {
      _teleported = true;
      final p = respawnPoint;
      if (p != null) position = p.clone();
      healthNotifier.value = maxHealth;
      _sinceDamage = regenDelay;
      gameRef.camera.moveToPlayer();
    }
    if (_respawnT >= fadeOutSeconds + fadeHoldSeconds && respawnFade.value) {
      respawnFade.value = false;
    }
    if (_respawnT >= fadeOutSeconds + fadeHoldSeconds + fadeInSeconds) {
      _respawnT = -1;
      _grace = respawnGraceSeconds;
      setupMovementByJoystick(enabled: true);
    }
  }

  void _updateRegen(double dt) {
    _sinceDamage += dt;
    WellRested.tick(dt);
    final hp = healthNotifier.value;
    // Calm regen after a quiet spell; "Well rested" trickles in even mid-fight.
    final rate = (_sinceDamage >= regenDelay ? regenPerSecond : 0.0) +
        (WellRested.active ? WellRested.regenPerSecond : 0.0);
    if (hp <= 0 || hp >= maxHealth || rate <= 0) {
      _regenAcc = 0;
      return;
    }
    _regenAcc += rate * dt;
    final whole = _regenAcc.floor();
    if (whole > 0) {
      _regenAcc -= whole;
      healthNotifier.value = min(maxHealth, hp + whole);
    }
  }

  bool isBlocked = false;
  double _blockedTimer = 0;
  bool _eWasPressed = false;
  double _footstepTimer = 0;
  bool _joystickMoving = false;
  double _shootCooldown = 0;
  Map<Direction, SpriteAnimation>? _shootAnims;
  /// Visual-only knockback after a shot (does not move the hitbox).
  double _shootKickT = 0;
  Vector2 _shootKick = Vector2.zero();

  CustomPlayer(Vector2 position) : super(
    position: position,
    size: Vector2.all(sizePlayer),
    speed: sizePlayer * 2.5,
    life: 100,
    initDirection: Direction.down,
  ) {
    priority = 1000;
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;
    final glowColor = isBlocked ? const Color(0xFFFF3333) : const Color(0xFF00FFFF);

    // Glow aura (state indicator kept on top of sprite)
    canvas.drawCircle(
      Offset(cx, cy),
      r + 3,
      Paint()
        ..color = glowColor.withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Brief visual kick opposite the shot — keeps walk art intact.
    if (_shootKickT > 0) {
      canvas.save();
      final u = (_shootKickT / 0.1).clamp(0.0, 1.0);
      canvas.translate(_shootKick.x * u, _shootKick.y * u);
      super.render(canvas);
      canvas.restore();
    } else {
      super.render(canvas);
    }
  }

  @override
  Future<void> onLoad() async {
    current = this;
    respawnFade.value = false;
    SfxManager().init();
    paint.filterQuality = FilterQuality.none;
    animation = await WalkSheet.load('sprites/kaela_walk.png');
    _shootAnims = await ShootSheet.load('sprites/kaela_shoot.png');
    add(RectangleHitbox(
      size: Vector2(feetWidth, sizePlayer / 3),
      position: Vector2(sizePlayer * 0.25, sizePlayer * 0.65),
    ));
    return super.onLoad();
  }

  // Bonfire's collision shouldn't push us around for our own bullets or the
  // AI fragment (it's something you interact with, not an obstacle).
  @override
  bool onBlockMovement(Set<Vector2> intersectionPoints, GameComponent other) {
    if (other is PlayerBullet || other is AIFragment) return false;
    return super.onBlockMovement(intersectionPoints, other);
  }

  // Setting `position` (spawn / teleport) goes through translate(), which
  // Bonfire also uses to update lastDirection from the jump. Keep the facing
  // so Kaela doesn't turn towards wherever she was teleported.
  @override
  void translate(Vector2 displacement) {
    final facing = lastDirection;
    final facingH = lastDirectionHorizontal;
    super.translate(displacement);
    lastDirection = facing;
    lastDirectionHorizontal = facingH;
  }

  // Walls are Tiled tile collisions; BlockMovementCollision pushes us out and
  // removes only the velocity component into the wall, so we slide along it.
  // Flag "blocked" (red glow, no footsteps) only while pressing into a wall.
  @override
  void onBlockedMovement(PositionComponent other, CollisionData collisionData) {
    super.onBlockedMovement(other, collisionData);
    // After super, velocity is what's left once the into-wall part is
    // removed: near zero means we're pushing straight into the wall.
    if ((other is TileWithCollision || other is CollisionMapComponent || other is Building) &&
        velocity.length < speed * 0.2) {
      _blockedTimer = 0.1;
    }
  }

  @override
  void onRemove() {
    if (current == this) current = null;
    respawnFade.value = false;
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    positionNotifier.value = position.clone();
    _blockedTimer = max(0, _blockedTimer - dt);
    isBlocked = _blockedTimer > 0;
    _grace = max(0, _grace - dt);
    if (isRespawning) {
      _updateRespawn(dt);
      pendingShot.value = null;
      return;
    }
    _updateRegen(dt);
    _checkInteraction();
    _updateFootsteps(dt);
    _handleShooting(dt);
    if (_shootKickT > 0) _shootKickT = max(0, _shootKickT - dt);
  }

  void _updateFootsteps(double dt) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final keyboardMoving = keys.contains(LogicalKeyboardKey.keyW) ||
        keys.contains(LogicalKeyboardKey.keyS) ||
        keys.contains(LogicalKeyboardKey.keyA) ||
        keys.contains(LogicalKeyboardKey.keyD) ||
        keys.contains(LogicalKeyboardKey.arrowUp) ||
        keys.contains(LogicalKeyboardKey.arrowDown) ||
        keys.contains(LogicalKeyboardKey.arrowLeft) ||
        keys.contains(LogicalKeyboardKey.arrowRight);
    final moving = keyboardMoving || _joystickMoving;
    if (moving && !isBlocked) {
      _footstepTimer -= dt;
      if (_footstepTimer <= 0) {
        SfxManager().playFootstep();
        _footstepTimer = 0.38;
      }
    } else {
      _footstepTimer = 0;
    }
  }

  void _checkInteraction() {
    final ePressed = HardwareKeyboard.instance.logicalKeysPressed
        .contains(LogicalKeyboardKey.keyE);
    if (ePressed && !_eWasPressed) {
      AIFragment.nearbyFragment?.interact();
      NpcCharacter.nearbyNpc?.interact();
    }
    _eWasPressed = ePressed;
  }

  void _handleShooting(double dt) {
    _shootCooldown = max(0, _shootCooldown - dt);
    final shot = pendingShot.value;
    if (shot == null) return;
    pendingShot.value = null;
    if (_shootCooldown > 0) return;

    final camCenter = gameRef.camera.viewfinder.position;
    final screenCenter = gameRef.size / 2;
    final zoom = gameRef.camera.viewfinder.zoom;
    final worldPos = camCenter + (shot - screenCenter) / zoom;

    final origin = position + size / 2;
    final dir = _lockShotDirection(origin, worldPos);
    if (dir == null) return;

    gameRef.add(PlayerBullet(
      origin - PlayerBullet.spriteSize / 2,
      dir,
    ));
    gameRef.add(MuzzleFlash(origin + dir * 12, dir));
    SfxManager().playShoot();
    shotCount++;
    lastShotFrom = origin;
    _shootCooldown = 0.28 * Progression.fireCooldownMult;
    lastDirection = WalkSheet.facingVector(dir);
    _shootKick = -dir.normalized() * 1.5;
    _shootKickT = 0.08;
    _playShootAnim(dir);
  }

  void _playShootAnim(Vector2 dir) {
    final face = WalkSheet.facingVector(dir);
    final anim = _shootAnims?[face];
    if (anim == null || animation == null) return;
    lastDirection = face;
    animation!.playOnce(anim.clone(), runToTheEnd: true);
  }

  /// Soft aim assist: snap toward a drone near the tap, or inside the aim cone.
  Vector2? _lockShotDirection(Vector2 origin, Vector2 worldAim) {
    var aim = worldAim - origin;
    if (aim.length < 1) {
      // Tap on Kaela: fire toward the nearest foe in range, else face forward.
      final nearest = _nearestHostile(origin, maxRange: 280);
      if (nearest != null) return (nearest - origin).normalized();
      return Vector2(1, 0);
    }
    final aimDir = aim.normalized();

    Vector2? best;
    var bestScore = double.infinity;
    const lockAimRadius = 88.0;
    const lockRange = 460.0;
    const coneDot = 0.72; // ~44° either side of the aim line

    void consider(Vector2 center) {
      final to = center - origin;
      final dist = to.length;
      if (dist < 10 || dist > lockRange) return;
      final aimDist = center.distanceTo(worldAim);
      final aligned = aimDir.dot(to.normalized()) >= coneDot;
      if (aimDist > lockAimRadius && !aligned) return;
      // Prefer the foe under the finger; break ties by distance.
      final score = aimDist * 1.6 + dist * 0.25;
      if (score < bestScore) {
        bestScore = score;
        best = center;
      }
    }

    for (final d in UECDrone.active) {
      if (!d.isMounted || d.isDead) continue;
      consider(d.position + d.size / 2);
    }
    final s = SentinelDrone.instance;
    if (s != null && s.isMounted && !s.isDead) {
      consider(s.position + s.size / 2);
    }

    if (best != null) return (best! - origin).normalized();
    return aimDir;
  }

  Vector2? _nearestHostile(Vector2 origin, {required double maxRange}) {
    Vector2? best;
    var bestD = maxRange;
    for (final d in UECDrone.active) {
      if (!d.isMounted || d.isDead) continue;
      final c = d.position + d.size / 2;
      final dist = c.distanceTo(origin);
      if (dist < bestD) {
        bestD = dist;
        best = c;
      }
    }
    final s = SentinelDrone.instance;
    if (s != null && s.isMounted && !s.isDead) {
      final c = s.position + s.size / 2;
      final dist = c.distanceTo(origin);
      if (dist < bestD) best = c;
    }
    return best;
  }

  // Joystick and keyboard (Bonfire's Keyboard controller) both arrive here.
  // super (MovementByJoystick) turns the event into a velocity that Bonfire
  // applies with the real dt each frame, so speed no longer depends on how
  // often the joystick fires.
  @override
  void onJoystickChangeDirectional(JoystickDirectionalEvent event) {
    _joystickMoving = event.directional != JoystickMoveDirectional.IDLE;
    super.onJoystickChangeDirectional(event);
  }
}
