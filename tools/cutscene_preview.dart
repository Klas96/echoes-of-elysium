// Cutscene preview for authoring and screenshots (not part of the game).
//
//   flutter run -d chrome -t tools/cutscene_preview.dart
//   flutter build web -t tools/cutscene_preview.dart
//
// URL query: ?id=awakening            play it from the start (loops)
//            &panel=2&t=3             freeze on panel 2, 3 s in, line shown
//            &line=0&typing=1         freeze mid-typewriter
//            &title=1                 freeze on the panel's title card
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/ui/cutscene_player.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/ui/cutscenes.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: _Preview()));

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final q = Uri.base.queryParameters;
  CutscenePlayback? _playback;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scene = await loadCutscene(Cutscenes.assetFor(q['id'] ?? Cutscenes.awakening));
    final p = CutscenePlayback(scene);
    final panel = int.tryParse(q['panel'] ?? '');
    if (panel != null) {
      p.jumpTo(panel,
          time: double.tryParse(q['t'] ?? '') ?? 3,
          line: int.tryParse(q['line'] ?? '') ?? 0,
          revealed: q['typing'] != '1',
          title: q['title'] == '1');
      p.frozen = true;
    }
    setState(() => _playback = p);
  }

  @override
  Widget build(BuildContext context) {
    final p = _playback;
    return Scaffold(
      backgroundColor: Colors.black,
      body: p == null
          ? const SizedBox.expand()
          : CutscenePlayer(
              key: ValueKey(_run),
              playback: p,
              onFinished: () {
                _run++;
                _load();
              },
            ),
    );
  }
}
