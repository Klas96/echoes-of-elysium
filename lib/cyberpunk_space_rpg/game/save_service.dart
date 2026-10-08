import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A 2D point in map pixels (top-left of the player, like Bonfire positions).
@immutable
class SavePoint {
  final double x;
  final double y;
  const SavePoint(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  static SavePoint? fromJson(Object? json) {
    if (json is! Map) return null;
    final x = json['x'], y = json['y'];
    if (x is! num || y is! num) return null;
    return SavePoint(x.toDouble(), y.toDouble());
  }

  @override
  bool operator ==(Object other) => other is SavePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// Everything a playthrough needs to resume. Serialized as versioned JSON.
///
/// Schema (v1):
/// ```json
/// {
///   "version": 1,
///   "savedAt": "2026-10-03T09:54:00.000Z",
///   "playTimeSeconds": 0,
///   "mapId": "world",              // Tiled map file stem: world, world2, world3...
///   "regionId": "woods",           // woods, city, ruins (later: route1, lantern_town...)
///   "player": {"x": 0, "y": 0},    // null = use the map's spawn
///   "health": 100,
///   "checkpoint": {"x": 0, "y": 0},// last respawn point on mapId, null = spawn
///   "objectiveStep": 0,            // GameState step on mapId (only ever grows)
///   "fragments": 0,                // Aetherian fragments gathered on the current map
///   "storyFlags": {"sentinelDefeated": true},
///   "collected": ["world:fragment:120_340"],   // pickup ids, never respawn
///   "bonds": {"glowmoth": {"seen": true, "befriended": false}},
///   "activeCompanion": null,       // creature id
///   "abilities": ["light"],        // unlocked companion abilities
///   "glimmer": 0,
///   "level": 1,
///   "xp": 0,
///   "inventory": ["scrap_plating"],
///   "equipped": {"rifle": "pulse_optic", "suit": "scrap_plating"},
///   "challenges": {"riddle_old_colonist": {"done": true, "best": 41.2}},
///   "dayTime": 0.3,                // 0..1 fraction of the day cycle (0 = midnight)
///   "settings": {"storyMode": false}
/// }
/// ```
/// Unknown keys are kept in [extra] so an older build never drops data a newer
/// build wrote. Bump [currentVersion] and add a step to [SaveService.migrate]
/// when a field changes meaning.
class SaveData {
  static const currentVersion = 1;
  static const defaultDayTime = 0.3;

  int version;
  DateTime savedAt;
  double playTimeSeconds;
  String mapId;
  String regionId;
  SavePoint? player;
  int? health;
  SavePoint? checkpoint;
  int objectiveStep;
  int fragments;
  Map<String, bool> storyFlags;
  Set<String> collected;
  Map<String, Map<String, dynamic>> bonds;
  String? activeCompanion;
  Set<String> abilities;
  int glimmer;
  int level;
  int xp;
  List<String> inventory;
  Map<String, String> equipped;
  Map<String, Map<String, dynamic>> challenges;
  double dayTime;
  Map<String, dynamic> settings;
  Map<String, dynamic> extra;

  SaveData({
    this.version = currentVersion,
    DateTime? savedAt,
    this.playTimeSeconds = 0,
    this.mapId = 'world',
    this.regionId = 'woods',
    this.player,
    this.health,
    this.checkpoint,
    this.objectiveStep = 0,
    this.fragments = 0,
    Map<String, bool>? storyFlags,
    Set<String>? collected,
    Map<String, Map<String, dynamic>>? bonds,
    this.activeCompanion,
    Set<String>? abilities,
    this.glimmer = 0,
    this.level = 1,
    this.xp = 0,
    List<String>? inventory,
    Map<String, String>? equipped,
    Map<String, Map<String, dynamic>>? challenges,
    this.dayTime = defaultDayTime,
    Map<String, dynamic>? settings,
    Map<String, dynamic>? extra,
  })  : savedAt = savedAt ?? DateTime.now().toUtc(),
        storyFlags = storyFlags ?? {},
        collected = collected ?? {},
        bonds = bonds ?? {},
        abilities = abilities ?? {},
        inventory = inventory ?? [],
        equipped = equipped ?? {},
        challenges = challenges ?? {},
        settings = settings ?? {},
        extra = extra ?? {};

  static const _known = {
    'version', 'savedAt', 'playTimeSeconds', 'mapId', 'regionId', 'player',
    'health', 'checkpoint', 'objectiveStep', 'fragments', 'storyFlags',
    'collected', 'bonds', 'activeCompanion', 'abilities', 'glimmer',
    'level', 'xp', 'inventory', 'equipped',
    'challenges', 'dayTime', 'settings',
  };

  bool flag(String key) => storyFlags[key] ?? false;
  void setFlag(String key, [bool value = true]) => storyFlags[key] = value;

  Map<String, dynamic> toJson() => {
        ...extra,
        'version': version,
        'savedAt': savedAt.toIso8601String(),
        'playTimeSeconds': playTimeSeconds,
        'mapId': mapId,
        'regionId': regionId,
        'player': player?.toJson(),
        'health': health,
        'checkpoint': checkpoint?.toJson(),
        'objectiveStep': objectiveStep,
        'fragments': fragments,
        'storyFlags': storyFlags,
        'collected': collected.toList()..sort(),
        'bonds': bonds,
        'activeCompanion': activeCompanion,
        'abilities': abilities.toList()..sort(),
        'glimmer': glimmer,
        'level': level,
        'xp': xp,
        'inventory': inventory.toList(),
        'equipped': equipped,
        'challenges': challenges,
        'dayTime': dayTime,
        'settings': settings,
      };

  /// Lenient parse: a missing or malformed field falls back to its default
  /// rather than throwing away the whole save.
  factory SaveData.fromJson(Map<String, dynamic> j) {
    int asInt(Object? v, int d) => v is num ? v.toInt() : d;
    double asDouble(Object? v, double d) => v is num ? v.toDouble() : d;
    String asString(Object? v, String d) => v is String && v.isNotEmpty ? v : d;
    Map<String, Map<String, dynamic>> nested(Object? v) => v is Map
        ? {
            for (final e in v.entries)
              if (e.value is Map) e.key.toString(): Map<String, dynamic>.from(e.value as Map)
          }
        : {};
    Set<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toSet() : <String>{};

    return SaveData(
      version: asInt(j['version'], currentVersion),
      savedAt: DateTime.tryParse(j['savedAt']?.toString() ?? ''),
      playTimeSeconds: asDouble(j['playTimeSeconds'], 0),
      mapId: asString(j['mapId'], 'world'),
      regionId: asString(j['regionId'], 'woods'),
      player: SavePoint.fromJson(j['player']),
      health: j['health'] is num ? (j['health'] as num).toInt() : null,
      checkpoint: SavePoint.fromJson(j['checkpoint']),
      objectiveStep: asInt(j['objectiveStep'], 0),
      fragments: asInt(j['fragments'], 0),
      storyFlags: j['storyFlags'] is Map
          ? {
              for (final e in (j['storyFlags'] as Map).entries)
                if (e.value is bool) e.key.toString(): e.value as bool
            }
          : {},
      collected: strings(j['collected']),
      bonds: nested(j['bonds']),
      activeCompanion: j['activeCompanion'] is String ? j['activeCompanion'] as String : null,
      abilities: strings(j['abilities']),
      glimmer: asInt(j['glimmer'], 0),
      level: asInt(j['level'], 1).clamp(1, 99),
      xp: asInt(j['xp'], 0).clamp(0, 999999),
      inventory: j['inventory'] is List
          ? (j['inventory'] as List).whereType<String>().toList()
          : [],
      equipped: j['equipped'] is Map
          ? {
              for (final e in (j['equipped'] as Map).entries)
                if (e.value is String) e.key.toString(): e.value as String
            }
          : {},
      challenges: nested(j['challenges']),
      dayTime: asDouble(j['dayTime'], defaultDayTime),
      settings: j['settings'] is Map ? Map<String, dynamic>.from(j['settings'] as Map) : {},
      extra: {
        for (final e in j.entries)
          if (!_known.contains(e.key)) e.key: e.value
      },
    );
  }
}

/// Persistent single-slot save on shared_preferences (localStorage on web,
/// SharedPreferences on Android, a JSON file in the app support dir on Linux).
///
/// [data] is the live record for the current playthrough: gameplay code
/// mutates it (or lets [snapshot] fill it in) and calls [requestAutosave] or
/// [saveNow]. Every write is best effort: a storage failure is logged and the
/// game keeps going.
class SaveService {
  static const storageKey = 'echoes.save';

  /// The live playthrough record.
  static SaveData data = SaveData();

  /// True once a save exists on disk (or was written this session).
  static final hasSave = ValueNotifier<bool>(false);

  /// Called right before every write to copy live game state into [data]
  /// (player position, objective...). Set by the game screens.
  static void Function(SaveData data)? snapshot;

  /// Set by CONTINUE: the next map to load should take its player position,
  /// checkpoint and objective from [data] instead of starting fresh. Each
  /// flag is consumed once by its user (objective by onReady, position by the
  /// spawn).
  static bool resumeObjective = false;
  static bool resumePlayer = false;

  static Timer? _debounce;
  static const autosaveDelay = Duration(milliseconds: 400);

  /// Reads the save from storage. Call once at startup.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      final parsed = raw == null ? null : decode(raw);
      if (parsed != null) {
        data = parsed;
        hasSave.value = true;
      } else {
        data = SaveData();
        hasSave.value = false;
      }
    } catch (e) {
      debugPrint('SaveService.load failed: $e');
    }
  }

