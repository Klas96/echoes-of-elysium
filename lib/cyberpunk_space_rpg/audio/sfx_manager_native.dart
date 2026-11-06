import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_contexts.dart';
import 'sfx_audio_port.dart';

/// Desktop / mobile SFX via audioplayers (Linux, Windows, Android, iOS, macOS).
/// just_audio has no Linux plugin — MissingPluginException on desktop.
///
/// Shoot uses MediaPlayer + round-robin (never Android SoundPool / lowLatency):
/// SoundPool `seek` after `stop` hung ~30s (EOE-55 / #123), and `stop`+`resume`
/// still missed or lagged shots on phones because SoundPool never completes /
/// clears stream state the way MediaPlayer does. Re-`play(AssetSource)` on a
/// 4-slot pool keeps auto-fire snappy without overlapping one player.
///
/// VO reuses a warmed MediaPlayer on Android/iOS (same stop→play chain as
/// shoot). Dispose+recreate every line was a Linux/GStreamer workaround that
/// left dialogue/cutscene VO silent on phones (EOE-85).
class SfxManager {
  static final SfxManager _instance = SfxManager._();
  factory SfxManager() => _instance;
  SfxManager._();

  /// Override in tests to inject recording fakes (no real AudioPlayer).
  @visibleForTesting
  static SfxAudioPortFactory portFactory = AudioplayersSfxPort.new;

  /// Override in tests to skip [AudioPlayer.global.setAudioContext].
  @visibleForTesting
  static SfxGlobalContextSetter globalContextSetter =
      defaultSfxGlobalContextSetter;

  /// Production default: fresh only on Linux/GStreamer.
  @visibleForTesting
  static bool get defaultFreshVoicePlayerPerLine => Platform.isLinux;

  /// When true, dispose + create a new VO player each line (Linux/GStreamer).
  /// Android must keep this false — fresh players were silent (EOE-85).
  @visibleForTesting
  static bool freshVoicePlayerPerLine = defaultFreshVoicePlayerPerLine;

  SfxAudioPort? _footstep;
  SfxAudioPort? _damage;
  SfxAudioPort? _portal;
  SfxAudioPort? _chime;
  SfxAudioPort? _heal;
  SfxAudioPort? _voice;
  /// Round-robin so auto-fire never stop/plays the same player twice in a row
  /// (Android MediaPlayer goes laggy/silent under overlapping stop+play).
  List<SfxAudioPort>? _shootPlayers;
  Future<List<SfxAudioPort>?>? _shootPlayersLoading;
  int _shootIdx = 0;
  bool _ready = false;
  bool _initStarted = false;
  int _voiceToken = 0;
  /// Drops stale stop/play chains when the same one-shot is re-triggered.
  final Map<SfxAudioPort, int> _oneShotGen = {};

  double _userVolume = 1.0;
  bool _enabled = true;

  static const _footAsset = 'audio/sfx/footstep_grass.mp3';
  static const _damageAsset = 'audio/sfx/damage_hit.mp3';
  static const _portalAsset = 'audio/sfx/portal.mp3';
  /// PCM WAV — short combat one-shot; kept as WAV for snappy MediaPlayer decode.
  static const _shootAsset = 'audio/sfx/shoot.wav';
  static const _chimeAsset = 'audio/sfx/computer_beep.wav';
  static const _healAsset = 'audio/sfx/health_pickup.mp3';

  static const _shootSlots = 4;

  static const _baseFoot = 0.45;
  static const _baseDamage = 0.7;
  static const _basePortal = 0.75;
  static const _baseShoot = 0.85;
  static const _baseChime = 0.55;
  static const _baseHeal = 0.7;
  static const _baseVoice = 1.0;

  static String _asset(String path) =>
      path.startsWith('assets/') ? path.substring(7) : path;

  double get _scale => _enabled ? _userVolume.clamp(0.0, 1.0) : 0.0;
  bool get _audible => _scale > 0.001;

  /// Always MediaPlayer — Android SoundPool (lowLatency) is the EOE-55 footgun.
  static PlayerMode get _shootMode => PlayerMode.mediaPlayer;

  /// Test-only: wipe singleton state between cases.
  @visibleForTesting
  void debugReset() {
    _footstep = null;
    _damage = null;
    _portal = null;
    _chime = null;
    _heal = null;
    _voice = null;
    _shootPlayers = null;
    _shootPlayersLoading = null;
    _shootIdx = 0;
    _ready = false;
    _initStarted = false;
    _voiceToken = 0;
    _oneShotGen.clear();
    _userVolume = 1.0;
    _enabled = true;
  }

  @visibleForTesting
  List<SfxAudioPort>? get debugShootPlayers => _shootPlayers;

  @visibleForTesting
  int get debugShootIdx => _shootIdx;

