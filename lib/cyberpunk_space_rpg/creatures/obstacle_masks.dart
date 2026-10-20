import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Runtime collider store for ability-gate props. Designer JSON under
/// `assets/images/obstacles/` is the source of truth; [GateArt] /
/// [HiddenPath] getters read from here. The debug mask editor mutates and
/// [save] writes back to disk (desktop / `flutter run` from repo root).
enum ObstacleMaskId { boulder, bramble, grotto }

class ObstacleMasks {
  ObstacleMasks._();

  static const assetDir = 'assets/images/obstacles';

  /// Defaults match the checked-in JSON (and former Dart consts).
  // Full 3×2 footprint when closed — a top gap let feet slip past nook chokes.
  static List<Rect> boulderClosed = [const Rect.fromLTWH(0, 0, 96, 64)];
  static List<Rect> boulderOpen = [const Rect.fromLTWH(64, 30, 28, 26)];
  static List<Rect> brambleClosed = [const Rect.fromLTWH(4, 16, 56, 46)];
  static List<Rect> brambleOpen = [
    const Rect.fromLTWH(1, 39, 15, 22),
    const Rect.fromLTWH(48, 39, 15, 22),
  ];
  static List<Rect> grottoClosed = [
    const Rect.fromLTWH(16, 3, 19, 30),
    const Rect.fromLTWH(58, 3, 19, 30),
    const Rect.fromLTWH(35, 3, 23, 10),
    const Rect.fromLTWH(14, 33, 65, 29),
    const Rect.fromLTWH(35, 13, 23, 20),
  ];
  static List<Rect> grottoOpen = [
    const Rect.fromLTWH(16, 3, 19, 30),
    const Rect.fromLTWH(58, 3, 19, 30),
    const Rect.fromLTWH(35, 3, 23, 10),
    const Rect.fromLTWH(14, 33, 65, 29),
    const Rect.fromLTWH(35, 13, 23, 20),
  ];

  static bool loaded = false;
  static Future<void>? _loading;

  static List<Rect> closed(ObstacleMaskId id) => switch (id) {
        ObstacleMaskId.boulder => boulderClosed,
        ObstacleMaskId.bramble => brambleClosed,
        ObstacleMaskId.grotto => grottoClosed,
      };

  static List<Rect> open(ObstacleMaskId id) => switch (id) {
        ObstacleMaskId.boulder => boulderOpen,
        ObstacleMaskId.bramble => brambleOpen,
        ObstacleMaskId.grotto => grottoOpen,
      };

  static void setClosed(ObstacleMaskId id, List<Rect> rects) {
    switch (id) {
      case ObstacleMaskId.boulder:
        boulderClosed = List.of(rects);
      case ObstacleMaskId.bramble:
        brambleClosed = List.of(rects);
      case ObstacleMaskId.grotto:
        grottoClosed = List.of(rects);
    }
  }

  static void setOpen(ObstacleMaskId id, List<Rect> rects) {
    switch (id) {
      case ObstacleMaskId.boulder:
        boulderOpen = List.of(rects);
      case ObstacleMaskId.bramble:
        brambleOpen = List.of(rects);
      case ObstacleMaskId.grotto:
        grottoOpen = List.of(rects);
    }
  }

  static void setRects(ObstacleMaskId id, {required bool openState, required List<Rect> rects}) {
    if (openState) {
      setOpen(id, rects);
    } else {
      setClosed(id, rects);
    }
  }

  static List<Rect> rects(ObstacleMaskId id, {required bool openState}) =>
      openState ? open(id) : closed(id);

  /// Parse `[x,y,w,h]` arrays into [Rect]s.
  static List<Rect> rectsFromJson(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Rect>[];
    for (final e in raw) {
      if (e is! List || e.length < 4) continue;
      out.add(Rect.fromLTWH(
        (e[0] as num).toDouble(),
        (e[1] as num).toDouble(),
        (e[2] as num).toDouble(),
        (e[3] as num).toDouble(),
      ));
    }
    return out;
  }

  static List<List<num>> rectsToJson(List<Rect> rects) => [
        for (final r in rects)
          [r.left, r.top, r.width, r.height]
              .map((n) => n == n.roundToDouble() ? n.round() : n)
              .toList(),
      ];

  static String assetFile(ObstacleMaskId id) => switch (id) {
        ObstacleMaskId.boulder => 'road_boulder.json',
        ObstacleMaskId.bramble => 'bramble_closed.json', // closed file; open is separate
        ObstacleMaskId.grotto => 'pond_grotto.json',
      };

