import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../audio/music_manager.dart';
import 'cutscene_data.dart';

export 'cutscene_data.dart';

/// Loads a cutscene JSON asset; image paths are resolved against its folder.
Future<Cutscene> loadCutscene(String assetPath, {AssetBundle? bundle}) async {
  final raw = await (bundle ?? rootBundle).loadString(assetPath);
  final slash = assetPath.lastIndexOf('/');
  return Cutscene.parse(raw, basePath: slash < 0 ? '' : assetPath.substring(0, slash));
}

enum CutscenePhase { lines, hold, title, outro, done }

/// Pure playback state machine for a [Cutscene], advanced by [tick] (seconds)
/// and user input ([advance], [skip]). The widget only renders what it says,
/// which keeps timing testable without a renderer.
///
/// Per panel: each line waits its `delay`, types out at [charsPerSecond],
/// then stays for its hold before the next line. After the last line the
/// panel holds until its duration is reached, then crossfades to the next
/// panel (or shows the panel's title card). The last panel fades to black.
class CutscenePlayback extends ChangeNotifier {
  CutscenePlayback(this.scene, {this.onDone});

  final Cutscene scene;
  VoidCallback? onDone;

  static const charsPerSecond = 38.0;
  static const outroSeconds = 0.9;
  static const skipOutroSeconds = 0.45;

  CutscenePhase phase = CutscenePhase.lines;
  int panelIndex = 0;
  double panelTime = 0;

  /// Panel fading out underneath the current one (null when no crossfade).
  int? previousIndex;
  double previousTime = 0;
  double fadeTime = 0;

  int lineIndex = 0;
  double lineTime = 0;
  double titleTime = 0;
  double outroTime = 0;
  double _outroLength = outroSeconds;

  /// Preview/test aid: when true [tick] does nothing.
  bool frozen = false;

  CutscenePanel get panel => scene.panels[panelIndex];
  CutscenePanel? get previousPanel => previousIndex == null ? null : scene.panels[previousIndex!];
  bool get isDone => phase == CutscenePhase.done;

  static double revealSeconds(CutsceneLine l) => l.text.length / charsPerSecond;

  /// The panel's real running time: its duration, stretched if its lines need
  /// longer to read. The Ken Burns move spans this.
  static double runtime(CutscenePanel p) {
    var t = 0.0;
    for (final l in p.lines) {
      t += l.delay + revealSeconds(l) + l.holdSeconds;
    }
    return math.max(p.duration, t + 0.3);
  }

  /// Crossfade progress of the current panel over the previous one (0..1).
  double get crossfade =>
      previousIndex == null || scene.crossfade <= 0 ? 1 : (fadeTime / scene.crossfade).clamp(0.0, 1.0);

  PanKey panFor(int index, double t) {
    final p = scene.panels[index];
    return p.panAt(t / runtime(p) * p.duration);
  }

  /// The subtitle to show now (null = none).
  CutsceneLine? get currentLine {
    final lines = panel.lines;
    if (phase == CutscenePhase.lines && lineIndex < lines.length) {
      return lineTime >= lines[lineIndex].delay ? lines[lineIndex] : null;
    }
    if (phase == CutscenePhase.hold && lines.isNotEmpty) return lines.last;
    return null;
  }

  /// Characters of [currentLine] revealed so far.
  int get visibleChars {
    final l = currentLine;
    if (l == null) return 0;
    if (phase != CutscenePhase.lines) return l.text.length;
    return ((lineTime - l.delay) * charsPerSecond + 1e-6).floor().clamp(0, l.text.length);
  }

  /// Seconds since the current line appeared (for its fade-in).
  double get lineAge {
    final l = currentLine;
    if (l == null) return 0;
    if (phase != CutscenePhase.lines) return 99;
    return lineTime - l.delay;
  }

  bool get lineComplete {
    final l = currentLine;
    return l != null && visibleChars >= l.text.length;
  }

