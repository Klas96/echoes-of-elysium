import 'dart:math';

import 'package:flutter/widgets.dart';

/// Shared HUD geometry so the top bar, prompts, toasts, pops and the
/// on-screen joystick never overlap at phone sizes (412x915, 360x800) or
/// landscape (915x412).
class HudLayout {
  HudLayout._();

  /// Bonfire joystick: background radius = size / 2, centred at
  /// (margin.left + r, H - margin.bottom - r).
  static const joystickSize = 80.0;
  static const joystickMargin = EdgeInsets.only(left: 100, bottom: 100, right: 100, top: 100);

  /// Screen rect the joystick background covers.
  static Rect joystickRect(Size screen) {
    const r = joystickSize / 2;
    final cx = joystickMargin.left + r;
    final cy = screen.height - joystickMargin.bottom - r;
    return Rect.fromCircle(center: Offset(cx, cy), radius: r);
  }

  /// Narrow (portrait phone): bottom-centre widgets would sit on the
  /// joystick, so they move above it.
  static bool narrow(Size screen) => screen.width < 600;

  /// Top chip row uses icon-only buttons below this width.
  static bool compactChips(double width) => width < 560;

  /// Bottom offset of the TALK / INTERACT / hold prompts.
  static double promptBottom(Size screen) =>
      narrow(screen) ? joystickMargin.bottom + joystickSize + 16 : 80;

  /// Toasts: above the prompt in portrait; in landscape along the bottom
  /// edge under the prompt, so they never cover Kaela in the middle.
  static double toastBottom(Size screen, {bool compact = false}) =>
      narrow(screen) ? promptBottom(screen) + 100 : 12;

  /// +XP / loot pops: right-aligned column beside the joystick (under the
  /// prompt) in portrait; bottom-right corner in landscape.
  static double popsBottom(Size screen) => narrow(screen) ? joystickMargin.bottom : 12;
  static const popsRight = 16.0;
  /// Room right of the joystick, capped.
  static double popsMaxWidth(Size screen) =>
      min(220, screen.width - joystickRect(screen).right - 16 - popsRight);

  /// Max width of the quest tracker (top right) next to the health block.
  static double trackerMaxWidth(double width) => min(220, max(140, (width - 24) * 0.48));

  /// Max tracked jobs listed before collapsing into "+N more".
  static int trackerJobs(Size screen) => screen.height < 500 ? 1 : 2;
}
