import 'music_manager.dart' show MusicManager;
import 'sfx_manager.dart';

/// Browsers block AudioContext / HTMLAudio until a user gesture.
/// Call [nudge] from clicks/taps/keys so music and SFX can start.
class AudioUnlock {
  AudioUnlock._();

  static bool _sfxUnlocked = false;

  /// Music unlock is safe every gesture (idempotent). SFX unlock runs once —
  /// re-running it was restarting the footstep element on every click.
  static void nudge() {
    MusicManager().unlockAfterGesture();
    if (!_sfxUnlocked) {
      _sfxUnlocked = true;
      SfxManager().unlockAfterGesture();
    }
  }
}
