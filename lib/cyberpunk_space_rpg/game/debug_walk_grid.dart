import 'dart:ui';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import 'click_pathfinder.dart';
import 'game_debug.dart';

/// Paints pathfinding walkable (tint) vs blocked (solid) half-cells while
/// [GameDebug] is on. Only draws the camera window for speed.
class DebugWalkGrid extends GameComponent {
  static const _blocked = Color(0x66FF2244);
  static const _blockedEdge = Color(0x99FF4466);
  static const _walkable = Color(0x2200FF88);

  @override
  bool get isVisible => true;

  @override
  int get priority => LayerPriority.getAbovePriority(900);

  @override
  void render(Canvas canvas) {
    if (!GameDebug.isOn || !hasGameRef) return;
    if (!ClickPathfinder.hasGrid) {
      // Still priming — show nothing rather than a wrong empty grid.
      return;
    }

    final barriers = ClickPathfinder.barriersFor(gameRef);
    final cell = ClickPathfinder.cellSize;
    final cols = ClickPathfinder.cols;
    final rows = ClickPathfinder.rows;

    final cam = gameRef.camera.viewfinder.position;
    final zoom = gameRef.camera.viewfinder.zoom;
    final view = gameRef.size / zoom;
    final pad = cell * 2;
    final left = cam.x - view.x / 2 - pad;
    final top = cam.y - view.y / 2 - pad;
    final right = cam.x + view.x / 2 + pad;
    final bottom = cam.y + view.y / 2 + pad;

    final x0 = (left / cell).floor().clamp(0, cols - 1);
    final y0 = (top / cell).floor().clamp(0, rows - 1);
    final x1 = (right / cell).floor().clamp(0, cols - 1);
    final y1 = (bottom / cell).floor().clamp(0, rows - 1);

    final blockPaint = Paint()..color = _blocked;
    final walkPaint = Paint()..color = _walkable;
    final edgePaint = Paint()
      ..color = _blockedEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;

    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final r = Rect.fromLTWH(x * cell, y * cell, cell, cell);
        if (barriers.contains((x, y))) {
          canvas.drawRect(r, blockPaint);
          canvas.drawRect(r, edgePaint);
        } else {
          canvas.drawRect(r, walkPaint);
        }
      }
    }
    super.render(canvas);
  }
}
