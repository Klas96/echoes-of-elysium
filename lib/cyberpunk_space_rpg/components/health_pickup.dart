import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'custom_player.dart';

class HealthPickup extends GameDecoration {
  static const double _collectRadius = 24;
  static const int _healAmount = 40;
  double _pulse = 0;
  bool _collected = false;
  Sprite? _sprite;

  HealthPickup(Vector2 position)
      : super(position: position, size: Vector2.all(16));

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load('sprites/health_pickup.png');
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 2.5;
    if (_collected) return;

    final player = gameRef.player;
    if (player == null) return;
    if (((player.position + player.size / 2) - (position + size / 2)).length < _collectRadius) {
      _collected = true;
      CustomPlayer.healthNotifier.value =
          (CustomPlayer.healthNotifier.value + _healAmount).clamp(0, CustomPlayer.maxHealth);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    if (_collected) return;
    final cx = size.x / 2;
    final cy = size.y / 2;
    final p = sin(_pulse);

    canvas.drawCircle(Offset(cx, cy), 10 + p * 2,
        Paint()
          ..color = const Color(0xFF00FF88).withOpacity(0.22 + p * 0.06)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));

    if (_sprite != null) {
      _sprite!.render(canvas, size: size);
    }
  }
}
