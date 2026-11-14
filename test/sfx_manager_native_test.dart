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
    // Exercise the Android/mobile reuse path even when CI runs on Linux.
    SfxManager.freshVoicePlayerPerLine = false;
    sfx = SfxManager();
    sfx.debugReset();
  });

  tearDown(() {
    sfx.debugReset();
    SfxManager.portFactory = AudioplayersSfxPort.new;
    SfxManager.globalContextSetter = defaultSfxGlobalContextSetter;
    SfxManager.freshVoicePlayerPerLine =
        SfxManager.defaultFreshVoicePlayerPerLine;
  });

  test('init warms four MediaPlayer shoot slots without seeking', () async {
    await sfx.init();
    expect(sfx.debugReady, isTrue);
    expect(sfx.debugShootPlayers, hasLength(4));
    final shootPool = sfx.debugShootPlayers!.cast<RecordingSfxPort>();
    for (final p in shootPool) {
      expect(
        p.calls.contains('setPlayerMode:mediaPlayer'),
        isTrue,
        reason: 'SoundPool/lowLatency regresses EOE-55 on phones',
      );
      expect(p.calls.any((c) => c.startsWith('seek:')), isFalse);
    }
  });

  test('playShoot uses stop → setVolume → play and never seek/resume (EOE-55)',
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
    expect(seq[2], startsWith('play:AssetSource'));
    expect(fired.calls.any((c) => c.startsWith('seek:')), isFalse);
    expect(fired.calls.contains('resume'), isFalse);
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

  test('playShoot never calls resume or seek (EOE-80 / post-#123)', () async {
    await sfx.init();
    final pool = sfx.debugShootPlayers!.cast<RecordingSfxPort>();
    for (final p in pool) {
      p.calls.clear();
    }
    for (var i = 0; i < 8; i++) {
      await sfx.playShoot();
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    for (final p in pool) {
      expect(p.calls.contains('resume'), isFalse);
      expect(p.calls.any((c) => c.startsWith('seek:')), isFalse);
      expect(
        p.calls.where((c) => c.startsWith('play:AssetSource')).length,
        greaterThan(0),
      );
    }
  });

  test('playVoice reuses warmed MediaPlayer: stop → volume → play (EOE-85)',
      () async {
    await sfx.init();
    final voice = created[5]; // init order: foot, dmg, portal, chime, heal, voice
    voice.calls.clear();
    final beforeCount = created.length;

    await sfx.playVoice('audio/voices/test.mp3');

    expect(created.length, beforeCount, reason: 'must not create a fresh VO player');
    expect(voice.calls.any((c) => c.startsWith('seek:')), isFalse);
    expect(voice.calls.contains('resume'), isFalse);
    expect(voice.calls.contains('dispose'), isFalse);
    final seq = voice.calls
        .where((c) =>
            c == 'stop' ||
            c.startsWith('setVolume:') ||
            c.startsWith('play:'))
        .toList();
    expect(seq.length, greaterThanOrEqualTo(3));
    expect(seq[0], 'stop');
    expect(seq[1], startsWith('setVolume:'));
    expect(seq.last, startsWith('play:AssetSource'));
  });

  test('second playVoice reuses same port without dispose', () async {
    await sfx.init();
    final voice = created[5];
    await sfx.playVoice('audio/voices/a.mp3');
    voice.calls.clear();
    final beforeCount = created.length;

    await sfx.playVoice('audio/voices/b.mp3');

    expect(created.length, beforeCount);
    expect(voice.calls.contains('dispose'), isFalse);
    expect(
      voice.calls.where((c) => c.startsWith('play:AssetSource')).length,
      1,
    );
  });

  test('stopVoice stops reused port without disposing (EOE-85)', () async {
    await sfx.init();
    final voice = created[5];
    await sfx.playVoice('audio/voices/test.mp3');
    voice.calls.clear();
    await sfx.stopVoice();
    expect(voice.calls, contains('stop'));
    expect(voice.calls.contains('dispose'), isFalse);
  });

  test('freshVoicePlayerPerLine disposes between lines (Linux path)', () async {
    SfxManager.freshVoicePlayerPerLine = true;
    await sfx.init();
    final before = created.length;
    await sfx.playVoice('audio/voices/a.mp3');
    expect(created.length, greaterThan(before));
    final mid = created.length;
    await sfx.playVoice('audio/voices/b.mp3');
    expect(created.length, greaterThan(mid));
    expect(
      created.where((p) => p.calls.contains('dispose')).length,
      greaterThan(0),
    );
  });

  test('muted playVoice skips play and stops current line', () async {
    await sfx.init();
    final voice = created[5];
    await sfx.playVoice('audio/voices/a.mp3');
    voice.calls.clear();
    await sfx.applyUserVolume(1, enabled: false);
    await sfx.playVoice('audio/voices/b.mp3');
    expect(voice.calls.where((c) => c.startsWith('play:')), isEmpty);
    expect(voice.calls, contains('stop'));
  });
}
