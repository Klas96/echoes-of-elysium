import 'dart:math';
import 'dart:ui' as ui;

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../creatures/day_cycle.dart';
import '../ui/hud_layout.dart';

/// Kinds of night light a Tiled `light` object can be (#35). The map
/// generator stamps one under every street lamp, lantern, campfire, brazier
/// and neon streetlight.
enum LightKind { lamp, lantern, fire, energy, neon }

extension LightKindStyle on LightKind {
  static LightKind parse(String raw) => LightKind.values
      .firstWhere((k) => k.name == raw.toLowerCase(), orElse: () => LightKind.lamp);

  /// Glow colour; matches the glass/flame of each prop.
  Color get color => switch (this) {
        LightKind.lamp => const Color(0xFFFF9E40),
        LightKind.lantern => const Color(0xFFB8F0C8),
        LightKind.fire => const Color(0xFFFF8A3C),
        LightKind.energy => const Color(0xFF6AE8FF),
        LightKind.neon => const Color(0xFFFF6AD8),
      };

  /// How much the light flickers (alpha), 0 = steady.
  double get flicker => switch (this) {
        LightKind.fire => 0.16,
        LightKind.lantern => 0.06,
        LightKind.neon => 0.05,
        _ => 0.03,
      };
}

/// One light source in world pixels. Registers with [NightLights] for the
/// night wash, and paints its own glow cookie at map-floor priority so
/// lantern / lamp / fire sprites (dynamicAbove) draw **over** the glow.
class LampLight extends GameComponent {
  final LightKind kind;
  final double radius;

  /// Cookie art set: `warm` (amber) or `neon` (cyan). Empty = by kind.
  final String style;

  /// Per-lamp flicker phase so a street of lamps doesn't pulse in sync.
  final double phase;

  final _glow = Paint()
    ..blendMode = BlendMode.plus
    ..filterQuality = FilterQuality.none;

  LampLight(Vector2 position, Vector2 size,
      {required this.kind, required this.radius, this.style = ''})
      : phase = ((position.x * 12.9898 + position.y * 78.233).abs() % 6.283) {
    this.position = position;
    this.size = size;
  }

  /// Fixture centre in world px (Tiled light object) — pool is drawn here so
  /// the light reads as coming from the lantern/lamp, not south of it.
  Vector2 get centre => position + size / 2;

  /// World rect of the prop sprite (matches `make_tiled_maps.LIGHTS` anchors).
  /// Glow cookies skip this so the pool sits on the ground, not as a disc
  /// behind the lantern / fire art.
  Rect get fixtureWorldRect {
    final c = centre;
    // Travel portals stamp a large-radius light on a 48×48 pad.
    if (radius >= 120) {
      return Rect.fromCenter(center: Offset(c.x, c.y), width: 48, height: 48);
    }
    const tile = 32.0;
    final fy = switch (kind) {
      LightKind.fire => 0.5,
      LightKind.lantern => 0.7,
      LightKind.energy => 0.5,
      LightKind.lamp || LightKind.neon => 0.75,
    };
    // Campfire flame FX sits a little above the bowl tile.
    final h = kind == LightKind.fire ? 40.0 : tile;
    final top = kind == LightKind.fire ? c.y - tile * fy - 8 : c.y - h * fy;
    return Rect.fromLTWH(c.x - tile / 2, top, tile, h);
  }

  /// Under Y-sorted props / Kaela (MAP+2, same idea as indoor room glows):
  /// sprites sit above their glow pass. [NightTint] is wash-only.
  @override
  int get priority => LayerPriority.MAP + 2;

  @override
  void onMount() {
    super.onMount();
    NightLights.register(this, gameRef);
  }

