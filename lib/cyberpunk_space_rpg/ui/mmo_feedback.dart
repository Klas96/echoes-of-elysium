import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Floating +XP / loot pops and zone-enter banners — WoW/RS-style feedback.
class MmoFeedback {
  MmoFeedback._();

  static final pops = ValueNotifier<List<HudPop>>(const []);
  static final zoneTitle = ValueNotifier<String?>(null);
  static final zoneBlurb = ValueNotifier<String?>(null);

  // Damage numbers (components/damage_number.dart) share the pop look.
  static const hitColor = Color(0xFFFFFFFF);
  static const restedHitColor = Color(0xFFFFCC66);
  static const shieldColor = Color(0xFF66CCFF);
  static const damageTakenColor = Color(0xFFFF6666);

  /// Text style of HUD pops and in-world damage numbers.
  static TextStyle popStyle(Color color, {double fontSize = 13}) => TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
        shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
      );

  static int _seq = 0;
  static String? _zoneClearToken;

  static void pushPop(String text, {Color color = const Color(0xFFFFE08A)}) {
    _seq++;
    final id = _seq;
    final next = [...pops.value, HudPop(id: id, text: text, color: color)];
    while (next.length > 5) {
      next.removeAt(0);
    }
    pops.value = next;
    Future.delayed(const Duration(milliseconds: 1600), () {
      pops.value = [for (final p in pops.value) if (p.id != id) p];
    });
  }

  static void enterZone(String title, {String? blurb}) {
    zoneTitle.value = title;
    zoneBlurb.value = blurb;
    final token = title;
    _zoneClearToken = token;
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (_zoneClearToken == token) {
        zoneTitle.value = null;
        zoneBlurb.value = null;
      }
    });
  }
}

@immutable
class HudPop {
  final int id;
  final String text;
  final Color color;

  const HudPop({required this.id, required this.text, required this.color});
}
