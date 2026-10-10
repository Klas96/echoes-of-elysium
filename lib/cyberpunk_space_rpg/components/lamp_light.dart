import 'dart:math';
import 'dart:ui' as ui;

import 'package:bonfire/bonfire.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../creatures/day_cycle.dart';

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

/// One light source in world pixels. Invisible on its own; [NightTint]
/// draws all registered lights through [NightLights].
class LampLight extends GameComponent {
  final LightKind kind;
  final double radius;

  /// Cookie art set: `warm` (amber) or `neon` (cyan). Empty = by kind.
  final String style;

  /// Per-lamp flicker phase so a street of lamps doesn't pulse in sync.
  final double phase;

  LampLight(Vector2 position, Vector2 size,
      {required this.kind, required this.radius, this.style = ''})
      : phase = ((position.x * 12.9898 + position.y * 78.233).abs() % 6.283) {
    this.position = position;
    this.size = size;
  }

  /// Pool centre in world px.
  Vector2 get centre => position + size / 2;

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

/// Registry + camera snapshot the [NightTint] painter reads every frame.
class NightLights {
  static final _lights = <LampLight>[];
  static _CameraProbe? _probe;

  /// Camera centre (world px) and zoom from the last game update; null when no
  /// map is running, in which case NightTint is a flat wash.
  static Vector2? camera;
  static double zoom = 1;

  /// Seconds of unpaused play, drives the flicker.
  static double clock = 0;

  /// Ticks whenever the camera/clock snapshot changes.
  static final frame = _Tick();

  /// Pools are slightly wider than tall: light on the ground.
  static const squash = 0.78;

  /// Max tint removed at the centre of a pool, and max additive glow.
  static const cutStrength = 0.65;
  static const glowStrength = 0.6;

  static List<LampLight> get lights => List.unmodifiable(_lights);

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
    if (_lights.isEmpty) {
      _probe?.removeFromParent();
      _probe = null;
      camera = null;
      _notify();
    }
  }

  static void _notify() => frame.tick();

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

  /// Lights to draw this frame (on screen and lit), empty by day.
  static List<ScreenLight> visible(Size screen, double darkness) {
    final cam = camera;
    if (cam == null || darkness <= 0.01 || _lights.isEmpty) return const [];
    final view = Offset.zero & screen;
    final out = <ScreenLight>[];
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
      out.add(ScreenLight(rect, l.kind.color, s, l.kind, l.phase,
          cookie: cookie, tinted: art == null || !artMatches(l.kind, style)));
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

/// Copies the camera into [NightLights] once per game update.
class _CameraProbe extends GameComponent {
  @override
  Future<void> onLoad() async {
    await NightLights.ensureCookie();
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    NightLights.clock += dt;
    NightLights.camera = gameRef.camera.viewfinder.position.clone();
    NightLights.zoom = gameRef.camera.viewfinder.zoom;
    NightLights._notify();
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

/// Day/night wash with warm pools cut into it around every lamp (#35). One
/// cached cookie image drawn per visible light; no blur.
class NightTintPainter extends CustomPainter {
  NightTintPainter() : super(repaint: Listenable.merge([DayCycle.time, NightLights.frame]));

  @override
  void paint(Canvas canvas, Size size) {
    final t = DayCycle.time.value;
    final tint = DayCycle.tint(t);
    final full = Offset.zero & size;
    final lights = NightLights.visible(size, DayCycle.darkness(t));
    if (lights.isEmpty) {
      if (tint.a > 0) canvas.drawRect(full, Paint()..color = tint);
      return;
    }
    final clock = NightLights.clock;
    // 1) the tint with soft holes punched under each lamp
    canvas.saveLayer(full, Paint());
    canvas.drawRect(full, Paint()..color = tint);
    final cut = Paint()
      ..blendMode = BlendMode.dstOut
      ..filterQuality = FilterQuality.none;
    for (final l in lights) {
      cut.color = Color.fromRGBO(0, 0, 0, NightLights.cutStrength * l.strength);
      canvas.drawImageRect(l.cookie.image, l.cookie.src(clock, l.phase), l.rect, cut);
    }
    canvas.restore();
    // 2) coloured additive glow on top
    final glow = Paint()
      ..blendMode = BlendMode.plus
      ..filterQuality = FilterQuality.none;
    for (final l in lights) {
      final a = NightLights.glowStrength * l.strength;
      if (l.tinted) {
        glow
          ..color = const Color(0xFFFFFFFF)
          ..colorFilter = ColorFilter.mode(l.color.withValues(alpha: a), BlendMode.srcIn);
      } else {
        glow
          ..colorFilter = null
          ..color = Color.fromRGBO(255, 255, 255, a);
      }
      canvas.drawImageRect(l.cookie.image, l.cookie.src(clock, l.phase), l.rect, glow);
    }
  }

  @override
  bool shouldRepaint(covariant NightTintPainter oldDelegate) => false;
}
