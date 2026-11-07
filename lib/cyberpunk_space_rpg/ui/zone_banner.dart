import 'package:flutter/material.dart';

import 'dialog_chrome.dart';
import 'hud_layout.dart';
import 'mmo_feedback.dart';

/// WoW-style enter-zone toast: themed pixel banner with baked-in title.
///
/// Fades in/out. Desktop gets a larger plate, nudged a bit further down.
/// Title glyphs live in the PNG so they always sit inside the plate art.
class ZoneBanner extends StatefulWidget {
  const ZoneBanner({super.key});

  static const assets = {
    'woods': 'assets/images/ui/zone_banners/woods.png',
    'city': 'assets/images/ui/zone_banners/city.png',
    'works': 'assets/images/ui/zone_banners/works.png',
    'ruins': 'assets/images/ui/zone_banners/ruins.png',
    'core': 'assets/images/ui/zone_banners/core.png',
    'town': 'assets/images/ui/zone_banners/town.png',
  };

  static const fadeDuration = Duration(milliseconds: 400);

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
  State<ZoneBanner> createState() => _ZoneBannerState();
}

class _ZoneBannerState extends State<ZoneBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  String? _region;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: ZoneBanner.fadeDuration,
    );
    MmoFeedback.zoneTitle.addListener(_onZone);
    MmoFeedback.zoneRegion.addListener(_onZone);
    _syncFromNotifiers(animate: false);
  }

  @override
  void dispose() {
    MmoFeedback.zoneTitle.removeListener(_onZone);
    MmoFeedback.zoneRegion.removeListener(_onZone);
    _fade.dispose();
    super.dispose();
  }

  void _onZone() => _syncFromNotifiers(animate: true);

  void _syncFromNotifiers({required bool animate}) {
    final title = MmoFeedback.zoneTitle.value;
    final region = MmoFeedback.zoneRegion.value;
    final asset = ZoneBanner.assetFor(region);
    if (title != null && asset != null) {
      setState(() => _region = region);
      if (animate) {
        _fade.forward();
      } else {
        _fade.value = 1;
      }
      return;
    }
    // Cleared — fade out, then drop the held plate.
    if (_region == null) return;
    if (!animate) {
      _fade.value = 0;
      setState(() => _region = null);
      return;
    }
    _fade.reverse().then((_) {
      if (!mounted) return;
      if (MmoFeedback.zoneTitle.value != null) return;
      setState(() => _region = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final region = _region;
    if (region == null) return const SizedBox.shrink();
    final asset = ZoneBanner.assetFor(region);
    if (asset == null) return const SizedBox.shrink();

    final screen = MediaQuery.sizeOf(context);
    final short = screen.height < 500;
    final narrow = HudLayout.narrow(screen);
    final desktop = !HudLayout.isTouch && !narrow;
    final maxW = screen.width * 0.9;
    // Desktop: larger plate. Short landscape stays capped for HUD room.
    final double bannerW;
    if (short) {
      bannerW = maxW.clamp(200.0, 300.0);
    } else if (desktop) {
      bannerW = maxW.clamp(360.0, 560.0);
    } else {
      bannerW = maxW.clamp(240.0, 420.0);
    }
    final artH = bannerW / 3;
    // Desktop: sit a bit further under the top HUD row.
    final topPad = desktop ? 36.0 : 0.0;

    return IgnorePointer(
      child: FadeTransition(
        opacity: _fade,
        child: Padding(
          padding: EdgeInsets.only(top: topPad),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: SizedBox(
                key: const ValueKey('hud-banner-card'),
                width: bannerW,
                height: artH,
                child: Image.asset(
                  asset,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                  isAntiAlias: false,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
