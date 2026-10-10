import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bonfire/bonfire.dart' hide Image;
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/walk_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// Side walk rows (right = 2, left = 3) must actually move the legs: v0.2.1
/// shipped sheets whose four side walk frames had identical legs, so walking
/// left/right looked like a single still frame.
void main() {
  const frame = 32;
  const legTop = 20; // leg band inside a 32px frame

  Future<ui.Image> decode(String path) async {
    final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
    return (await codec.getNextFrame()).image;
  }

  Future<(int, Uint8List)> rgba(String path) async {
    final image = await decode(path);
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
        if (px[a] != px[b] ||
            px[a + 1] != px[b + 1] ||
            px[a + 2] != px[b + 2] ||
            px[a + 3] != px[b + 3]) {
          diff++;
        }
      }
    }
    return diff;
  }

  for (final name in ['kaela', 'asha', 'voss', 'echo7']) {
    testWidgets('$name side walk frames move the legs', (tester) async {
      await tester.runAsync(() async {
        final (width, px) =
            await rgba('assets/images/sprites/${name}_walk.png');
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

  group('Kaela jog sheet', () {
    const jogPath = 'assets/images/sprites/kaela_jog.png';
    const walkPath = 'assets/images/sprites/kaela_walk.png';

    int frameDiff(int width, Uint8List px, int row, int colA, int colB) {
      var diff = 0;
      for (var y = 0; y < frame; y++) {
        for (var x = 0; x < frame; x++) {
          final py = row * frame + y;
          final a = (py * width + colA * frame + x) * 4;
          final b = (py * width + colB * frame + x) * 4;
          for (var k = 0; k < 4; k++) {
            if (px[a + k] != px[b + k]) {
              diff++;
              break;
            }
          }
        }
      }
      return diff;
    }

    testWidgets('same 192x128 layout as the walk sheet, six jog frames per row',
        (tester) async {
      await tester.runAsync(() async {
        final jog = await decode(jogPath);
        final walk = await decode(walkPath);
        expect(jog.width, walk.width);
        expect(jog.height, walk.height);
        expect(jog.width ~/ frame, JogSheet.frames);
        expect(jog.height ~/ frame, 4); // down, up, right, left
        final (width, px) = await rgba(jogPath);
        for (var row = 0; row < 4; row++) {
          for (var col = 0; col < JogSheet.frames; col++) {
            var opaque = 0;
            for (var y = 0; y < frame; y++) {
              for (var x = 0; x < frame; x++) {
                final i = ((row * frame + y) * width + col * frame + x) * 4;
                if (px[i + 3] > 0) opaque++;
              }
            }
            expect(opaque, greaterThan(100),
                reason: 'row $row col $col is empty');
            // Consecutive frames must differ (no stuck frame in the loop).
            final next = (col + 1) % JogSheet.frames;
            expect(frameDiff(width, px, row, col, next), greaterThan(4),
                reason: 'row $row col $col -> $next');
          }
        }
      });
    });

    testWidgets('side jog frames move the legs and left is not right',
        (tester) async {
      await tester.runAsync(() async {
        final (width, px) = await rgba(jogPath);
        for (final row in [2, 3]) {
          for (var col = 1; col < JogSheet.frames; col++) {
            expect(legDiff(width, px, row, 0, col), greaterThan(4),
                reason: 'jog row $row frame $col');
          }
        }
        // Right and left rows are different art (left faces left), so a row
        // swap or a flipped/duplicated side row fails here.
        for (var col = 0; col < JogSheet.frames; col++) {
          var diff = 0;
          for (var y = 0; y < frame; y++) {
            for (var x = 0; x < frame; x++) {
              final a = ((2 * frame + y) * width + col * frame + x) * 4;
              final b = ((3 * frame + y) * width + col * frame + x) * 4;
              if (px[a + 3] != px[b + 3] || px[a] != px[b]) diff++;
            }
          }
          expect(diff, greaterThan(50), reason: 'right/left col $col');
        }
      });
    });

    testWidgets(
        'right row faces right: more torso mass ahead on the right side',
        (tester) async {
      await tester.runAsync(() async {
        final (width, px) = await rgba(jogPath);
        // The torso leans 1 px forward and the face/nose sits on the facing
        // side: compare opaque pixels left/right of the frame centre in the
        // head band (y 4-16) for every side frame.
        int side(int row, int col, bool right) {
          var n = 0;
          for (var y = 4; y < 16; y++) {
            for (var x = right ? 16 : 0; x < (right ? 32 : 16); x++) {
              final i = ((row * frame + y) * width + col * frame + x) * 4;
              if (px[i + 3] > 0) n++;
            }
          }
          return n;
        }

        var rightRow = 0, leftRow = 0;
        for (var col = 0; col < JogSheet.frames; col++) {
          rightRow += side(2, col, true) - side(2, col, false);
          leftRow += side(3, col, false) - side(3, col, true);
        }
        expect(rightRow, greaterThan(0), reason: 'row 2 should face right');
        expect(leftRow, greaterThan(0), reason: 'row 3 should face left');
      });
    });

    testWidgets('JogSheet: jog rows for running, walk idle for standing',
        (tester) async {
      await tester.runAsync(() async {
        final jog = await decode(jogPath);
        final walk = await decode(walkPath);
        final sheet = JogSheet.fromImages(walk, jog);
        final runs = sheet.runs;
        expect(runs, hasLength(4));
        for (var row = 0; row < 4; row++) {
          final a = runs[row];
          expect(a.frames, hasLength(JogSheet.frames));
          for (var col = 0; col < JogSheet.frames; col++) {
            final s = a.frames[col].sprite;
            expect(identical(s.image, jog), isTrue);
            expect(s.srcPosition, Vector2(col * 32.0, row * 32.0));
          }
        }
        expect(sheet.stepTime, closeTo(JogSheet.jogStep, 1e-9));
        // Moss noodles (+15 %) -> faster cadence; slower ground speed -> slower.
        sheet.setSpeed(JogSheet.baseSpeed * 1.15);
        expect(sheet.stepTime, closeTo(JogSheet.jogStep / 1.15, 1e-6));
        for (final a in runs) {
          for (final f in a.frames) {
            expect(f.stepTime, closeTo(JogSheet.jogStep / 1.15, 1e-6));
          }
        }
        sheet.setSpeed(0); // standing still keeps the last pace
        expect(sheet.stepTime, closeTo(JogSheet.jogStep / 1.15, 1e-6));
        sheet.setSpeed(JogSheet.baseSpeed);
        expect(sheet.stepTime, closeTo(JogSheet.jogStep, 1e-9));
      });
    });
  });

  test('InstantFacing: facing follows the new velocity on the first frame', () {
    final p = _FacingPlayer();
    p.lastDirection = Direction.left;
    p.moveDown();
    expect(p.lastDirection, Direction.down);
    p.moveRight();
    expect(p.lastDirection, Direction.downRight);
    p.stopMove(forceIdle: true);
    expect(p.lastDirection, Direction.downRight);
  });
}

class _FacingPlayer extends SimplePlayer with InstantFacing {
  _FacingPlayer() : super(position: Vector2.zero(), size: Vector2.all(32));
}
