import 'package:flutter/material.dart';

import 'hud_layout.dart';

/// Shared neon night-forest / cyberpunk-pixel chrome for talk panels,
/// choice rows, toasts, and interact prompts.
///
/// One frame language everywhere: hard edges, double-line inset, corner
/// brackets, cyan/magenta accents on deep navy — no soft Material pills,
/// purple glow, or multi-layer shadows.
class DialogChrome {
  DialogChrome._();

  static const Color ink = Color(0xFF050814);
  static const Color inkRaised = Color(0xFF0A1220);
  static const Color cyan = Color(0xFF00FFCC);
  static const Color magenta = Color(0xFFFF2D6A);
  static const Color body = Color(0xFFE6EEF5);
  static const Color bodyDim = Color(0xFF9BB0BE);
  static const Color mute = Color(0xFF5A6A78);

  /// Default accent when a speaker has none.
  static const Color accentFallback = cyan;

  // --- type ---------------------------------------------------------------

  static TextStyle speakerStyle(Color accent, {required bool compact}) =>
      TextStyle(
        color: accent,
        fontSize: compact ? 9.5 : 11,
        fontWeight: FontWeight.w800,
        letterSpacing: compact ? 2.4 : 3.2,
        height: 1.1,
      );

  static TextStyle bodyStyle({required bool compact, bool dim = false}) =>
      TextStyle(
        color: dim ? bodyDim : body,
        fontSize: compact ? 12.5 : 15,
        height: compact ? 1.4 : 1.6,
        letterSpacing: 0.15,
      );

  static TextStyle choiceStyle(Color accent, {required bool compact}) =>
      TextStyle(
        color: accent,
        fontSize: compact ? 11.5 : 13,
        fontWeight: FontWeight.w700,
        letterSpacing: compact ? 1.0 : 1.4,
        height: 1.15,
      );

  static TextStyle toastTitleStyle(Color accent, {required bool compact}) =>
      TextStyle(
        color: accent,
        fontSize: compact ? 10 : 11,
        fontWeight: FontWeight.w800,
        letterSpacing: compact ? 1.2 : 1.8,
        height: 1.1,
      );

  static TextStyle toastBodyStyle({required bool compact, bool alone = false}) =>
      TextStyle(
        color: alone ? body.withValues(alpha: compact ? 0.85 : 0.92) : bodyDim,
        fontSize: compact ? 10 : 11,
        height: 1.35,
        letterSpacing: 0.1,
      );

  static TextStyle promptStyle({required bool compact, required bool enabled}) =>
      TextStyle(
        color: enabled ? cyan : bodyDim.withValues(alpha: 0.7),
        fontSize: compact ? 16 : 12,
        fontWeight: FontWeight.w800,
        letterSpacing: compact ? 2.2 : 2.0,
        fontStyle: enabled ? FontStyle.normal : FontStyle.italic,
        height: 1.2,
      );

  // --- frames -------------------------------------------------------------

  /// Bottom talk / room panel shell.
  static Widget panel({
    required Color accent,
    required Widget child,
    EdgeInsetsGeometry? padding,
    bool compact = false,
  }) {
    return _PixelFrame(
      accent: accent,
      fill: ink.withValues(alpha: 0.96),
      thickness: compact ? 1.5 : 2,
      padding: padding ??
          (compact
              ? const EdgeInsets.fromLTRB(12, 10, 12, 8)
              : const EdgeInsets.fromLTRB(22, 16, 22, 14)),
      child: child,
    );
  }

