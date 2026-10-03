import 'package:flutter/material.dart';

import '../game/save_service.dart';
import 'cutscene_player.dart';

/// Story cutscenes by id. Each lives in `assets/cutscenes/<id>/<id>.json`
/// next to its images, and is marked seen in the save as the story flag
/// `cutscene:<id>` once it finishes or is skipped.
class Cutscenes {
  Cutscenes._();

  /// Opening, after BEGIN JOURNEY.
  static const awakening = 'awakening';

  /// First time Kaela reaches the City (world2).
  static const coalition = 'coalition';

  static String assetFor(String id) => 'assets/cutscenes/$id/$id.json';
  static String flagFor(String id) => 'cutscene:$id';
  static bool seen(String id) => SaveService.data.flag(flagFor(id));

  static Future<void> markSeen(String id) async {
    SaveService.data.setFlag(flagFor(id));
    // No snapshot: no map is live while a cutscene plays.
    await SaveService.saveNow(takeSnapshot: false);
  }

  /// A route that plays cutscene [id] and then replaces itself with [then].
  /// With [once], a cutscene already seen in this save goes straight to
  /// [then].
  static Route<void> route({required String id, required WidgetBuilder then, bool once = false}) {
    if (once && seen(id)) return MaterialPageRoute(builder: then);
    return _fade((_) => CutsceneScreen(id: id, then: then));
  }

  static Route<void> _fade(WidgetBuilder builder) => PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, _, __) => builder(context),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      );
}

/// Full-screen page for a story cutscene: plays it, marks it seen, then
/// continues to [then] (the game screen).
class CutsceneScreen extends StatefulWidget {
  const CutsceneScreen({super.key, required this.id, required this.then});

  final String id;
  final WidgetBuilder then;

  @override
  State<CutsceneScreen> createState() => _CutsceneScreenState();
}

class _CutsceneScreenState extends State<CutsceneScreen> {
  bool _leaving = false;

  Future<void> _done() async {
    if (_leaving) return;
    _leaving = true;
    final nav = Navigator.of(context);
    await Cutscenes.markSeen(widget.id);
    nav.pushReplacement(Cutscenes._fade(widget.then));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CutscenePlayer(asset: Cutscenes.assetFor(widget.id), onFinished: _done),
    );
  }
}
