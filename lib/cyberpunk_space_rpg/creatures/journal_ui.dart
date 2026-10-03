import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import 'bonds.dart';
import 'creature_species.dart';
import 'day_cycle.dart';
import 'interaction.dart';

bool get _isTouch =>
    defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

const _teal = Color(0xFF00FFCC);
const _ink = Color(0xFF06060F);

/// Journal open state. The game screens hook [onOpenChanged] to pause and
/// resume the engine.
class Journal {
  static final open = ValueNotifier<bool>(false);
  static void Function(bool open)? onOpenChanged;

  /// Entry to show first when opened.
  static String? focus;

  static void show({String? entry}) {
    focus = entry;
    if (open.value) return;
    open.value = true;
    onOpenChanged?.call(true);
  }

  static void hide() {
    if (!open.value) return;
    open.value = false;
    onOpenChanged?.call(false);
  }

  static void toggle() => open.value ? hide() : show();
}

/// Subtle day/night tint over the game view (under the HUD).
class NightTint extends StatelessWidget {
  const NightTint({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<double>(
        valueListenable: DayCycle.time,
        builder: (_, t, __) => Container(color: DayCycle.tint(t)),
      ),
    );
  }
}

/// Small HUD row: journal button, time of day, current companion.
class CreatureHud extends StatelessWidget {
  const CreatureHud({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 90,
      left: 12,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const JournalButton(),
        const SizedBox(width: 8),
        ValueListenableBuilder<double>(
          valueListenable: DayCycle.time,
          builder: (_, t, __) {
            final night = DayCycle.isNight(t);
            return _Chip(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(night ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                    size: 11, color: night ? const Color(0xFFB8C4FF) : const Color(0xFFFFD27A)),
                const SizedBox(width: 4),
                Text(DayCycle.label(t),
                    style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.5)),
              ]),
            );
          },
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<int>(
          valueListenable: Bonds.revision,
          builder: (_, __, ___) {
            final id = Bonds.active;
            if (id == null) return const SizedBox.shrink();
            final s = creatureSpecies[id]!;
            return GestureDetector(
              onTap: () => Journal.show(entry: id),
              child: _Chip(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ClipOval(
                    child: Image.asset(s.portraitAsset(''),
                        width: 16, height: 16, fit: BoxFit.cover, filterQuality: FilterQuality.none),
                  ),
                  const SizedBox(width: 4),
                  Text(s.ability?.label ?? s.name.toUpperCase(),
                      style: const TextStyle(color: Color(0xFFE8D0FF), fontSize: 10, letterSpacing: 1.5)),
                ]),
              ),
            );
          },
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final Widget child;
  final Color border;
  const _Chip({required this.child, this.border = Colors.white24});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: child,
      );
}

class JournalButton extends StatelessWidget {
  const JournalButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Journal.show(),
      child: _Chip(
        border: _teal.withValues(alpha: 0.5),
        child: Text(_isTouch ? 'JOURNAL' : 'J  JOURNAL',
            style: const TextStyle(color: _teal, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ),
    );
  }
}

