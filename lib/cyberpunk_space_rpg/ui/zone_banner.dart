import 'package:flutter/material.dart';

import 'dialog_chrome.dart';
import 'mmo_feedback.dart';

/// Per-region pixel-art enter-zone plate (woods trees, city neon, etc.).
class ZoneBanner extends StatelessWidget {
  const ZoneBanner({super.key});

  static const _assets = {
    'woods': 'assets/images/ui/zone_banners/woods.png',
    'city': 'assets/images/ui/zone_banners/city.png',
    'works': 'assets/images/ui/zone_banners/works.png',
    'ruins': 'assets/images/ui/zone_banners/ruins.png',
    'core': 'assets/images/ui/zone_banners/core.png',
    'town': 'assets/images/ui/zone_banners/town.png',
  };

  /// Asset path for [regionId], or null when unknown.
  static String? assetFor(String? regionId) =>
      regionId == null ? null : _assets[regionId];

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
            final screen = MediaQuery.sizeOf(context);
            final maxW = screen.width * 0.86;
            // Native art is 360×120 (3:1). Cap hard on short landscape so the
            // plate stays above meal/toast chips (HUD layout tests at 915×412).
            final short = screen.height < 500;
            final bannerW = short ? maxW.clamp(160.0, 260.0) : maxW.clamp(220.0, 380.0);
            final artH = short ? bannerW / 3.4 : bannerW / 3;
            return IgnorePointer(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: SizedBox(
                    key: const ValueKey('hud-banner-card'),
                    width: bannerW,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (asset != null)
                          Image.asset(
                            asset,
                            width: bannerW,
                            height: artH,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.none,
                            isAntiAlias: false,
                            gaplessPlayback: true,
                          )
                        else
                          SizedBox(
                            width: bannerW,
                            height: artH,
                            child: DialogChrome.zoneBannerShell(
                              child: const SizedBox.expand(),
                            ),
                          ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: bannerW * 0.18,
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
                                style: DialogChrome.zoneTitleStyle().copyWith(
                                  fontSize: screen.width < 400 ? 12.0 : 14.0,
                                  shadows: const [
                                    Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(0, 1)),
                                  ],
                                ),
                              ),
                              ValueListenableBuilder<String?>(
                                valueListenable: MmoFeedback.zoneBlurb,
                                builder: (_, blurb, __) {
                                  if (blurb == null || blurb.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      blurb,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: DialogChrome.zoneBlurbStyle().copyWith(
                                        fontSize: screen.width < 400 ? 9.5 : 10.5,
                                        color: Colors.white.withValues(alpha: 0.88),
                                        shadows: const [
                                          Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(0, 1)),
                                        ],
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
