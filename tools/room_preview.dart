// Interior room preview for authoring and screenshots (not part of the game).
//
//   flutter run -d chrome -t tools/room_preview.dart
//   flutter build web -t tools/room_preview.dart
//
// URL query: ?id=tea_house          walk around the room (WASD / joystick)
//            &spot=wen              open that spot's panel (talk, menu, book...)
//            &night=1               night clock (lights matter less indoors)
//            &meal=night_bowl       a meal bonus is active (HUD chip)
//            &solved=2&day=3        Ferro's progress / in-game day
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/day_cycle.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/bonds.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/save_service.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/interiors/room_actions.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/interiors/room_data.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/interiors/room_scene.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/interiors/room_services.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: _Preview()));

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final q = Uri.base.queryParameters;
  RoomData? _room;

  @override
  void initState() {
    super.initState();
    SaveService.data = SaveData();
    Bonds.addGlimmer(20);
    if (q['night'] == '1') DayCycle.time.value = 0.9;
    SaveService.data.extra['day'] = int.tryParse(q['day'] ?? '') ?? 0;
    final solved = int.tryParse(q['solved'] ?? '');
    if (solved != null) SaveService.data.extra['ferro'] = {'riddle': solved, 'rumour': solved};
    final meal = q['meal'];
    if (meal != null) Meals.order(meal);
    Interiors.load(q['id'] ?? 'tea_house').then((r) {
      setState(() => _room = r);
      final spot = q['spot'];
      if (spot != null) {
        Future.delayed(const Duration(milliseconds: 1200), () {
          for (final s in r.spots) {
            if (s.id == spot) useSpot(r, s);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _room;
    return r == null ? const ColoredBox(color: Colors.black) : RoomScreen(room: r);
  }
}
