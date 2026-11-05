import 'dart:html' as html;

import 'sfx_web_engine.dart';

class _HtmlDomAudio implements SfxDomAudio {
  _HtmlDomAudio([html.AudioElement? el]) : _el = el ?? html.AudioElement();

  final html.AudioElement _el;

  @override
  bool get paused => _el.paused;

  @override
  double get currentTime => _el.currentTime.toDouble();

  @override
  set currentTime(double value) => _el.currentTime = value;

  @override
  double get volume => _el.volume.toDouble();

  @override
  set volume(double value) => _el.volume = value;

  @override
  bool get muted => _el.muted;

  @override
  set muted(bool value) => _el.muted = value;

  @override
  String get src => _el.src;

  @override
  set src(String value) => _el.src = value;

  @override
  String get preload => _el.preload;

  @override
  set preload(String value) => _el.preload = value;

  @override
  Future<dynamic> play() => _el.play().catchError((e) {
        // ignore: avoid_print — matches prior web SFX error surfacing
        print('SFX play error: $e');
      });

  @override
  void pause() => _el.pause();

  @override
  void load() {
    _el.load();
    _el.onError.listen((_) {});
  }
}

/// Web SFX via HTML AudioElement (logic in [SfxWebEngine] for VM unit tests).
class SfxManager {
  static final SfxManager _instance = SfxManager._();
  factory SfxManager() => _instance;
  SfxManager._() : _engine = SfxWebEngine(createAudio: _HtmlDomAudio.new);

  final SfxWebEngine _engine;

  Future<void> init() async => _engine.init();

  Future<void> applyUserVolume(double volume, {required bool enabled}) async {
    _engine.applyUserVolume(volume, enabled: enabled);
  }

  /// Unlock HTMLAudioElement playback after a user gesture (autoplay policy).
  /// Does not rewind elements that are already playing (footsteps, etc.).
  Future<void> unlockAfterGesture() => _engine.unlockAfterGesture();

  Future<void> playFootstep() async => _engine.playOneShot(_engine.footstep);
  Future<void> playDamage() async => _engine.playOneShot(_engine.damage);
  Future<void> playPortal() async => _engine.playOneShot(_engine.portal);
  Future<void> playShoot() async => _engine.playOneShot(_engine.shoot);

  /// Soft chime for bonds and finds (reuses the computer beep).
  Future<void> playChime() async => _engine.playOneShot(_engine.chime);

  /// Health pack / heal pickup.
  Future<void> playHeal() async => _engine.playOneShot(_engine.heal);

  /// Dialogue / cutscene VO — respects SFX mute / volume.
  Future<void> playVoice(String assetPath) => _engine.playVoice(assetPath);

  Future<void> stopVoice() => _engine.stopVoice();

  /// Stop one-shots and VO while the app / tab is backgrounded.
  Future<void> pauseForAppLifecycle() => _engine.pauseForAppLifecycle();

  /// SFX are one-shots; nothing to resume when returning to foreground.
  Future<void> resumeForAppLifecycle() => _engine.resumeForAppLifecycle();
}
