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
import '../creatures/interaction.dart';
import '../game/progression.dart';
import '../game/well_rested.dart';
import '../interiors/room_services.dart';
import 'damage_number.dart';

class CustomPlayer extends SimplePlayer with BlockMovementCollision, InstantFacing {
  static const double sizePlayer = 32;
  /// Width of the feet hitbox that collides with the world.
  /// Kept a bit narrower/shorter than half the sprite so Kaela can stand
  /// closer to walls (full-tile wall boxes are a tileset/designer concern).
  static const double feetWidth = sizePlayer * 0.38;
  static const int baseMaxHealth = 100;
  /// Base HP plus level/gear bonuses (Runescape-lite progression).
  static int get maxHealth => baseMaxHealth + Progression.bonusHealth;
  static final ValueNotifier<Vector2> positionNotifier = ValueNotifier(Vector2.zero());
  static final ValueNotifier<int> healthNotifier = ValueNotifier(baseMaxHealth);
  static final ValueNotifier<bool> damageFlash = ValueNotifier(false);
  /// Screen-space click/tap (League-style: ground = move, foe = attack).
  static final ValueNotifier<Vector2?> pendingClick = ValueNotifier(null);

  /// Legacy alias — some call sites still clear this on pause/cutscene.
  static ValueNotifier<Vector2?> get pendingShot => pendingClick;

  /// Shots fired so far and where the last one left from: creatures listen
  /// for noise (quiet approach).
  static int shotCount = 0;
  static Vector2? lastShotFrom;

  /// Auto-attack range (world px) — close mid-range like a LoL marksman.
  static const double attackRange = 170;
  static const double clickArrive = 10;
  static const double clickEnemyRadius = 36;

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
    // Dao's ember broth (#31): faster, and no wait after a hit.
    final delay = Meals.skipRegenDelay ? 0.0 : regenDelay;
    final rate = (_sinceDamage >= delay ? regenPerSecond * Meals.regenMultiplier : 0.0) +
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

  JogSheet? _jog;
  bool isBlocked = false;
  double _blockedTimer = 0;
  bool _eWasPressed = false;
  double _footstepTimer = 0;
  bool _joystickMoving = false;
  /// On-screen stick (not WASD). While true we leave Bonfire's direction alone.
  bool _touchStick = false;
  /// Last keyboard directional was non-IDLE (may desync if a KeyUp is lost).
  bool _keyboardStick = false;
  double _shootCooldown = 0;
  Map<Direction, SpriteAnimation>? _shootAnims;
  /// Visual-only knockback after a shot (does not move the hitbox).
  double _shootKickT = 0;
  Vector2 _shootKick = Vector2.zero();

  /// Click-to-move destination (world). Cleared on arrive / WASD / new order.
  Vector2? _moveGoal;
  /// Locked auto-attack target (drone / Sentinel). Chase then AA in range.
  GameComponent? _attackTarget;
  /// Clicked talk/examine/use target — walk into range, then interact once.
  _ClickUse? _useTarget;

  CustomPlayer(Vector2 position) : super(
    position: position,
    size: Vector2.all(sizePlayer),
    speed: sizePlayer * 2.5,
    life: 100,
    initDirection: Direction.down,
  );

  double _lastSortY = -1e9;