  /// 0..1 opacity of the title card.
  double get titleOpacity {
    final card = panel.titleCard;
    if (card == null) return 0;
    if (phase == CutscenePhase.title) return card.fadeIn <= 0 ? 1 : (titleTime / card.fadeIn).clamp(0.0, 1.0);
    if (phase == CutscenePhase.outro || phase == CutscenePhase.done) return titleTime > 0 ? 1 : 0;
    return 0;
  }

  /// 0..1 black fade at the very end (and at the start).
  double get blackout {
    if (phase == CutscenePhase.outro) return (outroTime / _outroLength).clamp(0.0, 1.0);
    if (phase == CutscenePhase.done) return 1;
    if (panelIndex == 0 && previousIndex == null) return (1 - panelTime / 0.8).clamp(0.0, 1.0);
    return 0;
  }

  void tick(double dt) {
    if (frozen || isDone || dt <= 0) return;
    panelTime += dt;
    if (previousIndex != null) {
      previousTime += dt;
      fadeTime += dt;
      if (fadeTime >= scene.crossfade) previousIndex = null;
    }
    switch (phase) {
      case CutscenePhase.lines:
        final lines = panel.lines;
        if (lineIndex >= lines.length) {
          phase = CutscenePhase.hold;
          break;
        }
        lineTime += dt;
        final l = lines[lineIndex];
        if (lineTime >= l.delay + revealSeconds(l) + l.holdSeconds) {
          if (lineIndex + 1 < lines.length) {
            lineIndex++;
            lineTime = 0;
          } else {
            phase = CutscenePhase.hold;
          }
        }
      case CutscenePhase.hold:
        if (panelTime >= panel.duration) _endPanel();
      case CutscenePhase.title:
        titleTime += dt;
        final card = panel.titleCard!;
        if (titleTime >= card.fadeIn + card.hold) _startOutro(outroSeconds);
      case CutscenePhase.outro:
        outroTime += dt;
        if (outroTime >= _outroLength) _finish();
      case CutscenePhase.done:
        break;
    }
    notifyListeners();
  }

  /// Tap / Space / Enter: show the waiting line now, finish typing, go to
  /// the next line, or move on to the next panel.
  void advance() {
    switch (phase) {
      case CutscenePhase.lines:
        final lines = panel.lines;
        if (lineIndex >= lines.length) {
          _endPanel();
          break;
        }
        final l = lines[lineIndex];
        if (lineTime < l.delay) {
          lineTime = l.delay;
        } else if (lineTime < l.delay + revealSeconds(l)) {
          lineTime = l.delay + revealSeconds(l);
        } else if (lineIndex + 1 < lines.length) {
          lineIndex++;
          lineTime = 0;
        } else {
          _endPanel();
        }
      case CutscenePhase.hold:
        _endPanel();
      case CutscenePhase.title:
        final card = panel.titleCard!;
        if (titleTime < card.fadeIn) {
          titleTime = card.fadeIn;
        } else {
          _startOutro(outroSeconds);
        }
      case CutscenePhase.outro:
      case CutscenePhase.done:
        break;
    }
    notifyListeners();
  }

  /// SKIP / Esc: fade out and finish.
  void skip() {
    if (phase == CutscenePhase.outro || isDone) return;
    _startOutro(skipOutroSeconds);
    notifyListeners();
  }

  /// Preview/test aid: jump to a panel at a given time with its line state.
  void jumpTo(int panel, {double time = 3, int line = 0, bool revealed = true, bool title = false}) {
    panelIndex = panel.clamp(0, scene.panels.length - 1);
    previousIndex = null;
    panelTime = time;
    lineIndex = line;
    final lines = this.panel.lines;
    lineTime = line < lines.length
        ? (revealed ? lines[line].delay + revealSeconds(lines[line]) + 0.01 : lines[line].delay + 0.6)
        : 0;
    phase = CutscenePhase.lines;
    if (title && this.panel.titleCard != null) {
      phase = CutscenePhase.title;
      panelTime = runtime(this.panel);
      titleTime = this.panel.titleCard!.fadeIn + 0.5;
    }
    notifyListeners();
  }

