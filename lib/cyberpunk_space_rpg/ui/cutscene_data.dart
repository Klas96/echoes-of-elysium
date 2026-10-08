import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Data model for illustrated cutscenes, parsed from JSON assets in
/// `assets/cutscenes/<id>/<id>.json`. See `assets/cutscenes/README.md` for the
/// authoring format. Parsing is lenient: unknown keys are ignored and a
/// malformed optional field falls back to its default, so a typo in one panel
/// never breaks the whole scene. Only a scene without any usable panel throws.
class Cutscene {
  final String id;
  final String title;

  /// Source art size in pixels; its aspect ratio drives the letterboxing.
  final Size size;
  final double crossfade;
  final List<CutscenePanel> panels;
  final Map<String, CutsceneSpeaker> speakers;

  const Cutscene({
    required this.id,
    this.title = '',
    this.size = const Size(1280, 720),
    this.crossfade = 0.8,
    required this.panels,
    this.speakers = const {},
  });

  double get aspectRatio => size.width / size.height;

  /// Style for a line's speaker key. Unknown keys get a default named speaker;
  /// "N" (or "" / "NARRATOR") is the narrator unless the JSON says otherwise.
  CutsceneSpeaker speaker(String key) =>
      speakers[key] ??
      (const {'', 'N', 'NARRATOR'}.contains(key.toUpperCase())
          ? const CutsceneSpeaker.narrator()
          : CutsceneSpeaker(name: key, color: defaultSpeakerColors[key.toUpperCase()] ?? const Color(0xFF00FFCC)));

  /// Cast colours used when the JSON has no "speakers" entry (they match the
  /// in-game dialogue boxes).
  static const defaultSpeakerColors = {
    'GAIA': Color(0xFF00FF88),
    'KAELA': Color(0xFF00FFCC),
    'VOSS': Color(0xFFFF4444),
    'ASHA': Color(0xFFFFAA00),
    'AETHERIAN': Color(0xFFCC66FF),
    'ECHO-7': Color(0xFFCC66FF),
    'ARCHIVIST': Color(0xFFFFDD44),
  };

  /// [basePath] is the asset folder the JSON lives in; relative image paths
  /// are resolved against it.
  factory Cutscene.fromJson(Map<String, dynamic> j, {String basePath = ''}) {
    final defaultDuration = _num(j['panelDuration'], 7.0).clamp(0.5, 60.0);
    final sizeList = j['size'];
    final size = sizeList is List &&
            sizeList.length >= 2 &&
            sizeList[0] is num &&
            sizeList[1] is num &&
            (sizeList[0] as num) > 0 &&
            (sizeList[1] as num) > 0
        ? Size((sizeList[0] as num).toDouble(), (sizeList[1] as num).toDouble())
        : const Size(1280, 720);

    final speakers = <String, CutsceneSpeaker>{};
    final rawSpeakers = j['speakers'];
    if (rawSpeakers is Map) {
      for (final e in rawSpeakers.entries) {
        if (e.value is Map) {
          speakers[e.key.toString()] =
              CutsceneSpeaker.fromJson(e.key.toString(), Map<String, dynamic>.from(e.value as Map));
        }
      }
    }

    final panels = <CutscenePanel>[];
    final rawPanels = j['panels'];
    if (rawPanels is List) {
      for (final p in rawPanels) {
        if (p is Map) {
          final panel = CutscenePanel.fromJson(Map<String, dynamic>.from(p),
              basePath: basePath, defaultDuration: defaultDuration.toDouble());
          if (panel != null) panels.add(panel);
        }
      }
    }
    if (panels.isEmpty) {
      throw const FormatException('Cutscene has no panels with an image');
    }
    return Cutscene(
      id: j['id'] is String ? j['id'] as String : '',
      title: j['title'] is String ? j['title'] as String : '',
      size: size,
      crossfade: _num(j['crossfade'], 0.8).clamp(0.0, 5.0).toDouble(),
      panels: panels,
      speakers: speakers,
    );
  }

