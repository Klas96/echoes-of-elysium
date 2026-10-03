import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bonfire/util/collision_game_component.dart';
import 'dart:math';
import 'ai_fragment.dart';
import 'npc_character.dart';
import 'player_bullet.dart';
import 'walk_sheet.dart';
import 'building.dart';
import '../audio/music_manager.dart';
import '../game/settings.dart';

class CustomPlayer extends SimplePlayer with BlockMovementCollision {
  static const double sizePlayer = 32;
  static const int maxHealth = 100;
  static final ValueNotifier<Vector2> positionNotifier = ValueNotifier(Vector2.zero());
  static final ValueNotifier<int> healthNotifier = ValueNotifier(maxHealth);
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

  /// All enemy damage goes through here. Story Mode, the respawn fade and
  /// the short grace period after it ignore damage. At 0 HP Kaela is pulled
  /// back to the last checkpoint instead of a game over.
  static void applyDamage(int amount) {
    if (GameSettings.storyMode.value) return;
    final p = current;
    if (p != null && p.isInvulnerable) return;
    final hp = (healthNotifier.value - amount).clamp(0, maxHealth);
    healthNotifier.value = hp;
    damageFlash.value = true;
    SfxManager().playDamage();
    if (p == null) return;
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
    final hp = healthNotifier.value;
    if (hp <= 0 || hp >= maxHealth || _sinceDamage < regenDelay) {
      _regenAcc = 0;
      return;
    }
    _regenAcc += regenPerSecond * dt;
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

    // Kaela walk/idle animation (DirectionAnimation, driven by movement)
    super.render(canvas);
  }

  @override
  Future<void> onLoad() async {
    current = this;
    respawnFade.value = false;
    SfxManager().init();
    paint.filterQuality = FilterQuality.none;
    animation = await WalkSheet.load('sprites/kaela_walk.png');
    add(RectangleHitbox(
      size: Vector2(sizePlayer * 0.5, sizePlayer / 3),
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

    final dir = worldPos - (position + size / 2);
    if (dir.length < 1) return;

    gameRef.add(PlayerBullet(
      position + size / 2 - Vector2.all(PlayerBullet.bulletSize / 2),
      dir.normalized(),
    ));
    SfxManager().playShoot();
    shotCount++;
    lastShotFrom = position + size / 2;
    _shootCooldown = 0.22;
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
