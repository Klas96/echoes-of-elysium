import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_contexts.dart';

/// Desktop / mobile SFX via audioplayers (Linux, Windows, Android, iOS, macOS).
/// just_audio has no Linux plugin — MissingPluginException on desktop.
///
/// Linux/GStreamer often no-ops `seek(0)+resume` once a short clip has finished.
/// Re-`play(AssetSource)` each shot (same path as VO) is reliable.
class SfxManager {
  static final SfxManager _instance = SfxManager._();
  factory SfxManager() => _instance;
  SfxManager._();

  AudioPlayer? _footstep;
  AudioPlayer? _damage;
  AudioPlayer? _portal;
  AudioPlayer? _shoot;
  AudioPlayer? _chime;
  AudioPlayer? _voice;
  bool _ready = false;
  bool _initStarted = false;
  int _voiceToken = 0;

  double _userVolume = 1.0;
  bool _enabled = true;

  static const _footAsset = 'audio/sfx/footstep_grass.mp3';
  static const _damageAsset = 'audio/sfx/damage_hit.mp3';
  static const _portalAsset = 'audio/sfx/portal.mp3';
  static const _shootAsset = 'audio/sfx/shoot.mp3';
  static const _chimeAsset = 'audio/sfx/computer_beep.wav';

  static const _baseFoot = 0.45;
  static const _baseDamage = 0.7;
  static const _basePortal = 0.75;
  static const _baseShoot = 0.85;
  static const _baseChime = 0.55;
  static const _baseVoice = 1.0;

  static String _asset(String path) =>
      path.startsWith('assets/') ? path.substring(7) : path;

  double get _scale => _enabled ? _userVolume.clamp(0.0, 1.0) : 0.0;
  bool get _audible => _scale > 0.001;

  Future<void> init() async {
    if (_ready) return;
    if (_initStarted) {
      // Another call is mid-init; wait briefly for players to exist.
      for (var i = 0; i < 50 && !_ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return;
    }
    _initStarted = true;
    try {
      // Must not use AndroidAudioFocus.gain — that pauses MusicManager BGM.
      final mix = GameAudioContexts.mix;
      _footstep ??= AudioPlayer();
      _damage ??= AudioPlayer();
      _portal ??= AudioPlayer();
      _shoot ??= AudioPlayer();
      _chime ??= AudioPlayer();
      _voice ??= AudioPlayer();
      try {
        await AudioPlayer.global.setAudioContext(mix);
      } catch (e) {
        debugPrint('SfxManager global context: $e');
      }
      await Future.wait([
        _safeContext(_footstep!, mix),
        _safeContext(_damage!, mix),
        _safeContext(_portal!, mix),
        _safeContext(_shoot!, mix),
        _safeContext(_chime!, mix),
        _safeContext(_voice!, mix),
        _footstep!.setReleaseMode(ReleaseMode.stop),
        _damage!.setReleaseMode(ReleaseMode.stop),
        _portal!.setReleaseMode(ReleaseMode.stop),
        _shoot!.setReleaseMode(ReleaseMode.stop),
        _chime!.setReleaseMode(ReleaseMode.stop),
        _voice!.setReleaseMode(ReleaseMode.stop),
      ]);
      _ready = true;
      await _applyVolumes();
    } catch (e) {
      debugPrint('SfxManager init: $e');
      // Still mark ready if players exist so VO/SFX can attempt play.
      _ready = _voice != null;
    } finally {
      _initStarted = false;
    }
  }

  Future<void> _safeContext(AudioPlayer p, AudioContext mix) async {
    try {
      await p.setAudioContext(mix);
    } catch (e) {
      debugPrint('SfxManager context: $e');
    }
  }

  Future<void> applyUserVolume(double volume, {required bool enabled}) async {
    _userVolume = volume.clamp(0.0, 1.0);
    _enabled = enabled;
    if (_ready) await _applyVolumes();
  }

  Future<void> _applyVolumes() async {
    final s = _scale;
    try {
      await Future.wait([
        if (_footstep != null) _footstep!.setVolume(_baseFoot * s),
        if (_damage != null) _damage!.setVolume(_baseDamage * s),
        if (_portal != null) _portal!.setVolume(_basePortal * s),
        if (_shoot != null) _shoot!.setVolume(_baseShoot * s),
        if (_chime != null) _chime!.setVolume(_baseChime * s),
        // VO is not part of SFX mute/volume — always full.
        if (_voice != null) _voice!.setVolume(_baseVoice),
      ]);
    } catch (_) {}
  }

  Future<void> _playOneShot(AudioPlayer? player, String asset) async {
    if (!_audible) return;
    if (!_ready) await init();
    final p = player ?? _footstep;
    if (p == null) return;
    try {
      await p.stop();
      await p.setVolume(_volumeForAsset(asset));
      await p.play(AssetSource(asset));
    } catch (e) {
      debugPrint('SfxManager play($asset): $e');
    }
  }

  double _volumeForAsset(String asset) {
    final s = _scale;
    if (asset == _footAsset) return _baseFoot * s;
    if (asset == _damageAsset) return _baseDamage * s;
    if (asset == _portalAsset) return _basePortal * s;
    if (asset == _shootAsset) return _baseShoot * s;
    if (asset == _chimeAsset) return _baseChime * s;
    return s;
  }

  Future<void> playFootstep() async => _playOneShot(_footstep, _footAsset);
  Future<void> playDamage() async => _playOneShot(_damage, _damageAsset);
  Future<void> playPortal() async => _playOneShot(_portal, _portalAsset);
  Future<void> playShoot() async => _playOneShot(_shoot, _shootAsset);

  /// Soft chime for bonds and finds (reuses the computer beep).
  Future<void> playChime() async => _playOneShot(_chime, _chimeAsset);

  /// Dialogue / cutscene VO — always on; ignores SFX mute and volume.
  Future<void> playVoice(String assetPath) async {
    if (!_ready) await init();
    final token = ++_voiceToken;
    final src = _asset(assetPath);
    try {
      // Fresh player each line — Linux/GStreamer often stays silent after
      // stop()+replay on the same short-clip player.
      final old = _voice;
      _voice = AudioPlayer();
      final p = _voice!;
      try {
        await old?.stop();
      } catch (_) {}
      try {
        await old?.dispose();
      } catch (_) {}
      if (token != _voiceToken) {
        try {
          await p.dispose();
        } catch (_) {}
        return;
      }
      await _safeContext(p, GameAudioContexts.mix);
      if (token != _voiceToken) {
        try {
          await p.dispose();
        } catch (_) {}
        return;
      }
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setVolume(_baseVoice);
      await p.setPlayerMode(PlayerMode.mediaPlayer);
      await p.play(AssetSource(src));
      if (token != _voiceToken) {
        try {
          await p.stop();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('SfxManager playVoice($src): $e');
    }
  }

  Future<void> stopVoice() async {
    _voiceToken++;
    final p = _voice;
    _voice = null;
    try {
      await p?.stop();
    } catch (_) {}
    try {
      await p?.dispose();
    } catch (_) {}
  }
}