  /// Parses a JSON string; see [Cutscene.fromJson].
  factory Cutscene.parse(String source, {String basePath = ''}) {
    final json = jsonDecode(source);
    if (json is! Map) throw const FormatException('Cutscene JSON must be an object');
    return Cutscene.fromJson(Map<String, dynamic>.from(json), basePath: basePath);
  }

  /// Image asset paths in play order (for precaching).
  List<String> get imagePaths => [for (final p in panels) p.image];

  /// Effect mask images (for precaching).
  List<String> get maskPaths => [
        for (final p in panels)
          for (final e in p.effects)
            if (e.mask != null) e.mask!
      ];
}

class CutsceneSpeaker {
  /// Shown above the line; null for the narrator.
  final String? name;
  final Color color;
  final bool narrator;

  const CutsceneSpeaker({this.name, this.color = const Color(0xFF00FFCC), this.narrator = false});
  const CutsceneSpeaker.narrator()
      : name = null,
        color = const Color(0xFFE8E8F0),
        narrator = true;

  factory CutsceneSpeaker.fromJson(String key, Map<String, dynamic> j) {
    final narrator = j['narrator'] == true;
    return CutsceneSpeaker(
      name: narrator ? null : (j['name'] is String ? j['name'] as String : key),
      color: parseColor(j['color']) ??
          (narrator ? const Color(0xFFE8E8F0) : const Color(0xFF00FFCC)),
      narrator: narrator,
    );
  }
}

/// A slow Ken Burns move: zoom (1 = the whole image) around a centre point
/// given as fractions of the image (0..1).
class PanKey {
  final double zoom;
  final double cx;
  final double cy;
  const PanKey(this.zoom, this.cx, this.cy);

  static const identity = PanKey(1, 0.5, 0.5);

  /// Accepts `[zoom, cx, cy]` or `{"zoom": .., "x": .., "y": ..}`.
  static PanKey? fromJson(Object? v) {
    if (v is List && v.length >= 3 && v.every((e) => e is num)) {
      return PanKey((v[0] as num).toDouble(), (v[1] as num).toDouble(), (v[2] as num).toDouble())
          ._clamped();
    }
    if (v is Map) {
      return PanKey(_num(v['zoom'], 1), _num(v['x'], 0.5), _num(v['y'], 0.5))._clamped();
    }
    return null;
  }

  PanKey _clamped() => PanKey(zoom.clamp(1.0, 4.0), cx.clamp(0.0, 1.0), cy.clamp(0.0, 1.0));

  static PanKey lerp(PanKey a, PanKey b, double t) => PanKey(
        a.zoom + (b.zoom - a.zoom) * t,
        a.cx + (b.cx - a.cx) * t,
        a.cy + (b.cy - a.cy) * t,
      );

  /// The centre actually used at this zoom so the view never leaves the image
  /// (at zoom 1 the centre is always 0.5).
  Offset clampedCenter() {
    final half = 0.5 / zoom;
    return Offset(cx.clamp(half, 1 - half), cy.clamp(half, 1 - half));
  }

  @override
  bool operator ==(Object other) =>
      other is PanKey && other.zoom == zoom && other.cx == cx && other.cy == cy;
  @override
  int get hashCode => Object.hash(zoom, cx, cy);
  @override
  String toString() => 'PanKey($zoom, $cx, $cy)';
}

class CutsceneLine {
  final String speaker;
  final String text;

  /// Seconds after the previous line (or the panel start) before it appears.
  final double delay;

  /// Seconds the fully revealed line stays before auto-advancing; null =
  /// derived from its length.
  final double? hold;

  /// Optional spoken line asset (`audio/voices/...` or `assets/audio/voices/...`).
  final String? voice;

  const CutsceneLine({
    required this.speaker,
    required this.text,
    this.delay = 0.5,
    this.hold,
    this.voice,
  });

