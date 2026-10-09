import 'package:audioplayers/audioplayers.dart';

/// Desktop / mobile SFX via audioplayers (Linux, Windows, Android, iOS, macOS).
/// just_audio has no Linux plugin — MissingPluginException on desktop.
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

  static String _asset(String path) =>
      path.startsWith('assets/') ? path.substring(7) : path;

  Future<void> init() async {
    if (_ready) return;
    try {
      await Future.wait([
        _footstep.setSource(AssetSource('audio/sfx/footstep_grass.mp3')),
        _damage.setSource(AssetSource('audio/sfx/damage_hit.mp3')),
        _portal.setSource(AssetSource('audio/sfx/portal.mp3')),
        _shoot.setSource(AssetSource('audio/sfx/shoot.mp3')),
        _chime.setSource(AssetSource('audio/sfx/computer_beep.wav')),
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
      await player.resume();
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
      await _voice.stop();
      if (token != _voiceToken) return;
      await _voice.play(AssetSource(_asset(assetPath)));
      if (token != _voiceToken) {
        await _voice.stop();
        return;
      }
      await _voice.setVolume(1.0);
    } catch (_) {}
  }

  Future<void> stopVoice() async {
    _voiceToken++;
    try {
      await _voice.stop();
    } catch (_) {}
  }
}
