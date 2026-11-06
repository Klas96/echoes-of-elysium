import 'package:audioplayers/audioplayers.dart';

/// Shared Android/iOS audio contexts.
///
/// SFX must use [mix] (`AndroidAudioFocus.none`). A global or per-SFX `gain`
/// steals focus from BGM and pauses music as soon as footsteps play.
class GameAudioContexts {
  GameAudioContexts._();

  static const AudioContextAndroid mixAndroid = AudioContextAndroid(
    isSpeakerphoneOn: false,
    stayAwake: false,
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.game,
    audioFocus: AndroidAudioFocus.none,
  );

  /// Dialogue / cutscene VO — speech content, still mixes with BGM (`none`).
  /// Sonification was fine for short SFX but is the wrong Android attribute
  /// for multi-second spoken lines (EOE-85).
  static const AudioContextAndroid voiceAndroid = AudioContextAndroid(
    isSpeakerphoneOn: false,
    stayAwake: false,
    contentType: AndroidContentType.speech,
    usageType: AndroidUsageType.game,
    audioFocus: AndroidAudioFocus.none,
  );

  static const AudioContextAndroid musicAndroid = AudioContextAndroid(
    isSpeakerphoneOn: false,
    stayAwake: true,
    contentType: AndroidContentType.music,
    usageType: AndroidUsageType.game,
    audioFocus: AndroidAudioFocus.gain,
  );

  /// Must be `playback` (or playAndRecord / multiRoute) — audioplayers asserts
  /// if `mixWithOthers` is paired with `ambient`, which broke SFX/VO/music
  /// init on every platform in debug (constructor runs before setAudioContext).
  static final AudioContextIOS mixIos = AudioContextIOS(
    category: AVAudioSessionCategory.playback,
    options: const {AVAudioSessionOptions.mixWithOthers},
  );

  static final AudioContextIOS musicIos = AudioContextIOS(
    category: AVAudioSessionCategory.playback,
    options: const {AVAudioSessionOptions.mixWithOthers},
  );

  static AudioContext get mix => AudioContext(
        android: mixAndroid,
        iOS: mixIos,
      );

  static AudioContext get voice => AudioContext(
        android: voiceAndroid,
        iOS: mixIos,
      );

  static AudioContext get music => AudioContext(
        android: musicAndroid,
        iOS: musicIos,
      );
}
