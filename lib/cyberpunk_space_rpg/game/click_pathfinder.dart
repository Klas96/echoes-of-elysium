import 'dart:convert';
import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:bonfire/util/collision_game_component.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../components/building.dart';
import '../creatures/gate_components.dart';
import '../creatures/obstacles.dart';

/// League-style click pathfinding over the whole map.
///
/// Half-tile grid (16px). Tile walls are loaded from the **Tiled JSON**
/// (Bonfire's live `map.layers` collision list was incomplete / empty on
/// first click, so A* walked straight through forests). A* is a tight
/// binary-heap search.
class ClickPathfinder {
  ClickPathfinder._();

  /// Path cells per map tile edge (2 → 16px on a 32px tileset).
  static const int subdivisions = 2;

  /// Must match [CustomPlayer.feetWidth] / feetHeight. Path agent is the
  /// feet hitbox center (not sprite mid) — see CustomPlayer._feetCenter.
  static const double _clearW = 32 * 0.38;
  static const double _clearH = 32 * 0.22;

  /// Exposed for tests — keep in sync with CustomPlayer feet hitbox.
  static double get clearWidth => _clearW;
  static double get clearHeight => _clearH;

  static GameMap? _cachedMap;
  static double _cell = 16;
  static int _cols = 0;
  static int _rows = 0;
  static Set<(int, int)> _tileBarriers = {};

  /// Scratch set rebuilt each find (tiles copied + live props). Do not
  /// retain across calls.
  static final Set<(int, int)> _scratchBarriers = {};

  /// Load solid tile collisions from a Tiled map asset (e.g. `maps/world.tmj`).
  /// Call from map `onReady` before the player clicks.
  static Future<void> primeFromAsset(String mapPath) async {
    final asset = mapPath.startsWith('assets/')
        ? mapPath
        : 'assets/images/$mapPath';
    // Always rebuild — clearance constants may change between runs.

    final raw = await rootBundle.loadString(asset);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final tw = (data['tilewidth'] as num?)?.toDouble() ?? 32.0;
    final th = (data['tileheight'] as num?)?.toDouble() ?? 32.0;
    final mw = (data['width'] as num?)?.toInt() ?? 0;
    final mh = (data['height'] as num?)?.toInt() ?? 0;
    if (mw <= 0 || mh <= 0) return;

    _cell = tw / subdivisions;
    _cols = max(1, (mw * tw / _cell).ceil());
    _rows = max(1, (mh * th / _cell).ceil());
    _cachedMap = null; // force size re-check against live GameMap later

    // tileset gid → (collision rects in tile-local px, optional prop id)
    final coll = <int, (List<Rect>, String?)>{};
    for (final ts in (data['tilesets'] as List? ?? const [])) {
      if (ts is! Map) continue;
      final firstGid = (ts['firstgid'] as num?)?.toInt() ?? 1;
      for (final tile in (ts['tiles'] as List? ?? const [])) {
        if (tile is! Map) continue;
        final id = (tile['id'] as num?)?.toInt();
        if (id == null) continue;
        final objs = tile['objectgroup'] is Map
            ? (tile['objectgroup'] as Map)['objects'] as List? ?? const []
            : const [];
        if (objs.isEmpty) continue;
        final rects = <Rect>[];
        for (final o in objs) {
          if (o is! Map) continue;
          final w = (o['width'] as num?)?.toDouble() ?? 0;
          final h = (o['height'] as num?)?.toDouble() ?? 0;
          if (w <= 0 || h <= 0) continue;
          rects.add(Rect.fromLTWH(
            (o['x'] as num?)?.toDouble() ?? 0,
            (o['y'] as num?)?.toDouble() ?? 0,
            w,
            h,
          ));
        }
        if (rects.isEmpty) continue;
        String? prop;
        for (final p in (tile['properties'] as List? ?? const [])) {
          if (p is Map && p['name'] == 'prop') {
            prop = p['value']?.toString();
            break;
          }
        }
        coll[firstGid + id] = (rects, prop);
      }
    }

    final blocked = <(int, int)>{};
    for (final layer in (data['layers'] as List? ?? const [])) {
      if (layer is! Map || layer['type'] != 'tilelayer') continue;
      final grid = layer['data'];
      if (grid is! List) continue;
      final isProps = layer['name'] == 'props';
      final lw = (layer['width'] as num?)?.toInt() ?? mw;
      for (var i = 0; i < grid.length; i++) {
        final gid = (grid[i] as num?)?.toInt() ?? 0;
        // Clear flip flags (Tiled high bits).
        final clean = gid & 0x1FFFFFFF;
        final entry = coll[clean];
        if (entry == null) continue;
        final tx = i % lw;
        final ty = i ~/ lw;
        final ox = tx * tw;
        final oy = ty * th;
        final tileBounds = Rect.fromLTWH(ox, oy, tw, th);
        for (final r in entry.$1) {
          var world = Rect.fromLTWH(ox + r.left, oy + r.top, r.width, r.height);
          // Props art: canopy / foliage should stay walkable — only the foot
          // of the sprite blocks (matches what the pixel art suggests).
          if (isProps) {
            final foot = _propArtFoot(world, tileBounds, entry.$2);
            if (foot == null) continue;
            world = foot;
          }
          _rasterizeRect(world, blocked);
        }
      }
    }
    _tileBarriers = blocked;
  }

