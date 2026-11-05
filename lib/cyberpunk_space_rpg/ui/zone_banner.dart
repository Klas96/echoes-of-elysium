import 'package:flutter/material.dart';

import 'dialog_chrome.dart';
import 'mmo_feedback.dart';

/// WoW-style enter-zone toast: themed pixel banner + zone name only.
///
/// The plate art *is* the frame (transparent outside the motifs). No DialogChrome
/// / toast border wrapper — just the hard AI→NN sheet with the title centered
/// on the empty plate band (no flavor subtext).
class ZoneBanner extends StatelessWidget {
  const ZoneBanner({super.key});

  static const assets = {
    'woods': 'assets/images/ui/zone_banners/woods.png',
    'city': 'assets/images/ui/zone_banners/city.png',
    'works': 'assets/images/ui/zone_banners/works.png',
    'ruins': 'assets/images/ui/zone_banners/ruins.png',
    'core': 'assets/images/ui/zone_banners/core.png',
    'town': 'assets/images/ui/zone_banners/town.png',
  };

  /// Fractional insets into the dark text plate of each 240×80 sheet
  /// (measured from art + a few px of inner margin so glyphs stay inside).
  static const plateInsets = {
    'woods': EdgeInsets.fromLTRB(0.30, 0.42, 0.32, 0.28),
    'city': EdgeInsets.fromLTRB(0.29, 0.38, 0.29, 0.22),
    'works': EdgeInsets.fromLTRB(0.27, 0.40, 0.25, 0.24),
    'ruins': EdgeInsets.fromLTRB(0.14, 0.40, 0.20, 0.26),
    'core': EdgeInsets.fromLTRB(0.26, 0.30, 0.27, 0.26),
    'town': EdgeInsets.fromLTRB(0.28, 0.34, 0.28, 0.32),
  };

  /// Plate insets for [regionId], or null when unknown.
  static EdgeInsets? plateInsetsFor(String? regionId) =>
      regionId == null ? null : plateInsets[regionId];

  /// Asset path for [regionId], or null when unknown.
  static String? assetFor(String? regionId) =>
      regionId == null ? null : assets[regionId];

  static Color accentFor(String? regionId) => switch (regionId) {
        'woods' => const Color(0xFFAAFFEE),
        'city' => DialogChrome.cyan,
        'works' => const Color(0xFFFFCCAA),
        'ruins' => const Color(0xFFFFAADD),
        'core' => const Color(0xFFAAFFEE),
        'town' => const Color(0xFFFFE08A),
        _ => DialogChrome.cyan,
      };

  static EdgeInsets _textPadding(String? regionId, double bannerW, double artH) {
    final f = plateInsets[regionId] ??
        const EdgeInsets.fromLTRB(0.28, 0.36, 0.28, 0.28);
    return EdgeInsets.fromLTRB(
      bannerW * f.left,
      artH * f.top,
      bannerW * f.right,
      artH * f.bottom,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: MmoFeedback.zoneTitle,
      builder: (_, title, __) {
        if (title == null) return const SizedBox.shrink();
        return ValueListenableBuilder<String?>(
          valueListenable: MmoFeedback.zoneRegion,
          builder: (_, region, __) {
            final asset = assetFor(region);
            if (asset == null) return const SizedBox.shrink();
            final accent = accentFor(region);
            final screen = MediaQuery.sizeOf(context);
            final short = screen.height < 500;
            final narrow = screen.width < 400;
            final compact = short || narrow;
            final maxW = screen.width * 0.9;
            // Native sheets are 240×80 (3:1). Cap on short landscape for HUD.
            final bannerW =
                short ? maxW.clamp(200.0, 300.0) : maxW.clamp(240.0, 420.0);
            final artH = bannerW / 3;

            return IgnorePointer(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: SizedBox(
                    key: const ValueKey('hud-banner-card'),
                    width: bannerW,
                    height: artH,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            asset,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.none,
                            isAntiAlias: false,
                            gaplessPlayback: true,
                          ),
                        ),
                        Padding(
                          padding: _textPadding(region, bannerW, artH),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                title.toUpperCase(),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                softWrap: false,
                                style: DialogChrome.zoneTitleStyle(
                                  accent: accent,
                                  compact: compact,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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
