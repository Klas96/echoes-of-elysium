import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_contexts.dart';

export 'sfx_manager.dart';

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

  static String _asset(String path) =>
      path.startsWith('assets/') ? path.substring(7) : path;

  double get _effective =>
      (_enabled ? _userVolume : 0.0) * _mix.clamp(0.0, 1.0);

  bool get _shouldPlay => _effective > 0.001;

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
        // resume() is a no-op while already playing.
        await p.resume();
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
    _currentTrack = assetPath;
    await _ensureReady();
    final p = _player;
    if (p == null) return;
    try {
      await p.stop();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(_effective.clamp(0.0, 1.0));
      await p.play(AssetSource(_asset(assetPath)));
      if (!_shouldPlay) {
        await p.pause();
        _awaitingGesture = false;
        return;
      }
      // Web autoplay often "succeeds" but leaves the player paused/silent.
      await Future<void>.delayed(const Duration(milliseconds: 40));
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

  /// Warm / resume the web audio context after a click, tap, or key.
  ///
  /// Safe to call before [play] (title screen) and again after map music is
  /// queued — Chrome often needs [play] itself to run inside a gesture turn.
  Future<void> unlockAfterGesture() async {
    await _ensureReady();
    final p = _player;
    if (p == null) return;
    try {
      // Resume even with no track so later play() is allowed on this context.
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
      // Hard replay — some browsers need play() inside the gesture turn.
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

  /// Relative mix (dialogue duck). Multiplies the user volume setting.
  Future<void> setVolume(double volume) async {
    _mix = volume.clamp(0.0, 1.0);
    await _apply();
  }
}