  /// World-space waypoints (cell centers), start → goal.
  ///
  /// League rules: click on a wall / sealed area → walk to the **closest
  /// reachable** walkable cell to that click (never empty just because the
  /// exact tile is blocked or cut off). Empty only if nowhere is reachable.
  static List<Vector2> find(
    BonfireGameInterface game, {
    required Vector2 from,
    required Vector2 to,
  }) {
    _ensureTileCache(game.map);
    if (_cols <= 0 || _rows <= 0) return [];

    final barriers = _combinedBarriers(game);

    var start = _clampCell(_cellOf(from));
    var end = _clampCell(_cellOf(to));

    if (barriers.contains(start)) {
      final free = _nearestWalkable(start, barriers, preferNear: from);
      if (free == null) return [];
      start = free;
    }
    // Click inside a wall/prop → closest free cell to the click (LoL).
    if (barriers.contains(end)) {
      final free = _nearestWalkable(end, barriers, preferNear: to);
      if (free == null) return [];
      end = free;
    }
    if (start == end) {
      return [_worldCenterAwayFromWalls(end, barriers)];
    }

    // Short clear hop only — long LOS shortcuts walked into forest walls
    // when the barrier cache was empty / incomplete (e.g. 19,15 → 13,18).
    final manhattan =
        (start.$1 - end.$1).abs() + (start.$2 - end.$2).abs();
    if (manhattan <= 3 && _lineClear(start, end, barriers)) {
      return [_worldCenterAwayFromWalls(end, barriers)];
    }

    // A* to goal; if the region is sealed, path to closest reachable instead.
    final path = _astar(barriers, start, end);
    if (path.isEmpty) return [];

    final cells = path.length > 1 ? path.skip(1) : path;
    return [
      for (final c in cells) _worldCenterAwayFromWalls(c, barriers),
    ];
  }

  static void clearCache() {
    _cachedMap = null;
    _tileBarriers = {};
    _scratchBarriers.clear();
    _cols = 0;
    _rows = 0;
  }

  /// Half-cell size in world px (for debug overlays).
  static double get cellSize => _cell;

  static int get cols => _cols;
  static int get rows => _rows;

  static bool get hasGrid => _cols > 0 && _rows > 0 && _tileBarriers.isNotEmpty;

  /// Live walk grid including stones/gates (same as click A*).
  static Set<(int, int)> barriersFor(BonfireGameInterface game) {
    if (_cols <= 0) _ensureTileCache(game.map);
    return _combinedBarriers(game);
  }

  static (int, int) cellOf(Vector2 world) => _clampCell(_cellOf(world));

  /// Tile walls are cached; stones/gates are re-scanned every click so a
  /// boulder that finished [onLoad] after the first path is never missing
  /// (a Bonds.revision-only cache let paths tunnel through the nook rock).
  static Set<(int, int)> _combinedBarriers(BonfireGameInterface game) {
    final barriers = _scratchBarriers
      ..clear()
      ..addAll(_tileBarriers);
    _addDynamicSolids(game, barriers);
    return barriers;
  }

