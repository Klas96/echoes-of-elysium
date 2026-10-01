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

  @override
  void update(double dt) {
    super.update(dt);
    positionNotifier.value = position.clone();
    _applyKeyboardMovement(dt);
    _validatePosition();
    _checkInteraction();
    _updateFootsteps(dt);
    _handleShooting(dt);
    _frameCount++;
  }

  void _applyKeyboardMovement(double dt) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    double dx = 0, dy = 0;
    if (keys.contains(LogicalKeyboardKey.keyW) || keys.contains(LogicalKeyboardKey.arrowUp)) dy -= 1;
    if (keys.contains(LogicalKeyboardKey.keyS) || keys.contains(LogicalKeyboardKey.arrowDown)) dy += 1;
    if (keys.contains(LogicalKeyboardKey.keyA) || keys.contains(LogicalKeyboardKey.arrowLeft)) dx -= 1;
    if (keys.contains(LogicalKeyboardKey.keyD) || keys.contains(LogicalKeyboardKey.arrowRight)) dx += 1;
    if (dx == 0 && dy == 0) return;
    final dir = Vector2(dx, dy)..normalize();
    _applyMovement(dir, dt);
  }

  void _applyMovement(Vector2 direction, double dt) {
    if (textureMap == null) return;
    final step = direction * speed * dt;
    final next = position + step;
    if (textureMap!.isWalkable(next)) {
      position = next;
      lastValidPosition = position;
      isBlocked = false;
    } else {
      isBlocked = true;
      final half = position + step * 0.5;
      if (textureMap!.isWalkable(half)) {
        position = half;
        lastValidPosition = position;
      }
    }
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

    gameRef.add(PlayerBullet(position + size / 2 - Vector2(5, 5), dir.normalized()));
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

  @override
  void onJoystickChangeDirectional(JoystickDirectionalEvent event) {
    _joystickMoving = event.directional != JoystickMoveDirectional.IDLE;
    if (event.directional == JoystickMoveDirectional.IDLE) return;
    Vector2 dir = Vector2.zero();
    switch (event.directional) {
      case JoystickMoveDirectional.MOVE_UP:         dir = Vector2(0, -1); break;
      case JoystickMoveDirectional.MOVE_DOWN:       dir = Vector2(0, 1); break;
      case JoystickMoveDirectional.MOVE_LEFT:       dir = Vector2(-1, 0); break;
      case JoystickMoveDirectional.MOVE_RIGHT:      dir = Vector2(1, 0); break;
      case JoystickMoveDirectional.MOVE_UP_LEFT:    dir = Vector2(-1, -1)..normalize(); break;
      case JoystickMoveDirectional.MOVE_UP_RIGHT:   dir = Vector2(1, -1)..normalize(); break;
      case JoystickMoveDirectional.MOVE_DOWN_LEFT:  dir = Vector2(-1, 1)..normalize(); break;
      case JoystickMoveDirectional.MOVE_DOWN_RIGHT: dir = Vector2(1, 1)..normalize(); break;
      default: break;
    }
    _applyMovement(dir, 0.016);
  }
}
