import 'package:flutter/foundation.dart';

import 'save_service.dart';

/// "Well rested" (#32): resting at a checkpoint grants a short buff, counted
/// in unpaused play time: extra health regen (even mid-fight) and a damage
/// bonus. Remaining seconds persist in the save (`extra.wellRested`).
class WellRested {
  WellRested._();

  static const duration = 180.0;
  static const damageBonus = 0.2; // +20%
  static const regenPerSecond = 2.0;
  static const _saveKey = 'wellRested';

  /// Seconds left (0 = not rested). Listen for the HUD chip.
  static final remaining = ValueNotifier<double>(0);

  static bool get active => remaining.value > 0;

  static void grant() {
    remaining.value = duration;
    _persist();
  }

  static void clear() {
    remaining.value = 0;
    _persist();
  }

  /// Restore from the save when a map starts.
  static void load() {
    final v = SaveService.data.extra[_saveKey];
    remaining.value = v is num ? v.toDouble().clamp(0.0, duration) : 0;
  }

  /// Called every game update with unpaused time.
  static void tick(double dt) {
    final before = remaining.value;
    if (before <= 0) return;
    final next = (before - dt).clamp(0.0, duration);
    remaining.value = next;
    // Persist on whole-second boundaries only; autosave picks it up.
    if (next.ceil() != before.ceil()) _persist();
  }

  static void _persist() {
    final v = remaining.value;
    if (v <= 0) {
      SaveService.data.extra.remove(_saveKey);
    } else {
      SaveService.data.extra[_saveKey] = double.parse(v.toStringAsFixed(1));
    }
  }

  /// Player shot damage with the buff applied.
  static int applyDamage(int base) => active ? (base * (1 + damageBonus)).round() : base;

  /// `2:58` style countdown.
  static String get label {
    final s = remaining.value.ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