  /// Binary-heap A* with diagonal moves (no corner-cutting through walls).
  /// If [end] is unreachable, returns a path to the reachable cell closest
  /// to [end] (League auto-path when the click is cut off).
  static List<(int, int)> _astar(
    Set<(int, int)> barriers,
    (int, int) start,
    (int, int) end,
  ) {
    final n = _cols * _rows;
    final gScore = List<double>.filled(n, double.infinity);
    final cameFrom = List<int>.filled(n, -1);
    final closed = List<bool>.filled(n, false);

    int idx((int, int) c) => c.$2 * _cols + c.$1;

    final startI = idx(start);
    final endI = idx(end);
    gScore[startI] = 0;

    // Closest-to-goal among visited (used if end is sealed off).
    var bestI = startI;
    var bestH = _heuristic(start, end);

    // Heap entries: (f, cellIndex)
    final heap = <(double, int)>[(bestH, startI)];

    const ortho = <(int, int)>[
      (0, -1),
      (0, 1),
      (-1, 0),
      (1, 0),
    ];
    const diag = <(int, int)>[
      (-1, -1),
      (1, -1),
      (-1, 1),
      (1, 1),
    ];

    while (heap.isNotEmpty) {
      final currentI = _heapPop(heap);
      if (closed[currentI]) continue;
      if (currentI == endI) {
        return _reconstruct(cameFrom, endI, barriers);
      }
      closed[currentI] = true;

      final cx = currentI % _cols;
      final cy = currentI ~/ _cols;
      final hHere = _heuristic((cx, cy), end);
      if (hHere < bestH || (hHere == bestH && gScore[currentI] < gScore[bestI])) {
        bestH = hHere;
        bestI = currentI;
      }

      for (final d in ortho) {
        final nx = cx + d.$1;
        final ny = cy + d.$2;
        if (nx < 0 || ny < 0 || nx >= _cols || ny >= _rows) continue;
        final ni = ny * _cols + nx;
        if (closed[ni] || barriers.contains((nx, ny))) continue;
        final tentative = gScore[currentI] + 1.0;
        if (tentative >= gScore[ni]) continue;
        cameFrom[ni] = currentI;
        gScore[ni] = tentative;
        _heapPush(heap, (tentative + _heuristic((nx, ny), end), ni));
      }

      for (final d in diag) {
        final nx = cx + d.$1;
        final ny = cy + d.$2;
        if (nx < 0 || ny < 0 || nx >= _cols || ny >= _rows) continue;
        final ni = ny * _cols + nx;
        if (closed[ni] || barriers.contains((nx, ny))) continue;
        // No corner-cutting: both adjacent orthogonals must be free.
        if (barriers.contains((nx, cy)) || barriers.contains((cx, ny))) {
          continue;
        }
        final tentative = gScore[currentI] + 1.41421356237;
        if (tentative >= gScore[ni]) continue;
        cameFrom[ni] = currentI;
        gScore[ni] = tentative;
        _heapPush(heap, (tentative + _heuristic((nx, ny), end), ni));
      }
    }

    // Goal unreachable — walk as close as the connected walkable allows.
    if (bestI == startI) return [];
    return _reconstruct(cameFrom, bestI, barriers);
  }

  static double _heuristic((int, int) a, (int, int) b) {
    final dx = (a.$1 - b.$1).abs();
    final dy = (a.$2 - b.$2).abs();
    // Octile distance.
    final m = min(dx, dy);
    return (dx + dy) - m + m * 0.41421356237;
  }

  static List<(int, int)> _reconstruct(
    List<int> cameFrom,
    int endI,
    Set<(int, int)> barriers,
  ) {
    final raw = <(int, int)>[];
    var cur = endI;
    while (cur >= 0) {
      raw.add((cur % _cols, cur ~/ _cols));
      cur = cameFrom[cur];
    }
    final cells = raw.reversed.toList();
    return _simplify(cells, barriers);
  }

