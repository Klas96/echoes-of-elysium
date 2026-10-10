import 'dart:math';
import 'dart:ui' as ui;

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../audio/sfx_manager.dart';
import 'creature_components.dart';
import 'creature_species.dart';
import 'gates.dart';
import 'interaction.dart';
import 'obstacles.dart' show HiddenPath;
import 'region_gates.dart';

/// Art for the main-route gates (assets/images/obstacles/, Designer's
/// "Woods gates" set; closed/open swap in place). Colliders are in the art's
/// own pixels, copied from the JSON next to each PNG (pond_grotto.json,
/// road_boulder.json, bramble_*.json; test/woods_gates_test.dart keeps them
/// in sync, and tools/make_tiled_maps.py GATE_ART uses the same rects).
class GateArt {
  GateArt._();

  static const grottoClosed = 'obstacles/pond_grotto_dark.png';
  static const grottoOpen = 'obstacles/pond_grotto_lit.png';

  /// Left rock, right rock, arch, pond (both states) + mouth_rect (dark only).
  static const grottoLitColliders = [
    Rect.fromLTWH(16, 3, 19, 30),
    Rect.fromLTWH(58, 3, 19, 30),
    Rect.fromLTWH(35, 3, 23, 10),
    Rect.fromLTWH(14, 33, 65, 29),
  ];
  static const grottoDarkColliders = [...grottoLitColliders, Rect.fromLTWH(35, 13, 23, 20)];

  /// The fragment just inside the mouth, and the south bank Kaela takes it
  /// from (the pond stays between them).
  static const grottoFragmentPoint = Offset(45, 27);
  static const grottoInteract = Offset(46, 66);

  static const boulderClosed = 'obstacles/road_boulder_closed.png';
  static const boulderOpen = 'obstacles/road_boulder_open.png';

  /// 3 frames of 96x64, 10 fps, once: closed -> roll east -> open.
  static const boulderRoll = 'obstacles/road_boulder_roll_anim.png';
  static const boulderRollFrames = 3;
  static const boulderRollFps = 10.0;

  /// Closed: all 3 road tiles; open: only the resting boulder on the right
  /// (passage x 0-64).
  static const boulderClosedColliders = [Rect.fromLTWH(0, 21, 96, 28)];
  static const boulderOpenColliders = [Rect.fromLTWH(64, 37, 29, 17)];

  /// road_boulder.json puts the interaction on the south side; on the Woods
  /// road Kaela arrives from the meadow, so she pushes from the north.
  static const boulderInteract = Offset(48, 10);

  static const brambleClosed = 'obstacles/bramble_closed.png';
  static const brambleOpen = 'obstacles/bramble_open.png';

  /// From the trail above the thorns (the fragment pocket is below).
  static const brambleInteract = Offset(32, 20);
}

/// A main-route ability gate (Tiled `abilitygate`). Closed until Kaela
/// presses E with its creature befriended (whoever follows her); then that
/// creature comes over and opens it. Walking into it closed gives the
/// escalating hints (gates.dart). Opened gates stay open (saved).
abstract class AbilityGate extends GameComponent with Interactable {
  final GateDef def;
  Sprite? _closed;
  Sprite? _open;
  final _hits = <RectangleHitbox>[];
  double openT;
  bool _near = false;
  bool _opening = false;

  /// All gates on the current map (for the screenshot harness / debug).
  static final live = <AbilityGate>{};

  AbilityGate(this.def, Vector2 position, Vector2 size) : openT = Gates.isOpen(def.id) ? 1 : 0 {
    this.position = position;
    this.size = size;
  }

  bool get isOpen => Gates.isOpen(def.id);
  String get closedArt;
  String get openArt;
  double get artWidth => 96;
  List<Rect> get closedColliders;
  List<Rect> get openColliders;

  @override
  Future<void> onLoad() async {
    _closed = await Sprite.load(closedArt);
    _open = await Sprite.load(openArt);
    _setColliders(isOpen ? openColliders : closedColliders);
    return super.onLoad();
  }

  @override
  void onMount() {
    super.onMount();
    live.add(this);
  }

  @override
  void onRemove() {
    live.remove(this);
    super.onRemove();
  }

