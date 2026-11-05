import 'dart:convert';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, kDebugMode;
import 'package:flutter/services.dart';

import '../creatures/interaction.dart';
import 'game_debug.dart';

/// One tile-layer cell under a Shift+click (debug builds only).
class DebugTileHit {
  final String layer;
  final String tileset;
  final int tileId;
  final String? propName;
  final String? objectName;
  final int tileX;
  final int tileY;

  const DebugTileHit({
    required this.layer,
    required this.tileset,
    required this.tileId,
    required this.tileX,
    required this.tileY,
    this.propName,
    this.objectName,
  });

  /// Compact label: tileset#id · layer · prop/object/tile.
  String get label {
    final name = propName ?? objectName;
    final who = (name != null && name.isNotEmpty) ? name : 'tile $tileId';
    return '$tileset#$tileId · $layer · $who';
  }
}

/// Shift+click walkable (and any) ground/prop tiles to toast their Tiled ids.
///
/// Only runs under [kDebugMode] + [GameDebug.isOn]. Primes from the same TMJ
/// asset as [ClickPathfinder] so local tile ids / `prop` names match the editor.
class DebugTileInspect {
  DebugTileInspect._();

  static const _tile = 32.0;
  static const _flipMask = 0x1FFFFFFF;

  /// Last Shift+click readout for the DEBUG HUD.
  static final lastLabel = ValueNotifier<String?>(null);

  static int _mapW = 0;
  static int _mapH = 0;
  static final List<_Ts> _tilesets = [];
  static final List<_Layer> _layers = [];
  /// Gameplay objects keyed loosely by tile cell for "object name if any".
  static final Map<(int, int), String> _objectsByCell = {};

  static void clear() {
    lastLabel.value = null;
    _mapW = 0;
    _mapH = 0;
    _tilesets.clear();
    _layers.clear();
    _objectsByCell.clear();
  }

