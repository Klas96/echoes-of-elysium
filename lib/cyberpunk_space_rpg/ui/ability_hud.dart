import 'dart:math';

import 'package:flutter/material.dart';

import '../components/custom_player.dart';
import '../game/progression.dart';
import 'hud_layout.dart';

/// Bottom-right combat ability bar (mobile-first; also on desktop).
/// Target · Phase · Pulse · Ward · Anchor.
class AbilityHud extends StatelessWidget {
  const AbilityHud({super.key});

  static const _targetAccent = Color(0xFFFF8866);
  static const _phaseAccent = Color(0xFF88EEFF);
  static const _pulseAccent = Color(0xFF00FFCC);
  static const _wardAccent = Color(0xFFE8D0FF);
  static const _anchorAccent = Color(0xFFAA44FF);
  static const _locked = Color(0xFF8899AA);
  static final _targetCd = ValueNotifier<double>(0);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final btn = HudLayout.isTouch ? 64.0 : 54.0;
    final gap = HudLayout.isTouch ? 8.0 : 6.0;
    final right = HudLayout.isTouch ? 10.0 : 16.0;
    final bottom = HudLayout.narrow(screen) ? 20.0 : 26.0;

    return Positioned(
      right: right,
      bottom: bottom,
      child: SafeArea(
        top: false,
        left: false,
        child: ValueListenableBuilder<int>(
          valueListenable: Progression.revision,
          builder: (_, __, ___) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Always unlocked — browser / touch stand-in for click-foe / T.
              _AbilityButton(
                size: btn,
                label: 'TARGET',
                hint: 'T',
                accent: _targetAccent,
                lockedColor: _locked,
                unlocked: true,
                unlockLevel: 1,
                cooldownLeft: _targetCd,
                cooldownMax: 1,
                onTap: () => CustomPlayer.current?.tryAcquireNearest(),
              ),
              SizedBox(width: gap),
              _AbilityButton(
                size: btn,
                label: 'PHASE',
                hint: 'Space',
                accent: _phaseAccent,
                lockedColor: _locked,
                unlocked: CustomPlayer.phaseUnlocked,
                unlockLevel: CustomPlayer.phaseUnlockLevel,
                cooldownLeft: CustomPlayer.phaseCdLeft,
                cooldownMax: CustomPlayer.phaseCooldown,
                onTap: () => CustomPlayer.current?.tryPhaseStep(),
              ),
              SizedBox(width: gap),
              _AbilityButton(
                size: btn,
                label: 'PULSE',
                hint: 'Q',
                accent: _pulseAccent,
                lockedColor: _locked,
                unlocked: CustomPlayer.pulseUnlocked,
                unlockLevel: CustomPlayer.pulseUnlockLevel,
                cooldownLeft: CustomPlayer.pulseCdLeft,
                cooldownMax: CustomPlayer.pulseCooldown,
                onTap: () => CustomPlayer.current?.tryPulseShot(),
              ),
              SizedBox(width: gap),
              _AbilityButton(
                size: btn,
                label: 'WARD',
                hint: 'F',
                accent: _wardAccent,
                lockedColor: _locked,
                unlocked: CustomPlayer.wardUnlocked,
                unlockLevel: CustomPlayer.wardUnlockLevel,
                cooldownLeft: CustomPlayer.wardCdLeft,
                cooldownMax: CustomPlayer.wardCooldown,
                onTap: () => CustomPlayer.current?.tryWard(),
              ),
              SizedBox(width: gap),
              _AbilityButton(
                size: btn,
                label: 'ANCHOR',
                hint: 'R',
                accent: _anchorAccent,
                lockedColor: _locked,
                unlocked: CustomPlayer.anchorUnlocked,
                unlockLevel: CustomPlayer.anchorUnlockLevel,
                cooldownLeft: CustomPlayer.anchorCdLeft,
                cooldownMax: CustomPlayer.anchorCooldown,
                onTap: () => CustomPlayer.current?.tryAnchor(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AbilityButton extends StatelessWidget {
  final double size;
  final String label;
  final String hint;
  final Color accent;
  final Color lockedColor;
  final bool unlocked;
  final int unlockLevel;
  final ValueNotifier<double> cooldownLeft;
  final double cooldownMax;
  final VoidCallback onTap;

  const _AbilityButton({
    required this.size,
    required this.label,
    required this.hint,
    required this.accent,
    required this.lockedColor,
    required this.unlocked,
    required this.unlockLevel,
    required this.cooldownLeft,
    required this.cooldownMax,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: cooldownLeft,
      builder: (_, cd, __) {
        final ready = unlocked && cd <= 0.01;
        final t = !unlocked
            ? 0.0
            : ready
                ? 1.0
                : (1.0 - cd / cooldownMax).clamp(0.0, 1.0);
        final text = !unlocked
            ? 'Lv$unlockLevel'
            : ready
                ? label
                : cd.ceil().toString();
        final color = unlocked ? accent : lockedColor;
        return Semantics(
          button: true,
          enabled: unlocked,
          label: !unlocked
              ? '$label locked until level $unlockLevel'
              : ready
                  ? label
                  : '$label cooling down',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: ready ? onTap : null,
            child: SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _AbilityPainter(
                  progress: t,
                  ready: ready,
                  unlocked: unlocked,
                  accent: color,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!unlocked)
                        Icon(Icons.lock_outline,
                            size: HudLayout.isTouch ? 14 : 12,
                            color: lockedColor.withValues(alpha: 0.9)),
                      if (!unlocked) const SizedBox(height: 2),
                      Text(
                        text,
                        style: TextStyle(
                          color: unlocked
                              ? (ready
                                  ? accent
                                  : Colors.white.withValues(alpha: 0.55))
                              : lockedColor,
                          fontSize: HudLayout.isTouch
                              ? (unlocked ? 11 : 9)
                              : (unlocked ? 10 : 8),
                          fontWeight: FontWeight.w800,
                          letterSpacing: unlocked ? 1.0 : 0.5,
                          height: 1,
                        ),
                      ),
                      if (ready && !HudLayout.isTouch) ...[
                        const SizedBox(height: 2),
                        Text(
                          hint,
                          style: TextStyle(
                            color: accent.withValues(alpha: 0.55),
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AbilityPainter extends CustomPainter {
  final double progress;
  final bool ready;
  final bool unlocked;
  final Color accent;

  _AbilityPainter({
    required this.progress,
    required this.ready,
    required this.unlocked,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = min(size.width, size.height) / 2 - 2;

    canvas.drawCircle(
      c,
      r,
      Paint()..color = Colors.black.withValues(alpha: unlocked ? 0.72 : 0.55),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = accent.withValues(alpha: ready ? 0.85 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = ready ? 2.4 : 1.4,
    );

    if (!unlocked) return;

    if (!ready) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 3),
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..color = accent.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
    } else {
      canvas.drawCircle(
        c,
        r - 5,
        Paint()
          ..color = accent.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AbilityPainter old) =>
      old.progress != progress ||
      old.ready != ready ||
      old.unlocked != unlocked ||
      old.accent != accent;
}
