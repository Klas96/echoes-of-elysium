import 'dart:html' as html;

class SfxManager {
  static final SfxManager _instance = SfxManager._();
  factory SfxManager() => _instance;
  SfxManager._();

  // Flutter web serves an asset with key 'assets/x' at URL 'assets/assets/x'.
  static String _url(String path) =>
      path.startsWith('assets/') ? path : 'assets/assets/$path';

  html.AudioElement? _footstep;
  html.AudioElement? _damage;
  html.AudioElement? _portal;
  html.AudioElement? _shoot;
  html.AudioElement? _chime;
  html.AudioElement? _currentVoice;

  Future<void> init() async {
    _footstep = _preload('audio/sfx/footstep_grass.mp3');
    _damage = _preload('audio/sfx/damage_hit.mp3');
    _portal = _preload('audio/sfx/portal.mp3');
    _shoot = _preload('audio/sfx/shoot.mp3');
    _chime = _preload('audio/sfx/computer_beep.wav');
  }

  html.AudioElement _preload(String path) {
    final el = html.AudioElement()
      ..src = _url(path)
      ..volume = 1.0
      ..preload = 'auto';
    el.load();
    el.onError.listen((_) => print('SFX load error: $path'));
    return el;
  }

  void _play(html.AudioElement? el, String label) {
    if (el == null) {
      print('SFX not ready: $label');
      return;
    }
    el.currentTime = 0;
    el.play().catchError((e) => print('SFX play error [$label]: $e'));
  }

  Future<void> playFootstep() async => _play(_footstep, 'footstep');
  Future<void> playDamage() async => _play(_damage, 'damage');
  Future<void> playPortal() async => _play(_portal, 'portal');
  Future<void> playShoot() async => _play(_shoot, 'shoot');

  /// Soft chime for bonds and finds (reuses the computer beep).
  Future<void> playChime() async => _play(_chime, 'chime');

  Future<void> playVoice(String assetPath) async {
    try {
      _currentVoice?.pause();
      _currentVoice = html.AudioElement(_url(assetPath))..volume = 1.0;
      await _currentVoice!.play();
    } catch (_) {}
  }

  Future<void> stopVoice() async {
    try {
      _currentVoice?.pause();
      _currentVoice = null;
    } catch (_) {}
  }
}
