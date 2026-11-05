import 'package:audioplayers/audioplayers.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/audio/sfx_audio_port.dart';

/// Records method calls for deterministic CI assertions (no platform channels).
class RecordingSfxPort implements SfxAudioPort {
  final List<String> calls = [];
  bool resumeThrows = false;
  Duration stopDelay = Duration.zero;

  @override
  Future<void> stop() async {
    if (stopDelay > Duration.zero) {
      await Future<void>.delayed(stopDelay);
    }
    calls.add('stop');
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    if (resumeThrows) throw StateError('resume failed');
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek:${position.inMilliseconds}');
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('setVolume:${volume.toStringAsFixed(3)}');
  }

  @override
  Future<void> setPlayerMode(PlayerMode mode) async {
    calls.add('setPlayerMode:${mode.name}');
  }

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {
    calls.add('setReleaseMode:${mode.name}');
  }

  @override
  Future<void> setAudioContext(AudioContext context) async {
    calls.add('setAudioContext');
  }

  @override
  Future<void> setSource(Source source) async {
    calls.add('setSource:${source.runtimeType}');
  }

  @override
  Future<void> play(Source source, {double? volume}) async {
    final v = volume == null ? '' : ':${volume.toStringAsFixed(3)}';
    calls.add('play:${source.runtimeType}$v');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }
}
