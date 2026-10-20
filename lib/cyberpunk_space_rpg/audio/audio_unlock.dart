import 'music_manager.dart' show MusicManager;
import 'sfx_manager.dart';

/// Browsers block AudioContext / HTMLAudio until a user gesture.
/// Call [nudge] from clicks/taps/keys so music and SFX can start.
class AudioUnlock {
  AudioUnlock._();

  static bool _sfxDone = false;

  /// Safe on every gesture. Music unlock is retried until a track is actually
  /// playing — the title-screen tap often runs *before* [MusicManager.play],
  /// so a one-shot unlock left BGM silent forever on web.
  static void nudge() {
    // Fire-and-forget; overlaps are fine (unlock is idempotent).
    MusicManager().unlockAfterGesture();
    if (!_sfxDone) {
      _sfxDone = true;
      SfxManager().unlockAfterGesture();
    }
  }
}
