import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Side walk rows (right = 2, left = 3) must actually move the legs: v0.2.1
/// shipped sheets whose four side walk frames had identical legs, so walking
/// left/right looked like a single still frame.
void main() {
  const frame = 32;
  const legTop = 26; // lower-leg band inside a 32px frame

  Future<(int, Uint8List)> rgba(String path) async {
    final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (image.width, data!.buffer.asUint8List());
  }

  int legDiff(int width, Uint8List px, int row, int colA, int colB) {
    var diff = 0;
    for (var y = legTop; y < frame; y++) {
      for (var x = 0; x < frame; x++) {
        final py = row * frame + y;
        final a = (py * width + colA * frame + x) * 4;
        final b = (py * width + colB * frame + x) * 4;
        if (px[a + 3] != px[b + 3]) diff++;
      }
    }
    return diff;
  }

  for (final name in ['kaela', 'asha', 'voss', 'echo7']) {
    testWidgets('$name side walk frames move the legs', (tester) async {
      await tester.runAsync(() async {
        final (width, px) = await rgba('assets/images/sprites/${name}_walk.png');
        final rows = px.length ~/ 4 ~/ width ~/ frame;
        for (final row in [2, 3].where((r) => r < rows)) {
          // stride -> passing and stride -> swapped stride
          expect(legDiff(width, px, row, 0, 1), greaterThan(4),
              reason: '$name row $row frame 1');
          expect(legDiff(width, px, row, 0, 2), greaterThan(4),
              reason: '$name row $row frame 2');
        }
      });
    });
  }
}
