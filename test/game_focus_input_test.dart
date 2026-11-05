import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/game_input.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/keyboard_guard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    KeyboardGuard.install();
    GameInput.install();
  });

  test('onFocusLost synthesizes KeyUps for stuck move keys', () {
    final kb = HardwareKeyboard.instance;
    kb.handleKeyEvent(const KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyW,
      logicalKey: LogicalKeyboardKey.keyW,
      timeStamp: Duration.zero,
    ));
    expect(kb.logicalKeysPressed.contains(LogicalKeyboardKey.keyW), isTrue);

    GameInput.onFocusLost();
    expect(kb.logicalKeysPressed.contains(LogicalKeyboardKey.keyW), isFalse);

    // Idempotent while still lost.
    kb.handleKeyEvent(const KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyD,
      logicalKey: LogicalKeyboardKey.keyD,
      timeStamp: Duration.zero,
    ));
    GameInput.onFocusLost();
    // Second lost is a no-op — D may still be pressed until gained.
    expect(kb.logicalKeysPressed.contains(LogicalKeyboardKey.keyD), isTrue);

    GameInput.onFocusGained();
    expect(kb.logicalKeysPressed.contains(LogicalKeyboardKey.keyD), isFalse);
  });

  test('onFocusGained is a no-op until a matching onFocusLost', () {
    final kb = HardwareKeyboard.instance;
    kb.handleKeyEvent(const KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: LogicalKeyboardKey.keyA,
      timeStamp: Duration.zero,
    ));
    GameInput.onFocusGained();
    expect(kb.logicalKeysPressed.contains(LogicalKeyboardKey.keyA), isTrue);

    GameInput.onFocusLost();
    GameInput.onFocusGained();
    expect(kb.logicalKeysPressed.contains(LogicalKeyboardKey.keyA), isFalse);
  });
}
