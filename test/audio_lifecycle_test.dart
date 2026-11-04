import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/audio/music_manager.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/audio/sfx_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lifecycle pause/resume APIs are safe with no active track', () async {
    // No play() yet — must not throw when the app backgrounds / resumes.
    await MusicManager().pauseForAppLifecycle();
    await SfxManager().pauseForAppLifecycle();
    await MusicManager().resumeForAppLifecycle();
    await SfxManager().resumeForAppLifecycle();
  });

  test('resume is a no-op until a matching pause', () async {
    await MusicManager().resumeForAppLifecycle();
    await MusicManager().pauseForAppLifecycle();
    await MusicManager().resumeForAppLifecycle();
  });
}
