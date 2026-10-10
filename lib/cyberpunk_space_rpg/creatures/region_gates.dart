/// Main-route ability gates and region friend goals
/// (brief-woods-befriend-gates.md). Pure data + the save migration, no
/// Flutter/Flame, so it is unit tested. Runtime state lives in gates.dart.
library;

import 'creature_species.dart';

/// What the gate looks like / how it blocks (matches the Tiled `kind`).
enum GateKind {
  /// Darkness: what is inside (the pond fragment) can't be seen or taken.
  grotto,

  /// Thorns across a trail (bramble_closed / bramble_open art).
  bramble,

  /// A fallen boulder across the road.
  boulder,
}

/// A tile rect (end exclusive), map tiles of 32 px.
class TileRect {
  final int x0, y0, x1, y1;
  const TileRect(this.x0, this.y0, this.x1, this.y1);

  bool containsPx(double x, double y) {
    final tx = x / 32, ty = y / 32;
    return tx >= x0 && tx < x1 && ty >= y0 && ty < y1;
  }
}

class GateDef {
  /// Save id, also the Tiled `gate` property.
  final String id;
  final String region;
  final GateKind kind;
  final Ability ability;

  /// Species that opens it (any befriended one of these, whoever follows).
  final String creature;

  /// Toast title + level-2 hint (walking into the closed gate).
  final String title;
  final String blockedHint;

  /// Level-3 hint: Gaia names the place after [GateHints.gaiaAfter] passes.
  final String gaiaHint;

  /// Prompt once its creature is a friend.
  final String action;

  /// Short toast when it opens.
  final String openedToast;

  /// Save migration (v1 -> v2): Kaela standing here (centre, map px) or
  /// respawning here is inside / beyond the closed gate, so it opens.
  final String mapId;
  final List<TileRect> zones;

  /// Pickup id (SaveData.collected) this gate guards: already taken in an
  /// older save means the gate no longer matters, so it opens.
  final String? guards;

  const GateDef({
    required this.id,
    required this.region,
    required this.kind,
    required this.ability,
    required this.creature,
    required this.title,
    required this.blockedHint,
    required this.gaiaHint,
    required this.action,
    required this.openedToast,
    required this.mapId,
    this.zones = const [],
    this.guards,
  });
}

/// "Meet this place's creatures, earn your way through": who is needed and
/// what is said at the goal, the tracker, the farewell and the return.
class RegionGoal {
  final String region;
  final List<String> friends;
  final String trackerPrefix;

  /// Asha (Woods) sets the goal with this line.
  final String goalLine;
  final String exitLocked;
  final String exitOpens;
  final String farewellGaia;
  final String farewellKaela;
  final String returnLine;

  const RegionGoal({
    required this.region,
    required this.friends,
    required this.trackerPrefix,
    required this.goalLine,
    required this.exitLocked,
    required this.exitOpens,
    required this.farewellGaia,
    required this.farewellKaela,
    required this.returnLine,
  });

  String tracker(int n) => '$trackerPrefix $n/${friends.length}';
}

const woodsGoal = RegionGoal(
  region: 'woods',
  friends: ['glowmoth', 'vinefox', 'stoneturtle'],
  trackerPrefix: 'Friends of the Woods',
  goalLine:
      'The woods won\'t let you through alone. Find three friends: something that glows, something that sniffs, something strong.',
  exitLocked: 'The road south is blocked. The woods still want something from you.',
  exitOpens: 'The boulder rolls aside. The road to the City is open.',
  farewellGaia: 'They belong to the forest, Kaela. It will keep them for you.',
  farewellKaela: 'I\'ll come back.',
  returnLine: 'Your friends find you at the treeline.',
);

const regionGoals = <String, RegionGoal>{'woods': woodsGoal};

/// Woods pickup ids of the two road fragments (Tiled pid, see
/// tools/make_tiled_maps.py map1: f2 was=(19.5, 16.5), f4 was=(24, 38.5)).
const woodsPondFragment = 'world:fragment:615_519';
const woodsGroveFragment = 'world:fragment:759_1223';

