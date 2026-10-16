import 'dart:ui';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import 'click_pathfinder.dart';
import 'game_debug.dart';

/// Optional pathfinding blocked-cell overlay (**G** while DEBUG is on).
///
/// Off by default — rebuilding dynamics + painting hundreds of rects each
/// frame made DEBUG feel laggy. When on, uses tile barriers only (fast) and
/// a cached [Picture]; full dynamic rescan only on [invalidate].
class DebugWalkGrid extends GameComponent {
  static const _blocked = Color(0x88FF2244);

  Picture? _picture;
  double _picLeft = 0;
  double _picTop = 0;
  int _camCellX = -999;
  int _camCellY = -999;
  bool _dirty = true;

  @override
  bool get isVisible => GameDebug.showWalkGrid;

  @override
  int get priority => LayerPriority.getAbovePriority(900);

  @override
  void update(double dt) {
    super.update(dt);
    if (!GameDebug.showWalkGrid || !hasGameRef || !ClickPathfinder.hasGrid) {
      _picture = null;
      return;
    }
    final cell = ClickPathfinder.cellSize;
    final cam = gameRef.camera.viewfinder.position;
    final cx = (cam.x / cell).floor();
    final cy = (cam.y / cell).floor();
    // Rebuild picture when camera moves a cell or something invalidated us.
    if (_dirty || cx != _camCellX || cy != _camCellY) {
      _camCellX = cx;
      _camCellY = cy;
      _dirty = false;
      _bake();
    }
  }

  void invalidate() {
    _dirty = true;
    // Prefer tile-only bake immediately after mask edits (still cheap).
  }

  void _bake() {
    final cell = ClickPathfinder.cellSize;
    final cols = ClickPathfinder.cols;
    final rows = ClickPathfinder.rows;
    // Tile walls only — skip per-frame collisions() scan.
    final barriers = ClickPathfinder.tileBarriersView;

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

    _picLeft = x0 * cell;
    _picTop = y0 * cell;

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = _blocked;
    // Translate so picture origin is top-left of the window.
    canvas.translate(-_picLeft, -_picTop);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if (!barriers.contains((x, y))) continue;
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
      }
    }
    _picture?.dispose();
    _picture = recorder.endRecording();
  }

  @override
  void render(Canvas canvas) {
    if (!GameDebug.showWalkGrid) return;
    final pic = _picture;
    if (pic == null) return;
    canvas.save();
    canvas.translate(_picLeft, _picTop);
    canvas.drawPicture(pic);
    canvas.restore();
  }

  @override
  void onRemove() {
    _picture?.dispose();
    _picture = null;
    super.onRemove();
  }
}
