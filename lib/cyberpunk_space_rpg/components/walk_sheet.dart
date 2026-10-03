import 'package:bonfire/bonfire.dart';

/// Builds a [SimpleDirectionAnimation] from a 32x32 walk-cycle sheet
/// (see assets/images/sprites/*_walk.png).
///
/// Sheet layout: rows are down, up, right[, left]; cols 0-3 are the walk
/// cycle (8 fps), cols 4-5 the idle breathe (2 fps). Sheets with only three
/// rows have no left row: Bonfire mirrors the right row instead.
///
/// Diagonals (keyboard/joystick up-left etc.) use the left/right walk and
/// idle explicitly, so all eight directions animate.
class WalkSheet {
  static const double frameSize = 32;
  static const double walkStep = 1 / 8;
  static const double idleStep = 1 / 2;

  static const int _down = 0;
  static const int _up = 1;
  static const int _right = 2;
  static const int _left = 3;

  static Future<SimpleDirectionAnimation> load(String path) async {
    final image = await Flame.images.load(path);
    final rows = image.height ~/ frameSize;
    final hasLeft = rows > _left;

    SpriteAnimation anim(int row, {required bool idle}) =>
        SpriteAnimation.fromFrameData(
          image,
          SpriteAnimationData.sequenced(
            amount: idle ? 2 : 4,
            stepTime: idle ? idleStep : walkStep,
            textureSize: Vector2.all(frameSize),
            texturePosition: Vector2(idle ? 4 * frameSize : 0, row * frameSize),
          ),
        );

    final idleRight = anim(_right, idle: true);
    final runRight = anim(_right, idle: false);
    final idleLeft = hasLeft ? anim(_left, idle: true) : null;
    final runLeft = hasLeft ? anim(_left, idle: false) : null;

    return SimpleDirectionAnimation(
      idleDown: anim(_down, idle: true),
      runDown: anim(_down, idle: false),
      idleUp: anim(_up, idle: true),
      runUp: anim(_up, idle: false),
      idleRight: idleRight,
      runRight: runRight,
      idleLeft: idleLeft,
      runLeft: runLeft,
      // Without a left row, leave the left diagonals unset so Bonfire falls
      // back to the mirrored right row.
      idleUpRight: idleRight,
      idleDownRight: idleRight,
      runUpRight: runRight,
      runDownRight: runRight,
      idleUpLeft: idleLeft,
      idleDownLeft: idleLeft,
      runUpLeft: runLeft,
      runDownLeft: runLeft,
    );
  }

  /// Direction (down/up/left/right) from [from] towards [to].
  static Direction facing(Vector2 from, Vector2 to) {
    final d = to - from;
    if (d.x.abs() > d.y.abs()) {
      return d.x > 0 ? Direction.right : Direction.left;
    }
    return d.y > 0 ? Direction.down : Direction.up;
  }
}