const gateDefs = <String, GateDef>{
  'woods_grotto': GateDef(
    id: 'woods_grotto',
    region: 'woods',
    kind: GateKind.grotto,
    ability: Ability.light,
    creature: 'glowmoth',
    title: 'DARK GROTTO',
    blockedHint: 'Too dark to see. Something that glows might help, and those only come out at night.',
    gaiaHint: 'The moths dance over the pond after dark.',
    action: 'LIGHT THE GROTTO',
    openedToast: 'The grotto glows',
    mapId: 'world',
    zones: [TileRect(36, 11, 39, 13)],
    guards: woodsPondFragment,
  ),
  'woods_brambles': GateDef(
    id: 'woods_brambles',
    region: 'woods',
    kind: GateKind.bramble,
    ability: Ability.scent,
    creature: 'vinefox',
    title: 'BRAMBLES',
    blockedHint: 'Thorns. Something with a good nose could find a way through.',
    gaiaHint: 'Foxes love sweetroot. I felt one growing in the western hollow.',
    action: 'SNIFF A WAY THROUGH',
    openedToast: 'Path found',
    mapId: 'world',
    // the bramble itself and the fragment pocket behind it
    zones: [TileRect(49, 26, 53, 31)],
    guards: woodsGroveFragment,
  ),
  'woods_boulder': GateDef(
    id: 'woods_boulder',
    region: 'woods',
    kind: GateKind.boulder,
    ability: Ability.push,
    creature: 'stoneturtle',
    title: 'FALLEN BOULDER',
    blockedHint: 'Far too heavy for one person. Something patient and strong, maybe from the river.',
    gaiaHint: 'Someone has trapped a turtle by the pond.',
    action: 'PUSH',
    openedToast: 'Boulder moved',
    mapId: 'world',
    // the boulder and the road south of it, down to the map edge
    zones: [TileRect(38, 40, 47, 44)],
  ),
};

List<GateDef> gatesIn(String region) => [for (final g in gateDefs.values) if (g.region == region) g];

/// The calm rule: Asha (level 1), a toast at the gate (level 2), then Gaia
/// names the place once the same closed gate has been walked into
/// [gaiaAfter] times (level 3).
class GateHints {
  static const gaiaAfter = 3;

  /// [passes]: times Kaela has walked up to this closed gate, this one
  /// included.
  static bool gaiaSpeaks(int passes) => passes >= gaiaAfter;
}

/// Save v1 -> v2 for the region gates. Never strands a player:
/// - story past the Woods (another map, a later region visited, the City
///   road already used): every Woods gate open, goal set, farewell seen;
/// - the old exit rule already met in the Woods (2 fragments): the boulder
///   stays out of the way, so the road they earned stays open;
/// - a fragment already taken: its gate opens (nothing left behind it);
/// - standing or respawning inside / beyond a gate: that gate opens.
/// Works on the raw JSON (before SaveData.fromJson).
Map<String, dynamic> migrateGatesV1(Map<String, dynamic> json) {
  final regions = json['regions'] is Map ? Map<String, dynamic>.from(json['regions'] as Map) : <String, dynamic>{};
  final flags = json['storyFlags'] is Map ? json['storyFlags'] as Map : const {};
  bool flag(String k) => flags[k] == true;
  final collected = json['collected'] is List ? (json['collected'] as List).whereType<String>().toSet() : <String>{};
  final mapId = json['mapId'] is String ? json['mapId'] as String : 'world';
  final fragments = json['fragments'] is num ? (json['fragments'] as num).toInt() : 0;
  ({double x, double y})? point(Object? v) {
    if (v is! Map || v['x'] is! num || v['y'] is! num) return null;
    // saved positions are the player's top-left; use the body centre
    return (x: (v['x'] as num).toDouble() + 16, y: (v['y'] as num).toDouble() + 16);
  }

  final spots = [point(json['player']), point(json['checkpoint'])].whereType<({double x, double y})>();

  for (final goal in regionGoals.values) {
    final r = regions[goal.region] is Map
        ? Map<String, dynamic>.from(regions[goal.region] as Map)
        : <String, dynamic>{};
    final gates = r['gates'] is Map ? Map<String, dynamic>.from(r['gates'] as Map) : <String, dynamic>{};
    final defs = gatesIn(goal.region);
    final homeMap = defs.isEmpty ? '' : defs.first.mapId;
    final pastRegion = goal.region == 'woods' &&
        (mapId != homeMap ||
            flag('visited:city') ||
            flag('visited:town') ||
            flag('visited:ruins') ||
            flag('visited:core') ||
            flag('portalUnlocked:world2') ||
            flag('sentinelDefeated'));
    final exitEarned = goal.region == 'woods' &&
        mapId == homeMap &&
        (flag('portalUnlocked:world') || fragments >= 2);
    for (final g in defs) {
      var open = gates[g.id] == true || pastRegion;
      if (g.guards != null && collected.contains(g.guards)) open = true;
      if (g.kind == GateKind.boulder && exitEarned) open = true;
      if (mapId == g.mapId && spots.any((p) => g.zones.any((z) => z.containsPx(p.x, p.y)))) open = true;
      if (open) gates[g.id] = true;
    }
    r['gates'] = gates;
    if (pastRegion) {
      r['goalSet'] = true;
      r['farewellSeen'] = true;
    }
    regions[goal.region] = r;
  }
  json['regions'] = regions;
  return json;
}
