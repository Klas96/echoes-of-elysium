import 'package:audioplayers/audioplayers.dart';

/// Minimal audioplayers surface used by [SfxManager] (native).
///
/// Production wraps [AudioPlayer]; tests inject recording fakes so CI never
/// touches platform channels.
abstract class SfxAudioPort {
  Future<void> stop();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setPlayerMode(PlayerMode mode);
  Future<void> setReleaseMode(ReleaseMode mode);
  Future<void> setAudioContext(AudioContext context);
  Future<void> setSource(Source source);
  Future<void> play(Source source, {double? volume});
  Future<void> dispose();
}

/// Production adapter around [AudioPlayer].
class AudioplayersSfxPort implements SfxAudioPort {
  AudioplayersSfxPort([AudioPlayer? player]) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setPlayerMode(PlayerMode mode) => _player.setPlayerMode(mode);

  @override
  Future<void> setReleaseMode(ReleaseMode mode) =>
      _player.setReleaseMode(mode);

  @override
  Future<void> setAudioContext(AudioContext context) =>
      _player.setAudioContext(context);

  @override
  Future<void> setSource(Source source) => _player.setSource(source);

  @override
  Future<void> play(Source source, {double? volume}) =>
      _player.play(source, volume: volume);

  @override
  Future<void> dispose() => _player.dispose();
}

typedef SfxAudioPortFactory = SfxAudioPort Function();

/// Optional override for [AudioPlayer.global.setAudioContext] in tests.
typedef SfxGlobalContextSetter = Future<void> Function(AudioContext context);

Future<void> defaultSfxGlobalContextSetter(AudioContext context) =>
    AudioPlayer.global.setAudioContext(context);
