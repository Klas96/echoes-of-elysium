import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Player settings that survive restarts (shared_preferences: localStorage on
/// web, the platform store elsewhere).
class GameSettings {
  static const _storyModeKey = 'storyMode';

  /// Story Mode: enemies can't hurt Kaela. Off by default (Klas can flip
  /// [storyModeDefault]); the choice is saved once the player changes it.
  static const storyModeDefault = false;
  static final storyMode = ValueNotifier<bool>(storyModeDefault);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      storyMode.value = prefs.getBool(_storyModeKey) ?? storyModeDefault;
    } catch (e) {
      debugPrint('GameSettings.load failed: $e');
    }
  }

  static Future<void> setStoryMode(bool on) async {
    storyMode.value = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storyModeKey, on);
    } catch (e) {
      debugPrint('GameSettings.setStoryMode failed: $e');
    }
  }
}
