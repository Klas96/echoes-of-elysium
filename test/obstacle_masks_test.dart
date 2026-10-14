import 'dart:io';

import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/obstacle_masks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rectsFromJson / rectsToJson round-trip', () {
    const src = [
      Rect.fromLTWH(64, 30, 28, 26),
      Rect.fromLTWH(0, 8, 96, 52),
    ];
    final json = ObstacleMasks.rectsToJson(src);
    expect(json, [
      [64, 30, 28, 26],
      [0, 8, 96, 52],
    ]);
    expect(ObstacleMasks.rectsFromJson(json), src);
  });

  test('loadFromDisk matches Designer boulder/bramble/grotto files', () {
    ObstacleMasks.loadFromDisk();
    expect(ObstacleMasks.boulderClosed, isNotEmpty);
    expect(ObstacleMasks.boulderOpen.single.left, greaterThanOrEqualTo(64));
    expect(ObstacleMasks.brambleClosed, isNotEmpty);
    expect(ObstacleMasks.brambleOpen.length, 2);
    expect(ObstacleMasks.grottoClosed.length, greaterThanOrEqualTo(3));
    expect(ObstacleMasks.grottoOpen.length, greaterThanOrEqualTo(3));
    expect(ObstacleMasks.loaded, isTrue);
  });

  test('projectRoot finds repo with obstacles assets', () {
    expect(ObstacleMasks.projectRoot(), isNotNull);
    expect(ObstacleMasks.diskPath('pond_grotto.json'), contains('pond_grotto.json'));
    expect(File(ObstacleMasks.diskPath('pond_grotto.json')).existsSync(), isTrue);
  });

  test('setRects updates open/closed independently', () {
    ObstacleMasks.loadFromDisk();
    final before = List<Rect>.of(ObstacleMasks.boulderOpen);
    ObstacleMasks.setRects(
      ObstacleMaskId.boulder,
      openState: true,
      rects: [const Rect.fromLTWH(70, 32, 20, 20)],
    );
    expect(ObstacleMasks.boulderOpen.single, const Rect.fromLTWH(70, 32, 20, 20));
    expect(ObstacleMasks.boulderClosed, isNot(equals(ObstacleMasks.boulderOpen)));
    // restore for other tests in the isolate
    ObstacleMasks.setOpen(ObstacleMaskId.boulder, before);
  });
}