/// Prompt for creatures and ability objects, in the same spot and style as
/// the NPC TALK prompt. Hold actions fill a bar; on phones hold the button.
class InteractPromptLayer extends StatelessWidget {
  const InteractPromptLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([Interaction.info, Interaction.progress, Journal.open]),
      builder: (_, __) {
        final info = Interaction.info.value;
        if (info == null || Journal.open.value) return const SizedBox.shrink();
        if (!info.enabled) {
          return Positioned(
            bottom: 80,
            left: 24,
            right: 24,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(info.note,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 12, fontStyle: FontStyle.italic, height: 1.4)),
                ),
              ),
            ),
          );
        }
        final hold = info.hold > 0;
        final action = hold ? 'HOLD  ${info.label}' : info.label;
        final label = _isTouch ? action : 'E  $action';
        return Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: Center(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) {
                Interaction.touchHeld = true;
                Interaction.touchTapped = true;
              },
              onPointerUp: (_) => Interaction.touchHeld = false,
              onPointerCancel: (_) => Interaction.touchHeld = false,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: _isTouch ? 28 : 14, vertical: _isTouch ? 14 : 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  border: Border.all(color: _teal),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(label,
                      style: TextStyle(
                          color: _teal, fontSize: _isTouch ? 16 : 12, letterSpacing: 2, fontWeight: FontWeight.bold)),
                  if (hold) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: _isTouch ? 140 : 90,
                      height: 3,
                      child: LinearProgressIndicator(
                        value: Interaction.progress.value,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(_teal),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Bond moments, finds and lore lines.
class ToastLayer extends StatelessWidget {
  const ToastLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ToastMessage?>(
      valueListenable: GameToast.current,
      builder: (_, m, __) {
        return Positioned(
          top: 124,
          left: 16,
          right: 16,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: m == null
                ? const SizedBox.shrink()
                : Center(
                    key: ValueKey(m.id),
                    child: GestureDetector(
                      onTap: () => GameToast.current.value = null,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 380),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _ink.withValues(alpha: 0.92),
                          border: Border.all(color: m.color.withValues(alpha: 0.8)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (m.portrait != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.asset(m.portrait!,
                                  width: 56, height: 56, filterQuality: FilterQuality.none),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.title,
                                    style: TextStyle(
                                        color: m.color, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                                if (m.body.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(m.body,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4)),
                                ],
                              ],
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// The creature journal: a grid of entries (silhouette until seen, sketch
/// when seen, portrait + lore when befriended) and a detail panel with the
/// set-companion button. Portrait phones stack grid over details; landscape
/// phones put them side by side.
class JournalOverlay extends StatelessWidget {
  const JournalOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Journal.open,
      builder: (_, open, __) => open ? const _JournalPanel() : const SizedBox.shrink(),
    );
  }
}

class _JournalPanel extends StatefulWidget {
  const _JournalPanel();

  @override
  State<_JournalPanel> createState() => _JournalPanelState();
}

class _JournalPanelState extends State<_JournalPanel> {
  late String _sel = Journal.focus ?? Bonds.active ?? creatureOrder.first;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 940),
              child: ValueListenableBuilder<int>(
                valueListenable: Bonds.revision,
                builder: (_, __, ___) => LayoutBuilder(builder: (context, box) {
                  final wide = box.maxWidth > box.maxHeight * 1.2 && box.maxWidth >= 600;
                  final grid = _grid(3);
                  final detail = _Detail(id: _sel);
                  if (wide) {
                    // The open book: entries on the left page, details on the right.
                    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(
                        flex: 5,
                        child: _UiSlice.bookLeft(
                          child: Column(children: [
                            _header(),
                            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.only(top: 6), child: grid)),
                          ]),
                        ),
                      ),
                      Expanded(
                        flex: 6,
                        child: _UiSlice.bookRight(
                          child: Stack(clipBehavior: Clip.none, children: [
                            SingleChildScrollView(padding: const EdgeInsets.only(right: 40), child: detail),
                            Positioned(right: -4, top: -12, child: _closeButton()),
                          ]),
                        ),
                      ),
                    ]);
                  }
                  // Phones in portrait: a single right-hand page (spine on the left).
                  return _UiSlice.bookRight(
                    child: Column(children: [
                      _header(close: true),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(top: 6, bottom: 8),
                          child: Column(children: [
                            grid,
                            const SizedBox(height: 10),
                            Container(height: 1, color: _inkSoft.withValues(alpha: 0.35)),
                            const SizedBox(height: 10),
                            detail,
                          ]),
                        ),
                      ),
                    ]),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _closeButton() => IconButton(
        tooltip: 'Close',
        onPressed: Journal.hide,
        icon: const Icon(Icons.close, color: _inkSoft),
      );

  Widget _header({bool close = false}) {
    return Row(children: [
      Image.asset('assets/images/ui/tab_paw_32@2x.png', width: 30, height: 30, filterQuality: FilterQuality.none),
      const SizedBox(width: 8),
      const Text('JOURNAL',
          style: TextStyle(color: _inkDark, fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 3)),
      const SizedBox(width: 10),
      Expanded(
        child: Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Befriended ${Bonds.befriendedCount}/${Bonds.total}',
              style: const TextStyle(color: _inkSoft, fontSize: 12, fontWeight: FontWeight.w600)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/images/ui/crystal_16@2x.png', width: 14, height: 14, filterQuality: FilterQuality.none),
            const SizedBox(width: 3),
            Text('${Bonds.glimmer} glimmer',
                style: const TextStyle(color: _inkSoft, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
      if (close) _closeButton(),
    ]);
  }

  Widget _grid(int cols) {
    return LayoutBuilder(builder: (context, box) {
      const gap = 6.0;
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final id in creatureOrder)
            SizedBox(
              width: w,
              child: _Tile(id: id, selected: id == _sel, onTap: () => setState(() => _sel = id)),
            ),
        ],
      );
    });
  }
}

// Journal palette: ink on Designer's parchment pages.
const _inkDark = Color(0xFF3A2414);
const _inkSoft = Color(0xFF6B4A2E);
const _inkGreen = Color(0xFF2F6B3A);

/// Designer UI kit 9-slice panels (assets/images/ui, from art/ui/ui_kit.json).
/// The @2x files are drawn at [_f] logical px per 1x source px. Flutter reads
/// centerSlice in logical image coordinates, so the 1x slice is scaled by [_f].
class _UiSlice extends StatelessWidget {
  final String asset;
  final Rect slice1x; // ui_kit.json flutter_centerSlice (1x)
  final EdgeInsets padding;
  final Widget child;
  static const double _f = 1.5;

  const _UiSlice(this.asset, this.slice1x, this.padding, this.child);

  /// insets L,T,R,B 28,28,30,30; centerSlice 28,28,53,84.
  factory _UiSlice.bookLeft({required Widget child}) => _UiSlice('assets/images/ui/book_left@2x.png',
      const Rect.fromLTWH(28, 28, 53, 84), const EdgeInsets.fromLTRB(36, 28, 32, 40), child);

  /// insets L,T,R,B 30,28,28,30; centerSlice 30,28,53,84.
  factory _UiSlice.bookRight({required Widget child}) => _UiSlice('assets/images/ui/book_right@2x.png',
      const Rect.fromLTWH(30, 28, 53, 84), const EdgeInsets.fromLTRB(32, 28, 54, 40), child);

  /// insets 12 all round; centerSlice 12,12,109,70.
  factory _UiSlice.card({required Widget child, EdgeInsets padding = const EdgeInsets.all(12)}) =>
      _UiSlice('assets/images/ui/entry_card@2x.png', const Rect.fromLTWH(12, 12, 109, 70), padding, child);

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(asset),
            centerSlice: Rect.fromLTWH(
                slice1x.left * _f, slice1x.top * _f, slice1x.width * _f, slice1x.height * _f),
            scale: 2 / _f,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.none,
          ),
        ),
        child: child,
      );
}

