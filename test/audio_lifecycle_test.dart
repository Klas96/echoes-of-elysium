import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/audio/music_manager.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/audio/sfx_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    // Leave the singleton unlocked for later tests / suites.
    await MusicManager().resumeForAppLifecycle();
  });

  test('lifecycle pause/resume APIs are safe with no active track', () async {
    // No play() yet — must not throw when the app backgrounds / resumes.
    await MusicManager().pauseForAppLifecycle();
    expect(MusicManager().debugPausedByLifecycle, isTrue);
    await SfxManager().pauseForAppLifecycle();
    await MusicManager().resumeForAppLifecycle();
    expect(MusicManager().debugPausedByLifecycle, isFalse);
    await SfxManager().resumeForAppLifecycle();
  });

  test('resume is a no-op until a matching pause', () async {
    expect(MusicManager().debugPausedByLifecycle, isFalse);
    await MusicManager().resumeForAppLifecycle();
    expect(MusicManager().debugPausedByLifecycle, isFalse);
    await MusicManager().pauseForAppLifecycle();
    expect(MusicManager().debugPausedByLifecycle, isTrue);
    await MusicManager().resumeForAppLifecycle();
    expect(MusicManager().debugPausedByLifecycle, isFalse);
  });

  test('unlockAfterGesture is ignored while lifecycle-paused', () async {
    await MusicManager().pauseForAppLifecycle();
    expect(MusicManager().debugPausedByLifecycle, isTrue);
    // Must not clear the lifecycle flag or throw with no player/track.
    await MusicManager().unlockAfterGesture();
    expect(MusicManager().debugPausedByLifecycle, isTrue);
  });

  test('repeated pause stays paused until resume', () async {
    await MusicManager().pauseForAppLifecycle();
    await MusicManager().pauseForAppLifecycle();
    expect(MusicManager().debugPausedByLifecycle, isTrue);
    await MusicManager().resumeForAppLifecycle();
    expect(MusicManager().debugPausedByLifecycle, isFalse);
  });
}
