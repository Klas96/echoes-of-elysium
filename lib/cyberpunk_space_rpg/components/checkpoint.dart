import 'dart:math';
import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'custom_player.dart';
import '../game/save_service.dart';
import '../creatures/day_cycle.dart';
import '../creatures/interaction.dart';

/// A respawn point placed in Tiled ("checkpoint" objects in the gameplay
/// layer: one at the spawn plus one per area entrance). Walking over it makes
/// it the place Gaia pulls Kaela back to at 0 HP. Drawn as a soft Aetherian
/// ring that blooms green once active (placeholder until Designer art).
///
/// It is also a rest spot: once active, REST skips to nightfall (by day) or
/// morning (by night) and restores health, so night-only creatures are
/// always reachable without waiting out the 10-minute day.
class Checkpoint extends GameDecoration with Interactable {
  static const double _activateRadius = 28;
  /// Don't spam toasts when several rings sit on the same trail.
  static const double _toastMinSeparation = 420;

  /// Short "Checkpoint · <label>" toast for the HUD (null = hidden).
  static final toast = ValueNotifier<String?>(null);

  final String label;
  double _pulse = 0;
  double _bloom = 0; // 0..1, eases in when activated

  Checkpoint(Vector2 position, {this.label = ''})
      : super(position: position, size: Vector2.all(CustomPlayer.sizePlayer)) {
    priority = 1; // under the player and other objects
  }

  CustomPlayer? get _player => gameRef.player as CustomPlayer?;

  bool get isActive {
    final p = _player?.respawnPoint;
    return p != null && p.distanceTo(position) < 4;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 1.6;
    final player = _player;
    if (player == null) return;
    final active = isActive;
    _bloom = active ? min(1, _bloom + dt * 1.5) : max(0, _bloom - dt * 1.5);
    if (active || player.isRespawning) return;
    final d = ((player.position + player.size / 2) - (position + size / 2)).length;
    if (d < _activateRadius) {
      final prev = player.respawnPoint;
      final first = prev == null;
      final movedFar = prev == null || prev.distanceTo(position) >= _toastMinSeparation;
      player.respawnPoint = position.clone();
      // No toast at spawn; later rings only announce when they're a real step forward.
      if (!first && movedFar) _showToast();
      // Autosave: the checkpoint becomes the place CONTINUE returns to.
      SaveService.data.checkpoint = SavePoint(position.x, position.y);
      SaveService.requestAutosave();
    }
  }

  @override
  bool get canFocus => isActive && !(_player?.isRespawning ?? true);

  @override
  double get interactRadius => 34;

  @override
  PromptInfo get prompt =>
      PromptInfo(DayCycle.night ? 'REST UNTIL MORNING' : 'REST UNTIL NIGHTFALL', hold: 0.6);

  @override
  void interact() {
    final wasNight = DayCycle.night;
    DayCycle.time.value = DayCycle.restTarget(DayCycle.time.value);
    CustomPlayer.healthNotifier.value = CustomPlayer.maxHealth;
    SaveService.data.dayTime = DayCycle.time.value;
    SaveService.requestAutosave();
    GameToast.show(wasNight ? 'MORNING' : 'NIGHTFALL',
        body: 'Rested · HP restored',
        color: wasNight ? const Color(0xFFFFD27A) : const Color(0xFFB8C4FF),
        compact: true);
  }

  void _showToast() {
    final text = label.isEmpty ? 'Checkpoint' : 'Checkpoint · $label';
    toast.value = text;
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (toast.value == text) toast.value = null;
    });
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final p = (sin(_pulse) + 1) / 2;
    const idle = Color(0xFF66CCDD);
    const on = Color(0xFF66FFAA);
    final col = Color.lerp(idle, on, _bloom)!;
    // soft glow
    canvas.drawCircle(
      c,
      11 + 5 * _bloom + p * 2,
      Paint()
        ..color = col.withValues(alpha: 0.10 + 0.14 * _bloom + p * 0.05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    // ring
    canvas.drawCircle(
      c,
      9,
      Paint()
        ..color = col.withValues(alpha: 0.45 + 0.35 * _bloom)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    // four small glyph petals
    final petal = Paint()..color = col.withValues(alpha: 0.35 + 0.5 * _bloom);
    for (var i = 0; i < 4; i++) {
      final a = i * pi / 2 + _pulse * 0.25;
      canvas.drawCircle(c + Offset(cos(a) * 9, sin(a) * 9), 1.6 + _bloom, petal);
    }
    // core
    canvas.drawCircle(c, 2 + 1.5 * _bloom, Paint()..color = col.withValues(alpha: 0.6 + 0.4 * _bloom));
  }
}