  static CutsceneLine? fromJson(Object? v) {
    if (v is String && v.trim().isNotEmpty) return CutsceneLine(speaker: 'N', text: v);
    if (v is! Map) return null;
    final text = v['text'];
    if (text is! String || text.trim().isEmpty) return null;
    final voice = v['voice'];
    return CutsceneLine(
      speaker: v['speaker'] is String ? v['speaker'] as String : 'N',
      text: text,
      delay: _num(v['delay'], 0.5).clamp(0.0, 30.0).toDouble(),
      hold: v['hold'] is num ? (v['hold'] as num).toDouble().clamp(0.2, 60.0) : null,
      voice: voice is String && voice.trim().isNotEmpty ? voice.trim() : null,
    );
  }

  /// Auto-advance hold after the typewriter finishes: long enough to read,
  /// and (when voiced) long enough for the spoken line to finish.
  double get holdSeconds {
    final read = hold ?? (1.6 + text.length * 0.045).clamp(1.8, 6.0);
    if (voice == null) return read;
    // Spoken pace ~12.5 chars/s; overlap with the typewriter reveal.
    final voiceDur = text.length / 12.5 + 0.45;
    final reveal = text.length / 38.0;
    return math.max(read, voiceDur - reveal + 0.35);
  }
}

class CutsceneTitleCard {
  final String text;
  final String subtitle;

  /// Centre of the title as fractions of the image (0..1).
  final Offset position;
  final Color color;
  final double fadeIn;
  final double hold;

  const CutsceneTitleCard({
    required this.text,
    this.subtitle = '',
    this.position = const Offset(0.5, 0.25),
    this.color = const Color(0xFF00FFCC),
    this.fadeIn = 1.4,
    this.hold = 4.0,
  });

  /// Designer shorthand on a panel: `"then": "title card ECHOES OF ELYSIUM
  /// over the upper sky, fade into the Woods"`. "upper"/"lower"/"centre" in
  /// the sentence pick the height.
  static CutsceneTitleCard? fromThen(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r'title(?:\s+card)?\s*:?\s+"?(.+?)"?(?=\s+over\b|\s+in\b|\s+on\b|,|;|\s+->|$)',
            caseSensitive: false)
        .firstMatch(v);
    final text = m?.group(1)?.trim();
    if (text == null || text.isEmpty) return null;
    final lower = v.toLowerCase();
    final y = lower.contains('upper') || lower.contains('sky') || lower.contains('top')
        ? 0.3
        : lower.contains('lower') || lower.contains('bottom')
            ? 0.65
            : 0.45;
    return CutsceneTitleCard(text: text, position: Offset(0.5, y));
  }

  static CutsceneTitleCard? fromJson(Object? v) {
    if (v is String && v.trim().isNotEmpty) return CutsceneTitleCard(text: v);
    if (v is! Map) return null;
    final text = v['text'];
    if (text is! String || text.trim().isEmpty) return null;
    final pos = v['position'];
    return CutsceneTitleCard(
      text: text,
      subtitle: v['subtitle'] is String ? v['subtitle'] as String : '',
      position: pos is List && pos.length >= 2 && pos[0] is num && pos[1] is num
          ? Offset((pos[0] as num).toDouble().clamp(0.0, 1.0), (pos[1] as num).toDouble().clamp(0.0, 1.0))
          : const Offset(0.5, 0.25),
      color: parseColor(v['color']) ?? const Color(0xFF00FFCC),
      fadeIn: _num(v['fadeIn'], 1.4).clamp(0.0, 10.0).toDouble(),
      hold: _num(v['hold'], 4.0).clamp(0.5, 60.0).toDouble(),
    );
  }
}

/// A per-panel visual effect, timed from the panel start. New effect types
/// are added by extending [CutsceneEffect.types] and the switch in the player
/// (`_applyEffect`).
class CutsceneEffect {
  /// brighten (screen-blend a colour in), darken (multiply), flash (a quick
  /// colour flash that fades out), pulse (a slow repeating glow; [duration]
  /// is one breath).
  static const types = {'brighten', 'darken', 'flash', 'pulse'};

  final String type;
  final Color color;
  final double start;
  final double duration;
  final double strength;

  /// Optional mask image (asset path): the effect only shows through its
  /// alpha, stretched over the panel and moving with the pan.
  final String? mask;

  /// Optional soft spot instead of a mask image: centre as fractions of the
  /// panel and [radius] as a fraction of its width.
  final Offset? center;
  final double radius;