String _variant(String id) => Bonds.isBefriended(id) ? '' : (Bonds.isSeen(id) ? 'sketch' : 'silhouette');

class _Tile extends StatelessWidget {
  final String id;
  final bool selected;
  final VoidCallback onTap;
  const _Tile({required this.id, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = creatureSpecies[id]!;
    final known = Bonds.isSeen(id);
    final friend = Bonds.isBefriended(id);
    final companion = Bonds.active == id;
    return GestureDetector(
      onTap: onTap,
      child: Stack(children: [
        _UiSlice.card(
          padding: const EdgeInsets.fromLTRB(9, 9, 9, 13),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AspectRatio(
              aspectRatio: 1,
              child: Image.asset(s.portraitAsset(_variant(id)), fit: BoxFit.contain, filterQuality: FilterQuality.none),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(known ? s.name : '???',
                  style: TextStyle(
                      color: friend ? _inkDark : (known ? _inkSoft : _inkSoft.withValues(alpha: 0.6)),
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(friend ? 'befriended' : (known ? 'seen' : 'not yet seen'),
                  style: TextStyle(color: friend ? _inkGreen : _inkSoft.withValues(alpha: 0.8), fontSize: 9)),
            ),
          ]),
        ),
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF1E8C7A), width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        if (companion)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFF1E8C7A), borderRadius: BorderRadius.circular(3)),
              child: const Text('WITH YOU',
                  style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)),
            ),
          ),
      ]),
    );
  }
}

class _Detail extends StatelessWidget {
  final String id;
  const _Detail({required this.id});

  @override
  Widget build(BuildContext context) {
    final s = creatureSpecies[id]!;
    final known = Bonds.isSeen(id);
    final friend = Bonds.isBefriended(id);
    final companion = Bonds.active == id;
    final status = friend ? 'BEFRIENDED' : (known ? 'SEEN' : 'NOT YET SEEN');
    final statusCol = friend ? _inkGreen : (known ? const Color(0xFF9A6A12) : _inkSoft.withValues(alpha: 0.7));
    TextStyle label() => TextStyle(color: _inkSoft.withValues(alpha: 0.85), fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold);
    const body = TextStyle(color: _inkDark, fontSize: 13, height: 1.4);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(known ? s.name.toUpperCase() : '???',
              style: const TextStyle(color: _inkDark, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2)),
        ),
        Text(status, style: TextStyle(color: statusCol, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 8),
      Text('HABITAT', style: label()),
      const SizedBox(height: 2),
      Text(s.habitat, style: body),
      const SizedBox(height: 8),
      Text('HINT', style: label()),
      const SizedBox(height: 2),
      Text(known ? s.hint : '???', style: body.copyWith(fontStyle: known ? FontStyle.italic : FontStyle.normal)),
      if (friend) ...[
        const SizedBox(height: 8),
        Text('GAIA', style: label()),
        const SizedBox(height: 2),
        Text(s.lore, style: body.copyWith(color: const Color(0xFF2C5A4E))),
      ],
      const SizedBox(height: 8),
      Text('COMPANION ABILITY', style: label()),
      const SizedBox(height: 2),
      Text(
          !known
              ? '???'
              : s.ability == null
                  ? '—'
                  : (friend ? '${s.ability!.label}: ${s.ability!.description}' : '${s.ability!.label}: ???'),
          style: body),
      const SizedBox(height: 12),
      if (friend)
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          TextButton(
            onPressed: () => Bonds.setActive(companion ? null : id),
            style: TextButton.styleFrom(
              backgroundColor: companion ? const Color(0x1A3A2414) : const Color(0xFF1E8C7A),
              side: BorderSide(color: companion ? _inkSoft : const Color(0xFF145F53)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: Text(companion ? 'SEND HOME' : 'SET AS COMPANION',
                style: TextStyle(
                    color: companion ? _inkDark : Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12)),
          ),
          if (companion)
            const Text('Walking with you', style: TextStyle(color: _inkGreen, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
    ]);
  }
}