  /// Compact toast / farewell shell (same grammar, denser).
  static Widget toastShell({
    required Color accent,
    required Widget child,
    bool compact = false,
  }) {
    return _PixelFrame(
      accent: accent,
      fill: ink.withValues(alpha: compact ? 0.88 : 0.92),
      thickness: 1.5,
      corner: compact ? 5 : 7,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 9,
      ),
      child: child,
    );
  }

  /// Enter-zone name plate — chunky hard-pixel RPG banner (WoW zone feel).
  /// Same neon double-frame grammar as talk/toast chrome — not Material.
  static Widget zoneBannerShell({
    required Widget child,
    Color? accent,
    EdgeInsetsGeometry? padding,
  }) {
    return _PixelFrame(
      accent: (accent ?? cyan).withValues(alpha: 0.95),
      fill: ink.withValues(alpha: 0.94),
      thickness: 2,
      corner: 12,
      padding: padding ?? const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: child,
    );
  }

  /// Wide-spaced uppercase zone name — hard 1px shadow, no soft glow.
  static TextStyle zoneTitleStyle({Color? accent, bool compact = false}) =>
      TextStyle(
        color: accent ?? const Color(0xFFAAFFEE),
        fontSize: compact ? 12 : 15,
        letterSpacing: compact ? 2.4 : 3.6,
        fontWeight: FontWeight.w800,
        height: 1.05,
        fontFamily: 'monospace',
        shadows: const [
          Shadow(color: Color(0xFF050814), offset: Offset(1, 1), blurRadius: 0),
        ],
      );

  /// One-line flavor under the zone name.
  static TextStyle zoneBlurbStyle({bool compact = false}) => TextStyle(
        color: bodyDim,
        fontSize: compact ? 9.5 : 11,
        height: 1.25,
        letterSpacing: 0.15,
        shadows: const [
          Shadow(color: Color(0xFF050814), offset: Offset(1, 1), blurRadius: 0),
        ],
      );

  /// TALK / INTERACT / hold prompt chip.
  static Widget promptShell({
    required Widget child,
    bool enabled = true,
    EdgeInsetsGeometry? padding,
  }) {
    return _PixelFrame(
      accent: enabled ? cyan : mute,
      fill: ink.withValues(alpha: enabled ? 0.86 : 0.72),
      thickness: 1.5,
      corner: 5,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: child,
    );
  }

  /// Cutscene caption plate — same double-line, no soft scrim card look.
  static Widget captionShell({
    required Color accent,
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return _PixelFrame(
      accent: accent.withValues(alpha: 0.85),
      fill: ink.withValues(alpha: 0.78),
      thickness: 1.5,
      corner: 6,
      padding: padding ?? const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: child,
    );
  }

  /// Speaker name with a hard accent underline rail.
  static Widget speakerLabel(String name, Color accent, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name.toUpperCase(), style: speakerStyle(accent, compact: compact)),
        SizedBox(height: compact ? 4 : 6),
        SizedBox(
          height: 2,
          child: Stack(children: [
            Container(color: accent.withValues(alpha: 0.22)),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.28,
                child: Container(color: accent),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: compact ? 8 : 10,
                color: magenta.withValues(alpha: 0.85),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  /// Hard-edged choice / action button for talk panels.
  static Widget choiceButton({
    required String label,
    required Color accent,
    required VoidCallback onTap,
    bool compact = false,
    bool filled = true,
    bool wide = false,
  }) {
    final padH = compact ? (filled ? 12.0 : 10.0) : (filled ? 18.0 : 14.0);
    final padV = compact ? (filled ? 8.0 : 7.0) : (filled ? 12.0 : 10.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: accent.withValues(alpha: 0.18),
        highlightColor: accent.withValues(alpha: 0.08),
        child: Ink(
          width: wide ? double.infinity : null,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: filled ? 0.14 : 0.05),
            border: Border(
              left: BorderSide(color: accent, width: filled ? 3 : 2),
              top: BorderSide(color: accent.withValues(alpha: 0.85), width: 1),
              right: BorderSide(color: accent.withValues(alpha: 0.85), width: 1),
              bottom: BorderSide(color: accent.withValues(alpha: 0.85), width: 1),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
            child: Text(
              label,
              textAlign: wide ? TextAlign.center : TextAlign.left,
              style: choiceStyle(accent, compact: compact),
            ),
          ),
        ),
      ),
    );
  }

  /// Square hard crop for toast portraits (no soft rounded clip).
  static Widget portrait(String asset, {double size = 44}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: inkRaised,
        border: Border.all(color: cyan.withValues(alpha: 0.45), width: 1),
      ),
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
        isAntiAlias: false,
      ),
    );
  }

  /// Layout helpers mirrored from [HudLayout] so callers stay one-hop.
  static bool compactOf(Size screen) => HudLayout.dialogueCompact(screen);
  static double maxWidthOf(Size screen) => HudLayout.dialogueMaxWidth(screen);
  static double maxHeightOf(Size screen) => HudLayout.dialogueMaxHeight(screen);
  static EdgeInsets outerOf(Size screen) => HudLayout.dialogueOuter(screen);
  static EdgeInsets paddingOf(Size screen) => HudLayout.dialoguePadding(screen);
}

