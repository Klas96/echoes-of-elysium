import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

/// Simple day/night cycle: one day is [dayLengthSeconds] of play (10 real
/// minutes). Time is a 0..1 fraction of the day, 0 = midnight (the same as
/// SaveData.dayTime).
class DayCycle {
  static const dayLengthSeconds = 600.0;
  static const nightStart = 0.8;
  static const nightEnd = 0.22;

  /// Live time of day for the current map; persisted via SaveData.dayTime.
  static final time = ValueNotifier<double>(0.3);

  static double advance(double t, double dt) => (t + dt / dayLengthSeconds) % 1.0;

  static bool isNight(double t) => t >= nightStart || t < nightEnd;
  static bool get night => isNight(time.value);

  static String label(double t) {
    if (t < nightEnd) return 'NIGHT';
    if (t < 0.3) return 'DAWN';
    if (t < 0.72) return 'DAY';
    if (t < nightStart) return 'DUSK';
    return 'NIGHT';
  }

  /// Resting at a checkpoint: by day sleep until nightfall, by night until
  /// morning.
  static double restTarget(double t) => isNight(t) ? 0.3 : 0.84;

  /// 0 (full day) .. 1 (deep night).
  static double darkness(double t) {
    double ramp(double a, double b, double x) => ((x - a) / (b - a)).clamp(0.0, 1.0);
    if (t >= 0.3 && t <= 0.72) return 0;
    if (t > 0.72) return ramp(0.72, 0.84, t);
    return 1 - ramp(0.18, 0.3, t);
  }

  /// Screen tint: cool blue at night only (no amber dawn/dusk wash).
  /// [strength] scales the wash (e.g. lower on maps with no lamp pools).
  static Color tint(double t, {double strength = 1.0}) {
    final n = darkness(t);
    if (n <= 0) return const Color(0x00000000);
    final a = (0.46 * n * strength.clamp(0.0, 1.0)).clamp(0.0, 0.5);
    return const Color(0xFF0A1236).withValues(alpha: a);
  }
}
