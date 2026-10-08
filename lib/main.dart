import 'package:flutter/material.dart';
import 'cyberpunk_space_rpg/game/custom_map_game.dart';
import 'cyberpunk_space_rpg/game/save_service.dart';

/// Main entry point for the Flutter game.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SaveService.load();
  runApp(const CustomMapGame());
}
