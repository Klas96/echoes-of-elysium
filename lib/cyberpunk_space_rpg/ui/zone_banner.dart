import 'package:flutter/material.dart';

import 'dialog_chrome.dart';
import 'mmo_feedback.dart';

/// WoW-style enter-zone toast: distinct AI→NN pixel-art plate per area.
///
/// Each region ships a hard-pixel banner sheet with clear theme motifs
/// (woods trees, city neon, Canal Works crane, cyber vents, core crystal).
/// Title + flavor overlay the empty center band — DialogChrome hard type,
/// not a soft Material card.
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
            final asset = assetFor(region);
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
                        if (asset != null)
                          Positioned.fill(
                            child: Image.asset(
                              asset,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.none,
                              isAntiAlias: false,
                              gaplessPlayback: true,
                            ),
                          )
                        else
                          Positioned.fill(
                            child: ColoredBox(color: DialogChrome.ink.withValues(alpha: 0.92)),
                          ),
                        // Thin hard neon rail — chrome grammar without hiding motifs.
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _HardBannerRailPainter(accent: accent),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: bannerW * 0.2,
                            vertical: artH * 0.16,
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

/// 1px outer + inset rails; hard corners — no soft Material radius/glow.
class _HardBannerRailPainter extends CustomPainter {
  final Color accent;

  _HardBannerRailPainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    final stroke = Paint()
      ..color = accent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = false;
    canvas.drawRect(outer, stroke);

    final inset = outer.deflate(3);
    if (inset.width > 8 && inset.height > 8) {
      final inner = Paint()
        ..color = DialogChrome.cyan.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = false;
      canvas.drawRect(inset, inner);
    }

    final tick = Paint()
      ..color = DialogChrome.magenta.withValues(alpha: 0.9)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square
      ..isAntiAlias = false;
    const c = 6.0;
    canvas.drawLine(Offset(outer.left, outer.top + c), Offset(outer.left, outer.top), tick);
    canvas.drawLine(Offset(outer.left, outer.top), Offset(outer.left + c, outer.top), tick);
    canvas.drawLine(Offset(outer.right - c, outer.top), Offset(outer.right, outer.top), tick);
    canvas.drawLine(Offset(outer.right, outer.top), Offset(outer.right, outer.top + c), tick);
    canvas.drawLine(Offset(outer.left, outer.bottom - c), Offset(outer.left, outer.bottom), tick);
    canvas.drawLine(Offset(outer.left, outer.bottom), Offset(outer.left + c, outer.bottom), tick);
    canvas.drawLine(Offset(outer.right - c, outer.bottom), Offset(outer.right, outer.bottom), tick);
    canvas.drawLine(Offset(outer.right, outer.bottom), Offset(outer.right, outer.bottom - c), tick);
  }

  @override
  bool shouldRepaint(covariant _HardBannerRailPainter old) => old.accent != accent;
}