  @override
  void onRemove() {
    NightLights.unregister(this);
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    if (!NightLights.draws(this)) return;
    final darkness = DayCycle.darkness(DayCycle.time.value);
    if (darkness <= 0.01) return;
    final styleKey = NightLights.styleFor(kind, style);
    final art = NightLights.cookies[styleKey];
    final cookie = art ?? NightLights.procedural;
    if (cookie == null) return;
    final s = NightLights.strength(darkness, kind, phase, NightLights.clock);
    if (s <= 0.01) return;
    final a = NightLights.glowStrength * s;
    if (art == null || !NightLights.artMatches(kind, styleKey)) {
      final aq = (a * 40).round().clamp(0, 40);
      final filter = NightLights.filterFor(kind, aq);
      _glow
        ..color = const Color(0xFFFFFFFF)
        ..colorFilter = filter;
    } else {
      _glow
        ..colorFilter = null
        ..color = Color.fromRGBO(255, 255, 255, a);
    }
    final squash = cookie.art ? 1.0 : NightLights.squash;
    final dest = Rect.fromCenter(
      center: Offset(size.x / 2, size.y / 2),
      width: radius * 2,
      height: radius * 2 * squash,
    );
    // Keep the cookie off the prop body — otherwise it reads as a yellow
    // eclipse behind the lantern / fire sprite.
    final f = fixtureWorldRect;
    final localFixture =
        Rect.fromLTWH(f.left - position.x, f.top - position.y, f.width, f.height);
    canvas.save();
    canvas.clipRect(localFixture, clipOp: ClipOp.difference);
    canvas.drawImageRect(
      cookie.image,
      cookie.src(NightLights.clock, phase),
      dest,
      _glow,
    );
    canvas.restore();
  }
}

/// A light ready to draw, in screen pixels.
@immutable
class ScreenLight {
  final Rect rect;
  final Color color;

  /// 0..1: how strongly it lights (already scaled by darkness and flicker).
  final double strength;
  final LightKind kind;
  final double phase;

  /// Cookie to draw, and whether to recolour it with [color] (procedural
  /// cookie, or art whose colour doesn't match the light).
  final LightCookie cookie;
  final bool tinted;
  const ScreenLight(this.rect, this.color, this.strength, this.kind, this.phase,
      {required this.cookie, required this.tinted});
}

/// Registry + camera snapshot the [NightTint] wash painter reads every frame.
/// Lamp cookies are painted by each [LampLight] under prop sprites.
class NightLights {
  static final _lights = <LampLight>[];
  static _CameraProbe? _probe;

  /// Nearest on-screen lamps allowed to paint this frame (EOE-84 cap).
  static final _drawSet = <LampLight>{};

  /// Camera centre (world px) and zoom from the last game update; null when no
  /// map is running, in which case NightTint is a flat wash.
  static Vector2? camera;
  static double zoom = 1;

  /// Seconds of unpaused play, drives the flicker.
  static double clock = 0;

  /// Ticks whenever the camera/clock snapshot changes (wash overlay only).
  static final frame = _Tick();

  /// Pools are slightly wider than tall: light on the ground.
  static const squash = 0.78;

  /// Additive lamp glow strength. Cookies paint in-world under the night wash
  /// (and under lantern/fire sprites). A bit stronger than the old overlay
  /// 0.18 so pools still read through the blue wash without day-holes.
  static const glowStrength = 0.32;

  /// Kept for docs / older notes; hole-punch path removed.
  static const cutStrength = 0.48;

  /// Max lamp cookies drawn per frame. City has 44 lights; a phone viewport
  /// usually sees ≤7, but dense clusters + large radii still stack
  /// BlendMode.plus cost. Prefer nearest-to-camera when over the cap.
  static int get maxDrawnLights => HudLayout.isTouch ? 6 : 12;

  /// Overlay notify rate while lit. Touch GPUs pay for a full-screen
  /// CustomPaint composite; ~15 Hz is enough for walk + soft wash.
  static double get notifyHz => HudLayout.isTouch ? 15 : 30;

  /// Flicker art / sine refresh while standing still (draw-set refresh).
  static double get flickerHz => HudLayout.isTouch ? 8 : 12;

  static List<LampLight> get lights => List.unmodifiable(_lights);

  /// Cached ColorFilter per (kind, quantized alpha) for tinted cookies.
  static final _filterCache = <int, ColorFilter>{};

  static ColorFilter filterFor(LightKind kind, int aq) {
    final key = Object.hash(kind.index, aq);
    return _filterCache[key] ??= ColorFilter.mode(
      kind.color.withValues(alpha: aq / 40),
      BlendMode.srcIn,
    );
  }

  /// Whether [l] is in this frame's nearest-light draw set.
  static bool draws(LampLight l) => _drawSet.contains(l);

  static void register(LampLight l, BonfireGameInterface game) {
    _lights.add(l);
    final p = _probe;
    if (p == null || !p.isMounted || p.gameRef != game) {
      final probe = _CameraProbe();
      _probe = probe;
      game.add(probe);
    }
  }

