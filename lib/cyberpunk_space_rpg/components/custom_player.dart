import 'package:bonfire/bonfire.dart';
import 'package:bonfire/util/collision_game_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'ai_fragment.dart';
import 'npc_character.dart';
import 'drone_spawn.dart';
import 'player_bullet.dart';
import 'sentinel_drone.dart';
import 'uec_drone.dart';
import 'walk_sheet.dart';
import 'building.dart';
import 'muzzle_flash.dart';
import '../audio/music_manager.dart';
import '../audio/sfx_manager.dart';
import '../creatures/interaction.dart';
import '../game/click_pathfinder.dart';
import '../game/debug_path_line.dart';
import '../game/game_debug.dart';
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
  /// Local Y of the feet hitbox top (must match [onLoad] RectangleHitbox).
  static const double feetTop = sizePlayer * 0.72;
  static const double feetHeight = sizePlayer * 0.22;
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
  /// Pulse shot (Q / on-screen button): cone burst cooldown.
  static const double pulseCooldown = 7.0;
  /// Phase Step (Space / on-screen button): dash distance & cooldown.
  static const double phaseCooldown = 8.5;
  static const double phaseDistance = 100;
  /// Ward (F): personal shield duration & cooldown.
  static const double wardCooldown = 10.0;
  static const double wardDuration = 3.2;
  /// Anchor (R): radial slow + knockback.
  static const double anchorCooldown = 12.0;
  static const double anchorRadius = 140;
  static const double anchorSlowSeconds = 3.5;
  static const double anchorSlowFactor = 0.22;
  static const double anchorKnockScale = 2.4;
  static const int anchorDamage = 8;
  /// Combat unlocks.
  static int get phaseUnlockLevel => Progression.phaseUnlockLevel;
  static int get pulseUnlockLevel => Progression.pulseUnlockLevel;
  static int get wardUnlockLevel => Progression.wardUnlockLevel;
  static int get anchorUnlockLevel => Progression.anchorUnlockLevel;
  /// Seconds left on ability cooldowns (HUD). 0 = ready.
  static final ValueNotifier<double> phaseCdLeft = ValueNotifier(0);
  static final ValueNotifier<double> pulseCdLeft = ValueNotifier(0);
  static final ValueNotifier<double> wardCdLeft = ValueNotifier(0);
  static final ValueNotifier<double> anchorCdLeft = ValueNotifier(0);
  static bool get phaseUnlocked =>
      Progression.level >= Progression.phaseUnlockLevel;
  static bool get pulseUnlocked =>
      Progression.level >= Progression.pulseUnlockLevel;
  static bool get wardUnlocked =>
      Progression.level >= Progression.wardUnlockLevel;
  static bool get anchorUnlocked =>
      Progression.level >= Progression.anchorUnlockLevel;
  /// Final click arrive (feet → exact click). Keep tight so Kaela walks
  /// all the way to where you clicked.
  static const double clickArrive = 3.5;
  /// Intermediate A* waypoint arrive — a bit looser so lane slides don't jam.
  static const double waypointArrive = 9;
  /// World-space fallback when screen pick misses (LoL-style click-to-attack).
  static const double clickEnemyRadius = 72;
  /// Screen-space foe pick radius (viewport px) — preferred on web/HiDPI.
  static const double clickEnemyScreenRadius = 52;

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
  bool get isInvulnerable =>
      isRespawning || _grace > 0 || _phaseIframes > 0 || _wardLeft > 0;

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
  double _pulseCd = 0;
  double _phaseCd = 0;
  double _phaseIframes = 0;
  double _wardCd = 0;
  double _wardLeft = 0;
  double _anchorCd = 0;
  bool _qWasPressed = false;
  bool _spaceWasPressed = false;
  bool _fWasPressed = false;
  bool _rWasPressed = false;
  bool _tWasPressed = false;
  Map<Direction, SpriteAnimation>? _shootAnims;
  /// Visual-only knockback after a shot (does not move the hitbox).
  double _shootKickT = 0;
  Vector2 _shootKick = Vector2.zero();
  /// Brief Phase Step afterimages (world top-left, age 0..1).
  final List<(Vector2, double)> _phaseGhosts = [];

  /// Click-to-move destination (world). Cleared on arrive / WASD / new order.
  Vector2? _moveGoal;
  /// Locked auto-attack target (drone / Sentinel). Chase then AA in range.
  GameComponent? _attackTarget;
  /// Clicked talk/examine/use target — walk into range, then interact once.
  _ClickUse? _useTarget;
  /// Repath timer while chasing a moving foe / use target (seconds).
  double _pathRepathT = 0;
  /// True when click-move fell back to straight steer (no A* path).
  bool _steerFallback = false;
  /// A* waypoints (tile centers). We walk these ourselves — Bonfire's
  /// [PathFinding] mixin often fails to stop (stopMove no-ops when idle).
  final List<Vector2> _waypoints = [];
  int _wpIndex = 0;
  DebugPathLine? _pathLine;
  bool get _isPathing => _waypoints.isNotEmpty;
  /// Progress watchdog: distance to current waypoint last frame / time stuck.
  double _wpLastDist = double.infinity;
  double _wpStuckT = 0;

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

    // Phase afterimages (drawn in local space relative to current position).
    for (final g in _phaseGhosts) {
      final age = g.$2.clamp(0.0, 1.0);
      final local = g.$1 - position;
      canvas.save();
      canvas.translate(local.x, local.y);
      canvas.drawCircle(
        Offset(cx, cy),
        r * 0.85,
        Paint()
          ..color = Color.fromRGBO(100, 255, 255, 0.28 * (1 - age))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy), width: size.x * 0.55, height: size.y * 0.7),
          const Radius.circular(4),
        ),
        Paint()..color = Color.fromRGBO(180, 255, 255, 0.22 * (1 - age)),
      );
      canvas.restore();
    }

    // Ward shield ring while active — bright so it's obvious in combat.
    if (_wardLeft > 0) {
      final pulse = 0.65 + 0.35 * sin(_wardLeft * 10).abs();
      canvas.drawCircle(
        Offset(cx, cy),
        r + 14,
        Paint()
          ..color = const Color(0xFFE8D0FF).withValues(alpha: 0.32 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        r + 11,
        Paint()
          ..color = const Color(0xFFAAFFEE).withValues(alpha: 0.85 * pulse)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4,
      );
      canvas.drawCircle(
        Offset(cx, cy),
        r + 7,
        Paint()
          ..color = const Color(0xFFE8D0FF).withValues(alpha: 0.45 * pulse)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }

    // Glow aura (state indicator kept on top of sprite)
    canvas.drawCircle(
      Offset(cx, cy),
      r + 3,
      Paint()
        ..color = glowColor.withValues(alpha: 0.22)
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
    _pulseCd = 0;
    _phaseCd = 0;
    _wardCd = 0;
    _wardLeft = 0;
    _anchorCd = 0;
    pulseCdLeft.value = 0;
    phaseCdLeft.value = 0;
    wardCdLeft.value = 0;
    anchorCdLeft.value = 0;
    _phaseGhosts.clear();
    SfxManager().init();
    paint.filterQuality = FilterQuality.none;
    _jog = await JogSheet.load();
    animation = _jog!.animation;
    _shootAnims = await ShootSheet.load('sprites/kaela_shoot.png');
    add(RectangleHitbox(
      size: Vector2(feetWidth, feetHeight),
      position: Vector2((sizePlayer - feetWidth) / 2, feetTop),
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
    final jammed = velocity.length < speed * 0.2;
    if ((other is TileWithCollision || other is CollisionMapComponent || other is Building) &&
        jammed) {
      _blockedTimer = 0.1;
    }
    // Do NOT skip waypoints here. Narrow lanes scrape walls every frame;
    // advancing on jam aborted the whole A* path while WASD still slid
    // through. The follow watchdog + repath handle true dead-ends.
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
    // Throttle HUD notifier — cloning every frame rebuilt Flutter debug text.
    final prev = positionNotifier.value;
    if ((position.x - prev.x).abs() >= 1 || (position.y - prev.y).abs() >= 1) {
      positionNotifier.value = position.clone();
    }
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
    _tickAbilityCds(dt);
    _pollAbilityKeys();
    _tickPhaseGhosts(dt);
    if (_shootKickT > 0) _shootKickT = max(0, _shootKickT - dt);
  }

  void _tickAbilityCds(double dt) {
    _phaseIframes = max(0, _phaseIframes - dt);
    _wardLeft = max(0, _wardLeft - dt);
    if (_pulseCd > 0) {
      _pulseCd = max(0, _pulseCd - dt);
      pulseCdLeft.value = _pulseCd;
    } else if (pulseCdLeft.value != 0) {
      pulseCdLeft.value = 0;
    }
    if (_phaseCd > 0) {
      _phaseCd = max(0, _phaseCd - dt);
      phaseCdLeft.value = _phaseCd;
    } else if (phaseCdLeft.value != 0) {
      phaseCdLeft.value = 0;
    }
    if (_wardCd > 0) {
      _wardCd = max(0, _wardCd - dt);
      wardCdLeft.value = _wardCd;
    } else if (wardCdLeft.value != 0) {
      wardCdLeft.value = 0;
    }
    if (_anchorCd > 0) {
      _anchorCd = max(0, _anchorCd - dt);
      anchorCdLeft.value = _anchorCd;
    } else if (anchorCdLeft.value != 0) {
      anchorCdLeft.value = 0;
    }
  }

  void _tickPhaseGhosts(double dt) {
    if (_phaseGhosts.isEmpty) return;
    for (var i = _phaseGhosts.length - 1; i >= 0; i--) {
      final age = _phaseGhosts[i].$2 + dt / 0.22;
      if (age >= 1) {
        _phaseGhosts.removeAt(i);
      } else {
        _phaseGhosts[i] = (_phaseGhosts[i].$1, age);
      }
    }
  }

  void _pollAbilityKeys() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final q = keys.contains(LogicalKeyboardKey.keyQ);
    if (q && !_qWasPressed) tryPulseShot();
    _qWasPressed = q;
    final space = keys.contains(LogicalKeyboardKey.space);
    if (space && !_spaceWasPressed) tryPhaseStep();
    _spaceWasPressed = space;
    final f = keys.contains(LogicalKeyboardKey.keyF);
    if (f && !_fWasPressed) tryWard();
    _fWasPressed = f;
    final r = keys.contains(LogicalKeyboardKey.keyR);
    if (r && !_rWasPressed) tryAnchor();
    _rWasPressed = r;
    // T = target nearest (keyboard stand-in for click-to-attack).
    final t = keys.contains(LogicalKeyboardKey.keyT);
    if (t && !_tWasPressed) tryAcquireNearest();
    _tWasPressed = t;
  }

  /// Lock the nearest hostile for auto-attack. With WASD held, only locks
  /// (kite + shoot in range); idle starts a chase path like a click.
  bool tryAcquireNearest() {
    if (isRespawning) return false;
    if (NpcCharacter.activeDialogue.value != null ||
        AIFragment.activeDialogue.value != null) {
      return false;
    }
    if (!hasGameRef) return false;
    final foe = _hostilePreferFacing(_feetCenter, attackRange * 2.8);
    if (foe == null) return false;
    _useTarget = null;
    _steerFallback = false;
    _attackTarget = foe;
    if (_moveKeysHeld || _touchStick) {
      _clearPath(stop: false);
      _moveGoal = null;
      return true;
    }
    _moveGoal = _targetCenter(foe);
    _pathRepathT = 0;
    _pathTo(_moveGoal!);
    return true;
  }

  /// Short dash — Space / HUD. Works while running (WASD, stick, or click-path).
  bool tryPhaseStep() {
    if (!phaseUnlocked || _phaseCd > 0 || isRespawning) return false;
    if (NpcCharacter.activeDialogue.value != null ||
        AIFragment.activeDialogue.value != null) {
      return false;
    }
    if (!hasGameRef) return false;
    final dir = _phaseDir();
    if (dir.length2 < 1e-6) return false;

    // Snapshot locomotion so we can keep running after the dash.
    final resumeGoal = _moveGoal?.clone();
    final resumeUse = _useTarget;
    final resumeAttack = _attackTarget;
    final resumeKeyboard = _moveKeysHeld;

    _clearClickOrders(keepAttack: true);
    // Zero velocity for the teleport steps without forcing idle — callers that
    // are still holding WASD / have a move goal resume immediately below.
    stopMove(forceIdle: false);

    const steps = 10;
    final step = dir * (phaseDistance / steps);
    var moved = 0.0;
    _phaseGhosts.add((position.clone(), 0));
    for (var i = 0; i < steps; i++) {
      final next = position + step;
      if (!_dashClear(next)) break;
      position = next;
      moved += step.length;
      if (i == 3 || i == 6) _phaseGhosts.add((position.clone(), 0));
    }
    if (moved < 10) {
      _phaseGhosts.clear();
      _resumeAfterPhase(
        keyboard: resumeKeyboard,
        goal: resumeGoal,
        attack: resumeAttack,
        use: resumeUse,
      );
      return false;
    }

    lastDirection = WalkSheet.facingVector(dir);
    _phaseCd = phaseCooldown;
    phaseCdLeft.value = _phaseCd;
    _phaseIframes = 0.16;
    _grace = max(_grace, 0.16);
    positionNotifier.value = position.clone();
    _resumeAfterPhase(
      keyboard: resumeKeyboard,
      goal: resumeGoal,
      attack: resumeAttack,
      use: resumeUse,
    );
    return true;
  }

  /// Continue WASD / click-move / chase after a Phase Step (or a failed dash).
  void _resumeAfterPhase({
    required bool keyboard,
    Vector2? goal,
    GameComponent? attack,
    _ClickUse? use,
  }) {
    if (keyboard && _moveKeysHeld) {
      syncMovementFromKeyboard();
      return;
    }
    if (attack != null && _targetAlive(attack)) {
      _attackTarget = attack;
      _useTarget = null;
      _moveGoal = _targetCenter(attack);
      _pathRepathT = 0;
      _pathTo(_moveGoal!);
      return;
    }
    if (use != null && use.alive()) {
      _attackTarget = null;
      _useTarget = use;
      _moveGoal = use.point();
      _pathRepathT = 0;
      _pathTo(_moveGoal!);
      return;
    }
    if (goal != null) {
      _attackTarget = null;
      _useTarget = null;
      _pathRepathT = 0;
      _pathTo(goal);
    }
  }

  Vector2 _phaseDir() {
    // Live run direction first — click-path / stick / WASD all share velocity.
    final minRun = speed * 0.2;
    if (velocity.length2 > minRun * minRun) {
      return velocity.normalized();
    }
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    var x = 0.0;
    var y = 0.0;
    if (keys.contains(LogicalKeyboardKey.keyW) ||
        keys.contains(LogicalKeyboardKey.arrowUp)) {
      y -= 1;
    }
    if (keys.contains(LogicalKeyboardKey.keyS) ||
        keys.contains(LogicalKeyboardKey.arrowDown)) {
      y += 1;
    }
    if (keys.contains(LogicalKeyboardKey.keyA) ||
        keys.contains(LogicalKeyboardKey.arrowLeft)) {
      x -= 1;
    }
    if (keys.contains(LogicalKeyboardKey.keyD) ||
        keys.contains(LogicalKeyboardKey.arrowRight)) {
      x += 1;
    }
    if (x != 0 || y != 0) return Vector2(x, y).normalized();
    return _aimDir();
  }

  /// Feet-center of [newTopLeft] lands on a walkable path cell.
  bool _dashClear(Vector2 newTopLeft) {
    final feet = newTopLeft +
        Vector2(
          (sizePlayer - feetWidth) / 2 + feetWidth / 2,
          feetTop + feetHeight / 2,
        );
    final barriers = ClickPathfinder.barriersFor(gameRef);
    return !barriers.contains(ClickPathfinder.cellOf(feet));
  }

  /// Cone burst — three piercing pulse bolts + slow. Button or Q.
  bool tryPulseShot() {
    if (!pulseUnlocked || _pulseCd > 0 || isRespawning) return false;
    if (NpcCharacter.activeDialogue.value != null ||
        AIFragment.activeDialogue.value != null) {
      return false;
    }
    final aim = _aimDir();
    if (aim.length2 < 1e-6) return false;
    final origin = _feetCenter;
    const spread = 0.32; // ~18°
    for (final a in [-spread, 0.0, spread]) {
      final c = cos(a);
      final s = sin(a);
      final dir = Vector2(aim.x * c - aim.y * s, aim.x * s + aim.y * c);
      final spawnSize = PlayerBullet.pulseSpriteSize;
      gameRef.add(PlayerBullet(
        origin - spawnSize / 2,
        dir,
        kind: BulletKind.pulse,
      ));
    }
    gameRef.add(MuzzleFlash(origin + aim * 14, aim));
    SfxManager().playShoot();
    shotCount++;
    lastShotFrom = origin;
    lastDirection = WalkSheet.facingVector(aim);
    _shootKick = -aim * 2.2;
    _shootKickT = 0.1;
    _playShootAnim(aim);
    _pulseCd = pulseCooldown;
    pulseCdLeft.value = _pulseCd;
    return true;
  }

  /// Personal shield — brief i-frames. Button or F.
  bool tryWard() {
    if (!wardUnlocked || _wardCd > 0 || isRespawning) return false;
    if (NpcCharacter.activeDialogue.value != null ||
        AIFragment.activeDialogue.value != null) {
      return false;
    }
    _wardLeft = wardDuration;
    _grace = max(_grace, wardDuration);
    _wardCd = wardCooldown;
    wardCdLeft.value = _wardCd;
    SfxManager().playChime();
    return true;
  }

  /// Radial slow + knockback around Kaela. Button or R.
  bool tryAnchor() {
    if (!anchorUnlocked || _anchorCd > 0 || isRespawning) return false;
    if (NpcCharacter.activeDialogue.value != null ||
        AIFragment.activeDialogue.value != null) {
      return false;
    }
    if (!hasGameRef) return false;
    final origin = _feetCenter;
    // Double ring so the blast reads clearly.
    gameRef.add(AbilityRing(
      origin,
      color: const Color(0xFFAA44FF),
      maxRadius: anchorRadius,
      life: 0.55,
      stroke: 5.5,
    ));
    gameRef.add(AbilityRing(
      origin,
      color: const Color(0xFFE8D0FF),
      maxRadius: anchorRadius * 0.72,
      life: 0.4,
      stroke: 3.5,
    ));
    var hits = 0;
    for (final d in UECDrone.active) {
      if (!d.isMounted || d.isDead) continue;
      final center = d.position + d.size / 2;
      final delta = center - origin;
      if (delta.length > anchorRadius) continue;
      final knock = delta.length2 < 1e-4
          ? _facingDir()
          : delta.normalized();
      d.applySlow(anchorSlowSeconds, factor: anchorSlowFactor);
      d.takeDamage(anchorDamage,
          knockbackDir: knock, knockbackScale: anchorKnockScale);
      hits++;
    }
    final s = SentinelDrone.instance;
    if (s != null && s.isMounted && !s.isDead) {
      final center = s.position + s.size / 2;
      final delta = center - origin;
      if (delta.length <= anchorRadius) {
        final knock = delta.length2 < 1e-4
            ? _facingDir()
            : delta.normalized();
        s.applySlow(anchorSlowSeconds, factor: anchorSlowFactor);
        s.takeDamage(anchorDamage,
            knockbackDir: knock, knockbackScale: anchorKnockScale);
        hits++;
      }
    }
    SfxManager().playShoot();
    if (hits > 0) SfxManager().playChime();
    _anchorCd = anchorCooldown;
    anchorCdLeft.value = _anchorCd;
    return true;
  }

  Vector2 _aimDir() {
    if (_attackTarget != null && _targetAlive(_attackTarget!)) {
      final d = _targetCenter(_attackTarget!) - _feetCenter;
      if (d.length2 > 1) return d.normalized();
    }
    final foe = _hostileNear(_feetCenter, attackRange * 1.35);
    if (foe != null) {
      final d = _targetCenter(foe) - _feetCenter;
      if (d.length2 > 1) return d.normalized();
    }
    return _facingDir();
  }

  Vector2 _facingDir() {
    switch (lastDirection) {
      case Direction.up:
      case Direction.upLeft:
      case Direction.upRight:
        return Vector2(0, -1);
      case Direction.down:
      case Direction.downLeft:
      case Direction.downRight:
        return Vector2(0, 1);
      case Direction.left:
        return Vector2(-1, 0);
      case Direction.right:
        return Vector2(1, 0);
    }
  }

  void _updateFootsteps(double dt) {
    final moving =
        _moveKeysHeld || _touchStick || _joystickMoving || _isPathing;
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
      // WASD cancels click-move / use, but keeps attack lock so you can kite
      // with keyboard after Tab/T or a click-target (LoL-style AA).
      _clearClickOrders(keepAttack: true);
      syncMovementFromKeyboard();
      return;
    }
    // Click-move / chase / A* path owns locomotion while active.
    if (_moveGoal != null ||
        _attackTarget != null ||
        _useTarget != null ||
        _isPathing) {
      return;
    }
    if (_keyboardStick || _joystickMoving) {
      haltMovement();
    }
  }

  void _clearClickOrders({bool keepAttack = false}) {
    _clearPath(stop: false);
    _moveGoal = null;
    _useTarget = null;
    _steerFallback = false;
    _pathRepathT = 0;
    if (!keepAttack) _attackTarget = null;
  }

  void _clearPath({bool stop = true}) {
    _waypoints.clear();
    _wpIndex = 0;
    _wpStuckT = 0;
    _wpLastDist = double.infinity;
    _removePathLine();
    if (stop) _steerToward(null);
  }

  void _removePathLine() {
    _pathLine?.removeFromParent();
    _pathLine = null;
  }

  /// Cyan route while [GameDebug] is on (includes steer-fallback straight line).
  void _showDebugPath(List<Vector2> points) {
    _removePathLine();
    if (!GameDebug.isOn || !hasGameRef) return;
    if (points.isEmpty) return;
    gameRef.add(
      _pathLine = DebugPathLine(
        points: List<Vector2>.from(points),
        origin: () => rectCollision.centerVector2,
      ),
    );
  }

  /// End click-move cleanly — zero velocity + idle anim (no leftover jog).
  void _finishClickMove() {
    _clearPath(stop: true);
    _moveGoal = null;
    _steerFallback = false;
    stopMove(forceIdle: true);
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

  /// League-lite: click/tap ground to move (A* around walls), foe to attack,
  /// person/object to use. WASD cancels click-move.
  void _tickLeagueCombat(double dt) {
    _shootCooldown = max(0, _shootCooldown - dt);
    _pathRepathT = max(0, _pathRepathT - dt);
    final tap = pendingClick.value;
    if (tap != null) {
      pendingClick.value = null;
      _issueClick(tap);
    }

    if (_attackTarget != null && !_targetAlive(_attackTarget!)) {
      _attackTarget = null;
      _clearPath();
    }
    if (_useTarget != null && !_useTarget!.alive()) {
      _useTarget = null;
      _clearPath();
    }

    // WASD / stick owns locomotion, but a locked target still auto-attacks
    // in range (keyboard kite without swapping to the mouse).
    if (_moveKeysHeld || _touchStick) {
      if (_attackTarget != null && _targetAlive(_attackTarget!)) {
        final origin = _feetCenter;
        final tc = _targetCenter(_attackTarget!);
        if (origin.distanceTo(tc) <= attackRange) {
          _tryAutoAttack(origin, tc);
        }
      }
      return;
    }

    // Path agent is the feet hitbox, not the sprite center — A* clearance
    // tests cell centers for feet, and the feet sit ~10px below mid-sprite.
    final origin = _feetCenter;

    if (_attackTarget != null) {
      final foe = _attackTarget!;
      final tc = _targetCenter(foe);
      final dist = origin.distanceTo(tc);
      if (dist > attackRange) {
        _moveGoal = tc;
        if (_steerFallback) {
          _steerToward(tc);
        } else if (!_isPathing ||
            _pathRepathT <= 0 ||
            (_moveGoal != null && _moveGoal!.distanceTo(tc) > 48)) {
          _pathRepathT = 0.7;
          _pathTo(tc);
        } else {
          _followWaypoints(origin, dt);
        }
      } else {
        _clearPath();
        _moveGoal = null;
        _steerFallback = false;
        _steerToward(null);
        stopMove(forceIdle: true);
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
        if (_steerFallback) {
          _steerToward(dest);
        } else if (!_isPathing || _pathRepathT <= 0) {
          _pathRepathT = 0.8;
          _pathTo(dest);
        } else {
          _followWaypoints(origin, dt);
        }
      } else {
        _clearPath();
        _moveGoal = null;
        _steerFallback = false;
        _steerToward(null);
        stopMove(forceIdle: true);
        _useTarget = null;
        use.run();
      }
      return;
    }

    final goal = _moveGoal;
    if (goal == null) return;
    final to = goal - origin;
    if (to.length <= clickArrive) {
      _finishClickMove();
    } else if (_steerFallback) {
      _steerToward(goal);
    } else if (_isPathing) {
      _followWaypoints(origin, dt);
    } else {
      // Path drained without arrive — hard stop so she doesn't jog forever.
      _finishClickMove();
    }
  }

  /// World-space center of the feet collision box (pathfinding agent).
  Vector2 get _feetCenter => rectCollision.centerVector2;

  void _issueClick(Vector2 screenPos) {
    if (!hasGameRef) return;
    final world = _screenToWorld(screenPos);
    // Prefer screen-space pick so sprite clicks work when camera zoom / web
    // viewport mapping would miss a tight world-radius test.
    final foe = _hostileNearScreen(screenPos, clickEnemyScreenRadius) ??
        _hostileNear(world, clickEnemyRadius);
    if (foe != null) {
      _clearPath(stop: false);
      _useTarget = null;
      _steerFallback = false;
      _attackTarget = foe;
      _moveGoal = _targetCenter(foe);
      _pathRepathT = 0;
      _pathTo(_moveGoal!);
      return;
    }
    final use = _useNear(world);
    if (use != null) {
      _clearPath(stop: false);
      _attackTarget = null;
      _steerFallback = false;
      _useTarget = use;
      _moveGoal = use.point();
      _pathRepathT = 0;
      _pathTo(_moveGoal!);
      return;
    }
    // Ground click: A* move, cancel attack/use.
    _attackTarget = null;
    _useTarget = null;
    _steerFallback = false;
    _moveGoal = world;
    _pathRepathT = 0;
    _pathTo(world);
  }

  /// A* around collisions (LoL): off-screen walls count. Unreachable /
  /// in-wall clicks walk to the closest reachable spot — never shove into
  /// the obstacle.
  void _pathTo(Vector2 world) {
    if (!hasGameRef) return;
    _clearPath(stop: false);
    _moveGoal = world;
    final origin = _feetCenter;
    final path = ClickPathfinder.find(gameRef, from: origin, to: world);
    if (path.isEmpty) {
      // Nowhere closer — stay put (LoL does not walk into the wall).
      _steerFallback = false;
      _moveGoal = null;
      stopMove(forceIdle: true);
      return;
    }
    _steerFallback = false;
    final pts = List<Vector2>.of(path);
    // A* ends on cell centres — if the click sits in that same free cell,
    // walk to the exact click so Kaela doesn't stop short.
    if (ClickPathfinder.cellOf(world) == ClickPathfinder.cellOf(pts.last)) {
      pts[pts.length - 1] = world.clone();
      _moveGoal = world;
    } else {
      // Click was redirected (wall / sealed) — stop at nearest walkable.
      _moveGoal = pts.last;
    }
    _waypoints
      ..clear()
      ..addAll(pts);
    _wpIndex = _firstForwardWaypoint(origin);
    // Remaining waypoints from current index (what she will actually walk).
    _showDebugPath(_waypoints.sublist(_wpIndex));
  }

  /// Skip waypoints already near Kaela or behind her travel direction so the
  /// first step faces the destination (not the start-tile center).
  int _firstForwardWaypoint(Vector2 origin) {
    if (_waypoints.isEmpty) return 0;
    final goal = _waypoints.last;
    final toGoal = goal - origin;
    var i = 0;
    while (i < _waypoints.length - 1) {
      final toWp = _waypoints[i] - origin;
      if (toWp.length <= waypointArrive * 2) {
        i++;
        continue;
      }
      if (toGoal.length > 1 && toWp.dot(toGoal) < 0) {
        i++;
        continue;
      }
      break;
    }
    return i;
  }

  double _arriveRadiusForWaypoint(int index) =>
      index >= _waypoints.length - 1 ? clickArrive : waypointArrive;

  /// Step along [_waypoints]; hard-stops when the list is done.
  void _followWaypoints(Vector2 origin, double dt) {
    while (_wpIndex < _waypoints.length &&
        origin.distanceTo(_waypoints[_wpIndex]) <=
            _arriveRadiusForWaypoint(_wpIndex)) {
      _wpIndex++;
      _wpStuckT = 0;
      _wpLastDist = double.infinity;
    }
    // Passed this waypoint along the path (common when sliding in a lane).
    if (_wpIndex < _waypoints.length - 1) {
      final toWp = _waypoints[_wpIndex] - origin;
      final toGoal = _waypoints.last - origin;
      if (toGoal.length > 1 &&
          toWp.length > waypointArrive &&
          toWp.dot(toGoal) < 0) {
        _wpIndex++;
        _wpStuckT = 0;
        _wpLastDist = double.infinity;
      }
    }
    if (_wpIndex >= _waypoints.length) {
      if (_attackTarget != null || _useTarget != null) {
        _clearPath();
        _steerToward(null);
        stopMove(forceIdle: true);
      } else {
        _finishClickMove();
      }
      return;
    }
    final dest = _waypoints[_wpIndex];
    final dist = origin.distanceTo(dest);
    // Still closing in, or sliding with leftover speed — keep patience.
    final closing = dist < _wpLastDist - 0.35;
    final sliding = velocity.length > speed * 0.15;
    if (!closing && !sliding) {
      _wpStuckT += dt;
    } else {
      _wpStuckT = 0;
    }
    _wpLastDist = dist;
    // True dead-end: repath from here (narrow scrapes used to skip every
    // waypoint and abort). Only give up after a failed repath.
    if (_wpStuckT > 0.7) {
      _wpStuckT = 0;
      _wpLastDist = double.infinity;
      final goal = _moveGoal ?? _waypoints.last;
      final path = ClickPathfinder.find(gameRef, from: origin, to: goal);
      if (path.isEmpty) {
        _finishClickMove();
        return;
      }
      final pts = List<Vector2>.of(path);
      if (_moveGoal != null &&
          ClickPathfinder.cellOf(_moveGoal!) ==
              ClickPathfinder.cellOf(pts.last)) {
        pts[pts.length - 1] = _moveGoal!.clone();
      } else {
        _moveGoal = pts.last;
      }
      _waypoints
        ..clear()
        ..addAll(pts);
      _wpIndex = _firstForwardWaypoint(origin);
      _showDebugPath(_waypoints.sublist(_wpIndex));
      if (_wpIndex >= _waypoints.length) {
        _finishClickMove();
        return;
      }
    }
    _steerToward(_waypoints[_wpIndex]);
    if (_pathLine != null) {
      if (!GameDebug.isOn) {
        _removePathLine();
      } else {
        _pathLine!.points = _waypoints.sublist(_wpIndex);
      }
    } else if (GameDebug.isOn && _isPathing) {
      _showDebugPath(_waypoints.sublist(_wpIndex));
    }
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

  /// [screen] is viewport-local (same space as the map pointer overlay).
  /// Use Bonfire's camera math — viewfinder-center math drifts when
  /// [CameraConfig.moveOnlyMapArea] clamps at map edges, so foe clicks miss.
  Vector2 _screenToWorld(Vector2 screen) {
    return gameRef.camera.screenToWorld(screen);
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
    // Steer by feet error so narrow-lane waypoints (feet-tested) are tracked
    // by the hitbox that actually collides — not the sprite mid-point.
    final origin = _feetCenter;
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
    if (t is DroneSpawnPoint) return !t.isDead;
    return false;
  }

  Vector2 _targetCenter(GameComponent t) {
    if (t is DroneSpawnPoint) return t.padCenter;
    return t.position + t.size / 2;
  }

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
    for (final pad in DroneSpawnPoint.active) {
      if (!pad.isMounted || pad.isDead) continue;
      final dist = pad.padCenter.distanceTo(world);
      if (dist < bestD) {
        bestD = dist;
        best = pad;
      }
    }
    final s = SentinelDrone.instance;
    if (s != null && s.isMounted && !s.isDead) {
      final dist = (s.position + s.size / 2).distanceTo(world);
      if (dist < bestD) {
        bestD = dist;
        best = s;
      }
    }
    return best;
  }

  /// Pick a foe by where its sprite sits on screen (viewport pixels).
  GameComponent? _hostileNearScreen(Vector2 screen, double radiusPx) {
    if (!hasGameRef) return null;
    final zoom = gameRef.camera.zoom;
    GameComponent? best;
    var bestD = radiusPx;
    void consider(GameComponent t, Vector2 center, Vector2 size) {
      final sp = gameRef.camera.worldToScreen(center);
      final dist = sp.distanceTo(screen);
      final pad = max(radiusPx, max(size.x, size.y) * 0.55 * zoom);
      if (dist < pad && dist < bestD) {
        bestD = dist;
        best = t;
      }
    }

    for (final d in UECDrone.active) {
      if (!d.isMounted || d.isDead) continue;
      consider(d, d.position + d.size / 2, d.size);
    }
    for (final pad in DroneSpawnPoint.active) {
      if (!pad.isMounted || pad.isDead) continue;
      consider(pad, pad.padCenter, pad.size);
    }
    final s = SentinelDrone.instance;
    if (s != null && s.isMounted && !s.isDead) {
      consider(s, s.position + s.size / 2, s.size);
    }
    return best;
  }

  /// Nearest hostile, preferring the facing cone (for keyboard target lock).
  GameComponent? _hostilePreferFacing(Vector2 world, double radius) {
    final face = _facingDir();
    GameComponent? best;
    var bestScore = double.infinity;
    void consider(GameComponent t, Vector2 center) {
      final delta = center - world;
      final dist = delta.length;
      if (dist > radius || dist < 1) return;
      final dir = delta / dist;
      // Facing targets score closer; behind you need to be much nearer.
      final align = face.dot(dir); // -1 .. 1
      final score = dist * (align >= 0.15 ? 0.55 : 1.35);
      if (score < bestScore) {
        bestScore = score;
        best = t;
      }
    }
    for (final d in UECDrone.active) {
      if (!d.isMounted || d.isDead) continue;
      consider(d, d.position + d.size / 2);
    }
    for (final pad in DroneSpawnPoint.active) {
      if (!pad.isMounted || pad.isDead) continue;
      consider(pad, pad.padCenter);
    }
    final s = SentinelDrone.instance;
    if (s != null && s.isMounted && !s.isDead) {
      consider(s, s.position + s.size / 2);
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
      // Legacy on-screen stick (removed from HUD) — still cancel click-move.
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
