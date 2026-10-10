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
    return build(image);
  }

  /// Builds the direction animation from a walk sheet [image]. Idle always
  /// comes from cols 4-5 of [image]. The run (moving) cycle comes from
  /// cols 0-3 of [image], or, when [runImage] is given, from the first
  /// [runFrames] cols of that sheet at [runStep] (same row order).
  /// The run animations it creates are added to [runs] when given (the
  /// diagonals reuse them), so a caller can retime them later.
  static SimpleDirectionAnimation build(
    Image image, {
    Image? runImage,
    int runFrames = 4,
    double runStep = walkStep,
    List<SpriteAnimation>? runs,
  }) {
    final rows = image.height ~/ frameSize;
    final hasLeft = rows > _left;

    SpriteAnimation idle(int row) => SpriteAnimation.fromFrameData(
          image,
          SpriteAnimationData.sequenced(
            amount: 2,
            stepTime: idleStep,
            textureSize: Vector2.all(frameSize),
            texturePosition: Vector2(4 * frameSize, row * frameSize),
          ),
        );
    SpriteAnimation run(int row) {
      final a = SpriteAnimation.fromFrameData(
        runImage ?? image,
        SpriteAnimationData.sequenced(
          amount: runFrames,
          stepTime: runStep,
          textureSize: Vector2.all(frameSize),
          texturePosition: Vector2(0, row * frameSize),
        ),
      );
      runs?.add(a);
      return a;
    }

    // Row order (down, up, right, left), so [runs] follows the sheet.
    final runDown = run(_down);
    final runUp = run(_up);
    final runRight = run(_right);
    final runLeft = hasLeft ? run(_left) : null;
    final idleRight = idle(_right);
    final idleLeft = hasLeft ? idle(_left) : null;

    return SimpleDirectionAnimation(
      idleDown: idle(_down),
      runDown: runDown,
      idleUp: idle(_up),
      runUp: runUp,
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

  /// Cardinal facing from a unit (or any) aim vector.
  static Direction facingVector(Vector2 dir) {
    if (dir.x.abs() > dir.y.abs()) {
      return dir.x > 0 ? Direction.right : Direction.left;
    }
    return dir.y > 0 ? Direction.down : Direction.up;
  }
}

/// Kaela's jog (kaela_jog.png): same 192x128 layout and row order as the
/// walk sheet (down, up, right, left), but all six cols are one jog cycle
/// (contact R, down, push-off, contact L, down, push-off; the bounce is baked
/// in). Idle stays on the walk sheet, so standing still looks the same.
class JogSheet {
  static const int frames = 6;

  /// Seconds per jog frame at Kaela's base speed (2.5 body lengths/s =
  /// 80 px/s): 6 x 75 ms = 0.45 s per cycle, ~36 px of ground per cycle
  /// (two steps of ~18 px).
  static const double jogStep = 0.075;

  /// Base ground speed the [jogStep] cadence is tuned for.
  static const double baseSpeed = 32 * 2.5;

  final SimpleDirectionAnimation animation;
  final List<SpriteAnimation> _runs;
  double _pace = 1;

  JogSheet._(this.animation, this._runs);

  /// The four jog rows the animation runs on, in sheet order (down, up,
  /// right, left).
  List<SpriteAnimation> get runs => List.unmodifiable(_runs);

  static Future<JogSheet> load({
    String walkPath = 'sprites/kaela_walk.png',
    String jogPath = 'sprites/kaela_jog.png',
  }) async {
    final walk = await Flame.images.load(walkPath);
    final jog = await Flame.images.load(jogPath);
    return fromImages(walk, jog);
  }

  /// Idle from [walk] (cols 4-5), the run from all six cols of [jog].
  static JogSheet fromImages(Image walk, Image jog) {
    // Diagonals share the four row animations, so retiming [runs] covers
    // all eight directions.
    final runs = <SpriteAnimation>[];
    final anim = WalkSheet.build(
      walk,
      runImage: jog,
      runFrames: frames,
      runStep: jogStep,
      runs: runs,
    );
    return JogSheet._(anim, runs);
  }

  /// Current step time per jog frame.
  double get stepTime => jogStep / _pace;

  /// Keeps the cadence matched to the ground speed so the feet don't slide:
  /// [speed] in px/s (e.g. moss noodles' +15 %). Clamped to 0.5x-1.5x.
  void setSpeed(double speed) {
    if (speed <= 1) return; // standing / pushing into a wall: keep the pace
    final pace = (speed / baseSpeed).clamp(0.5, 1.5);
    if ((pace - _pace).abs() < 0.01) return;
    _pace = pace;
    final step = stepTime;
    for (final a in _runs) {
      for (final f in a.frames) {
        f.stepTime = step;
      }
    }
  }
}

/// Bonfire 3.15 sets the joystick/keyboard velocity *after* Movement has
/// updated `lastDirection` for the frame, so the first moving frame plays
/// the run of the old facing (a one-frame flash of e.g. jog-left when
/// starting to move down from a left idle). Update the facing as soon as the
/// velocity is set instead.
mixin InstantFacing on Movement {
  @override
  void setVelocityAxis({double? x, double? y}) {
    super.setVelocityAxis(x: x, y: y);
    if (!velocity.isZero()) velocity = velocity.clone();
  }
}

/// One-shot shoot cycle: 4 rows (down/up/right/left) × 4 frames, cols
/// ready → aim → fire (cyan muzzle tip) → recover (kaela_shoot.png).
/// Built from [WalkSheet] pixels so palette/outline match the walk art.
class ShootSheet {
  static const double frameSize = 32;
  static const double stepTime = 1 / 12;

  static Future<Map<Direction, SpriteAnimation>> load(String path) async {
    final image = await Flame.images.load(path);
    SpriteAnimation row(int r) => SpriteAnimation.fromFrameData(
          image,
          SpriteAnimationData.sequenced(
            amount: 4,
            stepTime: stepTime,
            textureSize: Vector2.all(frameSize),
            texturePosition: Vector2(0, r * frameSize),
            loop: false,
          ),
        );
    return {
      Direction.down: row(0),
      Direction.up: row(1),
      Direction.right: row(2),
      Direction.left: row(3),
    };
  }
}