  static void unregister(LampLight l) {
    _lights.remove(l);
    _drawSet.remove(l);
    if (_lights.isEmpty) {
      _probe?.removeFromParent();
      _probe = null;
      camera = null;
      _drawSet.clear();
      _notify();
    }
  }

  static void _notify() => frame.tick();

  /// Nudge the night overlay when wash darkness steps (DayClock / dusk).
  /// Lets lamp-less maps ramp tint without NightTint listening to every
  /// DayCycle.time HUD tick.
  static void nudgeWash() => _notify();

  /// Night intensity of one light at [clock] seconds (0 in daylight).
  static double strength(double darkness, LightKind kind, double phase, double clock) {
    if (darkness <= 0) return 0;
    final f = kind.flicker;
    final wobble = f == 0
        ? 0.0
        : f * (0.6 * sin(clock * 7.3 + phase) + 0.4 * sin(clock * 17.9 + phase * 2.1));
    return (darkness * (1 - f + wobble)).clamp(0.0, 1.0);
  }

  /// World pool → screen rect for a camera centred at [cam] with [zoom] on a
  /// [screen]-sized view.
  static Rect screenRect(Vector2 centre, double radius, Vector2 cam, double zoom, Size screen,
      {double squash = NightLights.squash}) {
    final cx = (centre.x - cam.x) * zoom + screen.width / 2;
    final cy = (centre.y - cam.y) * zoom + screen.height / 2;
    final r = radius * zoom;
    return Rect.fromCenter(center: Offset(cx, cy), width: r * 2, height: r * 2 * squash);
  }

  /// Which art set a light uses: City street lamps and Core braziers are cyan
  /// neon, everything else (Town lamps, woods lanterns, fires) warm amber.
  static String styleFor(LightKind kind, String style) {
    if (style.isNotEmpty) return style;
    return kind == LightKind.energy ? 'neon' : 'warm';
  }

  /// Art colour already matches these; the rest get the art's rings tinted.
  static bool artMatches(LightKind kind, String style) =>
      kind != LightKind.neon || style == 'neon';

  /// Scratch buffer reused by [visible] to avoid a List alloc every paint.
  static final _visibleScratch = <ScreenLight>[];

  /// Scratch for distance-sort when capping drawn lamps.
  static final _rankScratch = <(double, ScreenLight)>[];
  static final _lampRankScratch = <(double, LampLight)>[];

  /// Approx half-diagonal (world px) of the view for in-world draw culling.
  /// Touch uses a tighter window (EOE-84).
  static double get _viewRadius => HudLayout.isTouch ? 320.0 : 520.0;

  /// Refresh [_drawSet]: nearest lit lamps inside the camera radius, capped.
  static void refreshDrawSet(double darkness) {
    _drawSet.clear();
    final cam = camera;
    if (cam == null || darkness <= 0.01 || _lights.isEmpty) return;
    final cap = maxDrawnLights;
    final ranked = _lampRankScratch..clear();
    for (final l in _lights) {
      final dx = l.centre.x - cam.x;
      final dy = l.centre.y - cam.y;
      final d2 = dx * dx + dy * dy;
      // Include radius so large pools near the edge still light.
      final reach = l.radius + _viewRadius;
      if (d2 > reach * reach) continue;
      final s = strength(darkness, l.kind, l.phase, clock);
      if (s <= 0.01) continue;
      ranked.add((d2, l));
    }
    if (ranked.length > cap) {
      ranked.sort((a, b) => a.$1.compareTo(b.$1));
      ranked.removeRange(cap, ranked.length);
    }
    for (final e in ranked) {
      _drawSet.add(e.$2);
    }
  }

