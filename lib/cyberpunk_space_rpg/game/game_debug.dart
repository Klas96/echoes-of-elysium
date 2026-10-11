import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Shared debug toggle (Flutter debug builds only). Backtick / the DEBUG chip
/// flips [enabled]; release builds always report off.
class GameDebug {
  GameDebug._();

  static final enabled = ValueNotifier<bool>(false);

  static bool get isOn => kDebugMode && enabled.value;

  static void toggle() {
    if (!kDebugMode) return;
    enabled.value = !enabled.value;
  }

  /// World-space label (enemies, props) — centred on [topCenter], green mono.
  static void paintLabel(Canvas canvas, String text, Offset topCenter) {
    if (!isOn || text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF00FF88),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          letterSpacing: 0.5,
          shadows: [
            Shadow(color: Color(0xFF000000), blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    // Soft plate so labels stay readable over bright sprites.
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(topCenter.dx, topCenter.dy - tp.height / 2),
        width: tp.width + 6,
        height: tp.height + 3,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(r, Paint()..color = const Color(0xCC000000));
    tp.paint(canvas, Offset(topCenter.dx - tp.width / 2, topCenter.dy - tp.height));
  }
}