  /// Apply parsed maps (bundle or disk). Bramble open lives in a second file.
  static void applyParsed({
    required Map boulder,
    required Map brambleClosedJson,
    required Map brambleOpenJson,
    required Map grotto,
  }) {
    final bClosed = (boulder['closed'] as Map?)?['collision'] ?? boulder['collision'];
    final bOpen = (boulder['open'] as Map?)?['collision'];
    boulderClosed = rectsFromJson(bClosed);
    if (bOpen != null) boulderOpen = rectsFromJson(bOpen);

    brambleClosed = rectsFromJson(brambleClosedJson['collision']);
    brambleOpen = rectsFromJson(brambleOpenJson['collision']);

    final gDark = (grotto['dark'] as Map?)?['collision'] ?? grotto['collision'];
    final gLit = (grotto['lit'] as Map?)?['collision'];
    grottoClosed = rectsFromJson(gDark);
    if (gLit != null) grottoOpen = rectsFromJson(gLit);
    loaded = true;
  }

  static Future<void> ensureLoaded() {
    if (loaded) return Future.value();
    return _loading ??= _loadBundle();
  }

  static Future<void> _loadBundle() async {
    try {
      Future<Map> load(String name) async =>
          jsonDecode(await rootBundle.loadString('$assetDir/$name')) as Map;
      applyParsed(
        boulder: await load('road_boulder.json'),
        brambleClosedJson: await load('bramble_closed.json'),
        brambleOpenJson: await load('bramble_open.json'),
        grotto: await load('pond_grotto.json'),
      );
    } catch (e) {
      debugPrint('ObstacleMasks: bundle load failed, using defaults: $e');
      loaded = true;
    }
  }

  /// Test helper: load from repo files (no asset bundle).
  static void loadFromDisk({String root = '.'}) {
    Map read(String name) =>
        jsonDecode(File('$root/$assetDir/$name').readAsStringSync()) as Map;
    applyParsed(
      boulder: read('road_boulder.json'),
      brambleClosedJson: read('bramble_closed.json'),
      brambleOpenJson: read('bramble_open.json'),
      grotto: read('pond_grotto.json'),
    );
  }

  /// Absolute path to a Designer JSON (resolves repo root from cwd / parents).
  static String diskPath(String fileName) {
    final root = projectRoot();
    if (root == null) {
      throw StateError(
          'cannot find project root (pubspec.yaml + $assetDir); cwd=${Directory.current.path}');
    }
    return '$root/$assetDir/$fileName';
  }

  /// Walk up from [Directory.current] until pubspec + obstacles dir exist.
  /// Null on web (`dart:io` [Directory.current] is unsupported in the browser).
  static String? projectRoot() {
    if (kIsWeb) return null;
    var dir = Directory.current.absolute;
    for (var i = 0; i < 8; i++) {
      final pub = File('${dir.path}/pubspec.yaml');
      final obs = Directory('${dir.path}/$assetDir');
      if (pub.existsSync() && obs.existsSync()) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  /// Write current rects into the Designer JSON. Returns null on success,
  /// else an error message. Bramble writes both closed and open files.
  /// On success [savedPath] is the primary file written.
  static String? savedPath;

  static Future<String?> save(ObstacleMaskId id) async {
    if (kIsWeb) return 'save not available on web';
    savedPath = null;
    try {
      switch (id) {
        case ObstacleMaskId.boulder:
          savedPath = await _patchBoulder();
        case ObstacleMaskId.bramble:
          savedPath = await _patchBramble();
        case ObstacleMaskId.grotto:
          savedPath = await _patchGrotto();
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String> _patchBoulder() async {
    final path = diskPath('road_boulder.json');
    final j = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    final closed = rectsToJson(boulderClosed);
    final open = rectsToJson(boulderOpen);
    j['collision'] = closed;
    final closedMap = Map<String, dynamic>.from(j['closed'] as Map? ?? {});
    closedMap['collision'] = closed;
    j['closed'] = closedMap;
    final openMap = Map<String, dynamic>.from(j['open'] as Map? ?? {});
    openMap['collision'] = open;
    j['open'] = openMap;
    await File(path).writeAsString('${const JsonEncoder.withIndent(' ').convert(j)}\n');
    return path;
  }

  static Future<String> _patchBramble() async {
    String? last;
    for (final (file, rects) in [
      ('bramble_closed.json', brambleClosed),
      ('bramble_open.json', brambleOpen),
    ]) {
      final path = diskPath(file);
      final j = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      j['collision'] = rectsToJson(rects);
      await File(path).writeAsString('${const JsonEncoder.withIndent(' ').convert(j)}\n');
      last = path;
    }
    return last!;
  }

  static Future<String> _patchGrotto() async {
    final path = diskPath('pond_grotto.json');
    final j = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    final closed = rectsToJson(grottoClosed);
    final open = rectsToJson(grottoOpen);
    // Top-level collision historically omitted pond/mouth; keep dark full set.
    j['collision'] = closed.take(3).toList();
    final dark = Map<String, dynamic>.from(j['dark'] as Map? ?? {});
    dark['collision'] = closed;
    j['dark'] = dark;
    final lit = Map<String, dynamic>.from(j['lit'] as Map? ?? {});
    lit['collision'] = open;
    j['lit'] = lit;
    await File(path).writeAsString('${const JsonEncoder.withIndent(' ').convert(j)}\n');
    return path;
  }
}