  const CutsceneEffect({
    required this.type,
    this.color = const Color(0xFFFFFFFF),
    this.start = 0,
    this.duration = 1.5,
    this.strength = 0.4,
    this.mask,
    this.center,
    this.radius = 0.22,
  });

  bool get isLocal => mask != null || center != null;

  /// Accepts an object `{"type": "brighten", "color": "#00FF88", "start": 0.5,
  /// "duration": 1.5, "strength": 0.35}` or the shorthand string
  /// `"brighten green over 1.5 s"`. Unknown types are dropped.
  /// [basePath] resolves a relative `mask` like the panel images.
  static CutsceneEffect? fromJson(Object? v, {String basePath = ''}) {
    if (v is String) return _fromShorthand(v);
    if (v is! Map) return null;
    final type = v['type'] is String ? (v['type'] as String).toLowerCase() : '';
    if (!types.contains(type)) return null;
    final mask = v['mask'];
    final center = v['center'];
    final pulse = type == 'pulse';
    return CutsceneEffect(
      type: type,
      color: parseColor(v['color']) ?? const Color(0xFFFFFFFF),
      start: _num(v['start'], pulse ? 0.4 : 0).clamp(0.0, 60.0).toDouble(),
      duration: _num(v['duration'], pulse ? 2.4 : 1.5).clamp(0.05, 60.0).toDouble(),
      // A masked effect only lights a small area, so it can be stronger.
      strength: _num(v['strength'], mask is String ? 0.6 : (pulse ? 0.22 : 0.4)).clamp(0.0, 1.0).toDouble(),
      mask: mask is String && mask.isNotEmpty ? resolvePath(basePath, mask) : null,
      center: center is List && center.length >= 2 && center[0] is num && center[1] is num
          ? Offset((center[0] as num).toDouble().clamp(0.0, 1.0), (center[1] as num).toDouble().clamp(0.0, 1.0))
          : null,
      radius: _num(v['radius'], 0.22).clamp(0.02, 2.0).toDouble(),
    );
  }

  static CutsceneEffect? _fromShorthand(String s) {
    final lower = s.toLowerCase();
    final words = lower.split(RegExp(r'[^a-z0-9#.]+')).where((w) => w.isNotEmpty).toList();
    final String type;
    if (words.contains('pulse') || words.contains('pulses') || words.contains('pulsing')) {
      type = 'pulse';
    } else if (words.contains('flash')) {
      type = 'flash';
    } else if (words.contains('darken') || words.contains('dim')) {
      type = 'darken';
    } else if (words.any((w) => const {'brighten', 'brightens', 'glow', 'glows', 'floods', 'light'}.contains(w))) {
      type = 'brighten';
    } else {
      return null;
    }
    Color color = const Color(0xFFFFFFFF);
    for (final w in words) {
      final c = parseColor(w);
      if (c != null) {
        color = c;
        break;
      }
    }
    final over = RegExp(r'(?:over|in)\s+([0-9.]+)\s*s\b').firstMatch(lower);
    final duration = double.tryParse(over?.group(1) ?? '') ?? (type == 'pulse' ? 2.4 : 1.5);
    // "(x0.58, y0.63)" = a soft spot there instead of the whole frame.
    final at = RegExp(r'\(\s*x\s*=?\s*([0-9.]+)\s*,\s*y\s*=?\s*([0-9.]+)\s*\)').firstMatch(lower);
    final cx = double.tryParse(at?.group(1) ?? ''), cy = double.tryParse(at?.group(2) ?? '');
    final center = cx != null && cy != null ? Offset(cx.clamp(0.0, 1.0), cy.clamp(0.0, 1.0)) : null;
    return CutsceneEffect(
      type: type,
      color: color,
      start: type == 'flash' ? 0 : 0.4,
      duration: duration.clamp(0.05, 60.0),
      strength: center != null ? 0.55 : (type == 'pulse' ? 0.22 : 0.35),
      center: center,
    );
  }

  /// 0..1 progress of the effect at [t] seconds into the panel (eased).
  double progress(double t) {
    final p = ((t - start) / duration).clamp(0.0, 1.0);
    return p * p * (3 - 2 * p);
  }

