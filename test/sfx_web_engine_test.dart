import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/audio/sfx_web_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDomAudio implements SfxDomAudio {
  final List<String> calls = [];
  bool _paused = true;
  double _currentTime = 0;
  double _volume = 1;
  bool _muted = false;
  String _src = '';
  String _preload = '';
  bool playThrows = false;

  @override
  bool get paused => _paused;
  set paused(bool value) => _paused = value;

  @override
  double get currentTime => _currentTime;

  @override
  set currentTime(double value) {
    _currentTime = value;
    calls.add('currentTime=$value');
  }

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value;
    calls.add('volume=$value');
  }

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) {
    _muted = value;
    calls.add('muted=$value');
  }

  @override
  String get src => _src;

  @override
  set src(String value) {
    _src = value;
    calls.add('src=$value');
  }

  @override
  String get preload => _preload;

  @override
  set preload(String value) {
    _preload = value;
    calls.add('preload=$value');
  }

  @override
  Future<dynamic> play() async {
    calls.add('play');
    if (playThrows) throw StateError('autoplay blocked');
    _paused = false;
  }

  @override
  void pause() {
    calls.add('pause');
    _paused = true;
  }

  @override
  void load() {
    calls.add('load');
  }
}

void main() {
  late List<FakeDomAudio> created;
  late SfxWebEngine engine;

  setUp(() {
    created = [];
    engine = SfxWebEngine(createAudio: () {
      final a = FakeDomAudio();
      created.add(a);
      return a;
    });
  });

  test('url prefixes non-assets paths for Flutter web serving', () {
    expect(
      SfxWebEngine.url('audio/sfx/shoot.wav'),
      'assets/assets/audio/sfx/shoot.wav',
    );
    expect(SfxWebEngine.url('assets/audio/x.mp3'), 'assets/audio/x.mp3');
  });

  test('init preloads six one-shot elements with web asset URLs', () {
    engine.init();
    expect(created, hasLength(6));
    expect(engine.shoot!.src, contains('shoot.wav'));
    expect(engine.shoot!.src, startsWith('assets/assets/'));
    expect(created.every((a) => a.calls.contains('load')), isTrue);
  });

  test('playShoot rewinds then plays (web one-shot quirk)', () {
    engine.init();
    final shoot = engine.shoot! as FakeDomAudio;
    shoot.calls.clear();
    shoot.currentTime = 0.4;
    shoot.calls.clear();
    engine.playOneShot(engine.shoot);
    expect(shoot.calls, ['currentTime=0.0', 'play']);
  });

  test('muted skips playOneShot', () {
    engine.init();
    engine.applyUserVolume(1, enabled: false);
    final shoot = engine.shoot! as FakeDomAudio;
    shoot.calls.clear();
    engine.playOneShot(engine.shoot);
    expect(shoot.calls, isEmpty);
  });

  test('unlockAfterGesture skips already-playing elements', () async {
    engine.init();
    final foot = engine.footstep! as FakeDomAudio;
    foot.paused = false;
    // Set time without recording (direct field) for "already playing".
    foot._currentTime = 0.2;
    foot.calls.clear();
    await engine.unlockAfterGesture();
    // applyVolumes may retouch volume; must not pause/rewind a playing clip.
    expect(foot.calls.any((c) => c == 'play' || c == 'pause'), isFalse);
    expect(foot.calls.any((c) => c.startsWith('currentTime=')), isFalse);

    final dmg = engine.damage! as FakeDomAudio;
    dmg.paused = true;
    dmg._currentTime = 0;
    dmg.calls.clear();
    await engine.unlockAfterGesture();
    expect(
      dmg.calls,
      containsAll(['muted=true', 'play', 'pause', 'currentTime=0.0', 'muted=false']),
    );
  });

  test('pauseForAppLifecycle pauses and rewinds one-shots; resume is no-op',
      () async {
    engine.init();
    final shoot = engine.shoot! as FakeDomAudio;
    shoot._currentTime = 0.5;
    shoot.paused = false;
    shoot.calls.clear();
    await engine.pauseForAppLifecycle();
    expect(shoot.calls, containsAll(['pause', 'currentTime=0.0']));

    shoot.calls.clear();
    await engine.resumeForAppLifecycle();
    expect(shoot.calls, isEmpty);
  });

  test('playVoice creates fresh element; stopVoice clears it', () async {
    engine.init();
    final before = created.length;
    await engine.playVoice('assets/audio/voices/line.mp3');
    expect(created.length, before + 1);
    expect(engine.currentVoice, isNotNull);
    expect(engine.currentVoice!.src, 'assets/audio/voices/line.mp3');
    await engine.stopVoice();
    expect(engine.currentVoice, isNull);
  });

  test('applyUserVolume scales shoot base volume', () {
    engine.init();
    engine.applyUserVolume(0.5, enabled: true);
    expect(
      (engine.shoot! as FakeDomAudio).volume,
      closeTo(SfxWebEngine.baseShoot * 0.5, 1e-9),
    );
  });
}
