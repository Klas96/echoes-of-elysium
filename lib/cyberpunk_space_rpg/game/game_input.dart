import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../components/custom_player.dart';
import 'keyboard_guard.dart';

/// Overworld keyboard focus + a focus-independent WASD path.
///
/// Bonfire only dispatches keys while its [FocusNode] has primary focus;
/// cutscenes/rooms steal that. [reclaim] asks for focus back; [_onKey] still
/// drives movement from [HardwareKeyboard] when focus is wrong.
class GameInput {
  GameInput._();

  static final focusNode = FocusNode(debugLabel: 'overworldInput');

  static bool _installed = false;

  /// False while an interior room owns the screen — steer the room player
  /// via [syncAlternateKeys] instead of the paused overworld Kaela.
  static bool overworldKeysEnabled = true;

  /// Set by [Interiors] so cutscenes can return keys to the room Bonfire.
  static void Function()? reclaimAlternate;

  /// WASD sync for the active room player (no Bonfire focus required).
  static void Function()? syncAlternateKeys;

  static final _moveKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyD,
  };

  /// Call once from [main] after [KeyboardGuard.install].
  static void install() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  static bool _isMove(LogicalKeyboardKey key) => _moveKeys.contains(key);

  static bool get moveKeysHeld =>
      HardwareKeyboard.instance.logicalKeysPressed.any(_isMove);

  static bool _onKey(KeyEvent event) {
    if (!_isMove(event.logicalKey)) return false;
    if (!overworldKeysEnabled) {
      syncAlternateKeys?.call();
      return false;
    }
    final player = CustomPlayer.current;
    if (player == null || !player.isMounted || player.isRespawning) return false;
    // Sync stick from keys only — never haltMovement() here (that cancels
    // League click-to-move / attack-chase when a key is released).
    player.syncMovementFromKeyboard();
    return false;
  }

  /// Release stuck keys and restore the right focus target.
  static void reclaim({bool releaseKeys = true}) {
    if (releaseKeys) KeyboardGuard.releaseAll();
    if (!overworldKeysEnabled) {
      reclaimAlternate?.call();
      return;
    }
    CustomPlayer.current?.haltMovement();

    void apply() {
      if (!overworldKeysEnabled) {
        reclaimAlternate?.call();
        return;
      }
      if (focusNode.context != null && focusNode.canRequestFocus) {
        focusNode.requestFocus();
      }
      final player = CustomPlayer.current;
      if (player == null || !player.isMounted) return;
      if (moveKeysHeld) {
        player.syncMovementFromKeyboard();
      } else {
        player.haltMovement();
      }
    }

    apply();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      apply();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        apply();
        Future<void>.delayed(const Duration(milliseconds: 500), apply);
      });
    });
  }
}
