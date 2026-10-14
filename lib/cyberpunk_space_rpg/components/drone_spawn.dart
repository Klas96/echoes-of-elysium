import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../creatures/bonds.dart';
import '../game/game_debug.dart';
import '../game/progression.dart';
import '../game/save_service.dart';
import '../ui/mmo_feedback.dart';
import 'damage_number.dart';
import 'explosion_effect.dart';
import 'uec_drone.dart';

/// Tiled object **`dronespawn`**: the object's rectangle is the spawn area
/// (designer draws it). A destructible UEC pad sits at the centre — shoot it
/// enough and the pad dies (saved in [SaveData.collected]) and stops spawning.
///
/// Each pad is locked to **one** [kind] (never mixed). Visuals differ per kind
/// (procedural placeholders until designer art — see GH #66).
///
/// Properties (all optional):
/// - `kind` — scout | swarm | sniper | shield (default scout); sole spawn type
/// - `interval` — seconds between spawns (default 8)
/// - `max` — live drones from this pad at once (default 2)
/// - `hp` — pad hit points (default 80)
/// - `level` — enemy level override
/// - `nest` — quest nest id for spawned drones
/// - `delay` — seconds before the first spawn (default 2)
/// - `id` — stable save id (else map:dronespawn:x_y)
class DroneSpawnPoint extends GameDecoration {
  static final List<DroneSpawnPoint> active = [];

  static const double padSize = 40;

  final String saveId;
  final DroneKind kind;
  final double interval;
  final int maxAlive;
  final int? level;
  final String? nestQuestId;
  final int maxHp;
  /// Designer rectangle top-left (Tiled object x/y). Kept separate because
  /// Bonfire may nudge [position] during construction.
  final Vector2 origin;
  /// Designer rectangle size in world px (Tiled object size, min [padSize]).
  final Vector2 areaSize;
  int _hp;
  double _timer;
  double _pulse = 0;
  bool _dead = false;
  final List<UECDrone> _children = [];
  final Random _rng = Random();

  DroneSpawnPoint(
    Vector2 position,
    Vector2 area, {
    required this.saveId,
    this.kind = DroneKind.scout,
    this.interval = 8,
    this.maxAlive = 2,
    this.level,
    this.nestQuestId,
    int hp = 80,
    double delay = 2,
  })  : origin = position.clone(),
        areaSize = Vector2(max(padSize, area.x), max(padSize, area.y)),
        maxHp = max(1, hp),
        _hp = max(1, hp),
        _timer = max(0.2, delay),
        super(
          position: position,
          size: Vector2(max(padSize, area.x), max(padSize, area.y)),
        );

  bool get isDead => _dead;
  Vector2 get padCenter => origin + areaSize / 2;

  /// Accent / silhouette for this pad's single enemy type (GH #66).
  _PadStyle get _style => _PadStyle.forKind(kind);

  @override
  Future<void> onLoad() async {
    active.add(this);
    add(RectangleHitbox(
      size: Vector2.all(padSize),
      position: Vector2(
        (areaSize.x - padSize) / 2,
        (areaSize.y - padSize) / 2,
      ),
      isSolid: true,
      collisionType: CollisionType.passive,
    ));
    return super.onLoad();
  }

  @override
  void onRemove() {
    active.remove(this);
    super.onRemove();
  }

  @override
  int get priority => LayerPriority.getComponentPriority(
        (position.y + size.y * 0.55).floor(),
      );

  void takeDamage(int amount, {Vector2? knockbackDir}) {
    if (_dead || amount <= 0) return;
    _hp = (_hp - amount).clamp(0, maxHp);
    DamageNumber.spawn(
      this,
      padCenter - Vector2(0, padSize * 0.35),
      amount,
      DamageNumberStyle.dealt,
    );
    if (_hp <= 0) _destroy();
  }

  void _destroy() {
    if (_dead) return;
    _dead = true;
    SaveService.data.collected.add(saveId);
    SaveService.requestAutosave();
    const xp = 35;
    const glimmer = 10;
    Bonds.addGlimmer(glimmer);
    Progression.grantXp(xp, reason: 'UEC spawn pad offline.');
    MmoFeedback.pushPop('SPAWN DOWN', color: const Color(0xFFFF8866));
    MmoFeedback.pushPop('+$glimmer ◆', color: const Color(0xFF88DDFF));
    gameRef.add(ExplosionEffect(padCenter));
    removeFromParent();
  }

