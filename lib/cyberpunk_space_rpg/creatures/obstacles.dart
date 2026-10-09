import 'dart:math';
import 'dart:ui' as ui;

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../audio/sfx_manager.dart';
import 'bonds.dart';
import 'creature_components.dart';
import 'creature_species.dart';
import 'day_cycle.dart';
import 'interaction.dart';

/// Ability-gated obstacles and the small finds they guard (M2). All of them
/// come from the Tiled 'gameplay' layer; art is in assets/images/obstacles/
/// (Designer files, see art/obstacles/README.md), swappable by file name.

const _glyphLore = <String, String>{
  'woods_nook': '"We moved the stones so the turtles could pass. In time, the turtles moved them for us."',
  'woods_pond': '"Light is only a memory that the dark agrees to keep."',
  'woods_gate': '"Before the gate there was only the forest, asking: who will remember us?"',
};

Vector2 _playerCenter(BonfireGameInterface g) {
  final p = g.player;
  return p == null ? Vector2.all(-9999) : p.position + p.size / 2;
}

/// PUSH: a heavy 2x2 boulder plugging a nook. With the stone turtle along,
/// hold E to shove it [push] (in pixels); otherwise it just blocks.
class Boulder extends GameComponent with Interactable, PointOfInterest {
  final String id;
  final Vector2 push;
  Sprite? _sprite;
  SpriteAnimation? _dust;
  SpriteAnimationTicker? _dustTicker;
  Vector2? _from;
  double _t = 0;
  static const _moveSeconds = 0.5;

  Boulder(Vector2 position, Vector2 size, {required this.id, required this.push}) {
    this.position = position + (Bonds.secretDone(id) ? push : Vector2.zero());
    this.size = size;
  }

  bool get pushed => Bonds.secretDone(id);

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load(size.x > 40 ? 'obstacles/boulder_2x2.png' : 'obstacles/boulder.png');
    try {
      final img = await Flame.images.load('obstacles/boulder_push_anim.png');
      _dust = SpriteAnimation.fromFrameData(
          img, SpriteAnimationData.sequenced(amount: 3, stepTime: 0.1, textureSize: Vector2(48, 40), loop: false));
    } catch (_) {}
    // Solid across the whole tunnel (the art's own rect leaves a gap at the
    // top that Kaela's feet could slip through).
    add(RectangleHitbox(position: Vector2(2, 4), size: size - Vector2(4, 6), isSolid: true));
    return super.onLoad();
  }

  @override
  Ability get poiAbility => Ability.push;
  @override
  bool get poiPending => !pushed;
  @override
  bool get canFocus => !pushed;
  @override
  double get interactRadius => size.x * 0.5 + 30;

  @override
  PromptInfo get prompt => Bonds.has(Ability.push)
      ? const PromptInfo('PUSH', hold: 0.5)
      : PromptInfo.note(Bonds.unlocked(Ability.push)
          ? 'A boulder with a carved handprint. The stone turtle could shove it.'
          : 'A heavy boulder with a carved handprint. Too heavy to move alone.');

  @override
  void interact() {
    if (pushed || !Bonds.has(Ability.push)) return;
    Bonds.markSecret(id);
    _from = position.clone();
    _t = 0;
    _dustTicker = _dust?.createTicker();
    SfxManager().playChime();
    GameToast.show('PUSH', body: 'Boulder moved', compact: true);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final from = _from;
    if (from != null) {
      _t += dt;
      final k = Curves.easeOut.transform((_t / _moveSeconds).clamp(0.0, 1.0));
      position = from + push * k;
      _dustTicker?.update(dt);
      if (_t >= _moveSeconds) _from = null;
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    _sprite?.render(canvas, size: size, overridePaint: paint);
    if (_from != null && _dustTicker != null) {
      final scale = size.x / 32;
      _dustTicker!.getSprite().render(canvas,
          position: Vector2(-8, -4) * scale, size: Vector2(48, 40) * scale, overridePaint: paint);
    }
    super.render(canvas);
  }
}

/// LIGHT: a patch of darkness (Designer darkness_overlay, 92%). With the
/// glowmoth along, light_mask cuts a soft circle around it; glyphs inside
/// only show while lit (or once read).
class DarkZone extends GameComponent with PointOfInterest {
  final String id;
  double lit = 0;
  double _t = 0;

