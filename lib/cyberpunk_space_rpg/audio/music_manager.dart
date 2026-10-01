import 'package:just_audio/just_audio.dart';
export 'sfx_manager.dart';

class MusicManager {
  static final MusicManager _instance = MusicManager._();
  factory MusicManager() => _instance;
  MusicManager._();

  final AudioPlayer _player = AudioPlayer();
  String? _currentTrack;

  Future<void> play(String assetPath) async {
    if (_currentTrack == assetPath) return;
    _currentTrack = assetPath;
    try {
      await _player.stop();
      await _player.setAsset(assetPath);
      _player.setLoopMode(LoopMode.one);
      _player.play();
    } catch (_) {}
  }

  Future<void> stop() async {
    _currentTrack = null;
    await _player.stop();
  }
}