  /// Depth sort by feet (not a fixed priority). Fixed `priority = 1000` made
  /// Kaela draw under southern props once she walked past that Y band.
  @override
  int get priority {
    if (renderAboveComponents && hasGameRef) {
      return LayerPriority.getAbovePriority(gameRef.highestPriority);
    }
    return LayerPriority.getComponentPriority(
      (position.y + size.y * 0.94).floor(),
    );
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
    _jog = await JogSheet.load();
    animation = _jog!.animation;
    _shootAnims = await ShootSheet.load('sprites/kaela_shoot.png');
    add(RectangleHitbox(
      size: Vector2(feetWidth, sizePlayer * 0.22),
      position: Vector2((sizePlayer - feetWidth) / 2, sizePlayer * 0.72),
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
    speed = sizePlayer * 2.5 * Meals.speedMultiplier; // moss noodles (#31)
    Meals.tick(dt);
    // Before Bonfire applies velocity: clear stale WASD if Flutter lost a KeyUp
    // (focus steal / Esc / cutscene), or re-arm keys after a new map Keyboard.
    if (!isRespawning) _reconcileKeyboardMovement();
    super.update(dt);
    _jog?.setSpeed(velocity.length);
    positionNotifier.value = position.clone();
    // Bonfire only rebalances depth on vertical move; also refresh after
    // teleports / pure horizontal walks past tall props.
    final sortY = position.y + size.y * 0.94;
    if ((sortY - _lastSortY).abs() >= 1 && hasGameRef) {
      _lastSortY = sortY;
      final g = gameRef;
      if (g is BonfireGame) g.requestUpdatePriority();
    }
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
    _tickLeagueCombat(dt);
    if (_shootKickT > 0) _shootKickT = max(0, _shootKickT - dt);
  }

  void _updateFootsteps(double dt) {
    final moving = _moveKeysHeld || _touchStick || _joystickMoving;
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

  /// Keep Bonfire's keyboard direction in lockstep with Flutter's pressed set.
  /// Lost KeyUps used to leave Kaela sliding forever in one direction.
  void _reconcileKeyboardMovement() {
    if (_touchStick) return;
    if (_moveKeysHeld) {
      // WASD overrides League click-orders (like canceling a move command).
      _clearClickOrders(keepAttack: false);
      syncMovementFromKeyboard();
      return;
    }
    // Click-move / chase owns the stick while active.
    if (_moveGoal != null || _attackTarget != null) return;
    if (_keyboardStick || _joystickMoving) {
      haltMovement();
    }
  }

  void _clearClickOrders({bool keepAttack = false}) {
    _moveGoal = null;
    _useTarget = null;
    if (!keepAttack) _attackTarget = null;
  }

  /// Hard stop — clears stick flags and Bonfire velocity (menus / lost keys).
  void haltMovement() {
    _clearClickOrders(keepAttack: false);
    _touchStick = false;
    _keyboardStick = false;
    _joystickMoving = false;
    onJoystickChangeDirectional(JoystickDirectionalEvent(
      directional: JoystickMoveDirectional.IDLE,
      intensity: 0,
      isKeyboard: true,
    ));
    stopMove(forceIdle: true);
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

  /// League-lite: click ground to move, foe to attack, person/object to use.
  /// WASD / virtual stick still work and cancel click-move.
  void _tickLeagueCombat(double dt) {
    _shootCooldown = max(0, _shootCooldown - dt);
    final tap = pendingClick.value;
    if (tap != null) {
      pendingClick.value = null;
      _issueClick(tap);
    }

    if (_attackTarget != null && !_targetAlive(_attackTarget!)) {
      _attackTarget = null;
    }
    if (_useTarget != null && !_useTarget!.alive()) {
      _useTarget = null;
    }

    // Manual move wins over click orders.
    if (_moveKeysHeld || _touchStick) return;

    final origin = position + size / 2;

    if (_attackTarget != null) {
      final tc = _targetCenter(_attackTarget!);
      final dist = origin.distanceTo(tc);
      if (dist > attackRange) {
        _moveGoal = tc;
        _steerToward(tc);
      } else {
        _moveGoal = null;
        _steerToward(null); // stop for AA
        _tryAutoAttack(origin, tc);
      }
      return;
    }

    final use = _useTarget;
    if (use != null) {
      final dest = use.point();
      final dist = origin.distanceTo(dest);
      if (dist > use.radius) {
        _moveGoal = dest;
        _steerToward(dest);
      } else {
        _moveGoal = null;
        _steerToward(null);
        _useTarget = null;
        use.run();
      }
      return;
    }

    final goal = _moveGoal;
    if (goal == null) return;
    final to = goal - origin;
    if (to.length <= clickArrive) {
      _moveGoal = null;
      _steerToward(null);
    } else {
      _steerToward(goal);
    }
  }

  void _issueClick(Vector2 screenPos) {
    if (!hasGameRef) return;
    final world = _screenToWorld(screenPos);
    final foe = _hostileNear(world, clickEnemyRadius);
    if (foe != null) {
      _useTarget = null;
      _attackTarget = foe;
      _moveGoal = _targetCenter(foe);
      return;
    }
    final use = _useNear(world);
    if (use != null) {
      _attackTarget = null;
      _useTarget = use;
      _moveGoal = use.point();
      return;
    }
    // Ground click: move, cancel attack/use.
    _attackTarget = null;
    _useTarget = null;
    _moveGoal = world;
  }

  _ClickUse? _useNear(Vector2 world) {
    if (!hasGameRef) return null;

    // Interactables (examine, doors, gates, creatures, glyphs…).
    final flame = findGame();
    if (flame == null) return null;
    final hit = Interaction.atWorld(world, game: flame, clickRadius: 42);
    if (hit != null) {
      final p = hit.prompt;
      if (!p.enabled) {
        // Still walk over so the note/prompt can show.
        return _ClickUse(
          point: () => hit.interactPoint,
          radius: hit.interactRadius * 0.85,
          alive: () => hit.isMounted,
          run: () {},
        );
      }
      return _ClickUse(
        point: () => hit.interactPoint,
        radius: hit.interactRadius * 0.85,
        alive: () => hit.isMounted,
        run: hit.interact,
      );
    }

    // NPCs / AI fragments use their own nearby system (not Interactable).
    NpcCharacter? bestNpc;
    var bestD = 42.0;
    for (final n in gameRef.query<NpcCharacter>()) {
      if (!n.isMounted) continue;
      final d = (n.position + n.size / 2).distanceTo(world);
      if (d < bestD) {
        bestD = d;
        bestNpc = n;
      }
    }
    if (bestNpc != null) {
      final npc = bestNpc;
      return _ClickUse(
        point: () => npc.position + npc.size / 2,
        radius: 56,
        alive: () => npc.isMounted,
        run: npc.interact,
      );
    }

    AIFragment? bestFrag;
    bestD = 42;
    for (final f in gameRef.query<AIFragment>()) {
      if (!f.isMounted) continue;
      final d = (f.position + f.size / 2).distanceTo(world);
      if (d < bestD) {
        bestD = d;
        bestFrag = f;
      }
    }
    if (bestFrag != null) {
      final frag = bestFrag;
      return _ClickUse(
        point: () => frag.position + frag.size / 2,
        radius: 40,
        alive: () => frag.isMounted,
        run: frag.interact,
      );
    }
    return null;
  }

  Vector2 _screenToWorld(Vector2 screen) {
    final camCenter = gameRef.camera.viewfinder.position;
    final screenCenter = gameRef.size / 2;
    final zoom = gameRef.camera.viewfinder.zoom;
    return camCenter + (screen - screenCenter) / zoom;
  }

  void _steerToward(Vector2? worldTarget) {
    if (worldTarget == null) {
      onJoystickChangeDirectional(JoystickDirectionalEvent(
        directional: JoystickMoveDirectional.IDLE,
        intensity: 0,
        isKeyboard: true,
      ));
      return;
    }
    final origin = position + size / 2;
    final d = worldTarget - origin;
    if (d.length < 1) {
      _steerToward(null);
      return;
    }
    // 8-way stick so Bonfire's MovementByJoystick stays happy.
    final n = d.normalized();
    final JoystickMoveDirectional dir;
    if (n.y < -0.4 && n.x < -0.4) {
      dir = JoystickMoveDirectional.MOVE_UP_LEFT;
    } else if (n.y < -0.4 && n.x > 0.4) {
      dir = JoystickMoveDirectional.MOVE_UP_RIGHT;
    } else if (n.y > 0.4 && n.x < -0.4) {
      dir = JoystickMoveDirectional.MOVE_DOWN_LEFT;
    } else if (n.y > 0.4 && n.x > 0.4) {
      dir = JoystickMoveDirectional.MOVE_DOWN_RIGHT;
    } else if (n.y < -0.4) {
      dir = JoystickMoveDirectional.MOVE_UP;
    } else if (n.y > 0.4) {
      dir = JoystickMoveDirectional.MOVE_DOWN;
    } else if (n.x < -0.4) {
      dir = JoystickMoveDirectional.MOVE_LEFT;
    } else if (n.x > 0.4) {
      dir = JoystickMoveDirectional.MOVE_RIGHT;
    } else if (n.y.abs() >= n.x.abs()) {
      dir = n.y < 0 ? JoystickMoveDirectional.MOVE_UP : JoystickMoveDirectional.MOVE_DOWN;
    } else {
      dir = n.x < 0 ? JoystickMoveDirectional.MOVE_LEFT : JoystickMoveDirectional.MOVE_RIGHT;
    }
    onJoystickChangeDirectional(JoystickDirectionalEvent(
      directional: dir,
      intensity: 1,
      isKeyboard: true,
    ));
  }

  void _tryAutoAttack(Vector2 origin, Vector2 target) {
    if (_shootCooldown > 0) return;
    final dir = (target - origin);
    if (dir.length < 1) return;
    final n = dir.normalized();
    gameRef.add(PlayerBullet(
      origin - PlayerBullet.spriteSize / 2,
      n,
    ));
    gameRef.add(MuzzleFlash(origin + n * 12, n));
    SfxManager().playShoot();
    shotCount++;
    lastShotFrom = origin;
    _shootCooldown = 0.32 * Progression.fireCooldownMult;
    lastDirection = WalkSheet.facingVector(n);
    _shootKick = -n * 1.5;
    _shootKickT = 0.08;
    _playShootAnim(n);
  }

  void _playShootAnim(Vector2 dir) {
    final face = WalkSheet.facingVector(dir);
    final anim = _shootAnims?[face];
    if (anim == null || animation == null) return;
    lastDirection = face;
    animation!.playOnce(anim.clone(), runToTheEnd: true);
  }

  bool _targetAlive(GameComponent t) {
    if (!t.isMounted) return false;
    if (t is UECDrone) return !t.isDead;
    if (t is SentinelDrone) return !t.isDead;
    return false;
  }

  Vector2 _targetCenter(GameComponent t) => t.position + t.size / 2;

  GameComponent? _hostileNear(Vector2 world, double radius) {
    GameComponent? best;
    var bestD = radius;
    for (final d in UECDrone.active) {
      if (!d.isMounted || d.isDead) continue;
      final dist = (d.position + d.size / 2).distanceTo(world);
      if (dist < bestD) {
        bestD = dist;
        best = d;
      }
    }
    final s = SentinelDrone.instance;
    if (s != null && s.isMounted && !s.isDead) {
      final dist = (s.position + s.size / 2).distanceTo(world);
      if (dist < bestD) best = s;
    }
    return best;
  }

  // Joystick and keyboard (Bonfire's Keyboard controller) both arrive here.
  // super (MovementByJoystick) turns the event into a velocity that Bonfire
  // applies with the real dt each frame, so speed no longer depends on how
  // often the joystick fires.
  @override
  void onJoystickChangeDirectional(JoystickDirectionalEvent event) {
    final moving = event.directional != JoystickMoveDirectional.IDLE;
    if (event.isKeyboard) {
      _keyboardStick = moving;
      if (moving) _touchStick = false;
    } else {
      // On-screen stick: cancel League click-move like WASD.
      if (moving) {
        _clearClickOrders(keepAttack: false);
        _keyboardStick = false;
      }
      _touchStick = moving;
    }
    _joystickMoving = moving;
    super.onJoystickChangeDirectional(event);
  }

  static bool get _moveKeysHeld {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.keyW) ||
        keys.contains(LogicalKeyboardKey.keyS) ||
        keys.contains(LogicalKeyboardKey.keyA) ||
        keys.contains(LogicalKeyboardKey.keyD) ||
        keys.contains(LogicalKeyboardKey.arrowUp) ||
        keys.contains(LogicalKeyboardKey.arrowDown) ||
        keys.contains(LogicalKeyboardKey.arrowLeft) ||
        keys.contains(LogicalKeyboardKey.arrowRight);
  }

  /// Re-apply Bonfire velocity from keys still held (new map / focus return).
  void syncMovementFromKeyboard() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final up = keys.contains(LogicalKeyboardKey.keyW) ||
        keys.contains(LogicalKeyboardKey.arrowUp);
    final down = keys.contains(LogicalKeyboardKey.keyS) ||
        keys.contains(LogicalKeyboardKey.arrowDown);
    final left = keys.contains(LogicalKeyboardKey.keyA) ||
        keys.contains(LogicalKeyboardKey.arrowLeft);
    final right = keys.contains(LogicalKeyboardKey.keyD) ||
        keys.contains(LogicalKeyboardKey.arrowRight);

    final JoystickMoveDirectional dir;
    if (up && left) {
      dir = JoystickMoveDirectional.MOVE_UP_LEFT;
    } else if (up && right) {
      dir = JoystickMoveDirectional.MOVE_UP_RIGHT;
    } else if (down && left) {
      dir = JoystickMoveDirectional.MOVE_DOWN_LEFT;
    } else if (down && right) {
      dir = JoystickMoveDirectional.MOVE_DOWN_RIGHT;
    } else if (up) {
      dir = JoystickMoveDirectional.MOVE_UP;
    } else if (down) {
      dir = JoystickMoveDirectional.MOVE_DOWN;
    } else if (left) {
      dir = JoystickMoveDirectional.MOVE_LEFT;
    } else if (right) {
      dir = JoystickMoveDirectional.MOVE_RIGHT;
    } else {
      dir = JoystickMoveDirectional.IDLE;
    }

    onJoystickChangeDirectional(JoystickDirectionalEvent(
      directional: dir,
      intensity: dir == JoystickMoveDirectional.IDLE ? 0.0 : 1.0,
      isKeyboard: true,
    ));
  }
}

/// Pending click-to-talk / examine / use order.
class _ClickUse {
  _ClickUse({
    required this.point,
    required this.radius,
    required this.alive,
    required this.run,
  });

  final Vector2 Function() point;
  final double radius;
  final bool Function() alive;
  final void Function() run;
}
