import 'dart:math';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';

/// Shared HUD geometry so the top bar, prompts, toasts and pops never
/// overlap at phone sizes (412x915, 360x800) or landscape (915x412).
/// Movement is click/tap pathfinding + WASD (no on-screen joystick).
class HudLayout {
  HudLayout._();

  /// Phones/tablets — keep existing zoom and HUD density.
  static bool get isTouch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Overworld camera zoom. Desktop monitors show far more pixels than a
  /// phone, so the same 2.0 zoom makes sprites/UI feel tiny on Linux.
  static double get worldZoom => isTouch ? 2.0 : 2.85;

  /// Extra Flutter text scale on desktop (world zoom does not affect HUD).
  static const desktopTextScale = 1.15;

  /// Top chip row (MENU / glimmer / day-night) — larger on desktop monitors.
  static double get chipFont => isTouch ? 10.0 : 13.0;
  static double get chipIcon => isTouch ? 13.0 : 16.0;
  static EdgeInsets get chipPadding => isTouch
      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
      : const EdgeInsets.symmetric(horizontal: 12, vertical: 7);

  /// HP / XP bar thickness (bars use a fixed width in GameHud).
  static double get statusBarHeight => isTouch ? 8.0 : 10.0;
  static double get statusLabelFont => isTouch ? 10.0 : 12.0;
  static double get statusMetaFont => isTouch ? 9.0 : 11.0;

  /// Narrow (portrait phone).
  static bool narrow(Size screen) => screen.width < 600;

  /// Top chip row uses icon-only buttons below this width.
  static bool compactChips(double width) => width < 560;

  /// Bottom offset of the TALK / INTERACT / hold prompts.
  static double promptBottom(Size screen) => narrow(screen) ? 24 : 80;

  /// +XP / loot pops sit with the HP/XP block (beside bars on landscape,
  /// under them on portrait) — not by the ability bar. See GameHud.
  static double popsMaxWidth(Size screen) => min(160, screen.width * 0.42);

  /// Toasts: clear of the interact prompt (portrait needs more lift).
  static double toastBottom(Size screen, {bool compact = false}) =>
      narrow(screen) ? promptBottom(screen) + 160 : promptBottom(screen) + 72;

  /// Max width of the quest tracker (top right) next to the health block.
  static double trackerMaxWidth(double width) => min(220, max(140, (width - 24) * 0.48));

  /// Max tracked jobs listed before collapsing into "+N more".
  static int trackerJobs(Size screen) => screen.height < 500 ? 1 : 2;
}
