import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'custom_texture_map.dart';
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

  CustomTextureMap? textureMap;
  bool isBlocked = false;
  Vector2 lastValidPosition = Vector2.zero();
  int _frameCount = 0;
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
    lastValidPosition = position;
    priority = 1000;
  }

  void setTextureMap(CustomTextureMap map) {
    textureMap = map;
    SfxManager().init();
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

  // Movement now comes from Bonfire (joystick + Keyboard controller set
  // velocity, Bonfire applies velocity * dt), so BlockMovementCollision can
  // resolve Tiled walls with sliding. While a map still uses the texture
  // mask, undo a step that lands on a blocked pixel.
  @override
  void onApplyDisplacement(double dt) {
    final before = position.clone();
    super.onApplyDisplacement(dt);
    final map = textureMap;
    if (map == null || before == position) return;
    if (map.isWalkable(position)) {
      lastValidPosition = position.clone();
      isBlocked = false;
    } else {
      position = before;
      isBlocked = true;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    positionNotifier.value = position.clone();
    _validatePosition();
    _checkInteraction();
    _updateFootsteps(dt);
    _handleShooting(dt);
    _frameCount++;
  }

  void _validatePosition() {
    if (textureMap == null || _frameCount % 30 != 0) return;
    if (!textureMap!.isWalkable(position)) {
      if (textureMap!.isWalkable(lastValidPosition)) {
        position = lastValidPosition;
      } else {
        final found = _findNearbyValidPosition(position);
        if (found != null) {
          position = found;
          lastValidPosition = found;
        }
      }
      isBlocked = true;
    } else {
      lastValidPosition = position;
      isBlocked = false;
    }
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

  Vector2? _findNearbyValidPosition(Vector2 center) {
    for (double r = 8.0; r <= 50.0; r += 8.0) {
      for (double a = 0; a < 2 * pi; a += 0.8) {
        final p = Vector2(center.x + r * cos(a), center.y + r * sin(a));
        if (textureMap!.isWalkable(p)) return p;
      }
    }
    return null;
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
