import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../creatures/bonds.dart';
import '../creatures/interaction.dart';
import '../game/adventure.dart';
import '../game/game_state.dart';

/// Aetherian lattice gate on the keyed ruins wing. Solid while sealed; once
/// [openFlag] is set it swaps to the open frame (keystone seated, doorway
/// clear) and stops colliding.
///
/// Art (96x96, 3x3 tiles, base on the bottom edge):
/// `sprites/obstacles/story_gate.png` closed,
/// `story_gate_pulse.png` 2-frame energy pulse over the closed gate,
/// `story_gate_open.png` open.
class StoryGate extends GameComponent {
  static const closedPath = 'sprites/obstacles/story_gate.png';
  static const openPath = 'sprites/obstacles/story_gate_open.png';
  static const pulsePath = 'sprites/obstacles/story_gate_pulse.png';

  final String openFlag;
  double _pulse = 0;
  bool _hinted = false;
  RectangleHitbox? _hitbox;
  Sprite? _closed;
  Sprite? _openSprite;
  Sprite? _pulseLit;

  StoryGate(Vector2 position, Vector2 size, {required this.openFlag}) {
    this.position = position;
    this.size = size;
  }

  bool get _open => Adventure.flag(openFlag);

  @override
  Future<void> onLoad() async {
    try {
      _closed = await Sprite.load(closedPath);
      _openSprite = await Sprite.load(openPath);
      final pulse = await Flame.images.load(pulsePath);
      // Frame 1 is the lit barrier; frame 0 matches the closed art.
      _pulseLit = Sprite(pulse,
          srcPosition: Vector2(pulse.width / 2, 0), srcSize: Vector2(pulse.width / 2, pulse.height.toDouble()));
    } catch (_) {
      // Missing art: fall back to the plain block below.
    }
    if (!_open) {
      // Full footprint solid — map choke is sized to this hitbox (no walk-around).
      add(_hitbox = RectangleHitbox(size: size, isSolid: true));
    }
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 2;
    if (_open) {
      // Keystone seated: walkable doorway.
      if (_hitbox != null) {
        _hitbox!.removeFromParent();
        _hitbox = null;
      }
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
        item: 'ruins_gate_key',
      );
    } else {
      GameToast.show(
        'SEALED GATE',
        body: 'Core beyond. Fetch the Aetherian Keystone from the north-east wing.',
        color: const Color(0xFFFFAABB),
        compact: true,
        item: 'ruins_gate_key',
      );
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    if (_open) {
      _openSprite?.render(canvas, size: size, overridePaint: paint);
      return;
    }
    if (_closed == null) {
      _renderFallback(canvas);
    } else {
      _closed!.render(canvas, size: size, overridePaint: paint);
      // Slow breathe of the lit barrier over the closed art.
      final a = 0.5 + 0.5 * sin(_pulse * pi / 2);
      if (a > 0.02) {
        _pulseLit?.render(canvas,
            size: size, overridePaint: paint..color = Color.fromRGBO(255, 255, 255, a));
      }
    }
    final label = Bonds.hasItem('ruins_gate_key') ? 'USE KEY' : 'NE KEY';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFFFAABB),
          fontSize: 8,
          letterSpacing: 1.2,
          shadows: [Shadow(color: Colors.black, blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // A small plate on the stone base, under the barrier.
    final at = Offset((size.x - tp.width) / 2, size.y - tp.height - 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(at.dx - 4, at.dy - 1, tp.width + 8, tp.height + 2),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xCC140E1A),
    );
    tp.paint(canvas, at);
  }

  void _renderFallback(Canvas canvas) {
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
  }
}