  /// Parses and migrates a stored JSON string; null if unusable.
  static SaveData? decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return SaveData.fromJson(migrate(Map<String, dynamic>.from(json)));
    } catch (e) {
      debugPrint('SaveService: unreadable save ($e)');
      return null;
    }
  }

  static String encode(SaveData d) => jsonEncode(d.toJson());

  /// Upgrades older save JSON to [SaveData.currentVersion], one step at a time.
  static Map<String, dynamic> migrate(Map<String, dynamic> json) {
    var v = json['version'] is num ? (json['version'] as num).toInt() : 1;
    // Future: if (v == 1) { ...rename/convert fields...; v = 2; }
    if (v > SaveData.currentVersion) {
      // Written by a newer build: read what we understand, keep the rest.
      debugPrint('SaveService: save version $v is newer than ${SaveData.currentVersion}');
    }
    json['version'] = v < SaveData.currentVersion ? SaveData.currentVersion : v;
    return json;
  }

  /// Starts a fresh playthrough and overwrites the stored save. Settings
  /// (Story Mode) carry over.
  static Future<void> startNewGame() async {
    _debounce?.cancel();
    final settings = Map<String, dynamic>.from(data.settings);
    data = SaveData(settings: settings);
    resumeObjective = false;
    resumePlayer = false;
    await _write();
  }

  /// Marks the next map load as a CONTINUE from [data].
  static void prepareResume() {
    resumeObjective = true;
    resumePlayer = true;
  }

  /// Coalesces bursts of progress events (fragment + objective + flag) into
  /// one write shortly after.
  static void requestAutosave() {
    _debounce?.cancel();
    _debounce = Timer(autosaveDelay, () {
      _debounce = null;
      saveNow();
    });
  }

  /// Snapshots live state and writes immediately (app backgrounding, pause,
  /// map transitions).
  static Future<void> saveNow({bool takeSnapshot = true}) async {
    _debounce?.cancel();
    _debounce = null;
    if (takeSnapshot) {
      try {
        snapshot?.call(data);
      } catch (e) {
        debugPrint('SaveService snapshot failed: $e');
      }
    }
    await _write();
  }

  static Future<void> _write() async {
    data.version = SaveData.currentVersion;
    data.savedAt = DateTime.now().toUtc();
    hasSave.value = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, encode(data));
    } catch (e) {
      debugPrint('SaveService write failed: $e');
    }
  }

  /// Removes the stored save (not used by any menu; for tests/debug).
  static Future<void> clear() async {
    _debounce?.cancel();
    data = SaveData();
    hasSave.value = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (e) {
      debugPrint('SaveService.clear failed: $e');
    }
  }
}
