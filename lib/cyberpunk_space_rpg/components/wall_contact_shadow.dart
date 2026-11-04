import 'dart:ui';

import 'package:bonfire/bonfire.dart';

import '../game/click_pathfinder.dart';

/// Soft floor contact shadow where walkable tiles meet solid walls.
///
/// Matches the woods blob-edge dither look: a dark rim on the floor beside
/// walls so blocked ground reads raised. Light bias is from the north-west
/// (stronger south / east strips).
///
/// Added from [_startLevel] on overworlds that lack baked wall-edge art.
/// Not used on the Woods — that tileset already has the dither.
class WallContactShadow extends GameComponent {
  static const double _tile = 32;

  /// Built after [ClickPathfinder.primeFromAsset].
  Set<(int, int)> _walls = {};
  int _mw = 0;
  int _mh = 0;
  bool _ready = false;

  @override
  int get priority => LayerPriority.MAP + 1;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _rebuild();
  }

  void _rebuild() {
    if (!ClickPathfinder.hasGrid) {
      _ready = false;
      return;
    }
    final cell = ClickPathfinder.cellSize;
    final sub = ClickPathfinder.subdivisions;
    final cols = ClickPathfinder.cols;
    final rows = ClickPathfinder.rows;
    _mw = (cols / sub).ceil();
    _mh = (rows / sub).ceil();
    final walls = <(int, int)>{};
    final barriers = ClickPathfinder.tileBarriersView;
    // A map tile is a wall when a majority of its half-cells are blocked
    // (full collision tiles, not skinny prop feet).
    for (var ty = 0; ty < _mh; ty++) {
      for (var tx = 0; tx < _mw; tx++) {
        var blocked = 0;
        var total = 0;
        for (var j = 0; j < sub; j++) {
          for (var i = 0; i < sub; i++) {
            final cx = tx * sub + i;
            final cy = ty * sub + j;
            if (cx >= cols || cy >= rows) continue;
            total++;
            if (barriers.contains((cx, cy))) blocked++;
          }
        }
        if (total > 0 && blocked * 2 >= total) {
          walls.add((tx, ty));
        }
      }
    }
    _walls = walls;
    _ready = walls.isNotEmpty;
    // Size covers the map so the camera culls naturally.
    size = Vector2(_mw * _tile, _mh * _tile);
    position = Vector2.zero();
    // Keep analyzer happy — cell size documents the half-tile grid we sampled.
    assert(cell > 0);
  }

  bool _wall(int tx, int ty) => _walls.contains((tx, ty));

  @override
  void render(Canvas canvas) {
    if (!_ready) {
      _rebuild();
      if (!_ready) return;
    }
    // Soft fill like interiors (0x55), slightly stronger on the "far" sides
    // from a north-west light (south + east).
    final side = Paint()
      ..color = const Color(0x5A000000)
      ..blendMode = BlendMode.srcOver;
    final deep = Paint()
      ..color = const Color(0x78000000)
      ..blendMode = BlendMode.srcOver;

    for (var ty = 0; ty < _mh; ty++) {
      for (var tx = 0; tx < _mw; tx++) {
        if (_wall(tx, ty)) continue;
        final px = tx * _tile;
        final py = ty * _tile;
        // West of a wall → shadow on our east edge (wall to the right)
        if (_wall(tx + 1, ty)) {
          canvas.drawRect(Rect.fromLTWH(px + _tile - 6, py, 6, _tile), deep);
        }
        // East of a wall → shadow on our west edge
        if (_wall(tx - 1, ty)) {
          canvas.drawRect(Rect.fromLTWH(px, py, 5, _tile), side);
        }
        // North of a wall (wall below) → strong south-facing contact shadow
        if (_wall(tx, ty + 1)) {
          canvas.drawRect(Rect.fromLTWH(px, py + _tile - 7, _tile, 7), deep);
        }
        // South of a wall (wall above) → thinner north rim
        if (_wall(tx, ty - 1)) {
          canvas.drawRect(Rect.fromLTWH(px, py, _tile, 5), side);
        }
      }
    }
  }
}
