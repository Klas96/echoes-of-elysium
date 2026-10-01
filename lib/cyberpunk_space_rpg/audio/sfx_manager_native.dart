import 'package:audioplayers/audioplayers.dart' as ap;

class SfxManager {
  static final SfxManager _instance = SfxManager._();
  factory SfxManager() => _instance;
  SfxManager._();

  final ap.AudioPlayer _footstep = ap.AudioPlayer();
  final ap.AudioPlayer _damage   = ap.AudioPlayer();
  final ap.AudioPlayer _portal   = ap.AudioPlayer();
  final ap.AudioPlayer _shoot    = ap.AudioPlayer();
  ap.AudioPlayer? _voice;

  Future<void> init() async {}

  Future<void> playFootstep() async {
    try { await _footstep.play(ap.AssetSource('audio/sfx/footstep_grass.mp3')); } catch (_) {}
  }

  Future<void> playDamage() async {
    try { await _damage.play(ap.AssetSource('audio/sfx/damage_hit.mp3')); } catch (_) {}
  }

  Future<void> playPortal() async {
    try { await _portal.play(ap.AssetSource('audio/sfx/portal.mp3')); } catch (_) {}
  }

  Future<void> playShoot() async {
    try { await _shoot.play(ap.AssetSource('audio/sfx/shoot.mp3')); } catch (_) {}
  }

  void playVoice(String assetPath) {
    try {
      _voice?.stop();
      _voice = ap.AudioPlayer();
      _voice!.play(ap.AssetSource(assetPath));
    } catch (_) {}
  }
}
