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

  double _userVolume = 1.0;
  bool _enabled = true;

  static const _baseFoot = 0.45;
  static const _baseDamage = 0.7;
  static const _basePortal = 0.75;
  static const _baseShoot = 0.85;
  static const _baseChime = 0.55;
  static const _baseVoice = 1.0;

  double get _scale => _enabled ? _userVolume.clamp(0.0, 1.0) : 0.0;
  bool get _audible => _scale > 0.001;

  Future<void> init() async {
    _footstep = _preload('audio/sfx/footstep_grass.mp3');
    _damage = _preload('audio/sfx/damage_hit.mp3');
    _portal = _preload('audio/sfx/portal.mp3');
    _shoot = _preload('audio/sfx/shoot.mp3');
    _chime = _preload('audio/sfx/computer_beep.wav');
    _applyVolumes();
  }

  Future<void> applyUserVolume(double volume, {required bool enabled}) async {
    _userVolume = volume.clamp(0.0, 1.0);
    _enabled = enabled;
    _applyVolumes();
  }

  void _applyVolumes() {
    final s = _scale;
    _footstep?.volume = _baseFoot * s;
    _damage?.volume = _baseDamage * s;
    _portal?.volume = _basePortal * s;
    _shoot?.volume = _baseShoot * s;
    _chime?.volume = _baseChime * s;
    // VO is not part of SFX mute/volume — always full.
    _currentVoice?.volume = _baseVoice;
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
    if (!_audible) return;
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

  /// Dialogue / cutscene VO — always on; ignores SFX mute and volume.
  Future<void> playVoice(String assetPath) async {
    try {
      _currentVoice?.pause();
      _currentVoice = html.AudioElement(_url(assetPath))..volume = _baseVoice;
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
