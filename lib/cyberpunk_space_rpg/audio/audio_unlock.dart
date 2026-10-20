import 'music_manager.dart' show MusicManager;
import 'sfx_manager.dart';

/// Browsers block AudioContext / HTMLAudio until a user gesture.
/// Call [nudge] from the first click/tap/key so music and SFX can start.
class AudioUnlock {
  AudioUnlock._();

  static bool _done = false;
  static Future<void>? _inFlight;

  /// Idempotent; safe to call on every pointer/key. Cheap after the first success.
  static void nudge() {
    if (_done) return;
    _inFlight ??= _run();
  }

  static Future<void> _run() async {
    try {
      await Future.wait([
        MusicManager().unlockAfterGesture(),
        SfxManager().unlockAfterGesture(),
      ]);
      _done = true;
    } catch (_) {
      // Allow a later gesture to retry.
      _inFlight = null;
    }
  }
}
