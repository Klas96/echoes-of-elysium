import '../game/save_service.dart';
import 'bonds.dart';
import 'region_gates.dart';
import 'regions.dart';

/// Hint shown when Kaela walks into a closed gate.
class GateHint {
  final String title;
  final String line;

  /// Level 3: Gaia speaks (names the place) instead of the examine toast.
  final bool gaia;
  const GateHint(this.title, this.line, {this.gaia = false});
}

/// Live state of the region goals and main-route gates, stored in
/// SaveData.regions (see save_service.dart). Gates open once and stay open.
class Gates {
  Gates._();

  /// GameState hooks (exit rule, tracker); set by GameState.
  static void Function(String gateId)? onOpened;
  static void Function()? onChanged;

  static Map<String, dynamic> _region(String r) => SaveService.data.regions.putIfAbsent(r, () => <String, dynamic>{});

  static Map<String, dynamic> _sub(String r, String key) {
    final m = _region(r);
    final v = m[key];
    if (v is Map<String, dynamic>) return v;
    final fresh = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    m[key] = fresh;
    return fresh;
  }

  static GateDef? def(String id) => gateDefs[id];

  static bool isOpen(String id) {
    final d = gateDefs[id];
    if (d == null) return true; // unknown gate: never block
    return SaveService.data.regions[d.region]?['gates'] is Map &&
        (SaveService.data.regions[d.region]!['gates'] as Map)[id] == true;
  }

  /// Its creature is a friend and Kaela is in the gate's (and creature's)
  /// home region, whoever is following her.
  static bool canOpen(String id) {
    final d = gateDefs[id];
    if (d == null || isOpen(id)) return false;
    return Bonds.isBefriended(d.creature) &&
        Regions.current == d.region &&
        Regions.abilityWorksIn(d.creature, Regions.current);
  }

  static void open(String id) {
    final d = gateDefs[id];
    if (d == null || isOpen(id)) return;
    _sub(d.region, 'gates')[id] = true;
    Bonds.revision.value++;
    onOpened?.call(id);
    onChanged?.call();
    SaveService.saveNow();
  }

  static int passes(String id) {
    final d = gateDefs[id];
    if (d == null) return 0;
    final v = SaveService.data.regions[d.region]?['hints'];
    return v is Map && v[id] is num ? (v[id] as num).toInt() : 0;
  }

  /// Kaela walked up to the closed gate [id] (call once per approach).
  /// Returns the hint to show, escalating to Gaia's line.
  static GateHint? registerPass(String id) {
    final d = gateDefs[id];
    if (d == null || isOpen(id)) return null;
    final n = passes(id) + 1;
    _sub(d.region, 'hints')[id] = n;
    SaveService.requestAutosave();
    if (GateHints.gaiaSpeaks(n)) return GateHint('GAIA', d.gaiaHint, gaia: true);
    return GateHint(d.title, d.blockedHint);
  }

  // --- region goal --------------------------------------------------------
  static bool goalSet(String region) => SaveService.data.regions[region]?['goalSet'] == true;

  static void setGoal(String region) {
    if (goalSet(region)) return;
    _region(region)['goalSet'] = true;
    onChanged?.call();
    SaveService.requestAutosave();
  }

  static int friends(String region) {
    final g = regionGoals[region];
    if (g == null) return 0;
    return g.friends.where(Bonds.isBefriended).length;
  }

  static String tracker(String region) => regionGoals[region]?.tracker(friends(region)) ?? '';

  /// Every gate of [region] is open.
  static bool allOpen(String region) => gatesIn(region).every((g) => isOpen(g.id));

  /// Snapshot of the friend count into the save (the bonds stay the truth).
  static void writeTo(SaveData d) {
    for (final r in regionGoals.keys) {
      if (!d.regions.containsKey(r) && friends(r) == 0) continue;
      d.regions.putIfAbsent(r, () => <String, dynamic>{})['friends'] = friends(r);
    }
  }

  // --- farewell ------------------------------------------------------------
  static bool farewellSeen(String region) => SaveService.data.regions[region]?['farewellSeen'] == true;

  /// The treeline farewell plays the first time Kaela leaves [region] with
  /// any of its friends.
  static bool wantsFarewell(String region) =>
      regionGoals.containsKey(region) && !farewellSeen(region) && Bonds.friendsIn(region).isNotEmpty;

  static void markFarewell(String region) {
    _region(region)['farewellSeen'] = true;
    SaveService.requestAutosave();
  }

  /// "Your friends find you at the treeline." on coming back.
  static bool wantsReturnLine(String region, {required String from}) =>
      regionGoals.containsKey(region) &&
      from.isNotEmpty &&
      from != region &&
      farewellSeen(region) &&
      Bonds.friendsIn(region).isNotEmpty;
}
