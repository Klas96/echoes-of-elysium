import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';

/// Web BGM via a DOM-mounted [html.AudioElement].
///
/// Must start (or unlock) inside a user-gesture turn — browsers block
/// autoplay once navigation / async gaps have consumed the activation.
class MusicManager {
  static final MusicManager _instance = MusicManager._();
  factory MusicManager() => _instance;
  MusicManager._();

  html.AudioElement? _el;
  String? _currentTrack;
  bool _domReady = false;

  double _userVolume = 0.7;
  bool _enabled = true;
  double _mix = 1.0;
  bool _awaitingGesture = false;

  /// Tiny silent wav — unlocks HTMLAudio when no track is chosen yet.
  static const _silentDataUri =
      'data:audio/wav;base64,UklGRigAAABXQVZFZm10IBIAAAABAAEARKwAAIhYAQACABAAAABkYXRhAgAAAAEA';

  double get _effective =>
      (_enabled ? _userVolume : 0.0) * _mix.clamp(0.0, 1.0);

  bool get _shouldPlay => _effective > 0.001;

  /// Resolve against `<base href="/games/echoes-of-elysium/">`.
  static String _url(String path) {
    final trimmed =
        path.startsWith('assets/') ? path.substring('assets/'.length) : path;
    return Uri.base.resolve('assets/assets/$trimmed').toString();
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
    // Some browsers refuse to play elements that were never inserted.
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

  Future<void> _waitReady(html.AudioElement el) async {
    if (el.readyState >= 2) return; // HAVE_CURRENT_DATA+
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
    timeout = Timer(const Duration(seconds: 4), finish);
    await done.future;
  }

  Future<bool> _tryPlay() async {
    _mountDom();
    final el = _el!;
    _applyVolume();
    if (!_shouldPlay) {
      el.pause();
      _awaitingGesture = false;
      return false;
    }
    try {
      await _waitReady(el);
      await el.play();
      _awaitingGesture = el.paused;
      return !_awaitingGesture;
    } catch (e) {
      debugPrint('MusicManager web play blocked: $e');
      _awaitingGesture = true;
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
      await _tryPlay();
    } else {
      _el?.pause();
      _awaitingGesture = false;
    }
  }

  Future<void> play(String assetPath) async {
    _mountDom();
    final el = _el!;
    final url = _url(assetPath);
    final sameTrack = _currentTrack == assetPath;
    final sameSrc = el.currentSrc.endsWith(assetPath.split('/').last) ||
        el.src.endsWith(Uri.parse(url).path);
    _currentTrack = assetPath;
    _applyVolume();

    if (!sameTrack || !sameSrc || el.src.isEmpty || el.src.startsWith('data:')) {
      el.loop = true;
      el.src = url;
      el.load();
    }

    final ok = await _tryPlay();
    if (!ok && _shouldPlay) {
      debugPrint('MusicManager web: waiting for gesture ($assetPath)');
    }
  }

  /// Call from clicks/taps/keys so autoplay policy allows playback.
  Future<void> unlockAfterGesture() async {
    _mountDom();
    final el = _el!;

    if (_currentTrack == null) {
      // Unlock the element with silence so a later [play] is allowed.
      try {
        el.loop = false;
        el.src = _silentDataUri;
        el.muted = true;
        await el.play();
        el.pause();
        el.currentTime = 0;
        el.muted = false;
        el.loop = true;
      } catch (e) {
        debugPrint('MusicManager web silent unlock: $e');
      }
      return;
    }

    if (!_shouldPlay) return;
    final ok = await _tryPlay();
    if (!ok) {
      final track = _currentTrack!;
      _currentTrack = null;
      await play(track);
    }
  }

  Future<void> stop() async {
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