  void _pruneChildren() {
    _children.removeWhere((d) => !d.isMounted || d.isDead);
  }

  void _trySpawn() {
    _pruneChildren();
    if (_dead || _children.length >= maxAlive) return;
    if (!hasGameRef) return;

    const margin = 8.0;
    final w = max(8.0, areaSize.x - margin * 2);
    final h = max(8.0, areaSize.y - margin * 2);
    final at = origin +
        Vector2(
          margin + _rng.nextDouble() * w,
          margin + _rng.nextDouble() * h,
        );
    // Centre the drone sprite on the pick.
    const droneSize = 28.0;
    final drone = UECDrone(
      at - Vector2.all(droneSize / 2),
      startAngle: _rng.nextDouble() * pi * 2,
      kind: kind,
      nestQuestId: nestQuestId,
      level: level,
    );
    _children.add(drone);
    gameRef.add(drone);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_dead) return;
    _pulse += dt * 2.4;
    _pruneChildren();
    _timer -= dt;
    if (_timer <= 0) {
      _trySpawn();
      _timer = interval;
    }
  }

  @override
  void render(Canvas canvas) {
    if (_dead) return;
    final style = _style;
    final area = Offset.zero & Size(areaSize.x, areaSize.y);
    final pad = Rect.fromCenter(
      center: Offset(areaSize.x / 2, areaSize.y / 2),
      width: padSize,
      height: padSize,
    );
    final hpT = (_hp / maxHp).clamp(0.0, 1.0);
    final glow = 0.55 + 0.45 * sin(_pulse * style.pulseRate);
    final accent = style.accent;

    // Designer area — faint only in debug so play stays clean.
    if (GameDebug.isOn) {
      canvas.drawRect(
        area,
        Paint()
          ..color = accent.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.25,
      );
      canvas.drawRect(
        area.deflate(1),
        Paint()..color = accent.withValues(alpha: 0.08),
      );
    }

    // Soft ground bloom under the pad.
    canvas.drawRRect(
      RRect.fromRectAndRadius(pad.inflate(6), Radius.circular(style.corner)),
      Paint()
        ..color = accent.withValues(alpha: 0.12 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Pad body — shape/fill differs by kind.
    style.paintBody(canvas, pad, glow);

    // Kind glyph (readability until designer sprites).
    style.paintGlyph(canvas, pad.center, glow);

    // Tiny kind tag under the pad.
    final tag = TextPainter(
      text: TextSpan(
        text: style.tag,
        style: TextStyle(
          color: accent.withValues(alpha: 0.85),
          fontSize: 7,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tag.paint(
      canvas,
      Offset(pad.center.dx - tag.width / 2, pad.bottom + 2),
    );

    // HP bar above pad when damaged.
    if (_hp < maxHp) {
      final bar = Rect.fromLTWH(pad.left, pad.top - 7, pad.width, 3);
      canvas.drawRect(bar, Paint()..color = const Color(0x88000000));
      canvas.drawRect(
        Rect.fromLTWH(bar.left, bar.top, bar.width * hpT, bar.height),
        Paint()
          ..color = hpT > 0.4 ? accent : const Color(0xFFFF3344),
      );
    }
  }
}

/// Procedural pad look per [DroneKind] (placeholders for GH #66 art).
class _PadStyle {
  final Color accent;
  final Color fill;
  final String tag;
  final double corner;
  final double pulseRate;
  final void Function(Canvas canvas, Rect pad, double glow) paintBody;
  final void Function(Canvas canvas, Offset center, double glow) paintGlyph;

  const _PadStyle({
    required this.accent,
    required this.fill,
    required this.tag,
    required this.corner,
    required this.pulseRate,
    required this.paintBody,
    required this.paintGlyph,
  });

  static _PadStyle forKind(DroneKind kind) => switch (kind) {
        DroneKind.scout => _PadStyle(
            accent: const Color(0xFFFF8844),
            fill: const Color(0xCC1A0A08),
            tag: 'SCOUT',
            corner: 5,
            pulseRate: 1,
            paintBody: _bodyRounded,
            paintGlyph: _glyphDot,
          ),
        DroneKind.swarm => _PadStyle(
            accent: const Color(0xFFFFCC44),
            fill: const Color(0xCC141008),
            tag: 'SWARM',
            corner: 3,
            pulseRate: 1.6,
            paintBody: _bodyHexish,
            paintGlyph: _glyphTriple,
          ),
        DroneKind.sniper => _PadStyle(
            accent: const Color(0xFFCC66FF),
            fill: const Color(0xCC100818),
            tag: 'SNIPER',
            corner: 2,
            pulseRate: 0.7,
            paintBody: _bodyDiamond,
            paintGlyph: _glyphCrosshair,
          ),
        DroneKind.shield => _PadStyle(
            accent: const Color(0xFF44AAFF),
            fill: const Color(0xCC081018),
            tag: 'SHIELD',
            corner: 8,
            pulseRate: 0.85,
            paintBody: _bodyShield,
            paintGlyph: _glyphRing,
          ),
      };

  static void _strokePad(Canvas canvas, Rect pad, Color accent, double glow,
      {double radius = 5, double width = 2}) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(pad, Radius.circular(radius)),
      Paint()
        ..color = accent.withValues(alpha: 0.35 + 0.35 * glow)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  static void _bodyRounded(Canvas canvas, Rect pad, double glow) {
    const accent = Color(0xFFFF8844);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pad, const Radius.circular(5)),
      Paint()..color = const Color(0xCC1A0A08),
    );
    _strokePad(canvas, pad, accent, glow);
  }

  static void _bodyHexish(Canvas canvas, Rect pad, double glow) {
    const accent = Color(0xFFFFCC44);
    final path = Path()
      ..moveTo(pad.center.dx, pad.top)
      ..lineTo(pad.right - 4, pad.top + pad.height * 0.25)
      ..lineTo(pad.right - 4, pad.bottom - pad.height * 0.25)
      ..lineTo(pad.center.dx, pad.bottom)
      ..lineTo(pad.left + 4, pad.bottom - pad.height * 0.25)
      ..lineTo(pad.left + 4, pad.top + pad.height * 0.25)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xCC141008));
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: 0.35 + 0.35 * glow)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  static void _bodyDiamond(Canvas canvas, Rect pad, double glow) {
    const accent = Color(0xFFCC66FF);
    final c = pad.center;
    final path = Path()
      ..moveTo(c.dx, pad.top + 2)
      ..lineTo(pad.right - 2, c.dy)
      ..lineTo(c.dx, pad.bottom - 2)
      ..lineTo(pad.left + 2, c.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xCC100818));
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: 0.4 + 0.35 * glow)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  static void _bodyShield(Canvas canvas, Rect pad, double glow) {
    const accent = Color(0xFF44AAFF);
    final path = Path()
      ..moveTo(pad.left + 4, pad.top + 6)
      ..lineTo(pad.right - 4, pad.top + 6)
      ..lineTo(pad.right - 6, pad.center.dy + 4)
      ..lineTo(pad.center.dx, pad.bottom - 3)
      ..lineTo(pad.left + 6, pad.center.dy + 4)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xCC081018));
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: 0.4 + 0.35 * glow)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  static void _glyphDot(Canvas canvas, Offset c, double glow) {
    const accent = Color(0xFFFF8844);
    canvas.drawCircle(
      c,
      7,
      Paint()
        ..color = accent.withValues(alpha: 0.25 + 0.35 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(c, 4.5, Paint()..color = accent);
    canvas.drawCircle(c, 2, Paint()..color = const Color(0xFFFFE0AA));
  }

  static void _glyphTriple(Canvas canvas, Offset c, double glow) {
    const accent = Color(0xFFFFCC44);
    for (final o in [
      Offset(c.dx, c.dy - 5),
      Offset(c.dx - 5, c.dy + 3),
      Offset(c.dx + 5, c.dy + 3),
    ]) {
      canvas.drawCircle(
        o,
        3.2,
        Paint()..color = accent.withValues(alpha: 0.55 + 0.35 * glow),
      );
    }
  }

  static void _glyphCrosshair(Canvas canvas, Offset c, double glow) {
    const accent = Color(0xFFCC66FF);
    final p = Paint()
      ..color = accent.withValues(alpha: 0.7 + 0.25 * glow)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(c, 6, p);
    canvas.drawLine(Offset(c.dx - 9, c.dy), Offset(c.dx + 9, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - 9), Offset(c.dx, c.dy + 9), p);
  }

  static void _glyphRing(Canvas canvas, Offset c, double glow) {
    const accent = Color(0xFF44AAFF);
    canvas.drawCircle(
      c,
      8,
      Paint()
        ..color = accent.withValues(alpha: 0.25 + 0.3 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      c,
      7,
      Paint()
        ..color = accent.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    canvas.drawCircle(c, 3, Paint()..color = accent);
  }
}
