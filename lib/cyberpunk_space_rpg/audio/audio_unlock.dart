import 'music_manager.dart' show MusicManager;
import 'sfx_manager.dart';

/// Browsers block AudioContext / HTMLAudio until a user gesture.
/// Call [nudge] from clicks/taps/keys so music and SFX can start.
class AudioUnlock {
  AudioUnlock._();

  /// Safe on every gesture. Both music and SFX unlocks are re-fired — the
  /// title-screen tap often runs *before* [MusicManager.play], and a one-shot
  /// unlock left BGM (and sometimes SFX) silent forever on web.
  static void nudge() {
    MusicManager().unlockAfterGesture();
    SfxManager().unlockAfterGesture();
  }
}