  @visibleForTesting
  bool get debugReady => _ready;

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
      _footstep ??= portFactory();
      _damage ??= portFactory();
      _portal ??= portFactory();
      _chime ??= portFactory();
      _heal ??= portFactory();
      _voice ??= portFactory();
      try {
        await globalContextSetter(mix);
      } catch (e) {
        debugPrint('SfxManager global context: $e');
      }
      await Future.wait([
        _safeContext(_footstep!, mix),
        _safeContext(_damage!, mix),
        _safeContext(_portal!, mix),
        _safeContext(_chime!, mix),
        _safeContext(_heal!, mix),
        _safeContext(_voice!, GameAudioContexts.voice),
        _footstep!.setPlayerMode(PlayerMode.mediaPlayer),
        _damage!.setPlayerMode(PlayerMode.mediaPlayer),
        _portal!.setPlayerMode(PlayerMode.mediaPlayer),
        _chime!.setPlayerMode(PlayerMode.mediaPlayer),
        _heal!.setPlayerMode(PlayerMode.mediaPlayer),
        _voice!.setPlayerMode(PlayerMode.mediaPlayer),
        _footstep!.setReleaseMode(ReleaseMode.stop),
        _damage!.setReleaseMode(ReleaseMode.stop),
        _portal!.setReleaseMode(ReleaseMode.stop),
        _chime!.setReleaseMode(ReleaseMode.stop),
        _heal!.setReleaseMode(ReleaseMode.stop),
        _voice!.setReleaseMode(ReleaseMode.stop),
      ]);
      _ready = true;
      await _applyVolumes();
      // Await warm so the first phone shot is not create/decode-on-play.
      await _ensureShootPlayers();
    } catch (e) {
      debugPrint('SfxManager init: $e');
      // Still mark ready if players exist so VO/SFX can attempt play.
      _ready = _voice != null;
    } finally {
      _initStarted = false;
    }
  }

  Future<List<SfxAudioPort>?> _ensureShootPlayers() async {
    if (_shootPlayers != null) return _shootPlayers;
    _shootPlayersLoading ??= () async {
      try {
        final mix = GameAudioContexts.mix;
        final mode = _shootMode;
        final vol = _baseShoot * _scale;
        // Parallel warm — sequential create/decode made the first phone shot late.
        final players = await Future.wait(List.generate(_shootSlots, (_) async {
          final p = portFactory();
          await p.setPlayerMode(mode);
          await _safeContext(p, mix);
          await p.setReleaseMode(ReleaseMode.stop);
          await p.setSource(AssetSource(_shootAsset));
          await p.setVolume(vol);
          return p;
        }));
        _shootPlayers = players;
        return players;
      } catch (e) {
        debugPrint('SfxManager shoot players: $e');
        _shootPlayersLoading = null;
        return null;
      }
    }();
    return _shootPlayersLoading;
  }

  Future<void> _safeContext(SfxAudioPort p, AudioContext mix) async {
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

  /// No-op on native (autoplay is not gated the same way as in browsers).
  Future<void> unlockAfterGesture() async {}

  Future<void> _applyVolumes() async {
    final s = _scale;
    try {
      await Future.wait([
        if (_footstep != null) _footstep!.setVolume(_baseFoot * s),
        if (_damage != null) _damage!.setVolume(_baseDamage * s),
        if (_portal != null) _portal!.setVolume(_basePortal * s),
        if (_chime != null) _chime!.setVolume(_baseChime * s),
        if (_heal != null) _heal!.setVolume(_baseHeal * s),
        if (_voice != null) _voice!.setVolume(_baseVoice * s),
        if (_shootPlayers != null)
          ..._shootPlayers!.map((p) => p.setVolume(_baseShoot * s)),
      ]);
    } catch (_) {}
  }

  Future<void> _playOneShot(SfxAudioPort? player, String asset) async {
    if (!_audible) return;
    if (!_ready) await init();
    final p = player;
    if (p == null) return;
    final gen = (_oneShotGen[p] = (_oneShotGen[p] ?? 0) + 1);
    try {
      await p.stop();
      if (_oneShotGen[p] != gen || !_audible) return;
      await p.setVolume(_volumeForAsset(asset));
      if (_oneShotGen[p] != gen || !_audible) return;
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
    if (asset == _healAsset) return _baseHeal * s;
    return s;
  }

  Future<void> playFootstep() async => _playOneShot(_footstep, _footAsset);
  Future<void> playDamage() async => _playOneShot(_damage, _damageAsset);
  Future<void> playPortal() async => _playOneShot(_portal, _portalAsset);

  Future<void> playShoot() async {
    if (!_audible) return;
    if (!_ready) await init();
    final players = await _ensureShootPlayers();
    if (players == null || players.isEmpty || !_audible) return;
    final p = players[_shootIdx++ % players.length];
    final vol = _baseShoot * _scale;
    // Return immediately — awaiting stop/resume would serialize auto-fire
    // and make shots sound laggy / drop when the previous await is still mid-flight.
    unawaited(_fireShoot(p, vol));
  }

  Future<void> _fireShoot(SfxAudioPort p, double vol) async {
    final gen = (_oneShotGen[p] = (_oneShotGen[p] ?? 0) + 1);
    try {
      // Same path as other one-shots: stop → volume → play(AssetSource).
      // Never seek (SoundPool/MediaPlayer seekComplete hangs). Never resume
      // alone (SoundPool keeps a stale streamId after the clip ends and
      // resume() becomes a silent no-op on phones — EOE-55 still on 0.4.5).
      await p.stop();
      if (_oneShotGen[p] != gen || !_audible) return;
      await p.setVolume(vol);
      if (_oneShotGen[p] != gen || !_audible) return;
      await p.play(AssetSource(_shootAsset), volume: vol);
    } catch (e) {
      debugPrint('SfxManager playShoot: $e');
    }
  }

  /// Soft chime for bonds and finds (reuses the computer beep).
  Future<void> playChime() async => _playOneShot(_chime, _chimeAsset);

  /// Health pack / heal pickup.
  Future<void> playHeal() async => _playOneShot(_heal, _healAsset);

  /// Dialogue / cutscene VO — respects SFX mute / volume.
  Future<void> playVoice(String assetPath) async {
    if (!_audible) {
      await stopVoice();
      return;
    }
    if (!_ready) await init();
    final token = ++_voiceToken;
    final src = _asset(assetPath);
    try {
      if (freshVoicePlayerPerLine) {
        await _playVoiceFresh(src, token);
      } else {
        await _playVoiceReuse(src, token);
      }
    } catch (e) {
      debugPrint('SfxManager playVoice($src): $e');
    }
  }

  /// Android/iOS/macOS/Windows: reuse the warmed MediaPlayer (EOE-85).
  Future<void> _playVoiceReuse(String src, int token) async {
    _voice ??= portFactory();
    final p = _voice!;
    final vol = _baseVoice * _scale;
    await _safeContext(p, GameAudioContexts.voice);
    if (token != _voiceToken) return;
    await p.setReleaseMode(ReleaseMode.stop);
    await p.setPlayerMode(PlayerMode.mediaPlayer);
    // Same path as shoot/one-shots: stop → volume → play(AssetSource).
    // Never seek; never resume-only; never dispose between lines on phones.
    await p.stop();
    if (token != _voiceToken || !_audible) return;
    await p.setVolume(vol);
    if (token != _voiceToken || !_audible) return;
    await p.play(AssetSource(src), volume: vol);
    if (token != _voiceToken) {
      try {
        await p.stop();
      } catch (_) {}
    }
  }

  /// Linux/GStreamer: stop()+replay on one player often stays silent.
  Future<void> _playVoiceFresh(String src, int token) async {
    final old = _voice;
    _voice = portFactory();
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
    await _safeContext(p, GameAudioContexts.voice);
    if (token != _voiceToken) {
      try {
        await p.dispose();
      } catch (_) {}
      return;
    }
    await p.setReleaseMode(ReleaseMode.stop);
    await p.setVolume(_baseVoice * _scale);
    await p.setPlayerMode(PlayerMode.mediaPlayer);
    if (!_audible || token != _voiceToken) {
      try {
        await p.dispose();
      } catch (_) {}
      return;
    }
    await p.play(AssetSource(src), volume: _baseVoice * _scale);
    if (token != _voiceToken) {
      try {
        await p.stop();
      } catch (_) {}
    }
  }

  Future<void> stopVoice() async {
    _voiceToken++;
    final p = _voice;
    if (freshVoicePlayerPerLine) {
      _voice = null;
      try {
        await p?.stop();
      } catch (_) {}
      try {
        await p?.dispose();
      } catch (_) {}
      return;
    }
    try {
      await p?.stop();
    } catch (_) {}
  }

  /// Stop one-shots and VO while the app is backgrounded / inactive.
  Future<void> pauseForAppLifecycle() async {
    await stopVoice();
    for (final p in [_footstep, _damage, _portal, _chime, _heal]) {
      if (p == null) continue;
      try {
        await p.stop();
      } catch (_) {}
    }
    final shootPool = _shootPlayers;
    if (shootPool != null) {
      for (final p in shootPool) {
        try {
          await p.stop();
        } catch (_) {}
      }
    }
  }

  /// SFX are one-shots; nothing to resume when returning to foreground.
  Future<void> resumeForAppLifecycle() async {}
}