  void _endPanel() {
    if (panel.titleCard != null && phase != CutscenePhase.title) {
      phase = CutscenePhase.title;
      titleTime = 0;
      return;
    }
    if (panelIndex + 1 >= scene.panels.length) {
      _startOutro(outroSeconds);
      return;
    }
    previousIndex = panelIndex;
    previousTime = panelTime;
    fadeTime = 0;
    panelIndex++;
    panelTime = 0;
    lineIndex = 0;
    lineTime = 0;
    phase = CutscenePhase.lines;
  }

  void _startOutro(double seconds) {
    phase = CutscenePhase.outro;
    outroTime = 0;
    _outroLength = seconds;
  }

  void _finish() {
    phase = CutscenePhase.done;
    final cb = onDone;
    onDone = null;
    cb?.call();
  }
}

/// Plays an illustrated cutscene full screen: Ken Burns pan/zoom per panel,
/// crossfades, per-panel effects, typewriter subtitles with speaker names and
/// an optional title card. Tap / click / Space / Enter advances, SKIP or Esc
/// ends it. [onFinished] is called exactly once (also if loading fails, so a
/// broken asset never blocks the game).
///
/// Give either [asset] (a JSON path such as
/// `assets/cutscenes/awakening/awakening.json`) or an already parsed [scene].
class CutscenePlayer extends StatefulWidget {
  const CutscenePlayer({
    super.key,
    this.asset,
    this.scene,
    required this.onFinished,
    this.playback,
  }) : assert(asset != null || scene != null || playback != null);

  final String? asset;
  final Cutscene? scene;
  final VoidCallback onFinished;

  /// Optional externally created playback (previews/tests).
  final CutscenePlayback? playback;

  @override
  State<CutscenePlayer> createState() => _CutscenePlayerState();
}

