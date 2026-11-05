import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_contexts.dart';

class MusicManager {
  static final MusicManager _instance = MusicManager._();
  factory MusicManager() => _instance;
  MusicManager._();

  AudioPlayer? _player;
  String? _currentTrack;
  bool _ready = false;

  /// User setting 0..1 (default matches the old hard-coded level).
  double _userVolume = 0.7;
  bool _enabled = true;

  /// Temporary mix used by dialogue / cutscenes (1 = full, 0.2 = ducked).
  double _mix = 1.0;

  /// True when [play] was blocked by the browser autoplay policy (web).
  bool _awaitingGesture = false;

  /// App left the foreground — keep BGM paused until [resumeForAppLifecycle].
  bool _pausedByLifecycle = false;

  /// Bumped on every lifecycle pause so an in-flight [play] cannot restart
  /// audible BGM after Home / app-switcher freezes the UI isolate.
  int _lifecycleEpoch = 0;

  /// Test seam: true while [pauseForAppLifecycle] is in effect.
  @visibleForTesting
  bool get debugPausedByLifecycle => _pausedByLifecycle;

  static String _asset(String path) =>
      path.startsWith('assets/') ? path.substring(7) : path;

  double get _effective =>
      (_enabled ? _userVolume : 0.0) * _mix.clamp(0.0, 1.0);

  bool get _shouldPlay => _effective > 0.001 && !_pausedByLifecycle;

  Future<void> _ensureReady() async {
    if (_ready) return;
    try {
      _player ??= AudioPlayer();
      // Default all players to mix; music opts into gain on this player only.
      try {
        await AudioPlayer.global.setAudioContext(GameAudioContexts.mix);
      } catch (e) {
        debugPrint('MusicManager global context: $e');
      }
      try {
        await _player!.setAudioContext(GameAudioContexts.music);
      } catch (e) {
        debugPrint('MusicManager context: $e');
      }
      await _player!.setVolume(_effective.clamp(0.0, 1.0));
      await _player!.setPlayerMode(PlayerMode.mediaPlayer);
      _ready = true;
    } catch (e) {
      debugPrint('MusicManager init: $e');
      _ready = _player != null;
    }
  }

  Future<void> applyUserVolume(double volume, {required bool enabled}) async {
    _userVolume = volume.clamp(0.0, 1.0);
    _enabled = enabled;
    // Apply even if play() hasn't finished init yet — pause/resume is what
    // actually mutes on Linux/GStreamer (setVolume alone is unreliable).
    if (_currentTrack != null) await _ensureReady();
    await _apply();
  }

  Future<void> _apply() async {
    final p = _player;
    if (p == null) return;
    try {
      final v = _effective.clamp(0.0, 1.0);
      await p.setVolume(v);
      if (_currentTrack == null) return;
      if (_shouldPlay) {
        // Dialogue/cutscene duck only changes volume. Calling resume() while
        // already playing re-requests Android AUDIOFOCUS_GAIN and can pause
        // or mute in-flight VO that mixes with focus none (EOE-85). Also
        // avoids undoing a just-issued lifecycle pause mid-await.
        if (p.state != PlayerState.playing) {
          await p.resume();
        }
      } else {
        await p.pause();
      }
    } catch (e) {
      debugPrint('MusicManager apply: $e');
    }
  }

  Future<void> play(String assetPath) async {
    if (_currentTrack == assetPath && !_awaitingGesture) {
      await _apply();
      return;
    }
    final epoch = _lifecycleEpoch;
    _currentTrack = assetPath;
    await _ensureReady();
    final p = _player;
    if (p == null) return;
    try {
      await p.stop();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(_effective.clamp(0.0, 1.0));
      await p.play(AssetSource(_asset(assetPath)));
      // Lifecycle pause may have landed while play() awaited the platform.
      if (!_shouldPlay || epoch != _lifecycleEpoch) {
        try {
          await p.setVolume(0);
        } catch (_) {}
        await p.pause();
        _awaitingGesture = false;
        return;
      }
      // Web autoplay often "succeeds" but leaves the player paused/silent.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (!_shouldPlay || epoch != _lifecycleEpoch) {
        try {
          await p.setVolume(0);
        } catch (_) {}
        await p.pause();
        _awaitingGesture = false;
        return;
      }
      final st = p.state;
      _awaitingGesture = st != PlayerState.playing;
      if (_awaitingGesture) {
        debugPrint('MusicManager: waiting for user gesture to start $assetPath');
      }
    } catch (e) {
      debugPrint('MusicManager play($assetPath): $e');
      _awaitingGesture = true;
    }
  }

  /// Warm / resume after a click, tap, or key (browser autoplay unlock).
  Future<void> unlockAfterGesture() async {
    if (_pausedByLifecycle) return;
    await _ensureReady();
    final p = _player;
    if (p == null) return;
    try {
      await p.resume();
    } catch (_) {}
    if (_currentTrack == null || !_shouldPlay) return;
    if (!_awaitingGesture && p.state == PlayerState.playing) return;
    try {
      await p.resume();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (p.state == PlayerState.playing) {
        _awaitingGesture = false;
        return;
      }
      final track = _currentTrack!;
      _currentTrack = null;
      _awaitingGesture = false;
      await play(track);
    } catch (e) {
      debugPrint('MusicManager unlock: $e');
      _awaitingGesture = true;
    }
  }

  Future<void> stop() async {
    _currentTrack = null;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// Pause BGM while the app is backgrounded / inactive (Android home, etc.).
  ///
  /// #93 already hooked [AppLifecycleState], but Android `mediaPlayer` +
  /// `AUDIOFOCUS_GAIN` (+ wake lock) can keep the track audible when the
  /// isolate freezes before a lone `pause()` lands, or when an in-flight
  /// [play] restarts afterwards. Mute, pause, and drop music focus.
  Future<void> pauseForAppLifecycle() async {
    _pausedByLifecycle = true;
    _lifecycleEpoch++;
    final p = _player;
    if (p == null) return;
    try {
      await p.setVolume(0);
    } catch (_) {}
    try {
      await p.pause();
    } catch (_) {}
    try {
      // Abandon Android music focus so the OS does not keep a background
      // media session after Activity pause (EOE-86).
      await p.setAudioContext(GameAudioContexts.mix);
    } catch (_) {}
  }

  /// Resume BGM after returning to the foreground, if settings still allow it.
  Future<void> resumeForAppLifecycle() async {
    if (!_pausedByLifecycle) return;
    _pausedByLifecycle = false;
    final p = _player;
    if (p != null) {
      try {
        await p.setAudioContext(GameAudioContexts.music);
      } catch (_) {}
    }
    if (_currentTrack == null) return;
    await _apply();
  }

  /// Relative mix (dialogue duck). Multiplies the user volume setting.
  Future<void> setVolume(double volume) async {
    _mix = volume.clamp(0.0, 1.0);
    await _apply();
  }
}