/// Hard-pixel double frame with corner brackets.
class _PixelFrame extends StatelessWidget {
  final Color accent;
  final Color fill;
  final double thickness;
  final double corner;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const _PixelFrame({
    required this.accent,
    required this.fill,
    required this.thickness,
    required this.padding,
    required this.child,
    this.corner = 8,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PixelFramePainter(
        accent: accent,
        fill: fill,
        thickness: thickness,
        corner: corner,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _PixelFramePainter extends CustomPainter {
  final Color accent;
  final Color fill;
  final double thickness;
  final double corner;

  _PixelFramePainter({
    required this.accent,
    required this.fill,
    required this.thickness,
    required this.corner,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    final fillPaint = Paint()..color = fill;
    canvas.drawRect(outer, fillPaint);

    final outerStroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;
    canvas.drawRect(outer, outerStroke);

    final inset = thickness + 2;
    final inner = outer.deflate(inset);
    if (inner.width > 4 && inner.height > 4) {
      final innerStroke = Paint()
        ..color = DialogChrome.cyan.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRect(inner, innerStroke);
    }

    final tick = Paint()
      ..color = DialogChrome.magenta.withValues(alpha: 0.9)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square;
    final c = corner;
    // TL
    canvas.drawLine(Offset(outer.left, outer.top + c), Offset(outer.left, outer.top), tick);
    canvas.drawLine(Offset(outer.left, outer.top), Offset(outer.left + c, outer.top), tick);
    // TR
    canvas.drawLine(Offset(outer.right - c, outer.top), Offset(outer.right, outer.top), tick);
    canvas.drawLine(Offset(outer.right, outer.top), Offset(outer.right, outer.top + c), tick);
    // BL
    canvas.drawLine(Offset(outer.left, outer.bottom - c), Offset(outer.left, outer.bottom), tick);
    canvas.drawLine(Offset(outer.left, outer.bottom), Offset(outer.left + c, outer.bottom), tick);
    // BR
    canvas.drawLine(Offset(outer.right - c, outer.bottom), Offset(outer.right, outer.bottom), tick);
    canvas.drawLine(Offset(outer.right, outer.bottom), Offset(outer.right, outer.bottom - c), tick);

    // Tiny cyan hash on the top edge — reads as terminal chrome, not glow.
    final hash = Paint()
      ..color = DialogChrome.cyan.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    final mid = outer.topCenter;
    canvas.drawLine(Offset(mid.dx - 10, outer.top + thickness + 3),
        Offset(mid.dx - 4, outer.top + thickness + 3), hash);
    canvas.drawLine(Offset(mid.dx + 4, outer.top + thickness + 3),
        Offset(mid.dx + 10, outer.top + thickness + 3), hash);
  }

  @override
  bool shouldRepaint(covariant _PixelFramePainter old) =>
      old.accent != accent ||
      old.fill != fill ||
      old.thickness != thickness ||
      old.corner != corner;
}
