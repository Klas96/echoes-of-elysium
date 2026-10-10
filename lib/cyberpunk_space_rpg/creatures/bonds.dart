import 'package:flutter/foundation.dart';

import '../game/save_service.dart';
import 'creature_species.dart';
import 'regions.dart';

/// Creature bonds, items, companion and ability-gated secrets, all stored in
/// the live save ([SaveService.data]):
/// - bonds: `{"glowmoth": {"seen": true, "befriended": false}}`
/// - activeCompanion: creature id (must be befriended)
/// - abilities: abilities unlocked by befriended creatures (the one in use
///   is the active companion's)
/// - storyFlags `item:<id>` (carried), `used:<id>` (given away),
///   `secret:<objectId>` (boulder pushed, path revealed, glyph read, stash or
///   buried item found, dark zone lit)
/// - glimmer
class Bonds {
  /// Bumped on every change so the journal/HUD can rebuild.
  static final revision = ValueNotifier<int>(0);

  static SaveData get _d => SaveService.data;

  static void _changed({bool now = false}) {
    revision.value++;
    if (now) {
      SaveService.saveNow();
    } else {
      SaveService.requestAutosave();
    }
  }

  static Map<String, dynamic> _entry(String id) => _d.bonds.putIfAbsent(id, () => <String, dynamic>{});

  static bool isBefriended(String id) => _d.bonds[id]?['befriended'] == true;
  static bool isSeen(String id) => _d.bonds[id]?['seen'] == true || isBefriended(id);

  /// Returns true the first time.
  static bool markSeen(String id) {
    if (isSeen(id)) return false;
    _entry(id)['seen'] = true;
    _changed();
    return true;
  }

  static void befriend(String id) {
    if (isBefriended(id)) return;
    _entry(id)
      ..['seen'] = true
      ..['befriended'] = true;
    final ability = creatureSpecies[id]?.ability;
    if (ability != null) _d.abilities.add(ability.saveKey);
    // First friend with an ability (or the very first friend) comes along.
    final cur = active;
    if (cur == null || (ability != null && creatureSpecies[cur]?.ability == null)) {
      _d.activeCompanion = id;
    }
    _changed(now: true);
  }

  static int get befriendedCount => creatureOrder.where(isBefriended).length;
  static int get total => creatureOrder.length;

  static String? get active {
    final id = _d.activeCompanion;
    return id != null && isBefriended(id) ? id : null;
  }

  /// Swap (or with null, send home) the companion. Only befriended ones.
  static void setActive(String? id) {
    if (id != null && !isBefriended(id)) return;
    if (_d.activeCompanion == id) return;
    _d.activeCompanion = id;
    _changed(now: true);
  }

  /// The chosen companion if it lives in the region on screen; companions
  /// wait at home elsewhere (Regions).
  static String? get activeHere {
    final id = active;
    return id != null && Regions.followsIn(id, Regions.current) ? id : null;
  }

  /// The ability of the companion walking with Kaela right now (none outside
  /// its home region).
  static Ability? get activeAbility {
    final id = activeHere;
    return id == null ? null : creatureSpecies[id]?.ability;
  }

  static bool has(Ability a) => activeAbility == a;

  /// Befriended creatures whose home is [region].
  static List<String> friendsIn(String region) =>
      [for (final id in creatureOrder) if (isBefriended(id) && Regions.homeOf(id) == region) id];
  static bool unlocked(Ability a) => _d.abilities.contains(a.saveKey);

  // --- items ---------------------------------------------------------------
  static bool hasItem(String item) => _d.flag('item:$item');
  static bool usedItem(String item) => _d.flag('used:$item');
  static Set<String> get items => {
        for (final e in _d.storyFlags.entries)
          if (e.value && e.key.startsWith('item:')) e.key.substring(5)
      };

  static void giveItem(String item) {
    _d.setFlag('item:$item');
    _changed();
  }

  static void useItem(String item) {
    _d.setFlag('item:$item', false);
    _d.setFlag('used:$item');
    _changed();
  }

  // --- secrets / glimmer ---------------------------------------------------
  static bool secretDone(String id) => _d.flag('secret:$id');

  static void markSecret(String id) {
    if (secretDone(id)) return;
    _d.setFlag('secret:$id');
    _changed();
  }

  static int get glimmer => _d.glimmer;

  static void addGlimmer(int n) {
    _d.glimmer += n;
    _changed();
  }

  /// Spend glimmer. Returns false if the balance is too low.
  static bool spendGlimmer(int n) {
    if (n <= 0) return true;
    if (_d.glimmer < n) return false;
    _d.glimmer -= n;
    _changed();
    return true;
  }
}
