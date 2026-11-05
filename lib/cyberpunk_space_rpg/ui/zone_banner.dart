import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dialog_chrome.dart';
import 'mmo_feedback.dart';

/// WoW-style enter-zone toast: chunky hard-pixel banner frame + themed flanks.
///
/// Matches [DialogChrome] neon-pixel grammar (double stroke, corner ticks,
/// cyan/magenta accents) — not a soft Material card. Per-region motifs sit
/// left/right of the name + flavor (woods trees, city neon, etc.).
class ZoneBanner extends StatelessWidget {
  const ZoneBanner({super.key});

  /// Kept for tests / asset catalog — flank art sheets live here if needed.
  static const assets = {
    'woods': 'assets/images/ui/zone_banners/woods.png',
    'city': 'assets/images/ui/zone_banners/city.png',
    'works': 'assets/images/ui/zone_banners/works.png',
    'ruins': 'assets/images/ui/zone_banners/ruins.png',
    'core': 'assets/images/ui/zone_banners/core.png',
    'town': 'assets/images/ui/zone_banners/town.png',
  };

  /// Asset path for [regionId], or null when unknown.
  static String? assetFor(String? regionId) =>
      regionId == null ? null : assets[regionId];

  static Color accentFor(String? regionId) => switch (regionId) {
        'woods' => const Color(0xFF66FFAA),
        'city' => DialogChrome.cyan,
        'works' => const Color(0xFFFF9966),
        'ruins' => DialogChrome.magenta,
        'core' => const Color(0xFF88E0FF),
        'town' => const Color(0xFFFFCC66),
        _ => DialogChrome.cyan,
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: MmoFeedback.zoneTitle,
      builder: (_, title, __) {
        if (title == null) return const SizedBox.shrink();
        return ValueListenableBuilder<String?>(
          valueListenable: MmoFeedback.zoneRegion,
          builder: (_, region, __) {
            final screen = MediaQuery.sizeOf(context);
            final short = screen.height < 500;
            final narrow = screen.width < 400;
            final accent = accentFor(region);
            final maxW = screen.width * 0.9;
            // Compact on short landscape so meal/toast chips stay clear.
            final bannerW = short ? maxW.clamp(220.0, 340.0) : maxW.clamp(260.0, 440.0);
            final motifW = short ? 28.0 : (narrow ? 34.0 : 42.0);
            final padH = short ? 10.0 : 14.0;
            final padV = short ? 7.0 : 10.0;

            return IgnorePointer(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: SizedBox(
                    key: const ValueKey('hud-banner-card'),
                    width: bannerW,
                    child: DialogChrome.zoneBannerShell(
                      accent: accent,
                      padding: EdgeInsets.fromLTRB(padH, padV, padH, padV),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: motifW,
                            height: short ? 36 : 48,
                            child: CustomPaint(
                              painter: _ZoneMotifPainter(region: region ?? '', mirror: false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title.toUpperCase(),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DialogChrome.zoneTitleStyle(
                                    accent: accent,
                                    compact: short || narrow,
                                  ),
                                ),
                                ValueListenableBuilder<String?>(
                                  valueListenable: MmoFeedback.zoneBlurb,
                                  builder: (_, blurb, __) {
                                    if (blurb == null || blurb.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        blurb,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: DialogChrome.zoneBlurbStyle(
                                          compact: short || narrow,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: motifW,
                            height: short ? 36 : 48,
                            child: CustomPaint(
                              painter: _ZoneMotifPainter(region: region ?? '', mirror: true),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Hard 1×1 / 2×2 block motifs — no gradients, no soft strokes.
class _ZoneMotifPainter extends CustomPainter {
  final String region;
  final bool mirror;

  _ZoneMotifPainter({required this.region, required this.mirror});

  @override
  void paint(Canvas canvas, Size size) {
    if (mirror) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final u = math.max(2.0, (size.width / 14).floorToDouble());
    void px(double x, double y, Color c, [double w = 1, double h = 1]) {
      canvas.drawRect(
        Rect.fromLTWH((x * u).floorToDouble(), (y * u).floorToDouble(),
            (w * u).floorToDouble().clamp(1, 999), (h * u).floorToDouble().clamp(1, 999)),
        Paint()..color = c,
      );
    }

    switch (region) {
      case 'woods':
        // Pine + moonflower flecks.
        px(5, 1, const Color(0xFF1A3A28), 4, 2);
        px(4, 3, const Color(0xFF2E6B45), 6, 2);
        px(3, 5, const Color(0xFF3F8A58), 8, 2);
        px(6, 7, const Color(0xFF4A3420), 2, 5);
        px(2, 10, const Color(0xFFAAFFEE), 2, 2);
        px(10, 9, const Color(0xFF66FFAA), 2, 2);
        px(1, 2, const Color(0xFF88E0FF), 2, 2); // moon speck
      case 'city':
        // Neon bar + rooftop blocks.
        px(2, 2, const Color(0xFF1A2030), 10, 3);
        px(3, 5, const Color(0xFF243044), 8, 4);
        px(4, 9, const Color(0xFF1A2030), 6, 3);
        px(2, 3, DialogChrome.cyan, 10, 1);
        px(5, 6, DialogChrome.magenta, 2, 1);
        px(8, 7, DialogChrome.cyan, 1, 1);
      case 'works':
        // Crane hook + barrel.
        px(6, 1, const Color(0xFF8A5A3A), 2, 8);
        px(4, 2, const Color(0xFFB87848), 6, 1);
        px(3, 8, const Color(0xFF664428), 4, 3);
        px(4, 9, const Color(0xFF88E0FF), 2, 1); // oil sheen
        px(9, 10, const Color(0xFFFF9966), 3, 2);
      case 'ruins':
        // Broken pillar + neon shard.
        px(5, 1, const Color(0xFF3A3A48), 4, 10);
        px(4, 2, const Color(0xFF4A4A5A), 1, 3);
        px(9, 4, DialogChrome.magenta, 2, 4);
        px(3, 8, DialogChrome.cyan, 2, 1);
        px(6, 11, const Color(0xFF2A2A38), 5, 1);
      case 'core':
        // Crystal + gold ring ticks.
        px(6, 1, const Color(0xFF88E0FF), 2, 10);
        px(5, 3, const Color(0xFFAAFFEE), 4, 2);
        px(4, 5, const Color(0xFF66CCFF), 6, 2);
        px(3, 7, const Color(0xFFFFE08A), 1, 1);
        px(10, 7, const Color(0xFFFFE08A), 1, 1);
        px(5, 10, const Color(0xFF3A5060), 4, 1);
      case 'town':
        // Lantern + awning.
        px(5, 1, const Color(0xFF4A3420), 2, 3);
        px(4, 4, const Color(0xFFFFCC66), 4, 4);
        px(5, 5, const Color(0xFFFFEEAA), 2, 2);
        px(3, 9, const Color(0xFF884422), 8, 2);
        px(2, 8, const Color(0xFFCC6644), 10, 1);
      default:
        px(5, 4, DialogChrome.cyan, 4, 4);
        px(6, 5, DialogChrome.magenta, 2, 2);
    }
  }

  @override
  bool shouldRepaint(covariant _ZoneMotifPainter old) =>
      old.region != region || old.mirror != mirror;
}
