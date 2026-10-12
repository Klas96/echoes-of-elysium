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

  /// +XP / loot pops: right column just above the prompt in portrait
  /// (prompt spans nearly full width, so same bottom overlaps); corner in
  /// landscape.
  static double popsBottom(Size screen) =>
      narrow(screen) ? promptBottom(screen) + 92 : 12;
  static const popsRight = 16.0;
  static double popsMaxWidth(Size screen) =>
      min(220, screen.width - popsRight - 32);

  /// Toasts: above pops in portrait; bottom edge in landscape under the
  /// (higher) prompt so they never cover Kaela in the middle.
  static double toastBottom(Size screen, {bool compact = false}) =>
      narrow(screen) ? popsBottom(screen) + 68 : 12;

  /// Max width of the quest tracker (top right) next to the health block.
  static double trackerMaxWidth(double width) => min(220, max(140, (width - 24) * 0.48));

  /// Max tracked jobs listed before collapsing into "+N more".
  static int trackerJobs(Size screen) => screen.height < 500 ? 1 : 2;
}
