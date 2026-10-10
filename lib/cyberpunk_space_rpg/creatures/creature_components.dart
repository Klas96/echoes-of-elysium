import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../audio/sfx_manager.dart';
import '../components/custom_player.dart';
import 'bonds.dart';
import 'creature_species.dart';
import 'day_cycle.dart';
import 'interaction.dart';
import '../interiors/room_services.dart';

/// Animations from a Designer creature sheet: 288x128, 32x32 frames, rows
/// down/up/right/left; cols 0-3 walk (8 fps), 4-5 idle (2 fps), 6-8 happy
/// (6 fps). Puffcap also has `puffcap_hide.png` (hidden, peeking, out).
class CreatureSprites {
  final List<SpriteAnimation> walk, idle, happy;
  final Sprite? shadow;
  final List<Sprite>? hide;
  CreatureSprites(this.walk, this.idle, this.happy, this.shadow, this.hide);

  static final _cache = <String, Future<CreatureSprites>>{};

  static Future<CreatureSprites> load(CreatureSpecies s) => _cache.putIfAbsent(s.id, () => _load(s));

  static Future<CreatureSprites> _load(CreatureSpecies s) async {
    final img = await Flame.images.load(s.sheet);
    SpriteAnimation anim(int row, int col, int n, double fps) => SpriteAnimation.fromFrameData(
        img,
        SpriteAnimationData.sequenced(
          amount: n,
          stepTime: 1 / fps,
          textureSize: Vector2.all(32),
          texturePosition: Vector2(col * 32, row * 32),
        ));
    Sprite? shadow;
    try {
      shadow = Sprite(await Flame.images.load(s.shadow));
    } catch (_) {}
    List<Sprite>? hide;
    if (s.rule == BondRule.stillWatch) {
      try {
        final h = await Flame.images.load('creatures/${s.id}_hide.png');
        final n = max(1, h.width ~/ h.height);
        hide = [
          for (var i = 0; i < n; i++)
            Sprite(h, srcPosition: Vector2(i * h.height.toDouble(), 0), srcSize: Vector2.all(h.height.toDouble()))
        ];
      } catch (_) {}
    }
    // Ambient critters (no ability) walk a little calmer: 0.15 s / 0.16 s
    // steps per art/creatures/ambient/README.md.
    final ambient = s.ability == null;
    return CreatureSprites(
      [for (var r = 0; r < 4; r++) anim(r, 0, 4, ambient ? 1 / 0.15 : 8)],
      [for (var r = 0; r < 4; r++) anim(r, 4, 2, 2)],
      [for (var r = 0; r < 4; r++) anim(r, 6, 3, ambient ? 1 / 0.16 : 6)],
      shadow,
      hide,
    );
  }
}

enum CreatureMode { walk, idle, happy }

/// Shared body for wild creatures and the companion: facing, animation,
/// float + shadow for flyers, fade in/out.
abstract class CreatureBody extends GameComponent {
  final CreatureSpecies species;
  CreatureSprites? sprites;
  int row = 0;
  CreatureMode mode = CreatureMode.idle;
  double alpha = 1;
  double _bob = Random().nextDouble() * 6;
  SpriteAnimationTicker? _ticker;
  int _tickRow = -1;
  CreatureMode? _tickMode;

  /// Replaces the sheet frame (puffcap hiding in its cap).
  Sprite? still;

  CreatureBody(this.species, Vector2 position) {
    this.position = position;
    size = Vector2.all(32);
  }

  Vector2 get bodyCenter => position + size / 2;

  void faceVector(Vector2 v) {
    if (v.length2 < 0.01) return;
    if (v.x.abs() > v.y.abs()) {
      row = v.x > 0 ? 2 : 3;
    } else {
      row = v.y > 0 ? 0 : 1;
    }
  }

  void tickBody(double dt) {
    _bob += dt * 2.4;
    final s = sprites;
    if (s == null) return;
    if (_tickRow != row || _tickMode != mode || _ticker == null) {
      final list = switch (mode) {
        CreatureMode.walk => s.walk,
        CreatureMode.idle => s.idle,
        CreatureMode.happy => s.happy,
      };
      _ticker = list[row].createTicker();
      _tickRow = row;
      _tickMode = mode;
    }
    _ticker!.update(dt);
  }

