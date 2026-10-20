import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';

/// Web BGM via a DOM-mounted [html.AudioElement].
///
/// Start [play] inside the CONTINUE / BEGIN click — never unlock with a
/// silent data-URI first (that raced and wiped the real track src).
class MusicManager {
  static final MusicManager _instance = MusicManager._();
  factory MusicManager() => _instance;
  MusicManager._();

  html.AudioElement? _el;
  String? _currentTrack;
  bool _domReady = false;
  int _playGen = 0;

  double _userVolume = 0.7;
  bool _enabled = true;
  double _mix = 1.0;
  bool _awaitingGesture = false;

  double get _effective =>
      (_enabled ? _userVolume : 0.0) * _mix.clamp(0.0, 1.0);

  bool get _shouldPlay => _effective > 0.001;

  /// Resolve against `<base href>`, encoding each path segment (spaces etc.).
  static String _url(String path) {
    final trimmed =
        path.startsWith('assets/') ? path.substring('assets/'.length) : path;
    final encoded =
        trimmed.split('/').map(Uri.encodeComponent).join('/');
    return Uri.base.resolve('assets/assets/$encoded').toString();
  }

  void _ensureEl() {
    if (_el != null) return;
    final el = html.AudioElement()
      ..loop = true
      ..preload = 'auto'
      ..controls = false
      ..style.display = 'none';
    el.onError.listen((_) {
      debugPrint('MusicManager web error src=${_el?.src}');
    });
    _el = el;
  }

  void _mountDom() {
    if (_domReady) return;
    _ensureEl();
    final el = _el!;
    if (el.parent == null) {
      html.document.body?.append(el);
    }
    _domReady = true;
  }

  void _applyVolume() {
    final el = _el;
    if (el == null) return;
    el.volume = _effective.clamp(0.0, 1.0);
  }

  Future<void> _waitReady(html.AudioElement el, int gen) async {
    if (el.readyState >= 2) return;
    final done = Completer<void>();
    StreamSubscription? sub;
    Timer? timeout;
    void finish() {
      if (done.isCompleted) return;
      sub?.cancel();
      timeout?.cancel();
      done.complete();
    }

    sub = el.onCanPlay.listen((_) => finish());
    timeout = Timer(const Duration(seconds: 5), finish);
    await done.future;
    if (gen != _playGen) return;
  }

  Future<bool> _tryPlay(int gen) async {
    _mountDom();
    final el = _el!;
    _applyVolume();
    if (!_shouldPlay) {
      el.pause();
      _awaitingGesture = false;
      return false;
    }
    try {
      await _waitReady(el, gen);
      if (gen != _playGen) return false;
      await el.play();
      if (gen != _playGen) return false;
      _awaitingGesture = el.paused;
      return !_awaitingGesture;
    } catch (e) {
      debugPrint('MusicManager web play blocked: $e');
      if (gen == _playGen) _awaitingGesture = true;
      return false;
    }
  }

  Future<void> applyUserVolume(double volume, {required bool enabled}) async {
    _userVolume = volume.clamp(0.0, 1.0);
    _enabled = enabled;
    _mountDom();
    _applyVolume();
    if (_currentTrack == null) return;
    if (_shouldPlay) {
      final gen = _playGen;
      await _tryPlay(gen);
    } else {
      _el?.pause();
      _awaitingGesture = false;
    }
  }

  Future<void> play(String assetPath) async {
    final gen = ++_playGen;
    _mountDom();
    final el = _el!;
    final url = _url(assetPath);
    _currentTrack = assetPath;
    _applyVolume();

    final needLoad = el.src.isEmpty ||
        el.src.startsWith('data:') ||
        !(el.currentSrc.contains(Uri.encodeComponent(assetPath.split('/').last)) ||
            el.src.contains(assetPath.split('/').last.split(' ').first));
    // Always reload when path changes.
    final sameTrack = el.getAttribute('data-track') == assetPath;
    if (!sameTrack || needLoad) {
      el.loop = true;
      el.setAttribute('data-track', assetPath);
      el.src = url;
      el.load();
    }

    final ok = await _tryPlay(gen);
    if (!ok && _shouldPlay && gen == _playGen) {
      debugPrint('MusicManager web: waiting for gesture ($assetPath)');
    }
  }

  /// Resume current track after a gesture. Does **not** invent a silent src.
  Future<void> unlockAfterGesture() async {
    if (_currentTrack == null || !_shouldPlay) return;
    final track = _currentTrack!;
    final gen = _playGen;
    final ok = await _tryPlay(gen);
    if (!ok && gen == _playGen) {
      _currentTrack = null;
      await play(track);
    }
  }

  Future<void> stop() async {
    _playGen++;
    _currentTrack = null;
    _awaitingGesture = false;
    try {
      _el?.pause();
      if (_el != null) _el!.currentTime = 0;
    } catch (_) {}
  }

  Future<void> setVolume(double volume) async {
    _mix = volume.clamp(0.0, 1.0);
    _applyVolume();
  }
}