  DarkZone(Vector2 position, Vector2 size, {required this.id}) {
    this.position = position;
    this.size = size;
    renderAboveComponents = true;
  }

  @override
  Ability get poiAbility => Ability.light;
  @override
  bool get poiPending => !Bonds.secretDone(id);

  Rect get _rect => Rect.fromLTWH(position.x, position.y, size.x, size.y);

  Vector2? get _lightSource {
    final c = Companion.current;
    if (c == null || !c.present || c.species.ability != Ability.light) return null;
    return c.bodyCenter;
  }

  bool covers(Vector2 p) => _rect.contains(Offset(p.x, p.y));

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    final src = _lightSource;
    final on = src != null && _rect.inflate(56).contains(Offset(src.x, src.y));
    lit = on ? min(1, lit + dt * 1.2) : max(0, lit - dt * 0.8);
    if (lit > 0.6 && !Bonds.secretDone(id)) {
      Bonds.markSecret(id);
      GameToast.show('LIGHT', body: 'Dark fades', compact: true);
    }
  }

  @override
  void render(Canvas canvas) {
    // Designer's darkness_overlay (#0b0a1a at 92%) with a soft light_mask-
    // style radial hole. A gradient shader is used instead of a dstOut
    // saveLayer, which the web renderer did not composite reliably.
    final player = _playerCenter(gameRef);
    final src = _lightSource;
    final k = src == null ? 0.0 : lit.toDouble();
    // The glow pools between Kaela and the moth hovering behind her.
    final centre = src == null ? player : player + (src - player) * (0.45 * k);
    final radius = 30 + (120 + sin(_t * 2) * 4 - 30) * k;
    final open = 0.55 + 0.45 * k; // how much of the dark the centre loses
    const dark = Color(0xEB0B0A1A);
    final inner = dark.withValues(alpha: dark.a * (1 - open));
    final c = centre - position;
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(c.x, c.y),
        radius,
        [inner, inner, dark],
        const [0.0, 0.25, 1.0],
      );
    canvas.drawRect(Offset.zero & Size(size.x, size.y), paint);
    super.render(canvas);
  }
}

/// An Aetherian glyph tablet: READ shows a lore line. Inside a dark zone it
/// can only be seen (and read) while the glowmoth lights it.
class GlyphTablet extends GameComponent with Interactable {
  final String id;
  final String glyph;
  Sprite? _sprite;
  DarkZone? _zone;
  bool _zoneChecked = false;
  double _pulse = 0;

  GlyphTablet(Vector2 position, {required this.id, required this.glyph}) {
    this.position = position;
    size = Vector2.all(24);
  }

  bool get read => Bonds.secretDone(id);
  bool get visible => _zone == null || _zone!.lit > 0.5 || read;

  @override
  Future<void> onLoad() async {
    _sprite = await Sprite.load('obstacles/glyph.png');
    return super.onLoad();
  }

  @override
  bool get canFocus => visible;
  @override
  double get interactRadius => 36;
  @override
  PromptInfo get prompt => const PromptInfo('READ');

