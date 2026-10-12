import 'dart:ui';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import 'game_debug.dart';

/// Cyan click-path overlay — only while [GameDebug] is on. Always considered
/// visible so camera culling does not hide a long route whose component sits
/// at the map origin (Bonfire's [LinePathComponent] often vanished).
class DebugPathLine extends GameComponent {
  List<Vector2> points;
  Vector2 Function()? origin;

  DebugPathLine({required this.points, this.origin});

  static const _color = Color(0xCC00E5FF);

  @override
  bool get isVisible => true;

  @override
  int get priority => LayerPriority.getAbovePriority(1000);

  @override
  void render(Canvas canvas) {
    if (!GameDebug.isOn) return;
    final pts = <Vector2>[
      if (origin != null) origin!(),
      ...points,
    ];
    if (pts.length < 2) {
      if (pts.length == 1) {
        canvas.drawCircle(
          Offset(pts.first.x, pts.first.y),
          4,
          Paint()..color = _color,
        );
      }
      return;
    }
    final path = Path()..moveTo(pts.first.x, pts.first.y);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].x, pts[i].y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = _color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final p in pts) {
      canvas.drawCircle(Offset(p.x, p.y), 3, Paint()..color = _color);
    }
    super.render(canvas);
  }
}
