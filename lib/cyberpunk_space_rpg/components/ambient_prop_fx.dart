import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Looping FX over static Tiled props that "want" to move — steam from
/// vents, fire from braziers/campfires, mist from fountains.
///
/// Plays Designer's sprite loops (`sprites/fx/<sheet>.png` + `.json` with
/// frameWidth/frameHeight/frames/stepTime) by [kind]:
/// steam → steam_loop (steam_loop_cyan when [cyan]), smoke → smoke_loop,
/// ember/fire → fire_loop, mist → mist_loop. Falls back to the procedural
/// wisps if a sheet is missing. Tiled API unchanged: `ambient` + `kind`.
class AmbientPropFx extends GameComponent {
  final String kind;
  final bool cyan;
  final _rng = Random();
  final _parts = <_Wisp>[];
  double _t = 0;
  SpriteAnimationTicker? _loop;
  Vector2 _frame = Vector2.all(32);

  AmbientPropFx(Vector2 position, {required this.kind, this.cyan = false}) {
    this.position = position;
    size = Vector2.all(24);
  }

  /// Sheet name under sprites/fx/ for a Tiled `kind`.
  static String sheetFor(String kind, {bool cyan = false}) => switch (kind) {
        'ember' || 'fire' => 'fire_loop',
        'mist' => 'mist_loop',
        'smoke' => 'smoke_loop',
        _ => cyan ? 'steam_loop_cyan' : 'steam_loop',
      };

  /// Wisp style used by the procedural fallback.
  String get _wispKind => switch (kind) {
        'ember' || 'fire' => 'ember',
        'mist' => 'mist',
        _ => 'steam',
      };

  @override
  Future<void> onLoad() async {
    try {
      final sheet = sheetFor(kind, cyan: cyan);
      final meta = jsonDecode(await rootBundle.loadString('assets/images/sprites/fx/$sheet.json')) as Map;
      final img = await Flame.images.load('sprites/fx/$sheet.png');
      _frame = Vector2((meta['frameWidth'] as num).toDouble(), (meta['frameHeight'] as num).toDouble());
      _loop = SpriteAnimation.fromFrameData(
        img,
        SpriteAnimationData.sequenced(
          amount: (meta['frames'] as num).toInt(),
          stepTime: (meta['stepTime'] as num).toDouble(),
          textureSize: _frame,
          loop: meta['loop'] != false,
        ),
      ).createTicker();
      // Neighbouring vents shouldn't puff in lockstep.
      _loop!.update(_rng.nextDouble() * 2);
    } catch (_) {
      _loop = null;
      final n = switch (_wispKind) {
        'ember' => 5,
        'mist' => 4,
        _ => 6, // steam
      };
      for (var i = 0; i < n; i++) {
        _parts.add(_Wisp.spawn(_rng, _wispKind, stagger: i / n));
      }
    }
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_loop != null) {
      _loop!.update(dt);
      return;
    }
    for (final p in _parts) {
      p.age += dt;
      if (p.age >= p.life) {
        final i = _parts.indexOf(p);
        _parts[i] = _Wisp.spawn(_rng, _wispKind);
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y * 0.7;
    final loop = _loop;
    if (loop != null) {
      // Plumes and flames rise from the frame's bottom edge, anchored where
      // the wisps used to start; mist is a single sheet centred on the prop.
      final left = cx - _frame.x / 2;
      final top = switch (_wispKind) {
        'mist' => size.y / 2 - _frame.y / 2,
        // the ambient object sits on the vent's lid; the plume's source is
        // the frame's bottom rows
        'steam' => size.y * 0.45 - _frame.y,
        _ => cy + 4 - _frame.y, // fire: in the bowl
      };
      loop.getSprite().render(
            canvas,
            position: Vector2(left.roundToDouble(), top.roundToDouble()),
            size: _frame,
            overridePaint: Paint()..filterQuality = FilterQuality.none,
          );
      return;
    }
    for (final p in _parts) {
      final u = (p.age / p.life).clamp(0.0, 1.0);
      final rise = u * p.rise;
      final sway = sin(_t * p.swaySpeed + p.phase) * p.sway;
      final fade = (u < 0.15)
          ? u / 0.15
          : (u > 0.7 ? (1 - u) / 0.3 : 1.0);
      final alpha = (p.alpha * fade).clamp(0.0, 1.0);
      if (alpha <= 0.01) continue;
      final r = p.radius * (0.55 + u * 0.9);
      final paint = Paint()
        ..color = p.color.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.55);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + sway + p.ox, cy - rise),
          width: r * (_wispKind == 'ember' ? 0.7 : 1.4),
          height: r * (_wispKind == 'ember' ? 0.9 : 1.8),
        ),
        paint,
      );
    }
  }
}

class _Wisp {
  double age;
  final double life;
  final double rise;
  final double radius;
  final double alpha;
  final double sway;
  final double swaySpeed;
  final double phase;
  final double ox;
  final Color color;

  _Wisp({
    required this.age,
    required this.life,
    required this.rise,
    required this.radius,
    required this.alpha,
    required this.sway,
    required this.swaySpeed,
    required this.phase,
    required this.ox,
    required this.color,
  });

  factory _Wisp.spawn(Random rng, String kind, {double stagger = 0}) {
    switch (kind) {
      case 'ember':
        return _Wisp(
          age: stagger * 1.4,
          life: 1.1 + rng.nextDouble() * 0.9,
          rise: 18 + rng.nextDouble() * 14,
          radius: 2.2 + rng.nextDouble() * 2.0,
          alpha: 0.45 + rng.nextDouble() * 0.35,
          sway: 3 + rng.nextDouble() * 4,
          swaySpeed: 2.5 + rng.nextDouble() * 2,
          phase: rng.nextDouble() * pi * 2,
          ox: (rng.nextDouble() - 0.5) * 6,
          color: Color.lerp(
                const Color(0xFFFF6622),
                const Color(0xFFFFCC44),
                rng.nextDouble(),
              )!,
        );
      case 'mist':
        return _Wisp(
          age: stagger * 2.2,
          life: 2.0 + rng.nextDouble() * 1.4,
          rise: 10 + rng.nextDouble() * 10,
          radius: 5 + rng.nextDouble() * 4,
          alpha: 0.18 + rng.nextDouble() * 0.14,
          sway: 6 + rng.nextDouble() * 6,
          swaySpeed: 1.2 + rng.nextDouble(),
          phase: rng.nextDouble() * pi * 2,
          ox: (rng.nextDouble() - 0.5) * 8,
          color: const Color(0xFFAADDEE),
        );
      default: // steam
        return _Wisp(
          age: stagger * 2.0,
          life: 1.6 + rng.nextDouble() * 1.2,
          rise: 22 + rng.nextDouble() * 18,
          radius: 4 + rng.nextDouble() * 3.5,
          alpha: 0.22 + rng.nextDouble() * 0.18,
          sway: 4 + rng.nextDouble() * 5,
          swaySpeed: 1.6 + rng.nextDouble() * 1.4,
          phase: rng.nextDouble() * pi * 2,
          ox: (rng.nextDouble() - 0.5) * 5,
          color: const Color(0xFFDDE8F0),
        );
    }
  }
}
