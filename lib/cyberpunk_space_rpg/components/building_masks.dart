import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'building.dart';
import '../creatures/obstacle_masks.dart';

/// Mutable building footprint store. Defaults match [buildingDefs]; Save
/// writes `tools/buildings/<id>.json` and the matching tile in
/// `tools/buildings/buildings.tsj`.
class BuildingMasks {
  BuildingMasks._();

  static const toolsDir = 'tools/buildings';

  /// Write current [BuildingDef.collision] for [id]. Returns error or null.
  static String? savedPath;

  static Future<String?> save(String id) async {
    if (kIsWeb) return 'save not available on web';
    savedPath = null;
    final def = buildingDefs[id];
    if (def == null) return 'unknown building "$id"';
    try {
      final root = ObstacleMasks.projectRoot();
      if (root == null) {
        return 'cannot find project root (cwd=${Directory.current.path})';
      }
      final jsonPath = '$root/$toolsDir/$id.json';
      final tsjPath = '$root/$toolsDir/buildings.tsj';
      await _patchJson(jsonPath, def);
      await _patchTsj(tsjPath, id, def.collision);
      savedPath = jsonPath;
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<void> _patchJson(String path, BuildingDef def) async {
    final file = File(path);
    final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final c = def.collision;
    j['collision'] = [
      {
        'x': _num(c.left),
        'y': _num(c.top),
        'w': _num(c.width),
        'h': _num(c.height),
      }
    ];
    await file.writeAsString('${const JsonEncoder.withIndent('  ').convert(j)}\n');
  }

  static Future<void> _patchTsj(String path, String id, Rect collision) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final tiles = j['tiles'];
    if (tiles is! List) return;
    for (final tile in tiles) {
      if (tile is! Map) continue;
      final props = tile['properties'];
      if (props is! List) continue;
      var match = false;
      for (final p in props) {
        if (p is Map && p['name'] == 'building' && p['value'] == id) {
          match = true;
          break;
        }
      }
      if (!match) continue;
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
          {
            'id': 1,
            'name': 'collision',
            'type': 'collision',
            'x': _num(collision.left),
            'y': _num(collision.top),
            'width': _num(collision.width),
            'height': _num(collision.height),
            'rotation': 0,
            'visible': true,
          }
        ],
      };
      break;
    }
    await file.writeAsString('${const JsonEncoder.withIndent(' ').convert(j)}\n');
  }

  static num _num(double v) => v == v.roundToDouble() ? v.round() : v;

  /// Load collision rects from tools JSON into live [buildingDefs] (optional).
  static void loadFromDisk({String? root}) {
    if (kIsWeb) return;
    final base = root ?? ObstacleMasks.projectRoot();
    if (base == null) return;
    for (final id in buildingDefs.keys) {
      final path = '$base/$toolsDir/$id.json';
      final f = File(path);
      if (!f.existsSync()) continue;
      final j = jsonDecode(f.readAsStringSync()) as Map;
      final list = j['collision'];
      if (list is! List || list.isEmpty) continue;
      final c = list.first;
      if (c is! Map) continue;
      buildingDefs[id]!.collision = Rect.fromLTWH(
        (c['x'] as num).toDouble(),
        (c['y'] as num).toDouble(),
        (c['w'] as num).toDouble(),
        (c['h'] as num).toDouble(),
      );
    }
  }
}
