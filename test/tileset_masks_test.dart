import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/tileset_masks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolveTileId finds stump by prop + rect', () {
    final id = TilesetMasks.resolveTileId(
      tileset: 'woods',
      propName: 'stump',
      rects: [const Rect.fromLTWH(4, 6, 26, 25)],
    );
    expect(id, 194);
  });

  test('tilesetForLevel maps regions', () {
    expect(TilesetMasks.tilesetForLevel(1), 'woods');
    expect(TilesetMasks.tilesetForLevel(2), 'city');
  });
}