  void _setColliders(List<Rect> rects) {
    for (final h in _hits) {
      h.removeFromParent();
    }
    _hits.clear();
    final k = _k;
    for (final r in rects) {
      final h = RectangleHitbox(
          position: Vector2(r.left * k, r.top * k), size: Vector2(r.width * k, r.height * k), isSolid: true);
      _hits.add(h);
      add(h);
    }
  }

  /// Where Kaela stands to use it, in art px.
  Offset get interactArt;

  double get _k => size.x / artWidth;

  @override
  Vector2 get interactPoint => absolutePosition + Vector2(interactArt.dx, interactArt.dy) * _k;
  @override
  double get interactRadius => 46;
  @override
  bool get canFocus => !isOpen && !_opening;

  @override
  PromptInfo get prompt => Gates.canOpen(def.id) ? PromptInfo(def.action, hold: 0.5) : PromptInfo.note(def.blockedHint);

  @override
  void interact() {
    if (isOpen || _opening || !Gates.canOpen(def.id)) return;
    _opening = true;
    final species = creatureSpecies[def.creature]!;
    final player = gameRef.player;
    final from = player == null ? interactPoint : player.position + player.size / 2;
    Companion.current?.lend(species.id, 2.6);
    gameRef.add(GateHelper(species, from, interactPoint - Vector2(0, 14), onArrive: _openNow));
  }

  /// Called as the gate opens (before the save / toast).
  void onOpening() {}

  void _openNow() {
    onOpening();
    Gates.open(def.id);
    _setColliders(openColliders);
    _opening = false;
    SfxManager().playChime();
    GameToast.show(def.ability.label, body: def.openedToast, compact: true);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isOpen) openT = min(1, openT + dt * 1.5);
    // Level 2/3 hints: once per walk-up to the closed gate.
    final p = gameRef.player;
    if (p == null) return;
    final d = (p.position + p.size / 2).distanceTo(interactPoint);
    final near = d < interactRadius + 4;
    if (near && !_near && !isOpen && !Gates.canOpen(def.id)) {
      final h = Gates.registerPass(def.id);
      if (h != null) {
        GameToast.show(h.title,
            body: h.line,
            color: h.gaia ? const Color(0xFF00FF88) : const Color(0xFFFFE0A8),
            portrait: h.gaia ? 'assets/images/sprites/npc_gaia.png' : null,
            seconds: h.gaia ? 5 : 3.6);
      }
    }
    if (!near && d > interactRadius + 40) _near = false;
    if (near) _near = true;
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    if (openT < 1) {
      paint.color = Color.fromRGBO(255, 255, 255, 1 - openT);
      _closed?.render(canvas, size: size, overridePaint: paint);
    }
    if (openT > 0) {
      paint.color = Color.fromRGBO(255, 255, 255, openT);
      _open?.render(canvas, size: size, overridePaint: paint);
    }
    super.render(canvas);
  }
}

/// LIGHT: the dark grotto by the pond (pond_grotto_dark / _lit). Dark, a
/// pool of shadow hides the fragment in its mouth; lit, Kaela takes it from
/// the south bank (the pond stays in between).
class GrottoGate extends AbilityGate {
  double _t = 0;
  GrottoGate(super.def, super.position, super.size);

  @override
  String get closedArt => GateArt.grottoClosed;
  @override
  String get openArt => GateArt.grottoOpen;
  @override
  List<Rect> get closedColliders => GateArt.grottoDarkColliders;
  @override
  List<Rect> get openColliders => GateArt.grottoLitColliders;
  @override
  Offset get interactArt => GateArt.grottoInteract;

  /// The grotto still hides the object at [p] (world px).
  bool hides(Vector2 p) => !isOpen && toRect().inflate(8).contains(Offset(p.x, p.y));

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final k = 1 - openT;
    final c = Offset(GateArt.grottoFragmentPoint.dx, GateArt.grottoFragmentPoint.dy) * _k;
    if (k > 0) {
      // darkness pooling in the mouth (darkness_overlay colour)
      canvas.drawCircle(
          c,
          size.x * 0.32,
          Paint()
            ..shader = ui.Gradient.radial(c, size.x * 0.32, [
              const Color(0xFF0B0A1A).withValues(alpha: 0.85 * k),
              const Color(0xFF0B0A1A).withValues(alpha: 0.0),
            ]));
    }
    if (openT > 0) {
      canvas.drawCircle(
          c,
          18 + sin(_t * 2) * 2,
          Paint()
            ..color = const Color(0xFFE8D0FF).withValues(alpha: 0.25 * openT)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
  }
}

/// SCENT: the bramble thicket in front of the east grove pocket.
class BrambleGate extends AbilityGate {
  BrambleGate(super.def, super.position, super.size);

