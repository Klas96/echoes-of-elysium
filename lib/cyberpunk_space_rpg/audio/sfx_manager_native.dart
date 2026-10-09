import 'package:audioplayers/audioplayers.dart';

/// Desktop / mobile SFX via audioplayers (Linux, Windows, Android, iOS, macOS).
/// just_audio has no Linux plugin — MissingPluginException on desktop.
///
/// Linux/GStreamer often no-ops `seek(0)+resume` once a short clip has finished.
/// Re-`play(AssetSource)` each shot (same path as VO) is reliable.
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

  static const _footAsset = 'audio/sfx/footstep_grass.mp3';
  static const _damageAsset = 'audio/sfx/damage_hit.mp3';
  static const _portalAsset = 'audio/sfx/portal.mp3';
  static const _shootAsset = 'audio/sfx/shoot.mp3';
  static const _chimeAsset = 'audio/sfx/computer_beep.wav';

  static String _asset(String path) =>
      path.startsWith('assets/') ? path.substring(7) : path;

  Future<void> init() async {
    if (_ready) return;
    try {
      await Future.wait([
        _footstep.setReleaseMode(ReleaseMode.stop),
        _damage.setReleaseMode(ReleaseMode.stop),
        _portal.setReleaseMode(ReleaseMode.stop),
        _shoot.setReleaseMode(ReleaseMode.stop),
        _chime.setReleaseMode(ReleaseMode.stop),
        _footstep.setVolume(0.45),
        _damage.setVolume(0.7),
        _portal.setVolume(0.75),
        _shoot.setVolume(0.85),
        _chime.setVolume(0.55),
      ]);
      _ready = true;
    } catch (_) {}
  }

  Future<void> _playOneShot(AudioPlayer player, String asset) async {
    if (!_ready) await init();
    try {
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (_) {}
  }

  Future<void> playFootstep() async => _playOneShot(_footstep, _footAsset);
  Future<void> playDamage() async => _playOneShot(_damage, _damageAsset);
  Future<void> playPortal() async => _playOneShot(_portal, _portalAsset);
  Future<void> playShoot() async => _playOneShot(_shoot, _shootAsset);

  /// Soft chime for bonds and finds (reuses the computer beep).
  Future<void> playChime() async => _playOneShot(_chime, _chimeAsset);

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
