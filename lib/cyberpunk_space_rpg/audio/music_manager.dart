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
    if (_currentTrack == assetPath) {
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
      if (!_shouldPlay) await p.pause();
    } catch (e) {
      debugPrint('MusicManager play($assetPath): $e');
      _currentTrack = null;
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
