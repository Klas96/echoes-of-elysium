import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bonfire/util/collision_game_component.dart';
import 'dart:math';
import 'ai_fragment.dart';
import 'npc_character.dart';
import 'player_bullet.dart';
import '../audio/music_manager.dart';

class CustomPlayer extends SimplePlayer with BlockMovementCollision {
  static const double sizePlayer = 32;
  static const int maxHealth = 100;
  static final ValueNotifier<Vector2> positionNotifier = ValueNotifier(Vector2.zero());
  static final ValueNotifier<int> healthNotifier = ValueNotifier(maxHealth);
  static final ValueNotifier<bool> damageFlash = ValueNotifier(false);
  static final ValueNotifier<Vector2?> pendingShot = ValueNotifier(null);

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
  ) {
    priority = 1000;
  }

  Sprite? _sprite;

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

    if (_sprite != null) {
      _sprite!.render(canvas, size: size);
    }
  }

  @override
  Future<void> onLoad() async {
    SfxManager().init();
    _sprite = await Sprite.load('sprites/player.png');
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

  // Walls are Tiled tile collisions; BlockMovementCollision pushes us out and
  // removes only the velocity component into the wall, so we slide along it.
  // Flag "blocked" (red glow, no footsteps) only while pressing into a wall.
  @override
  void onBlockedMovement(PositionComponent other, CollisionData collisionData) {
    super.onBlockedMovement(other, collisionData);
    // After super, velocity is what's left once the into-wall part is
    // removed: near zero means we're pushing straight into the wall.
    if ((other is TileWithCollision || other is CollisionMapComponent) &&
        velocity.length < speed * 0.2) {
      _blockedTimer = 0.1;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    positionNotifier.value = position.clone();
    _blockedTimer = max(0, _blockedTimer - dt);
    isBlocked = _blockedTimer > 0;
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
