import 'dart:math';

import 'package:flutter/foundation.dart'
    show ValueNotifier, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';

/// Shared HUD geometry so the top bar, prompts, toasts and pops never
/// overlap at phone sizes (412x915, 360x800) or landscape (915x412).
/// Movement is click/tap pathfinding + WASD (no on-screen joystick).
class HudLayout {
  HudLayout._();

  /// Top-right objective / jobs tracker folded to a compact chip.
  /// Session-only; tap the TRACKER header to toggle.
  static final trackerCollapsed = ValueNotifier<bool>(false);

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

  /// Ability bar [Positioned.bottom] (SafeArea still owns system insets).
  /// Phones / narrow layouts pin to the screen edge; desktop keeps a lift.
  static double abilityBottom(Size screen) =>
      (isTouch || narrow(screen)) ? 0 : 26;

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

  /// NPC / room talk cards — phones (and short landscape) need a denser plate.
  static bool dialogueCompact(Size screen) =>
      isTouch || screen.shortestSide < 600 || screen.height < 520;

  static double dialogueMaxWidth(Size screen) {
    final margin = dialogueCompact(screen) ? 24.0 : 48.0;
    final cap = dialogueCompact(screen) ? 420.0 : 560.0;
    return min(cap, max(200.0, screen.width - margin));
  }

  /// Cap height so many choices don't cover the whole phone screen.
  static double dialogueMaxHeight(Size screen) =>
      screen.height * (dialogueCompact(screen) ? 0.48 : 0.62);

  static EdgeInsets dialogueOuter(Size screen) => dialogueCompact(screen)
      ? const EdgeInsets.fromLTRB(10, 0, 10, 10)
      : const EdgeInsets.fromLTRB(24, 0, 24, 24);

  static EdgeInsets dialoguePadding(Size screen) => dialogueCompact(screen)
      ? const EdgeInsets.fromLTRB(12, 10, 12, 8)
      : const EdgeInsets.fromLTRB(24, 20, 24, 16);

  static double dialogueNameFont(Size screen) => dialogueCompact(screen) ? 9.5 : 11;
  static double dialogueBodyFont(Size screen) => dialogueCompact(screen) ? 12.5 : 15;
  static double dialogueBodyHeight(Size screen) => dialogueCompact(screen) ? 1.4 : 1.65;
}
