import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import '../game/game_state.dart';

class FragmentPickup extends GameDecoration {
  static const double defaultCollectRadius = 28;

  /// The grotto fragment is taken from the bank, across the pond.
  final double collectRadius;
  double _pulse = 0;
  bool _collected = false;

  /// Called once when collected, before the objective updates (and autosaves).
  final VoidCallback? onCollected;

  /// Still hidden (e.g. in the dark grotto until the glowmoth lights it):
  /// not drawn and can't be picked up.
  final bool Function()? hidden;

  FragmentPickup(Vector2 position, {this.onCollected, this.hidden, this.collectRadius = defaultCollectRadius})
      : super(position: position, size: Vector2.all(18));

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 3.5;
    if (_collected || (hidden?.call() ?? false)) return;

    final player = gameRef.player;
    if (player == null) return;
    if (((player.position + player.size / 2) - (position + size / 2)).length < collectRadius) {
      _collected = true;
      onCollected?.call();
      GameState.onFragmentCollected();
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    if (_collected || (hidden?.call() ?? false)) return;
    final cx = size.x / 2;
    final cy = size.y / 2;
    final p = sin(_pulse);

    canvas.drawCircle(Offset(cx, cy), 12 + p * 2,
        Paint()
          ..color = const Color(0xFFAA44FF).withOpacity(0.22 + p * 0.06)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    // Diamond crystal
    final path = Path()
      ..moveTo(cx, cy - 8)
      ..lineTo(cx + 5, cy)
      ..lineTo(cx, cy + 8)
      ..lineTo(cx - 5, cy)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFCC66FF));
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withOpacity(0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);
    canvas.drawCircle(Offset(cx, cy), 2, Paint()..color = Colors.white.withOpacity(0.9));
  }
}
