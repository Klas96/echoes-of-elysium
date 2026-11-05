/// DOM audio surface used by web SFX (mirrors HTML AudioElement bits we need).
///
/// Kept free of `dart:html` so VM unit tests can fake browser quirks.
abstract class SfxDomAudio {
  bool get paused;
  double get currentTime;
  set currentTime(double value);
  double get volume;
  set volume(double value);
  bool get muted;
  set muted(bool value);
  String get src;
  set src(String value);
  String get preload;
  set preload(String value);
  Future<dynamic> play();
  void pause();
  void load();
}

typedef SfxDomAudioFactory = SfxDomAudio Function();

/// Browser SFX play / unlock / lifecycle logic (no `dart:html`).
class SfxWebEngine {
  SfxWebEngine({required this.createAudio});

  final SfxDomAudioFactory createAudio;

  SfxDomAudio? footstep;
  SfxDomAudio? damage;
  SfxDomAudio? portal;
  SfxDomAudio? shoot;
  SfxDomAudio? chime;
  SfxDomAudio? heal;
  SfxDomAudio? currentVoice;

  double userVolume = 1.0;
  bool enabled = true;

  static const baseFoot = 0.45;
  static const baseDamage = 0.7;
  static const basePortal = 0.75;
  static const baseShoot = 0.85;
  static const baseChime = 0.55;
  static const baseHeal = 0.7;
  static const baseVoice = 1.0;

  /// Flutter web serves asset key `assets/x` at URL `assets/assets/x`.
  static String url(String path) =>
      path.startsWith('assets/') ? path : 'assets/assets/$path';

  double get scale => enabled ? userVolume.clamp(0.0, 1.0) : 0.0;
  bool get audible => scale > 0.001;

  void init() {
    footstep = _preload('audio/sfx/footstep_grass.mp3');
    damage = _preload('audio/sfx/damage_hit.mp3');
    portal = _preload('audio/sfx/portal.mp3');
    shoot = _preload('audio/sfx/shoot.wav');
    chime = _preload('audio/sfx/computer_beep.wav');
    heal = _preload('audio/sfx/health_pickup.mp3');
    applyVolumes();
  }

  void applyUserVolume(double volume, {required bool enabled}) {
    userVolume = volume.clamp(0.0, 1.0);
    this.enabled = enabled;
    applyVolumes();
  }

  void applyVolumes() {
    final s = scale;
    footstep?.volume = baseFoot * s;
    damage?.volume = baseDamage * s;
    portal?.volume = basePortal * s;
    shoot?.volume = baseShoot * s;
    chime?.volume = baseChime * s;
    heal?.volume = baseHeal * s;
    currentVoice?.volume = baseVoice * s;
  }

  SfxDomAudio _preload(String path) {
    final el = createAudio()
      ..src = url(path)
      ..volume = 1.0
      ..preload = 'auto';
    el.load();
    return el;
  }

  /// Unlock after a user gesture. Skips elements already playing (no rewind).
  Future<void> unlockAfterGesture() async {
    if (footstep == null) init();
    for (final el in [footstep, damage, portal, shoot, chime, heal]) {
      if (el == null) continue;
      try {
        final wasPlaying = !el.paused && el.currentTime > 0;
        if (wasPlaying) continue;
        el.muted = true;
        await el.play();
        el.pause();
        el.currentTime = 0;
        el.muted = false;
      } catch (_) {}
    }
    applyVolumes();
  }

  void playOneShot(SfxDomAudio? el) {
    if (!audible) return;
    if (el == null) return;
    el.currentTime = 0;
    // ignore: discarded_futures — matches production fire-and-forget
    el.play();
  }

  Future<void> playVoice(String assetPath) async {
    if (!audible) {
      await stopVoice();
      return;
    }
    try {
      currentVoice?.pause();
      currentVoice = createAudio()
        ..src = url(assetPath)
        ..volume = baseVoice * scale;
      await currentVoice!.play();
    } catch (_) {}
  }

  Future<void> stopVoice() async {
    try {
      currentVoice?.pause();
      currentVoice = null;
    } catch (_) {}
  }

  Future<void> pauseForAppLifecycle() async {
    await stopVoice();
    for (final el in [footstep, damage, portal, shoot, chime, heal]) {
      if (el == null) continue;
      try {
        el.pause();
        el.currentTime = 0;
      } catch (_) {}
    }
  }

  Future<void> resumeForAppLifecycle() async {}
}
