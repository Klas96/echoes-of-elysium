import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Softens Flutter Linux keyboard quirks that freeze WASD / E after cutscenes:
/// key-repeat often arrives as a second [KeyDownEvent], which asserts and aborts
/// dispatch, leaving that key (and sometimes the whole channel) dead.
class KeyboardGuard {
  KeyboardGuard._();

  static bool _installed = false;
  static ui.KeyDataCallback? _previous;

  /// Call once from [main] after [WidgetsFlutterBinding.ensureInitialized].
  static void install() {
    if (_installed) return;
    _installed = true;
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    _previous = dispatcher.onKeyData;
    dispatcher.onKeyData = _onKeyData;
  }

  static bool _isEscape(PhysicalKeyboardKey physical, LogicalKeyboardKey logical) =>
      physical == PhysicalKeyboardKey.escape ||
      logical == LogicalKeyboardKey.escape;

  static bool _onKeyData(ui.KeyData data) {
    if (data.physical != 0 && data.logical != 0) {
      final physical = PhysicalKeyboardKey(data.physical);
      final logical =
          HardwareKeyboard.instance.lookUpLayout(physical) ??
              LogicalKeyboardKey(data.logical);
      final kb = HardwareKeyboard.instance;

      if (data.type == ui.KeyEventType.down && kb.isPhysicalKeyPressed(physical)) {
        // Escape: swallow duplicate downs. Synthesizing a KeyUp here races the
        // real Esc up from the pause menu and floods assert errors that kill
        // the whole key channel (WASD stops working).
        if (_isEscape(physical, logical)) return true;

        // Duplicate down (Linux key-repeat / focus steal): release then let the
        // normal handler see a fresh down so Bonfire's Keyboard re-arms WASD
        // after map travel (a swallowed KeyRepeat leaves movement IDLE).
        try {
          kb.handleKeyEvent(KeyUpEvent(
            physicalKey: physical,
            logicalKey: logical,
            timeStamp: Duration.zero,
          ));
        } catch (_) {
          return true;
        }
      }
      if (data.type == ui.KeyEventType.up && !kb.isPhysicalKeyPressed(physical)) {
        return true; // orphan up after we already released
      }
    }
    try {
      return _previous?.call(data) ?? false;
    } catch (_) {
      // Swallow — do not releaseAll() here; cascading synthetic ups on Esc
      // were freezing movement after the pause/audio menu.
      return true;
    }
  }

  /// Synthesize KeyUps for every key Flutter still thinks is down.
  /// Prefer this over [HardwareKeyboard.clearState] (that also drops handlers).
  static void releaseAll() {
    final kb = HardwareKeyboard.instance;
    for (final physical in kb.physicalKeysPressed.toList()) {
      final logical = kb.lookUpLayout(physical);
      if (logical == null) continue;
      try {
        kb.handleKeyEvent(KeyUpEvent(
          physicalKey: physical,
          logicalKey: logical,
          timeStamp: Duration.zero,
        ));
      } catch (_) {}
    }
  }
}
