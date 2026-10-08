import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../components/uec_drone.dart';
import '../creatures/bonds.dart';
import '../creatures/interaction.dart';
import 'save_service.dart';

enum GearSlot { rifle, suit, relic }

/// A piece of gear Kaela can equip. MMO-light: small flat bonuses.
@immutable
class GearItem {
  final String id;
  final String name;
  final String blurb;
  final GearSlot slot;
  final int damage;
  final int health;
  /// Multiplier on fire cooldown (< 1 = shoots faster).
  final double fireCooldown;

  const GearItem({
    required this.id,
    required this.name,
    required this.blurb,
    required this.slot,
    this.damage = 0,
    this.health = 0,
    this.fireCooldown = 1.0,
  });

  int get score => damage * 3 + health + ((1.0 - fireCooldown) * 40).round();
}

/// XP, levels and loot — the Runescape/WoW-lite progression layer.
///
/// Main quest stays in [GameState] / memories; this only tracks power growth.
class Progression {
  Progression._();

  static final revision = ValueNotifier<int>(0);
  static final _rng = Random();

  static const catalog = <String, GearItem>{
    'scrap_plating': GearItem(
      id: 'scrap_plating',
      name: 'Scrap Plating',
      blurb: 'Bent UEC hull plates strapped to the suit.',
      slot: GearSlot.suit,
      health: 15,
    ),
    'pulse_optic': GearItem(
      id: 'pulse_optic',
      name: 'Pulse Optic',
      blurb: 'Sniper lens tuned for Kaela\'s rifle.',
      slot: GearSlot.rifle,
      damage: 5,
    ),
    'barrier_coil': GearItem(
      id: 'barrier_coil',
      name: 'Barrier Coil',
      blurb: 'Shield capacitor bolted into the suit lining.',
      slot: GearSlot.suit,
      health: 30,
      damage: 2,
    ),
    'swarm_thrusters': GearItem(
      id: 'swarm_thrusters',
      name: 'Swarm Thrusters',
      blurb: 'Tiny jets scavenged from pack drones.',
      slot: GearSlot.relic,
      fireCooldown: 0.85,
      damage: 1,
    ),
    'sentinel_core': GearItem(
      id: 'sentinel_core',
      name: 'Sentinel Core',
      blurb: 'A still-warm UEC command crystal.',
      slot: GearSlot.relic,
      damage: 6,
      health: 20,
      fireCooldown: 0.9,
    ),
    'lantern_charm': GearItem(
      id: 'lantern_charm',
      name: 'Lantern Charm',
      blurb: 'Colony glass that hums when Mira smiles.',
      slot: GearSlot.relic,
      health: 10,
      damage: 2,
      fireCooldown: 0.95,
    ),
  };

  static SaveData get _d => SaveService.data;

  static int get level => _d.level;
  static int get xp => _d.xp;
  static List<String> get inventory => _d.inventory;
  static Map<String, String> get equipped => _d.equipped;

  static int xpToNext(int forLevel) => 50 + (forLevel - 1) * 35;

  static double get xpProgress {
    final need = xpToNext(level);
    return need <= 0 ? 0 : (xp / need).clamp(0.0, 1.0);
  }

  /// Flat damage from level + rifle/relic.
  static int get bonusDamage {
    var n = level ~/ 2; // +1 every 2 levels
    for (final id in equipped.values) {
      n += catalog[id]?.damage ?? 0;
    }
    return n;
  }

  static int get bonusHealth {
    var n = (level - 1) * 5;
    for (final id in equipped.values) {
      n += catalog[id]?.health ?? 0;
    }
    return n;
  }

  /// Multiplies base shoot cooldown (lower = faster).
  static double get fireCooldownMult {
    var m = 1.0;
    for (final id in equipped.values) {
      final item = catalog[id];
      if (item != null) m *= item.fireCooldown;
    }
    return m.clamp(0.55, 1.0);
  }

  static GearItem? equippedIn(GearSlot slot) {
    final id = equipped[slot.name];
    return id == null ? null : catalog[id];
  }

  static String slotLabel(GearSlot slot) => switch (slot) {
        GearSlot.rifle => 'RIFLE',
        GearSlot.suit => 'SUIT',
        GearSlot.relic => 'RELIC',
      };

