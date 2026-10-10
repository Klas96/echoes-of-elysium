import 'dart:math';

import 'package:flutter/material.dart';

import '../creatures/bonds.dart';
import '../ui/mmo_feedback.dart';
import 'progression.dart';
import 'save_service.dart';

/// Grey loot: salvage that only exists to be sold.
@immutable
class JunkItem {
  final String id;
  final String name;
  final String blurb;
  final int value;
  const JunkItem(this.id, this.name, this.blurb, this.value);
}

/// Something sold at Mira's stall that can still be bought back.
@immutable
class BuybackEntry {
  final String kind; // 'junk' | 'gear'
  final String id;
  final int price;
  const BuybackEntry(this.kind, this.id, this.price);

  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'price': price};

  static BuybackEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = j['kind'], id = j['id'], price = j['price'];
    if (kind is! String || id is! String || price is! num) return null;
    return BuybackEntry(kind, id, price.toInt());
  }
}

/// Selling junk and spare gear to Mira, with a short buyback list (#32).
/// Stored in the save's `extra`: `junk` ({id: count}) and `buyback` (newest
/// first, at most [buybackSize]).
class Trade {
  Trade._();

  static final revision = ValueNotifier<int>(0);
  static final _rng = Random();
  static const buybackSize = 6;

  /// Chance a downed UEC drone leaves salvage.
  static const junkDropChance = 0.55;

  static const junkCatalog = <String, JunkItem>{
    'frayed_wiring': JunkItem('frayed_wiring', 'Frayed Wiring', 'Drone guts. Still warm, still useless.', 2),
    'bent_servo': JunkItem('bent_servo', 'Bent Servo', 'A drone joint that only turns one way now.', 3),
    'cracked_lens': JunkItem('cracked_lens', 'Cracked Lens', 'It watched you once. Mira buys them anyway.', 4),
    'scorched_chip': JunkItem('scorched_chip', 'Scorched Chip', 'UEC firmware, cooked. Traders melt it down.', 5),
  };

  static SaveData get _d => SaveService.data;

  // ---------------------------------------------------------------- junk
  static Map<String, int> get junk {
    final raw = _d.extra['junk'];
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        if (e.value is num && (e.value as num) > 0 && junkCatalog.containsKey(e.key))
          e.key.toString(): (e.value as num).toInt(),
    };
  }

  static void _setJunk(Map<String, int> m) {
    final clean = {for (final e in m.entries) if (e.value > 0) e.key: e.value};
    if (clean.isEmpty) {
      _d.extra.remove('junk');
    } else {
      _d.extra['junk'] = clean;
    }
  }

  static int junkCount(String id) => junk[id] ?? 0;
  static int get junkTotal => junk.values.fold(0, (a, b) => a + b);
  static int get junkValue =>
      junk.entries.fold(0, (a, e) => a + (junkCatalog[e.key]?.value ?? 0) * e.value);

  static void addJunk(String id, [int n = 1]) {
    if (!junkCatalog.containsKey(id) || n <= 0) return;
    final m = junk;
    m[id] = (m[id] ?? 0) + n;
    _setJunk(m);
    _bump();
  }

  /// Rolls salvage for a downed drone; returns the id dropped (if any).
  static String? rollDroneJunk({double? roll, int? pick}) {
    final r = roll ?? _rng.nextDouble();
    if (r >= junkDropChance) return null;
    final ids = junkCatalog.keys.toList();
    final id = ids[(pick ?? _rng.nextInt(ids.length)) % ids.length];
    addJunk(id);
    MmoFeedback.pushPop('Junk · ${junkCatalog[id]!.name}', color: const Color(0xFFB0B0B8));
    return id;
  }

  static bool sellJunk(String id) {
    final item = junkCatalog[id];
    if (item == null || junkCount(id) <= 0) return false;
    final m = junk;
    m[id] = m[id]! - 1;
    _setJunk(m);
    Bonds.addGlimmer(item.value);
    _pushBuyback(BuybackEntry('junk', id, item.value));
    _bump();
    return true;
  }

  /// Sells every piece of junk; returns glimmer earned.
  static int sellAllJunk() {
    var earned = 0;
    for (final e in junk.entries) {
      for (var i = 0; i < e.value; i++) {
        if (sellJunk(e.key)) earned += junkCatalog[e.key]!.value;
      }
    }
    if (earned > 0) MmoFeedback.pushPop('+$earned ◆', color: const Color(0xFF88DDFF));
    return earned;
  }

  // ---------------------------------------------------------------- gear
  /// What Mira pays for a piece of gear: well under what she charges.
  static int gearSellPrice(String id) {
    final item = Progression.catalog[id];
    if (item == null) return 0;
    return max(3, (item.score / 3).round());
  }

  /// Owned gear not currently equipped.
  static List<String> get spareGear => [
        for (final id in Progression.inventory)
          if (!Progression.equipped.values.contains(id) && Progression.catalog.containsKey(id)) id,
      ];

  static bool sellGear(String id) {
    if (!spareGear.contains(id)) return false;
    final price = gearSellPrice(id);
    _d.inventory = [for (final g in Progression.inventory) if (g != id) g];
    Bonds.addGlimmer(price);
    _pushBuyback(BuybackEntry('gear', id, price));
    Progression.revision.value++;
    _bump();
    return true;
  }

  // ---------------------------------------------------------------- buyback
  static List<BuybackEntry> get buyback {
    final raw = _d.extra['buyback'];
    if (raw is! List) return [];
    return raw.map(BuybackEntry.fromJson).whereType<BuybackEntry>().toList();
  }

  static void _setBuyback(List<BuybackEntry> l) {
    if (l.isEmpty) {
      _d.extra.remove('buyback');
    } else {
      _d.extra['buyback'] = [for (final e in l.take(buybackSize)) e.toJson()];
    }
  }

  static void _pushBuyback(BuybackEntry e) => _setBuyback([e, ...buyback]);

  static String nameOf(BuybackEntry e) => e.kind == 'gear'
      ? (Progression.catalog[e.id]?.name ?? e.id)
      : (junkCatalog[e.id]?.name ?? e.id);

  /// Buy back the [index]th entry at the price it sold for.
  static bool buyBack(int index) {
    final list = buyback;
    if (index < 0 || index >= list.length) return false;
    final e = list[index];
    if (e.kind == 'gear' && Progression.inventory.contains(e.id)) return false;
    if (!Bonds.spendGlimmer(e.price)) return false;
    list.removeAt(index);
    _setBuyback(list);
    if (e.kind == 'gear') {
      _d.inventory = [...Progression.inventory, e.id];
      Progression.revision.value++;
    } else {
      final m = junk;
      m[e.id] = (m[e.id] ?? 0) + 1;
      _setJunk(m);
    }
    _bump();
    return true;
  }

  static void _bump() {
    revision.value++;
    SaveService.requestAutosave();
  }
}
