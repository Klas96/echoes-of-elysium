import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/system_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SystemUi.install is idempotent and safe under lifecycle resume', () async {
    SystemUi.install();
    SystemUi.install();

    await SystemUi.enterImmersive();
    await SystemUi.restoreSystemBars();
    await SystemUi.enterImmersive();

    // Re-apply path used after Home / app switcher.
    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
