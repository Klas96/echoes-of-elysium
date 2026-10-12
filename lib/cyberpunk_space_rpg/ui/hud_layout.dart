import 'dart:math';

import 'package:flutter/widgets.dart';

/// Shared HUD geometry so the top bar, prompts, toasts and pops never
/// overlap at phone sizes (412x915, 360x800) or landscape (915x412).
/// Movement is click/tap pathfinding + WASD (no on-screen joystick).
class HudLayout {
  HudLayout._();

  /// Narrow (portrait phone).
  static bool narrow(Size screen) => screen.width < 600;

  /// Top chip row uses icon-only buttons below this width.
  static bool compactChips(double width) => width < 560;

  /// Bottom offset of the TALK / INTERACT / hold prompts.
  static double promptBottom(Size screen) => narrow(screen) ? 24 : 80;

  /// Toasts: above the prompt in portrait; in landscape along the bottom
  /// edge under the prompt, so they never cover Kaela in the middle.
  static double toastBottom(Size screen, {bool compact = false}) =>
      narrow(screen) ? promptBottom(screen) + 100 : 12;

  /// +XP / loot pops: bottom-right in portrait and landscape.
  static double popsBottom(Size screen) => narrow(screen) ? 24 : 12;
  static const popsRight = 16.0;
  static double popsMaxWidth(Size screen) =>
      min(220, screen.width - popsRight - 32);

  /// Max width of the quest tracker (top right) next to the health block.
  static double trackerMaxWidth(double width) => min(220, max(140, (width - 24) * 0.48));

  /// Max tracked jobs listed before collapsing into "+N more".
  static int trackerJobs(Size screen) => screen.height < 500 ? 1 : 2;
}
