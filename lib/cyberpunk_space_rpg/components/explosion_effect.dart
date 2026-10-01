import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

class ExplosionEffect extends GameDecoration {
  static const double _duration = 0.5;
  double _elapsed = 0;
  Sprite? _sprite;

  ExplosionEffect(Vector2 position)
      : super(position: position - Vector2.all(24), size: Vector2.all(48));

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load('sprites/explosion.png');
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    if (_sprite == null) return;
    final opacity = (1.0 - _elapsed / _duration).clamp(0.0, 1.0);
    final scale = 0.6 + (_elapsed / _duration) * 0.8;
    final paint = Paint()..color = const Color(0xFFFFFFFF).withOpacity(opacity);
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(scale);
    canvas.translate(-size.x / 2, -size.y / 2);
    _sprite!.render(canvas, size: size, overridePaint: paint);
    canvas.restore();
  }
}