  void renderGlow(Canvas canvas, Color color, double radius, double a) {
    canvas.drawCircle(
      Offset(16, species.flying ? 12 : 18),
      radius,
      Paint()
        ..color = color.withValues(alpha: a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.6),
    );
  }

  void renderBody(Canvas canvas) {
    final s = sprites;
    if (s == null || alpha <= 0.02) return;
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0));
    // shadow under the feet (feet on row 29 of the frame)
    s.shadow?.render(canvas, position: Vector2(8, 26), size: Vector2(16, 6), overridePaint: paint);
    final lift = species.flying ? -4 + sin(_bob) * 1.5 : 0.0;
    final sprite = still ?? _ticker?.getSprite();
    sprite?.render(canvas, position: Vector2(0, lift), size: Vector2.all(32), overridePaint: paint);
  }
}

/// Things a companion reacts to (sparkle emote) and abilities act on.
mixin PointOfInterest on GameComponent {
  static final registry = <PointOfInterest>{};
  Ability get poiAbility;

  /// Still something to do here.
  bool get poiPending;
  Vector2 get poiPoint => absoluteCenter;

  @override
  void onMount() {
    super.onMount();
    registry.add(this);
  }

  @override
  void onRemove() {
    registry.remove(this);
    super.onRemove();
  }
}

/// A creature living in its habitat: wanders, idles, watches the player,
/// gets startled by shots and running, and can be befriended (hold E /
/// hold the on-screen button) when its bond condition is met.
class WildCreature extends CreatureBody with Interactable {
  static const seenRadius = 150.0;
  final String objectId;
  final Vector2 home;
  final double radius;
  bool netted;

  final _quiet = QuietTracker();
  final _still = StillWatch();
  final _rng = Random();
  Vector2? _target;
  double _idleFor = 1;
  double _happyFor = 0;
  int _shots = CustomPlayer.shotCount;
  Vector2? _lastPlayer;
  /// Puffcap hide frame position 0 (hidden) .. 2 (out), animated.
  double _reveal = 0;
  bool _playerMoving = false;
  bool _hidden = false;

  WildCreature(super.species, super.position, {required this.objectId, double radiusTiles = 1, this.netted = false})
      : home = position.clone(),
        radius = radiusTiles * 32 {
    if (Bonds.isBefriended(species.id)) netted = false;
    alpha = species.nightOnly && !DayCycle.night ? 0 : 1;
  }

  @override
  Future<void> onLoad() async {
    sprites = await CreatureSprites.load(species);
    return super.onLoad();
  }

  bool get _present => !species.nightOnly || DayCycle.night;

  @override
  bool get canFocus => !_hidden && alpha > 0.6 && !Bonds.isBefriended(species.id);

  @override
  double get interactRadius => 46;

  BondCheck _check() => checkBond(
        species,
        BondContext(
          isNight: DayCycle.night,
          quiet: _quiet.quiet,
          items: Bonds.items,
          netted: netted,
          emerged: _still.out,
        ),
      );

  @override
  PromptInfo get prompt {
    final c = _check();
    if (!c.ok) return PromptInfo.note(c.note);
    return PromptInfo(c.label, hold: species.rule == BondRule.freeFromNet ? 1.4 : 1.0);
  }

