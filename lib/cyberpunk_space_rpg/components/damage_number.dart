import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../game/well_rested.dart';
import '../ui/mmo_feedback.dart';

enum DamageNumberStyle { dealt, shield, taken }

/// Floating damage number over a hit (#32): the in-world sibling of the HUD
/// +XP / loot pops ([MmoFeedback]) — same bold text and shadow, rising and
/// fading over [life] seconds. Text is laid out once; no per-frame layout.
class DamageNumber extends GameComponent {
  static const life = 0.85;
  static const rise = 22.0;

  final TextPainter _tp;
  final double _drift;
  double _t = 0;

  DamageNumber._(Vector2 at, this._tp, this._drift) {
    position = at;
    size = Vector2(_tp.width, _tp.height);
    anchor = Anchor.bottomCenter;
    renderAboveComponents = true;
  }

  static Color colorFor(DamageNumberStyle style, {bool rested = false}) => switch (style) {
        DamageNumberStyle.taken => MmoFeedback.damageTakenColor,
        DamageNumberStyle.shield => MmoFeedback.shieldColor,
        DamageNumberStyle.dealt => rested ? MmoFeedback.restedHitColor : MmoFeedback.hitColor,
      };

  static String textFor(int amount, DamageNumberStyle style) =>
      style == DamageNumberStyle.taken ? '-$amount' : '$amount';

  /// Adds a number at [at] (world px, usually the top centre of the target).
  static void spawn(GameComponent from, Vector2 at, int amount, DamageNumberStyle style) {
    if (amount <= 0 || !from.isMounted) return;
    final rested = style == DamageNumberStyle.dealt && WellRested.active;
    final tp = TextPainter(
      text: TextSpan(
        text: textFor(amount, style),
        style: MmoFeedback.popStyle(colorFor(style, rested: rested),
            fontSize: style == DamageNumberStyle.taken ? 9 : 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final drift = (Random().nextDouble() - 0.5) * 12;
    from.gameRef.add(DamageNumber._(at.clone(), tp, drift));
  }

  /// 0..1 progress → (dy, alpha).
  static (double, double) curve(double u) {
    final eased = 1 - pow(1 - u, 2).toDouble();
    final alpha = u < 0.6 ? 1.0 : (1 - (u - 0.6) / 0.4).clamp(0.0, 1.0);
    return (-rise * eased, alpha);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final (dy, alpha) = curve((_t / life).clamp(0.0, 1.0));
    if (alpha <= 0) return;
    final off = Offset(_drift * (_t / life), dy);
    if (alpha < 1) {
      canvas.saveLayer(
          (off & Size(size.x, size.y)).inflate(4), Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
      _tp.paint(canvas, off);
      canvas.restore();
    } else {
      _tp.paint(canvas, off);
    }
  }
}
