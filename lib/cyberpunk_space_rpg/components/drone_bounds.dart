import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:bonfire/util/collision_game_component.dart';

/// Keeps flying enemies inside the map, near their spawn, and out of solid
/// wall / building collision so knockback and chase can't strand them.
class DroneBounds {
  DroneBounds._();

  /// Try to apply [delta]. Slides on one axis if the full step is blocked.
  /// Returns false if nothing moved.
  static bool moveBy(
    GameDecoration drone,
    Vector2 delta, {
    required Vector2 origin,
    required double leash,
    double pad = 24,
  }) {
    if (delta.length2 < 1e-10) return false;
    final cur = drone.position;
    final full = cur + delta;
    if (_isFree(drone, full, origin: origin, leash: leash, pad: pad)) {
      drone.position.setFrom(full);
      return true;
    }
    final onlyX = Vector2(cur.x + delta.x, cur.y);
    if (_isFree(drone, onlyX, origin: origin, leash: leash, pad: pad)) {
      drone.position.setFrom(onlyX);
      return true;
    }
    final onlyY = Vector2(cur.x, cur.y + delta.y);
    if (_isFree(drone, onlyY, origin: origin, leash: leash, pad: pad)) {
      drone.position.setFrom(onlyY);
      return true;
    }
    return false;
  }

  /// Chase step: axis slide, then sideways / diagonal slips so bosses and
  /// drones don't hard-stop on corners, building feet, or the leash rim.
  static bool chaseStep(
    GameDecoration drone,
    Vector2 delta, {
    required Vector2 origin,
    required double leash,
    double pad = 24,
  }) {
    if (moveBy(drone, delta, origin: origin, leash: leash, pad: pad)) {
      return true;
    }
    if (delta.length2 < 1e-10) return false;
    final n = delta.normalized();
    final len = delta.length;
    final left = Vector2(-n.y, n.x);
    final right = Vector2(n.y, -n.x);
    for (final scale in [1.0, 1.7, 2.4]) {
      for (final side in [left, right]) {
        if (moveBy(drone, side * (len * scale),
            origin: origin, leash: leash, pad: pad)) {
          return true;
        }
      }
    }
    for (final side in [left, right]) {
      final slip = (n * 0.55 + side).normalized() * len;
      if (moveBy(drone, slip, origin: origin, leash: leash, pad: pad)) {
        return true;
      }
    }
    return false;
  }

  /// Pull back onto the map / leash if somehow already invalid.
  static void rescue(
    GameDecoration drone, {
    required Vector2 origin,
    required double leash,
    double pad = 24,
  }) {
    if (_isFree(drone, drone.position, origin: origin, leash: leash, pad: pad)) {
      return;
    }
    if (_isFree(drone, origin, origin: origin, leash: leash, pad: pad)) {
      drone.position.setFrom(origin.clone());
      return;
    }
    final mapSize = drone.gameRef.map.getMapSize();
    drone.position.setFrom(Vector2(
      origin.x.clamp(pad, max(pad, mapSize.x - drone.size.x - pad)),
      origin.y.clamp(pad, max(pad, mapSize.y - drone.size.y - pad)),
    ));
  }

  static bool _isFree(
    GameDecoration drone,
    Vector2 topLeft, {
    required Vector2 origin,
    required double leash,
    required double pad,
  }) {
    final mapSize = drone.gameRef.map.getMapSize();
    final maxX = max(pad, mapSize.x - drone.size.x - pad);
    final maxY = max(pad, mapSize.y - drone.size.y - pad);
    if (topLeft.x < pad ||
        topLeft.y < pad ||
        topLeft.x > maxX ||
        topLeft.y > maxY) {
      return false;
    }
    final fromOrigin = (topLeft + drone.size / 2) - (origin + drone.size / 2);
    if (fromOrigin.length > leash) return false;
    return !_hitsSolid(drone, topLeft);
  }

  static bool _hitsSolid(GameDecoration drone, Vector2 topLeft) {
    final probe = Rect.fromLTWH(
      topLeft.x + 3,
      topLeft.y + 3,
      max(4, drone.size.x - 6),
      max(4, drone.size.y - 6),
    );
    for (final hit in drone.gameRef.collisions(onlyVisible: true)) {
      if (!hit.isSolid) continue;
      final parent = hit.hitboxParent;
      if (identical(parent, drone)) continue;
      // Tile walls, collision objects, buildings — not other drones.
      // Skip tiny ground clutter (1-tile props): they made chase stutter when
      // dynamicAbove decorations filled the map with solid boxes.
      final wall = parent is TileWithCollision ||
          parent is CollisionMapComponent ||
          (parent is GameDecorationWithCollision &&
              (parent.size.x >= 40 || parent.size.y >= 40));
      if (!wall) continue;
      final aabb = hit.aabb;
      final hr = Rect.fromLTRB(aabb.min.x, aabb.min.y, aabb.max.x, aabb.max.y);
      if (probe.overlaps(hr)) return true;
    }
    return false;
  }
}