  static String statsLine(GearItem item) {
    final parts = <String>[];
    if (item.damage != 0) parts.add('+${item.damage} DMG');
    if (item.health != 0) parts.add('+${item.health} HP');
    if (item.fireCooldown < 1.0) {
      final pct = ((1.0 - item.fireCooldown) * 100).round();
      parts.add('+$pct% RATE');
    }
    return parts.isEmpty ? '—' : parts.join('  ·  ');
  }

  /// Buy catalog gear with glimmer (shop). Returns false if already owned or broke.
  static bool buyWithGlimmer(String id, int price) {
    final item = catalog[id];
    if (item == null || inventory.contains(id)) return false;
    if (!Bonds.spendGlimmer(price)) return false;
    _grantGear(id);
    return true;
  }

  /// Equip an owned item into its slot.
  static void equip(String id) {
    final item = catalog[id];
    if (item == null || !inventory.contains(id)) return;
    _d.equipped = {...equipped, item.slot.name: id};
    _bump();
  }

  /// Clear a slot (item stays in inventory).
  static void unequip(GearSlot slot) {
    if (!equipped.containsKey(slot.name)) return;
    final next = Map<String, String>.from(equipped)..remove(slot.name);
    _d.equipped = next;
    _bump();
  }

  static void _bump() {
    revision.value++;
    SaveService.requestAutosave();
  }

  static void grantXp(int amount, {String? reason}) {
    if (amount <= 0) return;
    _d.xp += amount;
    var leveled = false;
    while (_d.xp >= xpToNext(_d.level)) {
      _d.xp -= xpToNext(_d.level);
      _d.level += 1;
      leveled = true;
    }
    _bump();
    if (leveled) {
      GameToast.show(
        'LEVEL ${_d.level}',
        body: reason == null
            ? 'Kaela grows stronger. +${bonusHealth} max HP from levels & gear.'
            : reason,
        color: const Color(0xFFFFE08A),
        seconds: 3.5,
      );
    }
  }

  /// Called when a UEC drone is destroyed.
  static void onDroneKilled(DroneKind kind) {
    final xpGain = switch (kind) {
      DroneKind.scout => 15,
      DroneKind.sniper => 22,
      DroneKind.shield => 30,
      DroneKind.swarm => 10,
    };
    final glimmerGain = switch (kind) {
      DroneKind.scout => 2,
      DroneKind.sniper => 3,
      DroneKind.shield => 4,
      DroneKind.swarm => 1,
    };
    Bonds.addGlimmer(glimmerGain);
    grantXp(xpGain);

    final drop = _rollDrop(kind);
    if (drop != null) _grantGear(drop);
  }

  static void onSentinelKilled() {
    Bonds.addGlimmer(15);
    grantXp(120, reason: 'The Sentinel falls. Kaela\'s neural attunement deepens.');
    _grantGear('sentinel_core');
  }

  static String? _rollDrop(DroneKind kind) {
    final (id, chance) = switch (kind) {
      DroneKind.scout => ('scrap_plating', 0.35),
      DroneKind.sniper => ('pulse_optic', 0.40),
      DroneKind.shield => ('barrier_coil', 0.45),
      DroneKind.swarm => ('swarm_thrusters', 0.30),
    };
    if (inventory.contains(id)) return null;
    return _rng.nextDouble() < chance ? id : null;
  }

  static void _grantGear(String id) {
    final item = catalog[id];
    if (item == null) return;
    if (inventory.contains(id)) {
      Bonds.addGlimmer(5);
      GameToast.show(
        '+5 GLIMMER',
        body: 'Duplicate ${item.name} salvaged for parts.',
        color: const Color(0xFFFFE08A),
        seconds: 2.5,
      );
      return;
    }
    _d.inventory = [...inventory, id];
    final current = equippedIn(item.slot);
    final shouldEquip = current == null || item.score > current.score;
    if (shouldEquip) {
      _d.equipped = {...equipped, item.slot.name: id};
    }
    _bump();
    GameToast.show(
      shouldEquip ? 'EQUIPPED' : 'LOOT',
      body: '${item.name} — ${item.blurb}',
      color: const Color(0xFF66CCFF),
      seconds: 3.5,
    );
  }
}
