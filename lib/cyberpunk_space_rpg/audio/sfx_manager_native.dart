import 'package:just_audio/just_audio.dart';

class SfxManager {
  static final SfxManager _instance = SfxManager._();
  factory SfxManager() => _instance;
  SfxManager._();

  final AudioPlayer _footstep = AudioPlayer();
  final AudioPlayer _damage = AudioPlayer();
  final AudioPlayer _portal = AudioPlayer();
  final AudioPlayer _shoot = AudioPlayer();
  final AudioPlayer _chime = AudioPlayer();
  final AudioPlayer _voice = AudioPlayer();
  bool _ready = false;
  int _voiceToken = 0;

  Future<void> init() async {
    if (_ready) return;
    try {
      await Future.wait([
        _footstep.setAsset('assets/audio/sfx/footstep_grass.mp3'),
        _damage.setAsset('assets/audio/sfx/damage_hit.mp3'),
        _portal.setAsset('assets/audio/sfx/portal.mp3'),
        _shoot.setAsset('assets/audio/sfx/shoot.mp3'),
        _chime.setAsset('assets/audio/sfx/computer_beep.wav'),
      ]);
      await _footstep.setVolume(0.45);
      await _damage.setVolume(0.7);
      await _shoot.setVolume(0.6);
      await _chime.setVolume(0.55);
      _ready = true;
    } catch (_) {}
  }

  Future<void> _replay(AudioPlayer player) async {
    if (!_ready) await init();
    try {
      await player.seek(Duration.zero);
      player.play();
    } catch (_) {}
  }

  Future<void> playFootstep() async => _replay(_footstep);
  Future<void> playDamage() async => _replay(_damage);
  Future<void> playPortal() async => _replay(_portal);
  Future<void> playShoot() async => _replay(_shoot);

  /// Soft chime for bonds and finds (reuses the computer beep).
  Future<void> playChime() async => _replay(_chime);

  Future<void> playVoice(String assetPath) async {
    final token = ++_voiceToken;
    try {
      final path =
          assetPath.startsWith('assets/') ? assetPath : 'assets/$assetPath';
      await _voice.stop();
      if (token != _voiceToken) return;
      await _voice.setAsset(path);
      if (token != _voiceToken) return;
      await _voice.setVolume(1.0);
      await _voice.play();
    } catch (_) {}
  }

  Future<void> stopVoice() async {
    _voiceToken++;
    try {
      await _voice.stop();
    } catch (_) {}
  }
}