  /// Lights as screen cookies (tests / tooling). Wash overlay no longer paints
  /// these — [LampLight.render] does, under prop sprites.
  /// The returned list is owned by NightLights — copy if retaining.
  static List<ScreenLight> visible(Size screen, double darkness) {
    final cam = camera;
    final out = _visibleScratch..clear();
    if (cam == null || darkness <= 0.01 || _lights.isEmpty) return out;
    final view = Offset.zero & screen;
    final cap = maxDrawnLights;
    final ranked = _rankScratch..clear();
    for (final l in _lights) {
      final style = styleFor(l.kind, l.style);
      final art = cookies[style];
      final cookie = art ?? procedural;
      if (cookie == null) continue;
      // Designer cookies are already an oval inside a square canvas.
      final rect = screenRect(l.centre, l.radius, cam, zoom, screen,
          squash: cookie.art ? 1 : squash);
      if (!rect.overlaps(view)) continue;
      final s = strength(darkness, l.kind, l.phase, clock);
      if (s <= 0.01) continue;
      final dx = l.centre.x - cam.x;
      final dy = l.centre.y - cam.y;
      ranked.add((
        dx * dx + dy * dy,
        ScreenLight(rect, l.kind.color, s, l.kind, l.phase,
            cookie: cookie, tinted: art == null || !artMatches(l.kind, style)),
      ));
    }
    if (ranked.length > cap) {
      ranked.sort((a, b) => a.$1.compareTo(b.$1));
      ranked.removeRange(cap, ranked.length);
    }
    for (final e in ranked) {
      out.add(e.$2);
    }
    return out;
  }

  // ---------------------------------------------------------------- cookie
  /// Designer art (#35): warm amber and cyan neon pools, each optionally as
  /// a two-frame flicker sheet (twice as wide as tall). Missing files fall
  /// back to the procedural cookie, so art can be dropped in with no code
  /// change.
  static const artAssets = {
    'warm': ['assets/images/sprites/fx/lamp_light_flicker.png', 'assets/images/sprites/fx/lamp_light.png'],
    'neon': [
      'assets/images/sprites/fx/lamp_light_neon_flicker.png',
      'assets/images/sprites/fx/lamp_light_neon.png'
    ],
  };
  static final cookies = <String, LightCookie>{};
  static LightCookie? procedural;
  static Future<void>? _loading;

  static const cookieSize = 48;

  /// Procedural cookie alpha at pixel (x, y): a soft disc quantised into a
  /// few hard bands so it reads as pixel art when scaled with nearest filter.
  static double cookieAlpha(int x, int y, [int size = cookieSize]) {
    final c = (size - 1) / 2;
    final d = sqrt(pow(x - c, 2) + pow(y - c, 2)) / (size / 2);
    if (d >= 1) return 0;
    final soft = pow(1 - d, 1.5).toDouble();
    const bands = 8;
    return (soft * bands).floor() / bands;
  }

  static Future<void> ensureCookie() => _loading ??= _loadCookies();

  static Future<void> _loadCookies() async {
    Set<String> have = const {};
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      have = manifest.listAssets().toSet();
    } catch (_) {}
    for (final e in artAssets.entries) {
      for (final path in e.value) {
        if (!have.contains(path)) continue;
        try {
          final data = await rootBundle.load(path);
          final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
          final img = (await codec.getNextFrame()).image;
          cookies[e.key] = LightCookie(img, img.width >= img.height * 2 ? 2 : 1, art: true);
          break;
        } catch (_) {
          // try the next file / fall back to procedural
        }
      }
    }
    const n = cookieSize;
    final px = Uint8List(n * n * 4);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final i = (y * n + x) * 4;
        // Only alpha matters (dstOut / srcIn); keep RGB <= A so the pixels
        // are valid whether the backend reads them premultiplied or not.
        final a = (cookieAlpha(x, y) * 255).round();
        px[i] = px[i + 1] = px[i + 2] = px[i + 3] = a;
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(px);
    final desc = ui.ImageDescriptor.raw(buffer,
        width: n, height: n, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    procedural = LightCookie((await codec.getNextFrame()).image, 1, art: false);
    _notify();
  }
}

/// A cached light cookie image (one or two flicker frames side by side).
class LightCookie {
  final ui.Image image;
  final int frames;
  final bool art;
  const LightCookie(this.image, this.frames, {required this.art});

  /// Source rect of the frame to show at [clock] for a light with [phase].
  Rect src(double clock, double phase) {
    final fw = image.width / frames;
    final f = frames == 1 ? 0 : ((clock * 6 + phase).floor() % frames);
    return Rect.fromLTWH(fw * f, 0, fw, image.height.toDouble());
  }
}

