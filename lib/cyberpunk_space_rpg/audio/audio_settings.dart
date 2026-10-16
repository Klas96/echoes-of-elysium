import 'package:flutter/foundation.dart';

import '../game/save_service.dart';
import 'music_manager.dart';
import 'sfx_manager.dart';

/// Persistent music / SFX levels. Read from [SaveData.settings] so they survive
/// a new playthrough (see [SaveService.startNewGame]).
/// SFX Off also mutes dialogue / cutscene VO.
class AudioSettings {
  AudioSettings._();

  static const defaultMusic = 0.7;
  static const defaultSfx = 1.0;

  static final musicVolume = ValueNotifier<double>(defaultMusic);
  static final sfxVolume = ValueNotifier<double>(defaultSfx);
  static final musicOn = ValueNotifier<bool>(true);
  static final sfxOn = ValueNotifier<bool>(true);

  static double _clamp01(Object? v, double fallback) {
    if (v is num) return v.toDouble().clamp(0.0, 1.0);
    return fallback;
  }

  /// Call after [SaveService.load].
  static void loadFromSave() {
    final s = SaveService.data.settings;
    musicVolume.value = _clamp01(s['musicVolume'], defaultMusic);
    sfxVolume.value = _clamp01(s['sfxVolume'], defaultSfx);
    musicOn.value = s['musicOn'] != false;
    sfxOn.value = s['sfxOn'] != false;
    apply();
  }

  static void persist() {
    final s = SaveService.data.settings;
    s['musicVolume'] = musicVolume.value;
    s['sfxVolume'] = sfxVolume.value;
    s['musicOn'] = musicOn.value;
    s['sfxOn'] = sfxOn.value;
    SaveService.requestAutosave();
  }

  static void apply() {
    MusicManager().applyUserVolume(musicVolume.value, enabled: musicOn.value);
    SfxManager().applyUserVolume(sfxVolume.value, enabled: sfxOn.value);
  }

  static void setMusicVolume(double v) {
    musicVolume.value = v.clamp(0.0, 1.0);
    apply();
    persist();
  }

  static void setSfxVolume(double v) {
    sfxVolume.value = v.clamp(0.0, 1.0);
    apply();
    persist();
  }

  static void setMusicOn(bool on) {
    musicOn.value = on;
    apply();
    persist();
  }

  static void setSfxOn(bool on) {
    sfxOn.value = on;
    apply();
    if (!on) SfxManager().stopVoice();
    persist();
  }
}
