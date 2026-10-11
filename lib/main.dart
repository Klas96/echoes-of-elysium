import 'package:flutter/material.dart';
import 'cyberpunk_space_rpg/audio/audio_settings.dart';
import 'cyberpunk_space_rpg/game/custom_map_game.dart';
import 'cyberpunk_space_rpg/game/keyboard_guard.dart';
import 'cyberpunk_space_rpg/game/save_service.dart';

/// Main entry point for the Flutter game.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KeyboardGuard.install();
  await SaveService.load();
  AudioSettings.loadFromSave();
  runApp(const CustomMapGame());
}