class _Tick extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Copies the camera into [NightLights] — notifies the Flutter overlay only
/// when the wash actually needs a new frame (not every Bonfire tick).
///
/// Walk lag was dominated by [NightTintPainter]'s saveLayer + cookie draws
/// being scheduled 60×/s via [NightLights.frame], even in daylight.
class _CameraProbe extends GameComponent {
  final Vector2 _camScratch = Vector2.zero();
  double _lastCamX = double.nan;
  double _lastCamY = double.nan;
  double _lastZoom = double.nan;
  double _lastDarkness = -1;
  double _flickerAcc = 0;
  bool _wasLit = false;

  @override
  Future<void> onLoad() async {
    await NightLights.ensureCookie();
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    NightLights.clock += dt;
    final view = gameRef.camera.viewfinder.position;
    _camScratch.setValues(view.x, view.y);
    final zoom = gameRef.camera.viewfinder.zoom;
    final darkness = DayCycle.darkness(DayCycle.time.value);
    final lit = darkness > 0.01 && NightLights._lights.isNotEmpty;

    // Day / no lamps: idle CustomPaint, but still nudge on dusk/dawn so
    // lamp-less maps (flat wash only) ramp without listening to DayCycle.time.
    if (!lit) {
      NightLights.camera ??= _camScratch.clone();
      NightLights.camera!.setFrom(_camScratch);
      NightLights.zoom = zoom;
      NightLights._drawSet.clear();
      final duskShift = (darkness - _lastDarkness).abs() >= 0.01;
      if (_wasLit || _lastDarkness < 0 || duskShift) NightLights._notify();
      _wasLit = false;
      _lastDarkness = darkness;
      _lastCamX = _camScratch.x;
      _lastCamY = _camScratch.y;
      _lastZoom = zoom;
      return;
    }

    // Always keep the latest camera; refresh which lamps may paint cookies.
    // Flat wash is camera-independent — only notify on dusk / lit edges.
    NightLights.camera ??= _camScratch.clone();
    NightLights.camera!.setFrom(_camScratch);
    NightLights.zoom = zoom;

    _flickerAcc += dt;
    // Slightly coarser move threshold on touch: sub-pixel camera creep
    // does not need a draw-set rebuild every tick.
    final moveEps = HudLayout.isTouch ? 2.0 : 1.0;
    final moved = _lastCamX.isNaN ||
        (_camScratch.x - _lastCamX).abs() >= moveEps ||
        (_camScratch.y - _lastCamY).abs() >= moveEps ||
        (zoom - _lastZoom).abs() > 0.001;
    final flickerTick = _flickerAcc >= 1 / NightLights.flickerHz;
    final duskShift = (darkness - _lastDarkness).abs() >= 0.01;

    // Draw-set tracks the camera so in-world cookies follow walk;
    // flickerHz is enough when standing still (cookie frame / strength wobble).
    if (moved || flickerTick || duskShift || !_wasLit) {
      NightLights.refreshDrawSet(darkness);
      if (flickerTick) _flickerAcc = 0;
      _lastCamX = _camScratch.x;
      _lastCamY = _camScratch.y;
      _lastZoom = zoom;
    }

    if (duskShift || !_wasLit) {
      _lastDarkness = darkness;
      _wasLit = true;
      NightLights._notify();
      return;
    }
    _lastDarkness = darkness;
    _wasLit = true;
  }

  @override
  void onRemove() {
    if (NightLights._probe == this) {
      NightLights._probe = null;
      NightLights.camera = null;
    }
    super.onRemove();
  }
}

/// Day/night wash only (#35). Lamp cookies paint in-world on [LampLight] at
/// MAP+2 (clipped off the prop body) so lantern / fire / lamp sprites sit
/// above their glow with no yellow disc behind them.
///
/// Repaints on [NightLights.frame] only (dusk / DayClock wash steps). Flat
/// wash is camera-independent, so walk no longer schedules overlay paints
/// (EOE-84).
class NightTintPainter extends CustomPainter {
  NightTintPainter() : super(repaint: NightLights.frame);

  final _tintPaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final t = DayCycle.time.value;
    // Ruins (world3) and other maps with no lamp objects get a flat wash with
    // no warm pools — keep night readable instead of near-black.
    final strength = NightLights.lights.isEmpty ? 0.48 : 1.0;
    final tint = DayCycle.tint(t, strength: strength);
    if (tint.a <= 0) return;
    _tintPaint.color = tint;
    canvas.drawRect(Offset.zero & size, _tintPaint);
  }

  @override
  bool shouldRepaint(covariant NightTintPainter oldDelegate) => false;
}
