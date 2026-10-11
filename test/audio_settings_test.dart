import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/audio/audio_settings.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/save_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SaveService.data = SaveData();
    SaveService.hasSave.value = false;
    SaveService.snapshot = null;
    AudioSettings.loadFromSave();
  });

  test('defaults then persist music/sfx independently', () {
    expect(AudioSettings.musicVolume.value, AudioSettings.defaultMusic);
    expect(AudioSettings.sfxVolume.value, AudioSettings.defaultSfx);
    expect(AudioSettings.musicOn.value, isTrue);
    expect(AudioSettings.sfxOn.value, isTrue);

    AudioSettings.setMusicVolume(0.25);
    AudioSettings.setSfxOn(false);

    expect(SaveService.data.settings['musicVolume'], 0.25);
    expect(SaveService.data.settings['sfxOn'], isFalse);
    expect(SaveService.data.settings['musicOn'], isTrue);
    expect(SaveService.data.settings['sfxVolume'], AudioSettings.defaultSfx);
  });

  test('new game keeps audio settings', () async {
    AudioSettings.setMusicOn(false);
    AudioSettings.setSfxVolume(0.4);
    await SaveService.startNewGame();
    AudioSettings.loadFromSave();
    expect(AudioSettings.musicOn.value, isFalse);
    expect(AudioSettings.sfxVolume.value, 0.4);
  });
}