  @override
  void interact() {
    final c = _check();
    if (!c.ok || Bonds.isBefriended(species.id)) return;
    if (species.rule == BondRule.offerItem) Bonds.useItem(species.item!);
    netted = false;
    _still.out = true;
    Bonds.befriend(species.id);
    _happyFor = 2.4;
    _target = null;
    SfxManager().playChime();
    final ab = species.ability;
    GameToast.show(
      'BEFRIENDED · ${species.name}',
      body: ab != null ? ab.label : 'Journal updated',
      portrait: species.portraitAsset(''),
      seconds: 3.2,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    tickBody(dt);
    // The active companion walks with Kaela; its wild self is away.
    _hidden = Bonds.activeHere == species.id;
    final targetAlpha = (_hidden || !_present) ? 0.0 : 1.0;
    alpha += (targetAlpha - alpha).clamp(-dt * 1.5, dt * 1.5);
    final player = gameRef.player;
    if (player == null) return;
    final pc = player.position + player.size / 2;
    final last = _lastPlayer;
    _playerMoving = last != null && dt > 0 && last.distanceTo(pc) / dt > 20;
    _lastPlayer = pc.clone();
    final dist = pc.distanceTo(bodyCenter);

    if (alpha > 0.6 && dist < seenRadius * Meals.nightSightMultiplier && Bonds.markSeen(species.id)) {
      GameToast.show('${species.name} spotted', body: 'Journal', compact: true);
    }
    if (alpha <= 0.02) return;

    // quiet approach
    var startled = false;
    if (CustomPlayer.shotCount != _shots) {
      _shots = CustomPlayer.shotCount;
      final from = CustomPlayer.lastShotFrom;
      if (from != null) startled |= _quiet.onShot(from.distanceTo(bodyCenter));
    }
    startled |= _quiet.tick(dt, movingClose: _playerMoving && dist < 64);
    if (species.rule == BondRule.stillWatch && !Bonds.isBefriended(species.id)) {
      _still.tick(dt, near: dist < 96, moving: _playerMoving);
    }

    if (_happyFor > 0) {
      _happyFor -= dt;
      mode = CreatureMode.happy;
      faceVector(pc - bodyCenter);
      still = null;
      return;
    }
    // Puffcap in its cap: hidden -> peeking -> out (0.25 s a frame), and
    // back in a hurry (0.12 s a frame) when it hears footsteps.
    final hide = sprites?.hide;
    if (species.rule == BondRule.stillWatch && hide != null) {
      final out = _still.out || Bonds.isBefriended(species.id);
      final want = out ? 2.0 : (_still.progress > 0.5 ? 1.0 : 0.0);
      _reveal = want > _reveal ? min(want, _reveal + dt / 0.25) : max(want, _reveal - dt / 0.12);
      if (_reveal < 1.99) {
        still = hide[min(hide.length - 1, _reveal.floor())];
        mode = CreatureMode.idle;
        return;
      }
    }
    still = null;
    if (netted) {
      mode = CreatureMode.idle;
      return;
    }
    if (startled && radius > 0) {
      final away = (bodyCenter - pc)..normalize();
      _target = _clampHome(position + away * 30);
      _idleFor = 0;
    }
    final calmNear = dist < 64 && _quiet.quiet;
    final t = _target;
    if (t != null && !calmNear) {
      final d = t - position;
      final speed = _quiet.startledFor > 3 ? species.speed * 3 + 30 : species.speed;
      if (d.length <= speed * dt || speed <= 0) {
        _target = null;
        _idleFor = 1.5 + _rng.nextDouble() * 3;
      } else {
        final step = d.normalized() * speed * dt;
        position += step;
        faceVector(step);
        mode = CreatureMode.walk;
        return;
      }
    }
    mode = CreatureMode.idle;
    if (calmNear) {
      faceVector(pc - bodyCenter);
      return;
    }
    _idleFor -= dt;
    if (_idleFor <= 0 && radius > 0) {
      final a = _rng.nextDouble() * pi * 2;
      final r = _rng.nextDouble() * radius;
      _target = home + Vector2(cos(a), sin(a)) * r;
    }
  }

  Vector2 _clampHome(Vector2 p) {
    final d = p - home;
    if (d.length <= radius) return p;
    return home + d.normalized() * radius;
  }

  @override
  void render(Canvas canvas) {
    if (alpha <= 0.02) return;
    if (species.id == 'glowmoth') {
      renderGlow(canvas, const Color(0xFFE8D0FF), 14, 0.35 * alpha);
    }
    if (species.id == 'hushdeer') {
      renderGlow(canvas, const Color(0xFFCFE8FF), 16, 0.22 * alpha);
    }
    renderBody(canvas);
    if (netted) _renderNet(canvas);
    if (_happyFor > 0) _renderHearts(canvas);
    super.render(canvas);
  }

  void _renderNet(Canvas canvas) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(3, 9, 26, 22), const Radius.circular(8)));
    final p = Paint()
      ..color = const Color(0xCC9FB4C8)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = -2; i <= 6; i++) {
      canvas.drawLine(Offset(i * 6.0, 6), Offset(i * 6.0 + 18, 30), p);
      canvas.drawLine(Offset(i * 6.0 + 18, 6), Offset(i * 6.0, 30), p);
    }
    canvas.restore();
    canvas.drawRect(const Rect.fromLTWH(24, 22, 6, 5), Paint()..color = const Color(0xFFFF6666));
  }

  void _renderHearts(Canvas canvas) {
    final t = 2.4 - _happyFor;
    for (var i = 0; i < 3; i++) {
      final k = ((t * 0.8 + i / 3) % 1);
      final x = 8.0 + i * 8 + sin((t + i) * 3) * 2;
      final y = 4 - k * 18;
      final paint = Paint()..color = const Color(0xFFFF9FC8).withValues(alpha: (1 - k) * 0.9);
      canvas.drawCircle(Offset(x - 1.5, y), 2, paint);
      canvas.drawCircle(Offset(x + 1.5, y), 2, paint);
      canvas.drawPath(
          Path()
            ..moveTo(x - 3.4, y + 0.6)
            ..lineTo(x, y + 4)
            ..lineTo(x + 3.4, y + 0.6)
            ..close(),
          paint);
    }
  }
}