  /// Collapse collinear / same-diagonal runs — only when the chord stays clear.
  /// Also keep waypoints that sit next to a wall so shortcuts cannot clip a
  /// stump/cliff corner that the grid path had stepped around.
  static List<(int, int)> _simplify(
    List<(int, int)> path,
    Set<(int, int)> barriers,
  ) {
    if (path.length <= 2) return path;
    bool nearWall((int, int) c) {
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          if (barriers.contains((c.$1 + dx, c.$2 + dy))) return true;
        }
      }
      return false;
    }

    final out = <(int, int)>[path.first];
    for (var i = 1; i < path.length - 1; i++) {
      final prev = out.last;
      final cur = path[i];
      final next = path[i + 1];
      final dx1 = cur.$1 - prev.$1;
      final dy1 = cur.$2 - prev.$2;
      final dx2 = next.$1 - cur.$1;
      final dy2 = next.$2 - cur.$2;
      final sameDir = dx1 == dx2 && dy1 == dy2;
      if (!sameDir || nearWall(cur) || !_lineClear(prev, next, barriers)) {
        out.add(cur);
      }
    }
    out.add(path.last);
    return out;
  }

  static void _heapPush(List<(double, int)> heap, (double, int) item) {
    heap.add(item);
    var i = heap.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (heap[p].$1 <= heap[i].$1) break;
      final tmp = heap[p];
      heap[p] = heap[i];
      heap[i] = tmp;
      i = p;
    }
  }

  static int _heapPop(List<(double, int)> heap) {
    final result = heap.first.$2;
    final last = heap.removeLast();
    if (heap.isEmpty) return result;
    heap[0] = last;
    var i = 0;
    while (true) {
      final l = (i << 1) + 1;
      final r = l + 1;
      var smallest = i;
      if (l < heap.length && heap[l].$1 < heap[smallest].$1) smallest = l;
      if (r < heap.length && heap[r].$1 < heap[smallest].$1) smallest = r;
      if (smallest == i) break;
      final tmp = heap[i];
      heap[i] = heap[smallest];
      heap[smallest] = tmp;
      i = smallest;
    }
    return result;
  }

  /// Supercover + corner checks: every cell the segment touches must be free.
  static bool _lineClear(
    (int, int) a,
    (int, int) b,
    Set<(int, int)> barriers,
  ) {
    if (barriers.contains(a) || barriers.contains(b)) return false;
    final x0 = a.$1;
    final y0 = a.$2;
    final x1 = b.$1;
    final y1 = b.$2;
    final dx = (x1 - x0).abs();
    final dy = (y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final sy = y0 < y1 ? 1 : -1;
    // Dense samples along the segment (catches thin wall clips Bresenham misses).
    final steps = max(1, max(dx, dy) * 2);
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = (x0 + (x1 - x0) * t).round();
      final y = (y0 + (y1 - y0) * t).round();
      if (barriers.contains((x, y))) return false;
    }
    // Classic Bresenham with no diagonal corner-cutting.
    var cx = x0;
    var cy = y0;
    var err = dx - dy;
    while (true) {
      if (barriers.contains((cx, cy))) return false;
      if (cx == x1 && cy == y1) return true;
      final e2 = err * 2;
      var stepX = false;
      var stepY = false;
      if (e2 > -dy) {
        err -= dy;
        stepX = true;
      }
      if (e2 < dx) {
        err += dx;
        stepY = true;
      }
      if (stepX && stepY) {
        if (barriers.contains((cx + sx, cy)) ||
            barriers.contains((cx, cy + sy))) {
          return false;
        }
      }
      if (stepX) cx += sx;
      if (stepY) cy += sy;
    }
  }

  static void _ensureTileCache(GameMap map) {
    final mapTile = map.tileSize > 0 ? map.tileSize : 32.0;
    final cell = mapTile / subdivisions;
    // Prefer Tiled-primed walls (complete). Only rebuild from live layers
    // when we have no prime yet.
    if (_tileBarriers.isNotEmpty &&
        _cols > 0 &&
        (_cell - cell).abs() < 0.01) {
      _cachedMap = map;
      return;
    }
    if (identical(_cachedMap, map) &&
        _cols > 0 &&
        _tileBarriers.isNotEmpty &&
        (_cell - cell).abs() < 0.01) {
      return;
    }
    _cachedMap = map;
    _cell = cell.toDouble();
    final size = map.getMapSize();
    _cols = max(1, (size.x / _cell).ceil());
    _rows = max(1, (size.y / _cell).ceil());
    final blocked = <(int, int)>{};
    for (final layer in map.layers) {
      for (final t in layer.tiles) {
        if (t.collisions == null || t.collisions!.isEmpty) continue;
        var shaped = false;
        final ox = t.left + t.offsetX;
        final oy = t.top + t.offsetY;
        for (final shape in t.collisions!) {
          final w = shape.size.x;
          final h = shape.size.y;
          if (w <= 0 || h <= 0) continue;
          shaped = true;
          _rasterizeRect(
            Rect.fromLTWH(ox + shape.position.x, oy + shape.position.y, w, h),
            blocked,
          );
        }
        if (!shaped) {
          _rasterizeRect(Rect.fromLTWH(ox, oy, t.width, t.height), blocked);
        }
      }
    }
    // Don't replace a good Tiled prime with a weaker live scan.
    if (blocked.length >= _tileBarriers.length) {
      _tileBarriers = blocked;
    }
  }

  static void _addDynamicSolids(
    BonfireGameInterface game,
    Set<(int, int)> barriers,
  ) {
    for (final hit in game.collisions(onlyVisible: false)) {
      if (!hit.isSolid) continue;
      final parent = hit.hitboxParent;
      if (parent is TileWithCollision ||
          parent is Building ||
          parent is CollisionMapComponent) {
        _rasterizeRect(hit.toAbsoluteRect(), barriers);
      } else if (parent is GameDecorationWithCollision) {
        // Live props (trees, bushes, lanterns…): foot only, same as TMJ props.
        final raw = hit.toAbsoluteRect();
        final foot = _decorationArtFoot(raw, parent.size);
        if (foot != null) _rasterizeRect(foot, barriers);
      }
    }
    void addHits(Iterable<ShapeHitbox> hits) {
      for (final h in hits) {
        if (h.isSolid) _rasterizeRect(h.toAbsoluteRect(), barriers);
      }
    }

    for (final b in game.query<Boulder>(onlyVisible: false)) {
      final hits = b.children.whereType<ShapeHitbox>().where((h) => h.isSolid);
      if (hits.isNotEmpty) {
        addHits(hits);
      } else {
        // onLoad not finished — still block the closed plug footprint.
        final k = b.size.x / 96.0;
        for (final r in GateArt.boulderClosedColliders) {
          _rasterizeRect(
            Rect.fromLTWH(
              b.position.x + r.left * k,
              b.position.y + r.top * k,
              r.width * k,
              r.height * k,
            ),
            barriers,
          );
        }
      }
    }
    for (final g in game.query<AbilityGate>(onlyVisible: false)) {
      addHits(g.children.whereType<ShapeHitbox>());
    }
    for (final h in game.query<HiddenPath>(onlyVisible: false)) {
      addHits(h.children.whereType<ShapeHitbox>());
    }
    for (final s in game.query<SweetrootStump>(onlyVisible: false)) {
      // Inflate a hair so A* does not hug the trunk edge and jam on physics.
      for (final h in s.children.whereType<ShapeHitbox>()) {
        if (!h.isSolid) continue;
        _rasterizeRect(h.toAbsoluteRect().inflate(2), barriers);
      }
    }
  }

  /// Props layer: keep a trunk/base that matches the art (walk under canopy).
  static Rect? _propArtFoot(Rect shape, Rect tile, String? prop) {
    final p = prop ?? '';
    // Solid set pieces — keep the authored collider.
    if (p.startsWith('crashed_ship') ||
        p == 'tent' ||
        p == 'boulder' ||
        p == 'monolith' ||
        p == 'standing_stone' ||
        p == 'fence_h' ||
        p == 'fence_v' ||
        p == 'radio_dish' ||
        p == 'crate' ||
        p == 'campfire') {
      return shape;
    }
    // Soft props: only the visible base. Canopy / mossy edges stay walkable.
    final isFoliage = p.startsWith('tree_') || p.startsWith('bush_');
    final isClutter = isFoliage ||
        p.startsWith('rock_') ||
        p == 'lantern' ||
        p == 'stump' ||
        p == 'log' ||
        p == 'signpost';
    final footH = tile.height * (isFoliage ? 0.22 : (isClutter ? 0.32 : 0.40));
    final band = Rect.fromLTRB(
      tile.left,
      tile.bottom - footH,
      tile.right,
      tile.bottom,
    );
    final clipped = shape.intersect(band);
    if (clipped.isEmpty) return null;
    // Narrow toward center so soft art edges don't seal half-tiles of grass.
    if (isClutter) {
      final cx = clipped.center.dx;
      final maxW = tile.width * (isFoliage ? 0.38 : 0.50);
      final halfW = min(clipped.width, maxW) / 2;
      return Rect.fromLTRB(
        cx - halfW,
        clipped.top,
        cx + halfW,
        clipped.bottom,
      );
    }
    return clipped;
  }

  /// Live [GameDecorationWithCollision] foot — same idea as [_propArtFoot].
  static Rect? _decorationArtFoot(Rect hit, Vector2 parentSize) {
    // Large props / multi-tile set pieces: keep most of the collider, bias down.
    if (parentSize.x >= 48 || parentSize.y >= 48) {
      final keep = max(10.0, hit.height * 0.55);
      return Rect.fromLTRB(hit.left, hit.bottom - keep, hit.right, hit.bottom);
    }
    // Single-tile clutter: trunk/base only.
    final keep = max(5.0, hit.height * 0.28);
    final cx = hit.center.dx;
    final halfW = min(hit.width, 10.0) / 2;
    return Rect.fromLTRB(
      cx - halfW,
      hit.bottom - keep,
      cx + halfW,
      hit.bottom,
    );
  }

  static void _rasterizeRect(Rect rect, Set<(int, int)> barriers) {
    // Exact Kaela feet — A* must not route through a gap WASD cannot walk
    // (slim probes opened the stump cliff lane, then click-move jammed).
    const hw = _clearW * 0.5;
    const hh = _clearH * 0.5;
    final x0 = ((rect.left - hw) / _cell).floor().clamp(0, _cols - 1);
    final y0 = ((rect.top - hh) / _cell).floor().clamp(0, _rows - 1);
    final x1 = ((rect.right + hw - 0.01) / _cell).floor().clamp(0, _cols - 1);
    final y1 = ((rect.bottom + hh - 0.01) / _cell).floor().clamp(0, _rows - 1);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final feet = Rect.fromCenter(
          center: Offset((x + 0.5) * _cell, (y + 0.5) * _cell),
          width: _clearW,
          height: _clearH,
        );
        if (feet.overlaps(rect)) {
          barriers.add((x, y));
        }
      }
    }
  }

  static (int, int) _cellOf(Vector2 world) => (
        (world.x / _cell).floor(),
        (world.y / _cell).floor(),
      );

  static (int, int) _clampCell((int, int) c) => (
        c.$1.clamp(0, _cols - 1),
        c.$2.clamp(0, _rows - 1),
      );

  static Vector2 _worldCenter((int, int) c) =>
      Vector2((c.$1 + 0.5) * _cell, (c.$2 + 0.5) * _cell);

  /// Cell center nudged away from blocked neighbors so feet can actually
  /// arrive. Opposite walls cancel (narrow corridor → stay centered).
  static Vector2 _worldCenterAwayFromWalls(
    (int, int) c,
    Set<(int, int)> barriers,
  ) {
    var p = _worldCenter(c);
    var nx = 0.0;
    var ny = 0.0;
    const ortho = <(int, int)>[(0, -1), (0, 1), (-1, 0), (1, 0)];
    for (final d in ortho) {
      if (barriers.contains((c.$1 + d.$1, c.$2 + d.$2))) {
        nx -= d.$1;
        ny -= d.$2;
      }
    }
    // Mild nudge only — 0.3*cell shoved waypoints into the far wall of a
    // one-cell lane and the follower never arrived.
    if (nx != 0 || ny != 0) {
      final len = sqrt(nx * nx + ny * ny);
      p += Vector2(nx / len, ny / len) * (_cell * 0.12);
    }
    return p;
  }

  /// Closest free cell to [origin], breaking ties toward [preferNear] (world).
  static (int, int)? _nearestWalkable(
    (int, int) origin,
    Set<(int, int)> barriers, {
    Vector2? preferNear,
  }) {
    (int, int)? best;
    var bestD = double.infinity;
    final px = preferNear?.x ?? (origin.$1 + 0.5) * _cell;
    final py = preferNear?.y ?? (origin.$2 + 0.5) * _cell;
    for (var r = 0; r <= 24; r++) {
      var foundInRing = false;
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (r > 0 && dx.abs() != r && dy.abs() != r) continue;
          final c = (origin.$1 + dx, origin.$2 + dy);
          if (c.$1 < 0 || c.$2 < 0 || c.$1 >= _cols || c.$2 >= _rows) {
            continue;
          }
          if (barriers.contains(c)) continue;
          foundInRing = true;
          final cx = (c.$1 + 0.5) * _cell;
          final cy = (c.$2 + 0.5) * _cell;
          final d = (cx - px) * (cx - px) + (cy - py) * (cy - py);
          if (d < bestD) {
            bestD = d;
            best = c;
          }
        }
      }
      // First ring with any free cell: pick closest to the click in that
      // ring (and any earlier — only r=0 then growing). Stop once we have
      // a candidate at this radius so we don't jump to the far side of a
      // thick wall unless the near side has no walkable.
      if (foundInRing && best != null) return best;
    }
    return best;
  }
}
