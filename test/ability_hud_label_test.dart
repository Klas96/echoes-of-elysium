import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/progression.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/save_service.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/ui/ability_hud.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpAbilityHud(WidgetTester tester, {required int level}) async {
  // Phone portrait — the surface where Lv notes looked shoved down.
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SaveService.data = SaveData(level: level);
  Progression.revision.value++;

  // Clear the override before returning: testWidgets asserts foundation
  // debug vars unset *before* tearDown runs, so addTearDown alone fails CI.
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          SizedBox.expand(),
          AbilityHud(),
        ]),
      ),
    ));
    await tester.pump();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

double labelCenterY(WidgetTester tester, String id) {
  final f = find.byKey(ValueKey('ability-$id-label'));
  expect(f, findsOneWidget, reason: 'missing ability-$id-label');
  return tester.getCenter(f).dy;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SaveService.data = SaveData();
  });

  testWidgets('locked Lv3/5/7/9 notes share the same vertical center',
      (tester) async {
    await pumpAbilityHud(tester, level: 1);
    final ys = [
      for (final id in ['phase', 'pulse', 'ward', 'anchor'])
        labelCenterY(tester, id),
    ];
    for (var i = 1; i < ys.length; i++) {
      expect((ys[i] - ys[0]).abs(), lessThan(0.5),
          reason: 'locked notes must align; got $ys');
    }
  });

  testWidgets('locked Lv notes sit on the same center as unlocked skill names',
      (tester) async {
    // Lv 4: Phase unlocked (name), Pulse/Ward/Anchor still locked (Lv5/7/9).
    await pumpAbilityHud(tester, level: 4);
    final phaseY = labelCenterY(tester, 'phase');
    for (final id in ['pulse', 'ward', 'anchor']) {
      expect((labelCenterY(tester, id) - phaseY).abs(), lessThan(0.5),
          reason: '$id Lv note must match PHASE center ($phaseY)');
    }
  });
}
