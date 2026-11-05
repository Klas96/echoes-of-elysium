import 'package:flutter/material.dart';

import 'dialog_chrome.dart';
import 'mmo_feedback.dart';

/// WoW-style enter-zone toast: themed pixel banner + text only.
///
/// The plate art *is* the frame (transparent outside the motifs). No DialogChrome
/// / toast border wrapper — just the hard AI→NN sheet with name + flavor on the
/// empty center band.
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
            final maxW = screen.width * 0.9;
            // Native sheets are 240×80 (3:1). Cap on short landscape for HUD.
            final bannerW = short ? maxW.clamp(200.0, 300.0) : maxW.clamp(240.0, 420.0);
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
                      alignment: Alignment.center,
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
                          padding: EdgeInsets.symmetric(
                            horizontal: bannerW * 0.22,
                            vertical: artH * 0.18,
                          ),
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
                                    padding: const EdgeInsets.only(top: 2),
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