  /// Effect intensity (0..[strength]) at [t] seconds into the panel.
  double amount(double t) {
    final p = progress(t);
    if (t < start) return 0;
    if (type == 'flash') return strength * (1 - p);
    if (type == 'pulse') {
      final phase = ((t - start) / duration) * 2 * math.pi;
      // Fade the pulse in over the first breath so it never pops.
      final ramp = ((t - start) / duration).clamp(0.0, 1.0);
      return strength * ramp * (0.5 - math.cos(phase) / 2);
    }
    return strength * p;
  }
}

class CutscenePanel {
  final String image;
  final double duration;
  final PanKey from;
  final PanKey to;
  final List<CutsceneLine> lines;
  final List<CutsceneEffect> effects;
  final CutsceneTitleCard? titleCard;

  const CutscenePanel({
    required this.image,
    this.duration = 7,
    this.from = PanKey.identity,
    this.to = PanKey.identity,
    this.lines = const [],
    this.effects = const [],
    this.titleCard,
  });

  static CutscenePanel? fromJson(Map<String, dynamic> j,
      {String basePath = '', double defaultDuration = 7}) {
    final image = j['image'];
    if (image is! String || image.isEmpty) return null;
    final pan = j['pan'];
    final from = pan is Map ? PanKey.fromJson(pan['from']) : null;
    final to = pan is Map ? PanKey.fromJson(pan['to']) : null;
    final fx = j['fx'];
    final rawLines = j['lines'];
    return CutscenePanel(
      image: resolvePath(basePath, image),
      duration: _num(j['duration'], defaultDuration).clamp(0.5, 60.0).toDouble(),
      from: from ?? to ?? PanKey.identity,
      to: to ?? from ?? PanKey.identity,
      lines: rawLines is List
          ? [for (final l in rawLines) CutsceneLine.fromJson(l)].whereType<CutsceneLine>().toList()
          : const [],
      effects: [
        for (final e in (fx is List ? fx : [fx])) CutsceneEffect.fromJson(e, basePath: basePath),
      ].whereType<CutsceneEffect>().toList(),
      titleCard: CutsceneTitleCard.fromJson(j['titleCard'] ?? j['title']) ??
          CutsceneTitleCard.fromThen(j['then']),
    );
  }

  /// Ken Burns position at [t] seconds (eased, holds the end pose).
  PanKey panAt(double t) {
    final p = (t / duration).clamp(0.0, 1.0);
    final eased = 0.5 - math.cos(p * math.pi) / 2;
    return PanKey.lerp(from, to, eased);
  }
}

/// Joins a relative image path onto the JSON's folder; absolute asset paths
/// (starting with `assets/`) are kept.
String resolvePath(String base, String path) {
  if (base.isEmpty || path.startsWith('assets/') || path.startsWith('/')) return path;
  return base.endsWith('/') ? '$base$path' : '$base/$path';
}

const _namedColors = {
  'green': Color(0xFF00FF88),
  'cyan': Color(0xFF00FFCC),
  'teal': Color(0xFF00C8B4),
  'blue': Color(0xFF4FA8FF),
  'purple': Color(0xFFB070FF),
  'violet': Color(0xFFB070FF),
  'red': Color(0xFFFF4466),
  'amber': Color(0xFFFFAA00),
  'orange': Color(0xFFFF8833),
  'gold': Color(0xFFFFD166),
  'white': Color(0xFFFFFFFF),
  'black': Color(0xFF000000),
};

/// `#RRGGBB`, `#AARRGGBB` or a few colour names (green, cyan, amber...).
Color? parseColor(Object? v) {
  if (v is! String) return null;
  final s = v.trim().toLowerCase();
  if (_namedColors.containsKey(s)) return _namedColors[s];
  final hex = s.startsWith('#') ? s.substring(1) : null;
  if (hex == null) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  if (hex.length == 6) return Color(0xFF000000 | value);
  if (hex.length == 8) return Color(value);
  return null;
}

double _num(Object? v, double d) => v is num ? v.toDouble() : d;