/// The active companion: follows Kaela, sparkles near points of interest
/// for its ability, shows the SCENT trail / LIGHT glow. Swaps itself when
/// the journal changes [Bonds.active].
class Companion extends CreatureBody {
  static Companion? current;

  /// Farewell at the region's edge: the companion stops here and stays
  /// behind (cleared on the next map).
  static Vector2? holdAt;
  String? _id;
  String? _lentTo;
  double _lentFor = 0;

  /// A [GateHelper] of the same species is doing the job: hide this one for
  /// [seconds] so there aren't two of it.
  void lend(String speciesId, double seconds) {
    if (_id != speciesId) return;
    _lentTo = speciesId;
    _lentFor = seconds;
  }
  int _loadToken = 0;
  double _emote = 0;
  double _t = 0;
  PointOfInterest? _scentTarget;

  Companion() : super(creatureSpecies['glowmoth']!, Vector2.zero());

  CreatureSpecies? get active => _id == null ? null : creatureSpecies[_id];

  @override
  CreatureSpecies get species => active ?? super.species;

  bool get present => _id != null && sprites != null;

  @override
  void onMount() {
    super.onMount();
    current = this;
  }

  @override
  void onRemove() {
    if (current == this) current = null;
    super.onRemove();
  }

  void _snapNear(Vector2 pc) {
    position = pc - size / 2 + Vector2(-22, 6);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    final player = gameRef.player;
    if (player == null) return;
    final pc = player.position + player.size / 2;
    // Companions only follow Kaela in their home region (Regions).
    final want = Bonds.activeHere;
    if (_lentFor > 0) {
      _lentFor -= dt;
      alpha = 0;
      if (_lentFor <= 0) _lentTo = null;
    } else if (alpha < 1) {
      alpha = min(1, alpha + dt * 2);
    }
    if (want != _id) {
      _id = want;
      sprites = null;
      final token = ++_loadToken;
      if (want != null) {
        CreatureSprites.load(creatureSpecies[want]!).then((s) {
          if (token != _loadToken) return;
          sprites = s;
          _ticker = null;
          final p = gameRef.player;
          if (p != null) _snapNear(p.position + p.size / 2);
        });
      }
    }
    if (!present) return;
    tickBody(dt);

    final hold = holdAt;
    if (hold != null) {
      // stays at the treeline, watching her go
      final d = hold - bodyCenter;
      if (d.length > 4) {
        final step = d.normalized() * min(d.length, 60 * dt);
        position += step;
        faceVector(step);
        mode = CreatureMode.walk;
      } else {
        mode = CreatureMode.idle;
        faceVector(pc - bodyCenter);
      }
      return;
    }
    // follow: stay a little behind Kaela
    final dir = switch (player.lastDirection) {
      Direction.up || Direction.upLeft || Direction.upRight => Vector2(0, 1),
      Direction.down || Direction.downLeft || Direction.downRight => Vector2(0, -1),
      Direction.left => Vector2(1, 0),
      Direction.right => Vector2(-1, 0),
    };
    final target = pc + dir * 26 + Vector2(dir.y.abs() * 10, 0);
    final d = target - bodyCenter;
    if (d.length > 280) {
      _snapNear(pc);
    } else if (d.length > 8) {
      final speed = d.length > 60 ? 120.0 : 72.0;
      final step = d.normalized() * min(d.length, speed * dt);
      position += step;
      faceVector(step);
      mode = CreatureMode.walk;
    } else {
      mode = CreatureMode.idle;
      if (pc.distanceTo(bodyCenter) < 60) faceVector(pc - bodyCenter);
    }

    // points of interest for this companion's ability
    final ab = species.ability;
    PointOfInterest? near;
    var nd = double.infinity;
    PointOfInterest? scent;
    var sd = double.infinity;
    for (final p in PointOfInterest.registry) {
      if (!p.isMounted || !p.poiPending || p.poiAbility != ab) continue;
      final dd = p.poiPoint.distanceTo(bodyCenter);
      if (dd < 130 && dd < nd) {
        nd = dd;
        near = p;
      }
      if (ab == Ability.scent && dd < 480 && dd < sd) {
        sd = dd;
        scent = p;
      }
    }
    _emote = near != null ? min(1, _emote + dt * 3) : max(0, _emote - dt * 2);
    _scentTarget = scent;
  }

