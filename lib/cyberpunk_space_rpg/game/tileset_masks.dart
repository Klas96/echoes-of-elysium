import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../creatures/obstacle_masks.dart';
import 'game_state.dart';

/// Edit/save per-tile collision rects in `tools/tilesets/<name>.tsj` (+ `.tsx`)
/// and embedded copies inside `assets/images/maps/world*.tmj`.
class TilesetMasks {
  TilesetMasks._();

  static String? savedPath;

  /// Primary ground/prop tileset for the current overworld map.
  static String tilesetForLevel([int? level]) {
    final lv = level ?? GameState.level;
    return switch (lv) {
      1 => 'woods',
      2 => 'city',
      3 => 'cyberpunk',
      4 => 'core',
      5 => 'city',
      _ => 'woods',
    };
  }

  static String toolsTsj(String tileset) =>
      '${ObstacleMasks.projectRoot()}/tools/tilesets/$tileset.tsj';

  static String toolsTsx(String tileset) =>
      '${ObstacleMasks.projectRoot()}/tools/tilesets/$tileset.tsx';

  static final Map<String, Map> _tsjCache = {};

  static Map? _cachedTsj(String tileset) {
    final root = ObstacleMasks.projectRoot();
    if (root == null) return null;
    final path = '$root/tools/tilesets/$tileset.tsj';
    final hit = _tsjCache[path];
    if (hit != null) return hit;
    final f = File(path);
    if (!f.existsSync()) return null;
    final j = jsonDecode(f.readAsStringSync());
    if (j is! Map) return null;
    return _tsjCache[path] = Map<dynamic, dynamic>.from(j);
  }

  /// Drop cached `.tsj` after a successful save so the next resolve sees disk.
  static void clearTsjCache([String? tileset]) {
    if (tileset == null) {
      _tsjCache.clear();
      return;
    }
    final root = ObstacleMasks.projectRoot();
    if (root == null) return;
    _tsjCache.remove('$root/tools/tilesets/$tileset.tsj');
  }

  /// Find tileset tile id by optional [propName] + shape similarity to [rects].
  static int? resolveTileId({
    required String tileset,
    String? propName,
    required List<Rect> rects,
  }) {
    final j = _cachedTsj(tileset);
    if (j == null) return null;
    final tiles = j['tiles'];
    if (tiles is! List) return null;

    int? bestId;
    var bestScore = double.infinity;
    for (final t in tiles) {
      if (t is! Map) continue;
      final id = (t['id'] as num?)?.toInt();
      if (id == null) continue;
      final props = {
        for (final p in (t['properties'] as List? ?? const []))
          if (p is Map) p['name']: p['value'],
      };
      if (propName != null && propName.isNotEmpty && props['prop'] != propName) {
        continue;
      }
      final objs =
          (t['objectgroup'] is Map) ? (t['objectgroup'] as Map)['objects'] : null;
      if (objs is! List || objs.isEmpty) continue;
      final tileRects = <Rect>[
        for (final o in objs)
          if (o is Map)
            Rect.fromLTWH(
              (o['x'] as num?)?.toDouble() ?? 0,
              (o['y'] as num?)?.toDouble() ?? 0,
              (o['width'] as num?)?.toDouble() ?? 0,
              (o['height'] as num?)?.toDouble() ?? 0,
            ),
      ];
      final score = _rectSetDistance(rects, tileRects);
      if (score < bestScore) {
        bestScore = score;
        bestId = id;
      }
    }
    // Require a vaguely plausible match (sum of corner errors).
    if (bestId == null || bestScore > 80) return null;
    return bestId;
  }

