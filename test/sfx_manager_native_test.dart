import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/audio/sfx_audio_port.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/audio/sfx_manager_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_sfx_port.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<RecordingSfxPort> created;
  late SfxManager sfx;

  setUp(() {
    created = [];
    SfxManager.portFactory = () {
      final p = RecordingSfxPort();
      created.add(p);
      return p;
    };
    SfxManager.globalContextSetter = (_) async {};
    sfx = SfxManager();
    sfx.debugReset();
  });

  tearDown(() {
    sfx.debugReset();
    SfxManager.portFactory = AudioplayersSfxPort.new;
    SfxManager.globalContextSetter = defaultSfxGlobalContextSetter;
  });

  test('init warms four shoot slots without seeking', () async {
    await sfx.init();
    expect(sfx.debugReady, isTrue);
    expect(sfx.debugShootPlayers, hasLength(4));
    for (final p in created) {
      expect(p.calls.any((c) => c.startsWith('seek:')), isFalse);
    }
  });

  test('playShoot uses stop → setVolume → resume and never seek (EOE-55)',
      () async {
    await sfx.init();
    final shootPool = sfx.debugShootPlayers!.cast<RecordingSfxPort>();
    for (final p in shootPool) {
      p.calls.clear();
    }
    await sfx.playShoot();
    // Fire is unawaited; allow the async chain to finish.
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final fired = shootPool.firstWhere((p) => p.calls.contains('stop'));
    final seq = fired.calls
        .where((c) =>
            c == 'stop' ||
            c.startsWith('setVolume:') ||
            c == 'resume' ||
            c.startsWith('seek:') ||
            c.startsWith('play:'))
        .toList();
    expect(seq.length, 3);
    expect(seq[0], 'stop');
    expect(seq[1], startsWith('setVolume:'));
    expect(seq[2], 'resume');
    expect(fired.calls.any((c) => c.startsWith('seek:')), isFalse);
  });

  test('concurrent playShoot round-robins across slots without awaiting',
      () async {
    await sfx.init();
    final pool = sfx.debugShootPlayers!.cast<RecordingSfxPort>();
    for (final p in pool) {
      p.stopDelay = const Duration(milliseconds: 30);
    }

    final started = DateTime.now();
    await Future.wait([
      sfx.playShoot(),
      sfx.playShoot(),
      sfx.playShoot(),
      sfx.playShoot(),
    ]);
    // playShoot itself must return immediately (unawaited fire).
    expect(
      DateTime.now().difference(started).inMilliseconds,
      lessThan(25),
    );
    expect(sfx.debugShootIdx, 4);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final stops = pool.where((p) => p.calls.contains('stop')).length;
    expect(stops, 4);
    for (final p in pool) {
      expect(p.calls.any((c) => c.startsWith('seek:')), isFalse);
    }
  });

  test('muted SFX skips playShoot and one-shots', () async {
    await sfx.init();
    await sfx.applyUserVolume(0.5, enabled: false);
    final pool = sfx.debugShootPlayers!.cast<RecordingSfxPort>();
    for (final p in pool) {
      p.calls.clear();
    }
    final foot = created.first;
    foot.calls.clear();
    await sfx.playShoot();
    await sfx.playFootstep();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    for (final p in pool) {
      expect(p.calls, isEmpty);
    }
    expect(foot.calls, isEmpty);
  });

  test('playFootstep does stop → setVolume → play (not seek+resume)', () async {
    await sfx.init();
    final foot = created.first;
    foot.calls.clear();
    await sfx.playFootstep();
    final seq = foot.calls
        .where((c) =>
            c == 'stop' ||
            c.startsWith('setVolume:') ||
            c.startsWith('play:') ||
            c.startsWith('seek:') ||
            c == 'resume')
        .toList();
    expect(seq.length, 3);
    expect(seq[0], 'stop');
    expect(seq[1], startsWith('setVolume:'));
    expect(seq[2], startsWith('play:'));
  });

  test('pauseForAppLifecycle stops one-shots and shoot pool; resume is no-op',
      () async {
    await sfx.init();
    final pool = sfx.debugShootPlayers!.cast<RecordingSfxPort>();
    for (final p in created) {
      p.calls.clear();
    }
    await sfx.pauseForAppLifecycle();
    for (final p in pool) {
      expect(p.calls, contains('stop'));
    }
    final oneShotStops =
        created.take(5).where((p) => p.calls.contains('stop')).length;
    expect(oneShotStops, 5);

    for (final p in created) {
      p.calls.clear();
    }
    await sfx.resumeForAppLifecycle();
    for (final p in created) {
      expect(p.calls, isEmpty);
    }
  });

  test('shoot falls back to play when resume throws', () async {
    await sfx.init();
    final pool = sfx.debugShootPlayers!.cast<RecordingSfxPort>();
    pool.first.resumeThrows = true;
    await sfx.playShoot();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(
      pool.first.calls.any((c) => c.startsWith('play:AssetSource')),
      isTrue,
    );
    expect(pool.first.calls.any((c) => c.startsWith('seek:')), isFalse);
  });

  test('stopVoice disposes current voice port', () async {
    await sfx.init();
    final beforeDispose =
        created.where((p) => p.calls.contains('dispose')).length;
    await sfx.playVoice('audio/voices/test.mp3');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await sfx.stopVoice();
    final afterDispose =
        created.where((p) => p.calls.contains('dispose')).length;
    expect(afterDispose, greaterThan(beforeDispose));
  });
}
