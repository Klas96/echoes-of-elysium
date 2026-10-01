// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:cyberpunk_space_rpg/main.dart';

void main() {
  testWidgets('Game menu smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CyberpunkSpaceRPGApp());

    // Verify that the game menu is displayed
    expect(find.text('CYBERPUNK SPACE RPG'), findsOneWidget);
    expect(find.text('Start Earth Chapter'), findsOneWidget);
    expect(find.text('Continue Space Adventure'), findsOneWidget);
  });
}
