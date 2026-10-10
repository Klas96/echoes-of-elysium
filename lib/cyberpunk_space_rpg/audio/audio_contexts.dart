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

  static const AudioContextAndroid musicAndroid = AudioContextAndroid(
    isSpeakerphoneOn: false,
    stayAwake: true,
    contentType: AndroidContentType.music,
    usageType: AndroidUsageType.game,
    audioFocus: AndroidAudioFocus.gain,
  );

  static final AudioContextIOS mixIos = AudioContextIOS(
    category: AVAudioSessionCategory.ambient,
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

  static AudioContext get music => AudioContext(
        android: musicAndroid,
        iOS: musicIos,
      );
}