  @override
  String get closedArt => GateArt.brambleClosed;
  @override
  String get openArt => GateArt.brambleOpen;
  @override
  double get artWidth => 64;
  @override
  List<Rect> get closedColliders => HiddenPath.closedColliders;
  @override
  List<Rect> get openColliders => HiddenPath.openColliders;
  @override
  Offset get interactArt => GateArt.brambleInteract;
  @override
  double get interactRadius => 40;
}

/// PUSH: the fallen boulder across the south road (road_boulder_*); the
/// stone turtle rolls it east (road_boulder_roll_anim, once).
class FallenBoulderGate extends AbilityGate {
  FallenBoulderGate(super.def, super.position, super.size);
  SpriteAnimationTicker? _roll;

  @override
  String get closedArt => GateArt.boulderClosed;
  @override
  String get openArt => GateArt.boulderOpen;
  @override
  List<Rect> get closedColliders => GateArt.boulderClosedColliders;
  @override
  List<Rect> get openColliders => GateArt.boulderOpenColliders;
  @override
  Offset get interactArt => GateArt.boulderInteract;

  @override
  void onOpening() {
    Flame.images.load(GateArt.boulderRoll).then((img) {
      _roll = SpriteAnimation.fromFrameData(
              img,
              SpriteAnimationData.sequenced(
                  amount: GateArt.boulderRollFrames,
                  stepTime: 1 / GateArt.boulderRollFps,
                  textureSize: Vector2(96, 64),
                  loop: false))
          .createTicker();
      openT = 0;
    }).catchError((_) {});
  }

  @override
  void update(double dt) {
    final r = _roll;
    if (r != null) {
      r.update(dt);
      if (r.done()) {
        _roll = null;
        openT = 1;
      } else {
        openT = 0;
      }
    }
    super.update(dt);
    if (_roll != null) openT = 0;
  }

  @override
  void render(Canvas canvas) {
    final r = _roll;
    if (r != null) {
      r.getSprite().render(canvas, size: size, overridePaint: Paint()..filterQuality = FilterQuality.none);
      return;
    }
    super.render(canvas);
  }
}

AbilityGate? buildAbilityGate(String gateId, Vector2 position, Vector2 size) {
  final def = gateDefs[gateId];
  if (def == null) return null;
  return switch (def.kind) {
    GateKind.grotto => GrottoGate(def, position, size),
    GateKind.bramble => BrambleGate(def, position, size),
    GateKind.boulder => FallenBoulderGate(def, position, size),
  };
}

/// "The right befriended creature comes over and opens it": a short-lived
/// copy of the creature walks (or flutters) from Kaela to the gate, plays
/// its happy animation, calls [onArrive], then fades away home.
class GateHelper extends CreatureBody {
  final Vector2 to;
  final VoidCallback onArrive;
  double _t = 0;
  bool _arrived = false;
  static const travel = 0.9, celebrate = 1.0, fade = 0.6;

  GateHelper(CreatureSpecies species, Vector2 from, this.to, {required this.onArrive})
      : _from = from - Vector2.all(16),
        super(species, from - Vector2.all(16)) {
    alpha = 0;
  }
  final Vector2 _from;

  @override
  Future<void> onLoad() async {
    sprites = await CreatureSprites.load(species);
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    tickBody(dt);
    final dest = to - Vector2.all(16);
    if (_t < travel) {
      final k = Curves.easeInOut.transform(_t / travel);
      final step = _from + (dest - _from) * k - position;
      position += step;
      faceVector(step);
      mode = CreatureMode.walk;
      alpha = min(1, alpha + dt * 4);
    } else if (_t < travel + celebrate) {
      if (!_arrived) {
        _arrived = true;
        position = dest;
        onArrive();
      }
      mode = CreatureMode.happy;
      row = 0;
    } else {
      alpha = max(0, alpha - dt / fade);
      mode = CreatureMode.idle;
      if (alpha <= 0) removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    if (species.ability == Ability.light) {
      renderGlow(canvas, const Color(0xFFE8D0FF), 30, 0.5 * alpha);
    }
    renderBody(canvas);
    super.render(canvas);
  }
}
