import 'dart:collection';
import 'dart:convert';

/// A rect in room tiles: [x, y, w, h] with the origin at the top left.
class RoomRect {
  final int x, y, w, h;
  const RoomRect(this.x, this.y, this.w, this.h);

  static RoomRect parse(Object? v) {
    if (v is! List || v.length < 4) throw FormatException('bad rect $v');
    final n = [for (final e in v.take(4)) (e as num).toInt()];
    return RoomRect(n[0], n[1], n[2], n[3]);
  }

  bool contains(int tx, int ty) => tx >= x && tx < x + w && ty >= y && ty < y + h;

  Iterable<(int, int)> get tiles sync* {
    for (var j = y; j < y + h; j++) {
      for (var i = x; i < x + w; i++) {
        yield (i, j);
      }
    }
  }

  @override
  String toString() => '[$x, $y, $w, $h]';
}

/// A static NPC standing idle in a room.
class RoomNpc {
  final String name, sprite, role;
  final int tx, ty;
  const RoomNpc(this.name, this.sprite, this.tx, this.ty, this.role);
}

/// An E-press spot. The player must stand on or next to [rect] (4-neighbour)
/// and face it.
class RoomSpot {
  final String id, kind, note;
  final RoomRect rect;
  const RoomSpot(this.id, this.rect, this.kind, this.note);

  static const kinds = {
    'npc', 'rest', 'shop', 'errand', 'lore', 'clue', 'stash', 'journal', 'map', 'note', 'flavour',
  };
}

class RoomLight {
  final int tx, ty;
  final String kind; // warm | fire | neon | cyan
  const RoomLight(this.tx, this.ty, this.kind);
}

/// Room data for an enterable building interior (#31), loaded from
/// `assets/images/interiors/<id>.json` next to its 512x288 background.
/// Schema: see `assets/images/interiors/README.md`.
class RoomData {
  final String id, title, image;
  final int cols, rows, tile;
  final List<RoomRect> collision;
  final RoomRect door;
  final (int, int) spawn;
  final List<RoomNpc> npcs;
  final List<RoomSpot> spots;
  final List<RoomLight> lights;

  const RoomData({
    required this.id,
    required this.title,
    required this.image,
    required this.cols,
    required this.rows,
    required this.tile,
    required this.collision,
    required this.door,
    required this.spawn,
    required this.npcs,
    required this.spots,
    required this.lights,
  });

  static String assetFor(String id) => 'assets/images/interiors/$id.json';

  /// Flame image path (relative to assets/images/).
  String get imagePath => 'interiors/$image';

  double get widthPx => (cols * tile).toDouble();
  double get heightPx => (rows * tile).toDouble();

  factory RoomData.parse(String source) {
    final m = jsonDecode(source) as Map<String, dynamic>;
    final size = m['size'] as List? ?? const [16, 9];
    final spawn = m['spawn'] as List;
    return RoomData(
      id: m['id'] as String,
      title: (m['title'] ?? m['id']) as String,
      image: (m['image'] ?? '${m['id']}.png') as String,
      cols: (size[0] as num).toInt(),
      rows: (size[1] as num).toInt(),
      tile: (m['tile'] as num? ?? 32).toInt(),
      collision: [for (final r in (m['collision'] as List? ?? const [])) RoomRect.parse(r)],
      door: RoomRect.parse(m['door']),
      spawn: ((spawn[0] as num).toInt(), (spawn[1] as num).toInt()),
      npcs: [
        for (final n in (m['npcs'] as List? ?? const []))
          RoomNpc(
            n['name'] as String,
            (n['sprite'] ?? n['name']) as String,
            ((n['tile'] as List)[0] as num).toInt(),
            ((n['tile'] as List)[1] as num).toInt(),
            (n['role'] ?? '') as String,
          ),
      ],
      spots: [
        for (final s in (m['interact'] as List? ?? const []))
          RoomSpot(s['id'] as String, RoomRect.parse(s['rect']), s['kind'] as String,
              (s['note'] ?? '') as String),
      ],
      lights: [
        for (final l in (m['lights'] as List? ?? const []))
          RoomLight(((l['tile'] as List)[0] as num).toInt(), ((l['tile'] as List)[1] as num).toInt(),
              (l['kind'] ?? 'warm') as String),
      ],
    );
  }

  bool inBounds(int tx, int ty) => tx >= 0 && ty >= 0 && tx < cols && ty < rows;

  /// Walls/furniture or an NPC standing there.
  bool solid(int tx, int ty) =>
      !inBounds(tx, ty) ||
      collision.any((r) => r.contains(tx, ty)) ||
      npcs.any((n) => n.tx == tx && n.ty == ty);

  /// Floor tiles reachable from [spawn] (4-neighbour flood fill).
  Set<(int, int)> reachable() {
    final seen = <(int, int)>{};
    if (solid(spawn.$1, spawn.$2)) return seen;
    final q = Queue<(int, int)>()..add(spawn);
    seen.add(spawn);
    while (q.isNotEmpty) {
      final (x, y) = q.removeFirst();
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final n = (x + dx, y + dy);
        if (seen.contains(n) || solid(n.$1, n.$2)) continue;
        seen.add(n);
        q.add(n);
      }
    }
    return seen;
  }

  /// Floor tiles from which [spot] can be used: on it or 4-next to it.
  Iterable<(int, int)> approachTiles(RoomRect rect) sync* {
    final out = <(int, int)>{};
    for (final (x, y) in rect.tiles) {
      for (final (dx, dy) in const [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final n = (x + dx, y + dy);
        if ((dx != 0 || dy != 0) && rect.contains(n.$1, n.$2)) continue;
        if (!solid(n.$1, n.$2) && out.add(n)) yield n;
      }
    }
  }

  /// Spots the player can actually walk up to.
  bool spotReachable(RoomSpot s, [Set<(int, int)>? floor]) {
    final f = floor ?? reachable();
    return approachTiles(s.rect).any(f.contains);
  }

  /// Direction from the player's tile into [rect]: null when not adjacent.
  /// (0, 0) = standing on it. Otherwise one of (±1, 0) / (0, ±1).
  (int, int)? stepInto(RoomRect rect, int tx, int ty) {
    if (rect.contains(tx, ty)) return (0, 0);
    for (final d in const [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
      if (rect.contains(tx + d.$1, ty + d.$2)) return d;
    }
    return null;
  }
}
