import 'package:bonfire/bonfire.dart';

/// Builds a [SimpleDirectionAnimation] from a 32x32 walk-cycle sheet
/// (see assets/images/sprites/*_walk.png).
///
/// Sheet layout: rows are down, up, right[, left]; cols 0-3 are the walk
/// cycle (8 fps), cols 4-5 the idle breathe (2 fps). Sheets with only three
/// rows have no left row: Bonfire mirrors the right row instead.
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

    return SimpleDirectionAnimation(
      idleDown: anim(_down, idle: true),
      runDown: anim(_down, idle: false),
      idleUp: anim(_up, idle: true),
      runUp: anim(_up, idle: false),
      idleRight: anim(_right, idle: true),
      runRight: anim(_right, idle: false),
      idleLeft: hasLeft ? anim(_left, idle: true) : null,
      runLeft: hasLeft ? anim(_left, idle: false) : null,
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
