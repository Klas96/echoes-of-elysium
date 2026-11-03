// Dialog chrome preview for before/after screenshots (not part of the game).
//
//   flutter run -d chrome -t tools/dialog_preview.dart
//   ?skin=legacy   rounded Material-ish panels (pre-restyle)
//   ?skin=pixel    DialogChrome neon night-forest frames (default)
//   ?view=talk|toast|choice|all
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/ui/dialog_chrome.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _Preview(),
    ));

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final q = Uri.base.queryParameters;
    final legacy = q['skin'] == 'legacy';
    final view = q['view'] ?? 'all';
    return Scaffold(
      backgroundColor: const Color(0xFF02060E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Night-forest stand-in so chrome reads against game-like dark.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF061018),
                  Color(0xFF0A1A14),
                  Color(0xFF03080C),
                ],
              ),
            ),
          ),
          // Soft tree silhouettes / neon wash — atmosphere only.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _AtmospherePainter()),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (view == 'all' || view == 'toast') ...[
                        legacy ? _LegacyToast() : _PixelToast(),
                        const SizedBox(height: 18),
                      ],
                      if (view == 'all' || view == 'talk' || view == 'choice')
                        legacy
                            ? _LegacyTalk(withChoices: view != 'talk')
                            : _PixelTalk(withChoices: view != 'talk'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AtmospherePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00FFCC).withValues(alpha: 0.07),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.7, size.height * 0.35),
          radius: size.width * 0.45));
    canvas.drawRect(Offset.zero & size, glow);
    final trees = Paint()..color = const Color(0xFF04140E).withValues(alpha: 0.55);
    for (var i = 0; i < 8; i++) {
      final x = size.width * (0.05 + i * 0.12);
      final h = size.height * (0.25 + (i % 3) * 0.08);
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + 18, size.height - h)
        ..lineTo(x + 36, size.height)
        ..close();
      canvas.drawPath(path, trees);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Legacy (pre-restyle) — mirrors production look before DialogChrome.
// ---------------------------------------------------------------------------

class _LegacyTalk extends StatelessWidget {
  final bool withChoices;
  const _LegacyTalk({required this.withChoices});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00FF88);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF06060F).withValues(alpha: 0.96),
        border: Border.all(color: accent, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('GAIA',
              style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3)),
          const SizedBox(height: 10),
          const Text(
            'They belong to the forest, Kaela. It will keep them for you.',
            style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.65),
          ),
          if (withChoices) ...[
            const SizedBox(height: 14),
            _legacyBtn('Ask about the lattice', accent),
            const SizedBox(height: 8),
            _legacyBtn('Tell her about the skiff', accent),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {},
                child: const Text('LEAVE',
                    style: TextStyle(color: Colors.white24, fontSize: 11)),
              ),
              if (!withChoices)
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    backgroundColor: accent.withValues(alpha: 0.07),
                    side: BorderSide(color: accent.withValues(alpha: 0.85)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('NEXT ›',
                      style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.4)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legacyBtn(String label, Color accent) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: () {},
        style: TextButton.styleFrom(
          backgroundColor: accent.withValues(alpha: 0.22),
          foregroundColor: accent,
          side: BorderSide(color: accent, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(label,
            style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.4,
                fontSize: 15)),
      ),
    );
  }
}

class _LegacyToast extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00FF88);
    return Align(
      alignment: Alignment.center,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF06060F).withValues(alpha: 0.82),
          border: Border.all(color: accent.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/images/sprites/npc_gaia.png',
                width: 44,
                height: 44,
                filterQuality: FilterQuality.none,
                errorBuilder: (_, __, ___) => Container(
                  width: 44,
                  height: 44,
                  color: const Color(0xFF0A1220),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('GAIA',
                      style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5)),
                  SizedBox(height: 3),
                  Text(
                    'They belong to the forest, Kaela. It will keep them for you.',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Color(0xA6FFFFFF), fontSize: 11, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pixel (DialogChrome) — production restyle.
// ---------------------------------------------------------------------------

class _PixelTalk extends StatelessWidget {
  final bool withChoices;
  const _PixelTalk({required this.withChoices});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00FF88);
    return DialogChrome.panel(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DialogChrome.speakerLabel('GAIA', accent, compact: false),
          const SizedBox(height: 10),
          Text(
            'They belong to the forest, Kaela. It will keep them for you.',
            style: DialogChrome.bodyStyle(compact: false),
          ),
          if (withChoices) ...[
            const SizedBox(height: 14),
            DialogChrome.choiceButton(
              label: 'Ask about the lattice',
              accent: accent,
              onTap: () {},
              wide: true,
            ),
            const SizedBox(height: 8),
            DialogChrome.choiceButton(
              label: 'Tell her about the skiff',
              accent: accent,
              onTap: () {},
              wide: true,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {},
                child: Text('LEAVE',
                    style: TextStyle(
                        color: DialogChrome.mute, fontSize: 11, letterSpacing: 1)),
              ),
              if (!withChoices) ...[
                const SizedBox(width: 8),
                DialogChrome.choiceButton(
                  label: 'NEXT ›',
                  accent: accent,
                  filled: false,
                  onTap: () {},
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PixelToast extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00FF88);
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: DialogChrome.toastShell(
          accent: accent,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogChrome.portrait('assets/images/sprites/npc_gaia.png'),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('GAIA',
                        style: DialogChrome.toastTitleStyle(accent, compact: false)),
                    const SizedBox(height: 3),
                    Text(
                      'They belong to the forest, Kaela. It will keep them for you.',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: DialogChrome.toastBodyStyle(compact: false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
