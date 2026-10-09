import 'package:audioplayers/audioplayers.dart';
export 'sfx_manager.dart';

class MusicManager {
  static final MusicManager _instance = MusicManager._();
  factory MusicManager() => _instance;
  MusicManager._();

  final AudioPlayer _player = AudioPlayer();
  String? _currentTrack;

  static String _asset(String path) =>
      path.startsWith('assets/') ? path.substring(7) : path;

  Future<void> play(String assetPath) async {
    if (_currentTrack == assetPath) return;
    _currentTrack = assetPath;
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource(_asset(assetPath)));
    } catch (_) {}
  }

  Future<void> stop() async {
    _currentTrack = null;
    await _player.stop();
  }

  Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume.clamp(0.0, 1.0));
    } catch (_) {}
  }
}