  @override
  void render(Canvas canvas) {
    if (!present || _lentTo != null) return;
    if (species.ability == Ability.light) {
      renderGlow(canvas, const Color(0xFFE8D0FF), DayCycle.night ? 30 : 16, DayCycle.night ? 0.45 : 0.25);
    }
    final s = _scentTarget;
    if (s != null) _renderTrail(canvas, s.poiPoint - position);
    renderBody(canvas);
    if (_emote > 0) _renderSparkle(canvas);
    super.render(canvas);
  }

  void _renderTrail(Canvas canvas, Vector2 to) {
    final from = Vector2(16, 26);
    final v = to - from;
    final len = v.length;
    if (len < 20) return;
    final dirn = v / len;
    final paint = Paint();
    final phase = (_t * 18) % 14;
    for (var s = 14.0 + phase; s < len - 6; s += 14) {
      final p = from + dirn * s + Vector2(-dirn.y, dirn.x) * sin(s / 18) * 3;
      final fade = (1 - s / max(len, 1)).clamp(0.2, 1.0);
      paint.color = const Color(0xFFFFE9A8).withValues(alpha: 0.75 * fade);
      canvas.drawCircle(Offset(p.x, p.y), 1.6, paint);
    }
  }

  void _renderSparkle(Canvas canvas) {
    final y = species.flying ? -12.0 : -8.0;
    final k = 2 + sin(_t * 6) * 1.2;
    final paint = Paint()..color = const Color(0xFFFFF2B0).withValues(alpha: 0.9 * _emote);
    final c = Offset(24, y);
    canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - k * 2)
          ..lineTo(c.dx + k * 0.6, c.dy - k * 0.6)
          ..lineTo(c.dx + k * 2, c.dy)
          ..lineTo(c.dx + k * 0.6, c.dy + k * 0.6)
          ..lineTo(c.dx, c.dy + k * 2)
          ..lineTo(c.dx - k * 0.6, c.dy + k * 0.6)
          ..lineTo(c.dx - k * 2, c.dy)
          ..lineTo(c.dx - k * 0.6, c.dy - k * 0.6)
          ..close(),
        paint);
  }
}

/// Advances the day/night clock while the map runs. Notifies listeners in
/// small steps (about every 0.3 s of play) rather than every frame.
class DayClock extends GameComponent {
  double? _t;
  double _pushed = -1;

  @override
  void update(double dt) {
    super.update(dt);
    final shown = DayCycle.time.value;
    if (_t == null || shown != _pushed) {
      // adopt outside changes (resting, loading a save)
      _t = shown;
      _pushed = shown;
    }
    final t = DayCycle.advance(_t!, dt);
    _t = t;
    if ((t - shown).abs() > 0.0005) {
      _pushed = t;
      DayCycle.time.value = t;
    }
  }
}
