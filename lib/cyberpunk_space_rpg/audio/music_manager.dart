import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_contexts.dart';

export 'sfx_manager.dart';

class MusicManager {
  static final MusicManager _instance = MusicManager._();
  factory MusicManager() => _instance;
  MusicManager._();

  final AudioPlayer _player = AudioPlayer();
  String? _currentTrack;
  bool _ready = false;

  static String _asset(String path) =>
      path.startsWith('assets/') ? path.substring(7) : path;

  Future<void> _ensureReady() async {
    if (_ready) return;
    _ready = true;
    try {
      // Default all players to mix; music opts into gain on this player only.
      await AudioPlayer.global.setAudioContext(GameAudioContexts.mix);
      await _player.setAudioContext(GameAudioContexts.music);
      await _player.setVolume(0.7);
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
    } catch (e) {
      debugPrint('MusicManager init: $e');
    }
  }

  Future<void> play(String assetPath) async {
    if (_currentTrack == assetPath) return;
    _currentTrack = assetPath;
    await _ensureReady();
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource(_asset(assetPath)));
    } catch (e) {
      debugPrint('MusicManager play($assetPath): $e');
      _currentTrack = null;
    }
  }

  Future<void> stop() async {
    _currentTrack = null;
    await _player.stop();
  }

  Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('MusicManager setVolume: $e');
    }
  }
}
