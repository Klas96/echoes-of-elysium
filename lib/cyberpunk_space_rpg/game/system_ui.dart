import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Hides Android (and similar) system bars during play via sticky immersive mode.
///
/// Kept separate from [CustomMapGame]'s audio/save lifecycle observer so music-
/// background work can land without merge conflicts on that file.
class SystemUi {
  SystemUi._();

  static bool _installed = false;
  static final _Observer _observer = _Observer();

  /// Call once from [main] after [WidgetsFlutterBinding.ensureInitialized].
  static void install() {
    if (_installed) return;
    _installed = true;
    enterImmersive();
    WidgetsBinding.instance.addObserver(_observer);
  }

  /// Game-standard fullscreen: hide status + navigation; bars briefly peek on
  /// edge swipe then auto-hide again ([SystemUiMode.immersiveSticky]).
  static Future<void> enterImmersive() {
    return SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// Bring system bars back (e.g. if a future overlay needs them). Not used on
  /// pause — the OS chrome returns when the app is backgrounded anyway.
  static Future<void> restoreSystemBars() {
    return SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

class _Observer with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android sometimes drops immersive flags after Home / app switcher;
    // re-apply when play resumes.
    if (state == AppLifecycleState.resumed) {
      SystemUi.enterImmersive();
    }
  }
}