  /// Load tile-layer + tileset metadata from a Tiled map asset.
  static Future<void> primeFromAsset(String mapPath) async {
    if (!kDebugMode) return;
    final asset =
        mapPath.startsWith('assets/') ? mapPath : 'assets/images/$mapPath';
    final raw = await rootBundle.loadString(asset);
    loadFromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Pure parse path (also used by unit tests).
  static void loadFromJson(Map<String, dynamic> data) {
    clear();
    _mapW = (data['width'] as num?)?.toInt() ?? 0;
    _mapH = (data['height'] as num?)?.toInt() ?? 0;

    for (final ts in (data['tilesets'] as List? ?? const [])) {
      if (ts is! Map) continue;
      final name = ts['name']?.toString() ?? 'tileset';
      final first = (ts['firstgid'] as num?)?.toInt() ?? 1;
      final count = (ts['tilecount'] as num?)?.toInt() ?? 0;
      final meta = <int, _TileMeta>{};
      for (final tile in (ts['tiles'] as List? ?? const [])) {
        if (tile is! Map) continue;
        final id = (tile['id'] as num?)?.toInt();
        if (id == null) continue;
        String? prop;
        for (final p in (tile['properties'] as List? ?? const [])) {
          if (p is Map && p['name'] == 'prop') {
            prop = p['value']?.toString();
            break;
          }
        }
        String? objectName;
        final objs = tile['objectgroup'] is Map
            ? (tile['objectgroup'] as Map)['objects'] as List? ?? const []
            : const [];
        for (final o in objs) {
          if (o is! Map) continue;
          final n = o['name']?.toString() ?? '';
          if (n.isNotEmpty && n.toLowerCase() != 'collision') {
            objectName = n;
            break;
          }
        }
        // Tiled tile type/class as a last-resort object name.
        final type = tile['type']?.toString() ?? tile['class']?.toString();
        if ((objectName == null || objectName.isEmpty) &&
            type != null &&
            type.isNotEmpty) {
          objectName = type;
        }
        meta[id] = _TileMeta(propName: prop, objectName: objectName);
      }
      _tilesets.add(_Ts(name: name, firstGid: first, tileCount: count, meta: meta));
    }
    // Highest firstgid first for resolve.
    _tilesets.sort((a, b) => b.firstGid.compareTo(a.firstGid));

    for (final layer in (data['layers'] as List? ?? const [])) {
      if (layer is! Map) continue;
      if (layer['type'] == 'tilelayer') {
        final grid = layer['data'];
        if (grid is! List) continue;
        _layers.add(_Layer(
          name: layer['name']?.toString() ?? 'layer',
          width: (layer['width'] as num?)?.toInt() ?? _mapW,
          data: [
            for (final g in grid) ((g as num?)?.toInt() ?? 0) & _flipMask,
          ],
        ));
      } else if (layer['type'] == 'objectgroup') {
        for (final o in (layer['objects'] as List? ?? const [])) {
          if (o is! Map) continue;
          final name = o['name']?.toString() ?? '';
          if (name.isEmpty) continue;
          final x = (o['x'] as num?)?.toDouble() ?? 0;
          final y = (o['y'] as num?)?.toDouble() ?? 0;
          final w = (o['width'] as num?)?.toDouble() ?? _tile;
          final h = (o['height'] as num?)?.toDouble() ?? _tile;
          // Tile objects are bottom-left anchored in Tiled.
          final cx = ((x + w / 2) / _tile).floor();
          final cy = ((y - h / 2) / _tile).floor();
          _objectsByCell[(cx, cy)] = name;
          // Also stamp the top-left cell for point-like markers.
          _objectsByCell[((x / _tile).floor(), (y / _tile).floor())] = name;
        }
      }
    }
  }

  /// Props layer first (drawn above), then remaining tile layers top→bottom.
  static List<DebugTileHit> hitsAt(Vector2 world) {
    if (_layers.isEmpty || _mapW <= 0) return const [];
    final tx = (world.x / _tile).floor();
    final ty = (world.y / _tile).floor();
    if (tx < 0 || ty < 0 || tx >= _mapW || ty >= _mapH) return const [];

    final ordered = [
      ..._layers.where((l) => l.name == 'props'),
      ..._layers.where((l) => l.name != 'props'),
    ];

    final out = <DebugTileHit>[];
    final seen = <String>{};
    for (final layer in ordered) {
      if (tx >= layer.width) continue;
      final i = ty * layer.width + tx;
      if (i < 0 || i >= layer.data.length) continue;
      final gid = layer.data[i];
      if (gid == 0) continue;
      final ts = _resolveTileset(gid);
      if (ts == null) continue;
      final local = gid - ts.firstGid;
      final meta = ts.meta[local];
      final key = '${layer.name}:$gid';
      if (!seen.add(key)) continue;
      out.add(DebugTileHit(
        layer: layer.name,
        tileset: ts.name,
        tileId: local,
        tileX: tx,
        tileY: ty,
        propName: meta?.propName,
        objectName: meta?.objectName ?? _objectsByCell[(tx, ty)],
      ));
    }
    return out;
  }

  static _Ts? _resolveTileset(int gid) {
    for (final ts in _tilesets) {
      if (gid >= ts.firstGid) {
        if (ts.tileCount > 0 && gid >= ts.firstGid + ts.tileCount) continue;
        return ts;
      }
    }
    return null;
  }

  /// Shift+click handler. Returns true when the click was consumed (no walk).
  static bool tryHandleWorldClick(Vector2 world) {
    if (!kDebugMode || !GameDebug.isOn) return false;
    if (!HardwareKeyboard.instance.isShiftPressed) return false;

    final hits = hitsAt(world);
    if (hits.isEmpty) {
      lastLabel.value = 'empty · tile '
          '${(world.x / _tile).floor()}, ${(world.y / _tile).floor()}';
      GameToast.show(
        'TILE',
        body: lastLabel.value!,
        compact: true,
        color: const Color(0xFF88AACC),
      );
      return true;
    }

    // Prefer a named prop when present; otherwise the topmost hit.
    final named = hits.where(
        (h) => (h.propName != null && h.propName!.isNotEmpty) ||
            (h.objectName != null && h.objectName!.isNotEmpty));
    final primary = named.isNotEmpty ? named.first : hits.first;
    final extras = hits.length > 1
        ? ' (+${hits.length - 1} under)'
        : '';
    final label = '${primary.label}$extras';
    lastLabel.value = label;
    GameToast.show(
      'TILE',
      body: label,
      compact: true,
      color: const Color(0xFF00FF88),
    );
    return true;
  }
}

class _Ts {
  final String name;
  final int firstGid;
  final int tileCount;
  final Map<int, _TileMeta> meta;
  const _Ts({
    required this.name,
    required this.firstGid,
    required this.tileCount,
    required this.meta,
  });
}

class _TileMeta {
  final String? propName;
  final String? objectName;
  const _TileMeta({this.propName, this.objectName});
}

class _Layer {
  final String name;
  final int width;
  final List<int> data;
  const _Layer({required this.name, required this.width, required this.data});
}
