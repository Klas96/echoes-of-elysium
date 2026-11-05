import 'package:flutter/material.dart';

import 'dialog_chrome.dart';
import 'hud_layout.dart';
import 'mmo_feedback.dart';

/// WoW-style enter-zone toast: themed pixel banner + zone name only.
///
/// Fades in/out. Desktop gets a larger plate, nudged a bit further down.
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

  static const fadeDuration = Duration(milliseconds: 400);

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

  @override
  State<ZoneBanner> createState() => _ZoneBannerState();
}

class _ZoneBannerState extends State<ZoneBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  String? _title;
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
      setState(() {
        _title = title;
        _region = region;
      });
      if (animate) {
        _fade.forward();
      } else {
        _fade.value = 1;
      }
      return;
    }
    // Cleared — fade out, then drop the held plate.
    if (_title == null) return;
    if (!animate) {
      _fade.value = 0;
      setState(() {
        _title = null;
        _region = null;
      });
      return;
    }
    _fade.reverse().then((_) {
      if (!mounted) return;
      if (MmoFeedback.zoneTitle.value != null) return;
      setState(() {
        _title = null;
        _region = null;
      });
    });
  }

  static EdgeInsets _textPadding(String? regionId, double bannerW, double artH) {
    final f = ZoneBanner.plateInsets[regionId] ??
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
    final title = _title;
    final region = _region;
    if (title == null) return const SizedBox.shrink();
    final asset = ZoneBanner.assetFor(region);
    if (asset == null) return const SizedBox.shrink();

    final accent = ZoneBanner.accentFor(region);
    final screen = MediaQuery.sizeOf(context);
    final short = screen.height < 500;
    final narrow = HudLayout.narrow(screen);
    final desktop = !HudLayout.isTouch && !narrow;
    final compact = short || narrow;
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
        ),
      ),
    );
  }
}
