import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../creatures/bonds.dart';
import '../creatures/interaction.dart';
import '../game/adventure.dart';
import '../game/game_state.dart';

/// Solid barricade that vanishes when [openFlag] is set (keyed ruins wing).
class StoryGate extends GameComponent {
  final String openFlag;
  double _pulse = 0;
  bool _hinted = false;

  StoryGate(Vector2 position, Vector2 size, {required this.openFlag}) {
    this.position = position;
    this.size = size;
  }

  bool get _open => Adventure.flag(openFlag);

  @override
  Future<void> onLoad() async {
    if (_open) {
      removeFromParent();
      return;
    }
    // Full footprint solid — map choke is sized to this hitbox (no walk-around).
    add(RectangleHitbox(size: size, isSolid: true));
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 2;
    if (_open && isMounted) {
      removeFromParent();
      return;
    }
    final player = gameRef.player;
    if (player == null || _hinted) return;
    final dist = ((player.position + player.size / 2) - (position + size / 2)).length;
    if (dist > 72) return;
    _hinted = true;
    GameState.refreshObjective();
    if (Bonds.hasItem('ruins_gate_key')) {
      GameToast.show(
        'KEYSTONE READY',
        body: 'Examine the sealed gate and USE the keystone.',
        color: const Color(0xFFFFE08A),
        compact: true,
      );
    } else {
      GameToast.show(
        'SEALED GATE',
        body: 'Core beyond. Fetch the Aetherian Keystone from the north-east wing.',
        color: const Color(0xFFFFAABB),
        compact: true,
      );
    }
  }

  @override
  void render(Canvas canvas) {
    if (_open) return;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.x, size.y),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      r,
      Paint()..color = const Color(0xFF2A2030).withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..color = const Color(0xFFFF6688).withValues(alpha: 0.45 + 0.15 * (0.5 + 0.5 * (1 - (_pulse % 1))))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final label = Bonds.hasItem('ruins_gate_key') ? 'USE KEY' : 'NE KEY';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Color(0xFFFFAABB), fontSize: 9, letterSpacing: 1.2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.x - tp.width) / 2, (size.y - tp.height) / 2));
  }
}
