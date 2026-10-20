import 'dart:html' as html;

import 'package:flutter/foundation.dart';

/// Web BGM via [html.AudioElement] — same approach as [SfxManager] web.
///
/// `audioplayers` on Flutter web is flaky with autoplay / AssetSource under a
/// non-root [base href]; HTMLAudio + an explicit `assets/assets/...` URL is
/// reliable once unlocked by a user gesture.
class MusicManager {
  static final MusicManager _instance = MusicManager._();
  factory MusicManager() => _instance;
  MusicManager._();

  html.AudioElement? _el;
  String? _currentTrack;

  double _userVolume = 0.7;
  bool _enabled = true;
  double _mix = 1.0;
  bool _awaitingGesture = false;

  // Flutter web serves asset key `assets/x` at URL `assets/assets/x`
  // (relative to <base href="/games/echoes-of-elysium/">).
  static String _url(String path) {
    final trimmed =
        path.startsWith('assets/') ? path.substring('assets/'.length) : path;
    return 'assets/assets/$trimmed';
  }

  double get _effective =>
      (_enabled ? _userVolume : 0.0) * _mix.clamp(0.0, 1.0);

  bool get _shouldPlay => _effective > 0.001;

  void _ensureEl() {
    if (_el != null) return;
    final el = html.AudioElement()
      ..loop = true
      ..preload = 'auto';
    el.onError.listen((_) {
      debugPrint('MusicManager web load error: ${_el?.src}');
    });
    _el = el;
  }

  void _applyVolume() {
    final el = _el;
    if (el == null) return;
    el.volume = _effective.clamp(0.0, 1.0);
  }

  Future<void> applyUserVolume(double volume, {required bool enabled}) async {
    _userVolume = volume.clamp(0.0, 1.0);
    _enabled = enabled;
    _ensureEl();
    _applyVolume();
    final el = _el!;
    if (_currentTrack == null) return;
    if (_shouldPlay) {
      try {
        await el.play();
        _awaitingGesture = el.paused;
      } catch (_) {
        _awaitingGesture = true;
      }
    } else {
      el.pause();
      _awaitingGesture = false;
    }
  }

  Future<void> play(String assetPath) async {
    _ensureEl();
    final el = _el!;
    final url = _url(assetPath);
    final same = _currentTrack == assetPath && el.src.endsWith(url);
    _currentTrack = assetPath;
    _applyVolume();

    if (!same) {
      el.src = url;
      el.load();
    }

    if (!_shouldPlay) {
      el.pause();
      _awaitingGesture = false;
      return;
    }

    try {
      await el.play();
      _awaitingGesture = el.paused;
      if (_awaitingGesture) {
        debugPrint('MusicManager web: waiting for gesture ($assetPath)');
      }
    } catch (e) {
      debugPrint('MusicManager web play($assetPath): $e');
      _awaitingGesture = true;
    }
  }

  /// Call from clicks/taps/keys so autoplay policy allows [play].
  Future<void> unlockAfterGesture() async {
    _ensureEl();
    final el = _el!;
    // Warm the element even before a track is chosen (title-screen CONTINUE).
    if (_currentTrack == null) {
      try {
        el.muted = true;
        await el.play();
        el.pause();
        el.currentTime = 0;
        el.muted = false;
      } catch (_) {}
      return;
    }
    if (!_shouldPlay) return;
    _applyVolume();
    try {
      if (el.paused || _awaitingGesture) {
        await el.play();
      }
      _awaitingGesture = el.paused;
      if (_awaitingGesture) {
        // Force reload+play inside the gesture turn.
        final track = _currentTrack!;
        _currentTrack = null;
        await play(track);
      }
    } catch (e) {
      debugPrint('MusicManager web unlock: $e');
      _awaitingGesture = true;
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