class _CutscenePlayerState extends State<CutscenePlayer> with SingleTickerProviderStateMixin {
  CutscenePlayback? _playback;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _finished = false;
  bool _started = false;
  final _focus = FocusNode(debugLabel: 'cutscene');
  String? _voiceKey;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    // precacheImage needs inherited widgets: start after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _init();
    });
  }

  Future<void> _init() async {
    try {
      final playback = widget.playback ??
          CutscenePlayback(widget.scene ?? await loadCutscene(widget.asset!));
      if (!mounted) return;
      playback.onDone = _finish;
      setState(() => _playback = playback);
      await _precache(playback.scene);
      if (!mounted || _finished) return;
      _started = true;
      _ticker.start();
    } catch (e, st) {
      debugPrint('CutscenePlayer: could not play ${widget.asset}: $e\n$st');
      _finish();
    }
  }

  /// Waits (briefly) for the first panel so the scene does not open on a
  /// blank frame; the rest load in the background.
  Future<void> _precache(Cutscene scene) async {
    final paths = {...scene.imagePaths, ...scene.maskPaths}.toList();
    Future<void> load(String p) => precacheImage(AssetImage(p), context, onError: (e, _) {
          debugPrint('CutscenePlayer: missing image $p ($e)');
        });
    final first = load(paths.first);
    for (final p in paths.skip(1)) {
      unawaited(load(p));
    }
    await first.timeout(const Duration(seconds: 3), onTimeout: () {});
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    // A long frame (tab in background) must not skip whole panels.
    _playback?.tick(dt.clamp(0.0, 0.1));
    _syncVoice();
  }

  /// Plays a line's voice once when its subtitle becomes visible.
  void _syncVoice() {
    final p = _playback;
    if (p == null || _finished) return;
    if (p.phase == CutscenePhase.outro || p.phase == CutscenePhase.done) {
      _stopVoice();
      return;
    }
    final line = p.currentLine;
    final voice = line?.voice;
    if (voice == null || voice.isEmpty) return;
    final key = '${p.panelIndex}:${p.lineIndex}:$voice';
    if (key == _voiceKey) return;
    _voiceKey = key;
    MusicManager().setVolume(0.2);
    SfxManager().playVoice(voice);
  }

  void _stopVoice() {
    if (_voiceKey == null) {
      SfxManager().stopVoice();
      return;
    }
    _voiceKey = null;
    SfxManager().stopVoice();
    MusicManager().setVolume(1.0);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    if (_ticker.isActive) _ticker.stop();
    _stopVoice();
    // Called from inside a tick/build: defer to the next frame.
    SchedulerBinding.instance.addPostFrameCallback((_) => widget.onFinished());
    SchedulerBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    _stopVoice();
    if (widget.playback == null) _playback?.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    final p = _playback;
    if (p == null || e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      p.skip();
      _syncVoice();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.arrowRight) {
      if (_started) {
        p.advance();
        _syncVoice();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = _playback;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_started) {
            p?.advance();
            _syncVoice();
          }
        },
        child: ColoredBox(
          color: Colors.black,
          child: p == null
              ? const SizedBox.expand()
              : AnimatedBuilder(
                  animation: p,
                  builder: (context, _) => LayoutBuilder(
                    builder: (context, box) => _CutsceneView(
                      playback: p,
                      size: box.biggest,
                      onSkip: () {
                        p.skip();
                        _syncVoice();
                      },
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Where the art, subtitles and title go for a given screen size.
@visibleForTesting
class CutsceneLayout {
  /// The 16:9 art at zoom 1, in screen coordinates (may extend past the
  /// screen by a little when cover-cropping).
  final Rect image;

  /// The visible part of [image].
  final Rect visible;

  /// Portrait: subtitles sit in the band under the picture.
  final bool portrait;
  final double fontSize;

  const CutsceneLayout(this.image, this.visible, this.portrait, this.fontSize);

  /// Landscape/desktop: fit the art, zooming towards cover by at most 15 %
  /// so very wide phones lose a little sky/ground rather than showing wide
  /// black bars. Portrait: full width, centred a bit high so the subtitle
  /// band below has room.
  factory CutsceneLayout.compute(Size screen, double aspect) {
    final w = screen.width, h = screen.height;
    if (w <= 0 || h <= 0) return const CutsceneLayout(Rect.zero, Rect.zero, false, 14);
    final portrait = w / h < 1.15;
    final double fontSize = (math.min(w, h) * (portrait ? 0.042 : 0.04)).clamp(13.0, 22.0).toDouble();
    if (portrait) {
      final iw = w, ih = w / aspect;
      final top = math.max(0.0, (h - ih) / 2 - h * 0.06);
      final r = Rect.fromLTWH(0, top, iw, ih);
      return CutsceneLayout(r, r.intersect(Offset.zero & screen), true, fontSize);
    }
    final contain = math.min(w / aspect, h);
    final cover = math.max(w / aspect, h);
    final ih = math.min(cover, contain * 1.15);
    final iw = ih * aspect;
    final r = Rect.fromCenter(center: Offset(w / 2, h / 2), width: iw, height: ih);
    return CutsceneLayout(r, r.intersect(Offset.zero & screen), false, fontSize);
  }
}

class _CutsceneView extends StatelessWidget {
  const _CutsceneView({required this.playback, required this.size, required this.onSkip});

  final CutscenePlayback playback;
  final Size size;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final p = playback;
    final layout = CutsceneLayout.compute(size, p.scene.aspectRatio);
    final img = layout.image;
    final vis = layout.visible;
    final prev = p.previousIndex;
    final line = p.currentLine;
    final card = p.panel.titleCard;
    final padding = MediaQuery.paddingOf(context);

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // The art: previous panel underneath while the new one fades in.
        Positioned.fromRect(
          rect: vis,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: img.width,
              maxWidth: img.width,
              minHeight: img.height,
              maxHeight: img.height,
              child: Transform.translate(
                offset: img.topLeft - vis.topLeft,
                child: Stack(children: [
                  if (prev != null) _panelImage(prev, p.previousTime, img.size),
                  Opacity(
                    opacity: p.crossfade,
                    child: _panelImage(p.panelIndex, p.panelTime, img.size),
                  ),
                ]),
              ),
            ),
          ),
        ),

        // Landscape: a soft scrim over the bottom of the picture for the text.
        if (!layout.portrait && line != null)
          Positioned(
            left: vis.left,
            right: size.width - vis.right,
            bottom: size.height - vis.bottom,
            height: vis.height * 0.32,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
                  ),
                ),
              ),
            ),
          ),

        // Title card over the art.
        if (card != null && p.titleOpacity > 0)
          Positioned(
            left: img.left + img.width * card.position.dx - img.width * 0.45,
            width: img.width * 0.9,
            top: (img.top + img.height * card.position.dy).clamp(vis.top, vis.bottom).toDouble(),
            child: FractionalTranslation(
              translation: const Offset(0, -0.5),
              child: Opacity(
                opacity: p.titleOpacity,
                child: _TitleCard(card: card, width: math.min(img.width, size.width)),
              ),
            ),
          ),

        // Subtitles: bottom fifth of the picture (landscape) or the band
        // under it (portrait). Anchored at one edge only so long lines grow
        // instead of overflowing.
        if (line != null)
          layout.portrait
              ? Positioned(
                  left: 20,
                  right: 20,
                  top: math.min(vis.bottom + layout.fontSize, size.height * 0.7),
                  child: _Subtitle(playback: p, line: line, fontSize: layout.fontSize, portrait: true),
                )
              : Positioned(
                  left: vis.left + 24,
                  right: size.width - vis.right + 24,
                  bottom: size.height - vis.bottom + math.max(vis.height * 0.045, padding.bottom),
                  child: _Subtitle(playback: p, line: line, fontSize: layout.fontSize, portrait: false),
                ),

        // Fade from/to black.
        if (p.blackout > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: p.blackout)),
            ),
          ),

        if (!p.isDone && p.phase != CutscenePhase.outro)
          Positioned(
            top: padding.top + 10,
            right: padding.right + 12,
            child: _SkipButton(onTap: onSkip, compact: size.shortestSide < 500),
          ),
      ],
    );
  }

  Widget _panelImage(int index, double t, Size size) {
    final panel = playback.scene.panels[index];
    final pan = playback.panFor(index, t);
    final c = pan.clampedCenter();
    final z = pan.zoom;
    final dx = size.width / 2 - c.dx * size.width * z;
    final dy = size.height / 2 - c.dy * size.height * z;
    Widget image = Image.asset(
      panel.image,
      width: size.width,
      height: size.height,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => SizedBox(width: size.width, height: size.height),
    );
    for (final fx in panel.effects) {
      image = _applyEffect(fx, fx.amount(t), image);
    }
    return Transform(
      transform: Matrix4.translationValues(dx, dy, 0)..multiply(Matrix4.diagonal3Values(z, z, 1)),
      child: image,
    );
  }

  /// One switch per effect type; add new [CutsceneEffect.types] here.
  /// A local effect (mask image or soft spot) draws the filtered panel again
  /// on top, cut down to the mask's alpha.
  static Widget _applyEffect(CutsceneEffect fx, double amount, Widget child) {
    if (amount <= 0.001) return child;
    final Widget filtered;
    switch (fx.type) {
      case 'brighten':
      case 'pulse':
      case 'flash':
        filtered = ColorFiltered(
          colorFilter: ColorFilter.mode(fx.color.withValues(alpha: amount), BlendMode.screen),
          child: child,
        );
      case 'darken':
        filtered = ColorFiltered(
          colorFilter: ColorFilter.mode(Color.lerp(Colors.white, fx.color, amount)!, BlendMode.multiply),
          child: child,
        );
      default:
        return child;
    }
    if (!fx.isLocal) return filtered;
    return Stack(children: [child, _LocalMask(fx: fx, child: filtered)]);
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.playback, required this.line, required this.fontSize, required this.portrait});

  final CutscenePlayback playback;
  final CutsceneLine line;
  final double fontSize;
  final bool portrait;

  static const _shadows = [
    Shadow(color: Colors.black, blurRadius: 6),
    Shadow(color: Colors.black, blurRadius: 2, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    final speaker = playback.scene.speaker(line.speaker);
    final shown = playback.visibleChars;
    final style = TextStyle(
      color: speaker.narrator ? speaker.color : Colors.white,
      fontSize: fontSize,
      height: 1.4,
      fontStyle: speaker.narrator ? FontStyle.italic : FontStyle.normal,
      letterSpacing: 0.3,
      shadows: _shadows,
    );
    final complete = playback.lineComplete;
    return Opacity(
      opacity: (playback.lineAge / 0.25).clamp(0.0, 1.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (speaker.name != null)
                Padding(
                  padding: EdgeInsets.only(bottom: fontSize * 0.25),
                  child: Text(
                    speaker.name!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: speaker.color,
                      fontSize: fontSize * 0.72,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                      shadows: _shadows,
                    ),
                  ),
                ),
              // The unrevealed tail is laid out but transparent, so the text
              // never reflows while it types.
              Text.rich(
                TextSpan(style: style, children: [
                  TextSpan(text: line.text.substring(0, shown)),
                  TextSpan(
                    text: line.text.substring(shown),
                    style: const TextStyle(color: Colors.transparent, shadows: []),
                  ),
                ]),
                textAlign: TextAlign.center,
              ),
              SizedBox(
                height: fontSize * 0.9,
                child: complete
                    ? Text('▸',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35 + 0.35 * math.sin(playback.panelTime * 4).abs()),
                          fontSize: fontSize * 0.6,
                        ))
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleCard extends StatelessWidget {
  const _TitleCard({required this.card, required this.width});

  final CutsceneTitleCard card;
  final double width;

  @override
  Widget build(BuildContext context) {
    final size = (width * 0.062).clamp(20.0, 64.0).toDouble();
    final glow = [
      Shadow(color: card.color.withValues(alpha: 0.8), blurRadius: size * 0.5),
      const Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 2)),
    ];
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(card.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: card.color,
                fontSize: size,
                fontWeight: FontWeight.bold,
                letterSpacing: size * 0.22,
                shadows: glow,
              )),
          if (card.subtitle.isNotEmpty) ...[
            SizedBox(height: size * 0.25),
            Text(card.subtitle.toUpperCase(),
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: size * 0.32,
                  letterSpacing: size * 0.12,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                )),
          ],
        ],
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onTap, required this.compact});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Skip cutscene',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          // At least a 44 px touch target.
          constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF00FFCC).withValues(alpha: 0.55)),
          ),
          child: Text(
            'SKIP  ▸▸',
            style: TextStyle(
              color: const Color(0xFF00FFCC),
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [child] only through the effect's mask: a mask image's alpha
/// (stretched over the panel) or a soft radial spot.
class _LocalMask extends StatefulWidget {
  const _LocalMask({required this.fx, required this.child});

  final CutsceneEffect fx;
  final Widget child;

  @override
  State<_LocalMask> createState() => _LocalMaskState();
}

class _LocalMaskState extends State<_LocalMask> {
  static final _cache = <String, ui.Image>{};
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_LocalMask old) {
    super.didUpdateWidget(old);
    if (old.fx.mask != widget.fx.mask) _resolve();
  }

  void _resolve() {
    final path = widget.fx.mask;
    if (path == null || _cache.containsKey(path)) return;
    _unlisten();
    final stream = AssetImage(path).resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      _cache[path] = info.image.clone();
      info.dispose();
      if (mounted) setState(() {});
    }, onError: (e, _) => debugPrint('CutscenePlayer: missing mask $path ($e)'));
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _unlisten() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fx = widget.fx;
    final Shader Function(Rect) shader;
    if (fx.mask != null) {
      final img = _cache[fx.mask!];
      if (img == null) return const SizedBox.shrink();
      shader = (b) => ImageShader(
            img,
            TileMode.clamp,
            TileMode.clamp,
            Matrix4.diagonal3Values(b.width / img.width, b.height / img.height, 1).storage,
          );
    } else {
      final c = fx.center!;
      shader = (b) => RadialGradient(
            center: Alignment(c.dx * 2 - 1, c.dy * 2 - 1),
            radius: fx.radius * b.width / math.max(1.0, b.shortestSide),
            colors: const [Colors.white, Color(0x99FFFFFF), Colors.transparent],
            stops: const [0, 0.45, 1],
          ).createShader(b);
    }
    return ShaderMask(shaderCallback: shader, blendMode: BlendMode.dstIn, child: widget.child);
  }
}