  @override
  void interact() {
    if (!read) SfxManager().playChime();
    Bonds.markSecret(id);
    GameToast.show('GLYPH', body: _glyphLore[glyph] ?? '...', color: const Color(0xFF66FFEE), compact: true);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 2.5;
    if (!_zoneChecked && isMounted) {
      _zoneChecked = true;
      for (final z in gameRef.query<DarkZone>()) {
        if (z.covers(absoluteCenter)) _zone = z;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (!visible && _zoneChecked) return;
    if (!_zoneChecked) return;
    final a = _zone == null || read ? 1.0 : ((_zone!.lit - 0.5) * 2).clamp(0.0, 1.0);
    canvas.drawCircle(
        const Offset(12, 12),
        12 + sin(_pulse) * 2,
        Paint()
          ..color = const Color(0xFF66FFEE).withValues(alpha: (read ? 0.12 : 0.3) * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    _sprite?.render(canvas,
        size: size,
        overridePaint: Paint()
          ..filterQuality = FilterQuality.none
          ..color = Color.fromRGBO(255, 255, 255, a));
    super.render(canvas);
  }
}

/// A small glimmer chest behind a boulder: OPEN for glimmer.
class GlimmerStash extends GameComponent with Interactable {
  final String id;
  final int amount;
  Sprite? _chest;
  SpriteAnimation? _spark;
  SpriteAnimationTicker? _sparkT;

  GlimmerStash(Vector2 position, {required this.id, required this.amount}) {
    this.position = position;
    size = Vector2.all(32);
  }

  bool get opened => Bonds.secretDone(id);

  @override
  Future<void> onLoad() async {
    _chest = await Sprite.load('obstacles/chest_plain.png');
    final img = await Flame.images.load('obstacles/fetch_sparkle_anim.png');
    _spark = SpriteAnimation.fromFrameData(
        img, SpriteAnimationData.sequenced(amount: 4, stepTime: 1 / 6, textureSize: Vector2.all(16)));
    _sparkT = _spark!.createTicker();
    return super.onLoad();
  }

  @override
  bool get canFocus => !opened;
  @override
  PromptInfo get prompt => const PromptInfo('OPEN');

  @override
  void interact() {
    if (opened) return;
    Bonds.markSecret(id);
    Bonds.addGlimmer(amount);
    SfxManager().playChime();
    GameToast.show('+$amount glimmer', color: const Color(0xFFFFE08A), compact: true);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _sparkT?.update(dt);
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..color = Color.fromRGBO(255, 255, 255, opened ? 0.55 : 1);
    _chest?.render(canvas, size: size, overridePaint: paint);
    if (!opened) _sparkT?.getSprite().render(canvas, position: Vector2(17, -2), size: Vector2.all(16), overridePaint: paint);
    super.render(canvas);
  }
}

/// SCENT: something buried. Invisible until the vine fox is along and close;
/// then a shimmer marks the spot and DIG finds glimmer.
class BuriedItem extends GameComponent with Interactable, PointOfInterest {
  final String id;
  final int amount;
  SpriteAnimationTicker? _shimmer;
  double _show = 0;

  BuriedItem(Vector2 position, {required this.id, required this.amount}) {
    this.position = position;
    size = Vector2.all(24);
  }

  bool get found => Bonds.secretDone(id);

  @override
  Future<void> onLoad() async {
    final img = await Flame.images.load('obstacles/shimmer_anim.png');
    _shimmer = SpriteAnimation.fromFrameData(
            img, SpriteAnimationData.sequenced(amount: 4, stepTime: 1 / 6, textureSize: Vector2.all(64)))
        .createTicker();
    return super.onLoad();
  }

  bool get _sniffed => Bonds.has(Ability.scent) && _playerCenter(gameRef).distanceTo(absoluteCenter) < 110;

  @override
  Ability get poiAbility => Ability.scent;
  @override
  bool get poiPending => !found;
  @override
  bool get canFocus => !found && _show > 0.5;
  @override
  double get interactRadius => 40;
  @override
  PromptInfo get prompt => const PromptInfo('DIG', hold: 0.6);

  @override
  void interact() {
    if (found) return;
    Bonds.markSecret(id);
    Bonds.addGlimmer(amount);
    SfxManager().playChime();
    GameToast.show('+$amount glimmer', color: const Color(0xFFFFE08A), compact: true);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _shimmer?.update(dt);
    final want = !found && _sniffed ? 1.0 : 0.0;
    _show += (want - _show).clamp(-dt * 2, dt * 2);
  }

  @override
  void render(Canvas canvas) {
    if (_show <= 0.02) return;
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..color = Color.fromRGBO(255, 255, 255, _show);
    canvas.drawOval(const Rect.fromLTWH(3, 12, 18, 9), Paint()..color = const Color(0xFF4A3A28).withValues(alpha: 0.7 * _show));
    _shimmer?.getSprite().render(canvas, position: Vector2(-12, -18), size: Vector2.all(48), overridePaint: paint);
    super.render(canvas);
  }
}

/// SCENT: Designer's 2x2 bramble (bramble_closed / bramble_open, 64x64,
/// swapped in place) plugging the trail into the hushdeer's glade. With the
/// vine fox along, hold E to have it nose a way through; the open bramble
/// keeps only its side clumps solid, leaving a north-south passage
/// ([passage], x 16-48 px) that Kaela's feet hitbox fits through.
class HiddenPath extends GameComponent with Interactable, PointOfInterest {
  final String id;

  /// Solid rects (x, y, w, h in the 64x64 art) from bramble_closed.json /
  /// bramble_open.json.
  static const closedColliders = [Rect.fromLTWH(5, 39, 52, 22)];
  static const openColliders = [Rect.fromLTWH(1, 39, 15, 22), Rect.fromLTWH(48, 39, 15, 22)];

  /// The walkable middle of the open bramble ('passage' x 16, w 32).
  static const passage = (x: 16.0, w: 32.0);

  Sprite? _closed;
  Sprite? _openSprite;
  SpriteAnimationTicker? _motes;
  SpriteAnimationTicker? _shimmer;
  final _hits = <RectangleHitbox>[];
  double _open;

  HiddenPath(Vector2 position, Vector2 size, {required this.id}) : _open = Bonds.secretDone(id) ? 1 : 0 {
    this.position = position;
    this.size = size;
  }

  bool get revealed => Bonds.secretDone(id);

  @override
  Future<void> onLoad() async {
    _closed = await Sprite.load('obstacles/bramble_closed.png');
    _openSprite = await Sprite.load('obstacles/bramble_open.png');
    final motes = await Flame.images.load('obstacles/bramble_open_motes_anim.png');
    _motes = SpriteAnimation.fromFrameData(
            motes, SpriteAnimationData.sequenced(amount: 4, stepTime: 1 / 6, textureSize: Vector2.all(64)))
        .createTicker();
    final shimmer = await Flame.images.load('obstacles/shimmer_anim.png');
    _shimmer = SpriteAnimation.fromFrameData(
            shimmer, SpriteAnimationData.sequenced(amount: 4, stepTime: 1 / 6, textureSize: Vector2.all(64)))
        .createTicker();
    _setColliders(revealed ? openColliders : closedColliders);
    return super.onLoad();
  }

  void _setColliders(List<Rect> rects) {
    for (final h in _hits) {
      h.removeFromParent();
    }
    _hits.clear();
    final k = size.x / 64; // art is 64 px; the object is 2x2 tiles
    for (final r in rects) {
      final h = RectangleHitbox(
          position: Vector2(r.left * k, r.top * k), size: Vector2(r.width * k, r.height * k), isSolid: true);
      _hits.add(h);
      add(h);
    }
  }

  @override
  Ability get poiAbility => Ability.scent;
  @override
  bool get poiPending => !revealed;

  // Reachable from either side: the middle of the thorny band.
  @override
  Vector2 get interactPoint => absolutePosition + Vector2(size.x / 2, size.y * 50 / 64);
  @override
  double get interactRadius => 40;
  @override
  bool get canFocus => !revealed;

  @override
  PromptInfo get prompt => Bonds.has(Ability.scent)
      ? const PromptInfo('SNIFF A WAY THROUGH', hold: 0.6)
      : const PromptInfo.note('Thick brambles. Something sweet-smelling lies beyond.');

  @override
  void interact() {
    if (revealed || !Bonds.has(Ability.scent)) return;
    Bonds.markSecret(id);
    _setColliders(openColliders);
    SfxManager().playChime();
    GameToast.show('SCENT', body: 'Path found', compact: true);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _shimmer?.update(dt);
    _motes?.update(dt);
    if (revealed) _open = min(1, _open + dt * 1.5);
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    if (_open < 1) {
      paint.color = Color.fromRGBO(255, 255, 255, 1 - _open);
      _closed?.render(canvas, size: size, overridePaint: paint);
    }
    if (_open > 0) {
      paint.color = Color.fromRGBO(255, 255, 255, _open.toDouble());
      _openSprite?.render(canvas, size: size, overridePaint: paint);
      _motes?.getSprite().render(canvas, size: size, overridePaint: paint);
    } else if (Bonds.has(Ability.scent)) {
      // the vine fox can smell the old path under the thorns
      paint.color = const Color(0xCCFFFFFF);
      _shimmer?.getSprite().render(canvas, size: size, overridePaint: paint);
    }
    super.render(canvas);
  }
}

/// The vine fox's sweetroot under Designer's 2x2 stump (sweetroot_stump.png,
/// then sweetroot_stump_plain.png once picked). Only the trunk base collides;
/// pick it standing just below the trunk.
class SweetrootStump extends GameComponent with Interactable {
  /// From sweetroot_stump.json (64x64 art px).
  static const collider = Rect.fromLTWH(16, 30, 32, 25);
  static final pickAt = Vector2(31, 59);
  static final tuber = Vector2(31, 45);

  Sprite? _full;
  Sprite? _plain;
  double _t = 0;

  SweetrootStump(Vector2 position, [Vector2? size]) {
    this.position = position;
    this.size = size ?? Vector2.all(64);
  }

  double get _k => size.x / 64;

  bool get _taken => Bonds.hasItem('sweetroot') || Bonds.usedItem('sweetroot');

  @override
  Future<void> onLoad() async {
    _full = await Sprite.load('obstacles/sweetroot_stump.png');
    _plain = await Sprite.load('obstacles/sweetroot_stump_plain.png');
    add(RectangleHitbox(
        position: Vector2(collider.left, collider.top) * _k,
        size: Vector2(collider.width, collider.height) * _k,
        isSolid: true));
    return super.onLoad();
  }

  @override
  Vector2 get interactPoint => absolutePosition + pickAt * _k;
  @override
  double get interactRadius => 26;

  @override
  PromptInfo get prompt => _taken ? const PromptInfo.note('An old, hollow stump.') : const PromptInfo('PICK SWEETROOT');

  @override
  void interact() {
    if (_taken) return;
    Bonds.giveItem('sweetroot');
    SfxManager().playChime();
    GameToast.show('SWEETROOT', color: const Color(0xFFFFC07A), compact: true);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    (_taken ? _plain : _full)?.render(canvas, size: size, overridePaint: paint);
    if (!_taken && (_t % 3) < 0.5) {
      final k = sin((_t % 3) / 0.5 * pi);
      final c = tuber * _k;
      canvas.drawCircle(Offset(c.x, c.y - 4), 1.5 + k, Paint()..color = Colors.white.withValues(alpha: 0.8 * k));
    }
    super.render(canvas);
  }
}

/// The brookling's river pebble: walk over it to pick it up.
class RiverPebble extends GameComponent {
  final String id;
  SpriteAnimationTicker? _anim;
  bool _gone;

  RiverPebble(Vector2 position, {required this.id}) : _gone = Bonds.secretDone(id) {
    this.position = position;
    size = Vector2.all(16);
  }

  @override
  Future<void> onLoad() async {
    // frame 0 = the pebble, frame 1 = a quick glint (1.2 s / 0.18 s)
    final img = await Flame.images.load('creatures/river_pebble_sparkle.png');
    final n = max(1, img.width ~/ 16);
    _anim = SpriteAnimation.fromFrameData(
            img,
            SpriteAnimationData.variable(
                amount: n, stepTimes: [for (var i = 0; i < n; i++) i == 0 ? 1.2 : 0.18], textureSize: Vector2.all(16)))
        .createTicker();
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _anim?.update(dt);
    if (_gone) return;
    if (_playerCenter(gameRef).distanceTo(absoluteCenter) < 20) {
      _gone = true;
      Bonds.markSecret(id);
      Bonds.giveItem('pebble');
      SfxManager().playChime();
      GameToast.show('RIVER PEBBLE', color: const Color(0xFF9FD0FF), compact: true);
    }
  }

  @override
  void render(Canvas canvas) {
    if (_gone) return;
    _anim?.getSprite().render(canvas, size: size, overridePaint: Paint()..filterQuality = FilterQuality.none);
    super.render(canvas);
  }
}

/// Moonflowers: a hint trail to the hushdeer's glade. By day the plain
/// flower; as night falls its glow (moonflower_glow.png, 2 frames ping-pong
/// at 0.9 s) fades in on top.
class Moonflower extends GameComponent {
  Sprite? _plain;
  SpriteAnimationTicker? _glow;

  /// [position]: top-left of the 16x16 Tiled object; the 16x24 sprite
  /// stands on its bottom edge.
  Moonflower(Vector2 position) {
    this.position = position - Vector2(0, 8);
    size = Vector2(16, 24);
  }

  @override
  Future<void> onLoad() async {
    _plain = await Sprite.load('creatures/moonflower.png');
    final img = await Flame.images.load('creatures/moonflower_glow.png');
    _glow = SpriteAnimation.fromFrameData(img,
            SpriteAnimationData.sequenced(amount: max(1, img.width ~/ 16), stepTime: 0.9, textureSize: Vector2(16, 24)))
        .createTicker();
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _glow?.update(dt);
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    _plain?.render(canvas, size: size, overridePaint: paint);
    final n = DayCycle.darkness(DayCycle.time.value);
    if (n > 0) {
      paint.color = Color.fromRGBO(255, 255, 255, n);
      _glow?.getSprite().render(canvas, size: size, overridePaint: paint);
    }
    super.render(canvas);
  }
}