  static double _rectSetDistance(List<Rect> a, List<Rect> b) {
    if (a.isEmpty || b.isEmpty) return 1e9;
    if (a.length != b.length) {
      // Still allow: compare first rects only.
      return _rectDistance(a.first, b.first) + (a.length - b.length).abs() * 20;
    }
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += _rectDistance(a[i], b[i]);
    }
    return sum;
  }

  static double _rectDistance(Rect a, Rect b) =>
      (a.left - b.left).abs() +
      (a.top - b.top).abs() +
      (a.width - b.width).abs() +
      (a.height - b.height).abs();

  /// Write [rects] onto tile [tileId] in tools tsj/tsx + all world*.tmj embeds.
  static Future<String?> save({
    required String tileset,
    required int tileId,
    required List<Rect> rects,
  }) async {
    if (kIsWeb) return 'save not available on web';
    savedPath = null;
    try {
      final root = ObstacleMasks.projectRoot();
      if (root == null) return 'cannot find project root';
      final tsj = '$root/tools/tilesets/$tileset.tsj';
      final tsx = '$root/tools/tilesets/$tileset.tsx';
      await _patchTsj(tsj, tileId, rects);
      if (File(tsx).existsSync()) await _patchTsx(tsx, tileId, rects);
      for (final map in ['world', 'world2', 'world3', 'world4', 'world5']) {
        final tmj = '$root/assets/images/maps/$map.tmj';
        if (File(tmj).existsSync()) {
          await _patchTmj(tmj, tileset, tileId, rects);
        }
      }
      savedPath = tsj;
      clearTsjCache(tileset);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<void> _patchTsj(String path, int tileId, List<Rect> rects) async {
    final j = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    final tiles = j['tiles'];
    if (tiles is! List) throw StateError('no tiles in $path');
    Map? tile;
    for (final t in tiles) {
      if (t is Map && (t['id'] as num?)?.toInt() == tileId) {
        tile = t;
        break;
      }
    }
    if (tile == null) throw StateError('tile $tileId missing in $path');
    _setObjectGroup(tile, rects);
    // Ensure collides property.
    final props = List<Map>.from((tile['properties'] as List? ?? const []).whereType<Map>());
    props.removeWhere((p) => p['name'] == 'collides');
    if (rects.isNotEmpty) {
      props.insert(0, {'name': 'collides', 'type': 'bool', 'value': true});
    }
    tile['properties'] = props;
    await File(path).writeAsString('${const JsonEncoder.withIndent(' ').convert(j)}\n');
  }

  static void _setObjectGroup(Map tile, List<Rect> rects) {
    if (rects.isEmpty) {
      tile.remove('objectgroup');
      return;
    }
    tile['objectgroup'] = {
      'draworder': 'index',
      'id': 2,
      'name': '',
      'opacity': 1,
      'type': 'objectgroup',
      'visible': true,
      'x': 0,
      'y': 0,
      'objects': [
        for (var i = 0; i < rects.length; i++)
          {
            'id': i + 1,
            'name': '',
            'type': 'collision',
            'x': _n(rects[i].left),
            'y': _n(rects[i].top),
            'width': _n(rects[i].width),
            'height': _n(rects[i].height),
            'rotation': 0,
            'visible': true,
          }
      ],
    };
  }

  static Future<void> _patchTsx(String path, int tileId, List<Rect> rects) async {
    var s = await File(path).readAsString();
    final pat = RegExp(
      '<tile id="$tileId">([\\s\\S]*?)</tile>',
    );
    final m = pat.firstMatch(s);
    if (m == null) return;
    final body = m.group(1)!;
    // Keep non-collides properties.
    final propLines = RegExp(r'<property [^/]*/>')
        .allMatches(body)
        .map((x) => x.group(0)!)
        .where((l) => !l.contains('name="collides"'))
        .toList();
    final buf = StringBuffer('\n');
    buf.writeln('  <properties>');
    if (rects.isNotEmpty) {
      buf.writeln('   <property name="collides" type="bool" value="true" />');
    }
    for (final l in propLines) {
      buf.writeln('   $l');
    }
    buf.writeln('  </properties>');
    if (rects.isNotEmpty) {
      buf.writeln('  <objectgroup draworder="index" id="2">');
      for (var i = 0; i < rects.length; i++) {
        final r = rects[i];
        buf.writeln(
            '   <object id="${i + 1}" type="collision" x="${_n(r.left)}" y="${_n(r.top)}" '
            'width="${_n(r.width)}" height="${_n(r.height)}" rotation="0" />');
      }
      buf.writeln('  </objectgroup>');
    }
    buf.write(' ');
    s = s.replaceFirst(pat, '<tile id="$tileId">${buf}</tile>');
    await File(path).writeAsString(s);
  }

  static Future<void> _patchTmj(
      String path, String tileset, int tileId, List<Rect> rects) async {
    final j = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    final sets = j['tilesets'];
    if (sets is! List) return;
    var touched = false;
    for (final ts in sets) {
      if (ts is! Map) continue;
      if (ts['name'] != tileset) continue;
      final tiles = ts['tiles'];
      if (tiles is! List) continue;
      for (final t in tiles) {
        if (t is! Map) continue;
        if ((t['id'] as num?)?.toInt() != tileId) continue;
        _setObjectGroup(t, rects);
        final props =
            List<Map>.from((t['properties'] as List? ?? const []).whereType<Map>());
        props.removeWhere((p) => p['name'] == 'collides');
        if (rects.isNotEmpty) {
          props.insert(0, {'name': 'collides', 'type': 'bool', 'value': true});
        }
        t['properties'] = props;
        touched = true;
        break;
      }
    }
    if (touched) {
      await File(path)
          .writeAsString('${const JsonEncoder.withIndent(' ').convert(j)}\n');
    }
  }

  static num _n(double v) {
    final r = (v * 100).round() / 100;
    return r == r.roundToDouble() ? r.round() : r;
  }
}
