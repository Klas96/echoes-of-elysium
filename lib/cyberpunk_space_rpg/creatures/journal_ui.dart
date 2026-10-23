import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../audio/audio_settings.dart';
import '../components/lamp_light.dart';
import '../game/adventure.dart';
import '../ui/app_version_label.dart';
import '../ui/hud_layout.dart';
import '../game/memories.dart';
import '../game/quests.dart';
import '../game/save_service.dart';
import '../game/well_rested.dart';
import '../ui/equipment_ui.dart';
import '../ui/shop_ui.dart';
import 'bonds.dart';
import 'creature_species.dart';
import 'day_cycle.dart';
import 'interaction.dart';

bool get _isTouch => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

const _teal = Color(0xFF00FFCC);
const _ink = Color(0xFF06060F);

/// In-game Menu tablet (creatures, quests, items, memories, system).
/// Game screens hook [onOpenChanged] to pause and resume the engine.
class Journal {
  static const tabCreatures = 0;
  static const tabQuests = 1;
  static const tabItems = 2;
  static const tabMemories = 3;
  static const tabSystem = 4;

  static final open = ValueNotifier<bool>(false);
  /// Bumped when [show] changes tab while already open.
  static final tabTick = ValueNotifier<int>(0);
  static void Function(bool open)? onOpenChanged;

  /// Creature entry to focus when opened on Creatures.
  static String? focus;

  /// Optional: close gear (or other overlays) without resuming.
  static void Function()? dismissOthers;

  /// Leave the map and return to the title screen (wired by the map host).
  static Future<void> Function(BuildContext context)? returnToTitle;

  /// Requested tab (see [tabCreatures]…).
  static int? focusTab;

  /// Last tab shown by the open panel (for I-key toggle).
  static int activeTab = tabCreatures;

  static void show({String? entry, int? tab}) {
    focus = entry;
    if (tab != null) focusTab = tab;
    dismissOthers?.call();
    if (open.value) {
      if (tab != null) {
        activeTab = tab;
        tabTick.value++;
      }
      return;
    }
    if (tab != null) activeTab = tab;
    open.value = true;
    onOpenChanged?.call(true);
  }

  static void hide() {
    if (!open.value) return;
    open.value = false;
    focusTab = null;
    onOpenChanged?.call(false);
  }

  static void toggle() => open.value ? hide() : show();

  static void toggleItems() {
    if (open.value && activeTab == tabItems) {
      hide();
    } else {
      show(tab: tabItems);
    }
  }
}

/// Subtle day/night tint over the game view (under the HUD). At night lamps,
/// lanterns and fires cut warm pools into it (see [NightTintPainter]).
class NightTint extends StatelessWidget {
  const NightTint({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: NightTintPainter(), size: Size.infinite),
      ),
    );
  }
}

/// Small HUD row: menu, glimmer, time of day, current companion.
class CreatureHud extends StatelessWidget {
  /// Icon-only buttons (narrow screens); labels stay for wide screens.
  final bool compact;
  const CreatureHud({super.key, this.compact = false});

  static const _gold = Color(0xFFFFE08A);

  @override
  Widget build(BuildContext context) {
    final gap = compact ? 6.0 : 8.0;
    final chips = <Widget>[
      const _MenuChip(),
      ValueListenableBuilder<int>(
        valueListenable: Bonds.revision,
        builder: (_, __, ___) => _Chip(
          border: _gold.withValues(alpha: 0.45),
          child: Text('${Bonds.glimmer}◆',
              style: TextStyle(
                  color: _gold,
                  fontSize: HudLayout.chipFont,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
        ),
      ),
      if (SaveService.data.mapId == 'world5')
        GestureDetector(
          onTap: Shop.show,
          child: _Chip(
            border: _gold,
            child: compact
                ? Icon(Icons.storefront_outlined,
                    size: HudLayout.chipIcon, color: _gold)
                : Text('STALL',
                    style: TextStyle(
                        color: _gold,
                        fontSize: HudLayout.chipFont,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5)),
          ),
        ),
      ValueListenableBuilder<double>(
        valueListenable: DayCycle.time,
        builder: (_, t, __) {
          final night = DayCycle.isNight(t);
          final icon = Icon(night ? Icons.nightlight_round : Icons.wb_sunny_outlined,
              size: compact ? HudLayout.chipIcon : HudLayout.chipFont + 1,
              color: night ? const Color(0xFFB8C4FF) : const Color(0xFFFFD27A));
          return Tooltip(
            message: DayCycle.label(t),
            child: _Chip(
              child: compact
                  ? icon
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      icon,
                      SizedBox(width: HudLayout.isTouch ? 4 : 6),
                      Text(DayCycle.label(t),
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: HudLayout.chipFont,
                              letterSpacing: 1.5)),
                    ]),
            ),
          );
        },
      ),
      ValueListenableBuilder<int>(
        valueListenable: Bonds.revision,
        builder: (_, __, ___) {
          // Companions stay in their home region: no chip (and no ability)
          // outside it.
          final id = Bonds.activeHere;
          if (id == null) return const SizedBox.shrink();
          final s = creatureSpecies[id]!;
          final face = HudLayout.isTouch ? 16.0 : 20.0;
          final portrait = ClipOval(
            child: Image.asset(s.portraitAsset(''),
                width: face,
                height: face,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.none),
          );
          return GestureDetector(
            onTap: () => Journal.show(entry: id),
            child: _Chip(
              child: compact
                  ? portrait
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      portrait,
                      SizedBox(width: HudLayout.isTouch ? 4 : 6),
                      Text(s.ability?.label ?? s.name.toUpperCase(),
                          style: TextStyle(
                              color: const Color(0xFFE8D0FF),
                              fontSize: HudLayout.chipFont,
                              letterSpacing: 1.5)),
                    ]),
            ),
          );
        },
      ),
    ];

    // Single row on wide layouts; wrap when compact.
    if (!compact) {
      return Row(
        key: const ValueKey('hud-chips'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            chips[i],
          ],
        ],
      );
    }
    return Wrap(
      key: const ValueKey('hud-chips'),
      spacing: gap,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
  }
}

/// "Well rested" buff chip under the HUD row, with a countdown (#32).
class WellRestedChip extends StatelessWidget {
  const WellRestedChip({super.key});

  static const _gold = Color(0xFFFFCC66);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: WellRested.remaining,
      builder: (_, left, __) {
        if (left <= 0) return const SizedBox.shrink();
        // Narrow screens: the bonus line goes under the timer instead of
        // beside it, so nothing has to shrink.
        final narrow = MediaQuery.sizeOf(context).width < 440;
        final title = Text('WELL RESTED  ${WellRested.label}',
            style: const TextStyle(
                color: _gold, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2));
        final bonus = Text('+${(WellRested.damageBonus * 100).round()}% DMG · REGEN',
            style: const TextStyle(color: Colors.white54, fontSize: 9, letterSpacing: 0.8));
        return Padding(
          key: const ValueKey('hud-rested'),
          padding: const EdgeInsets.only(top: 6),
          child: _Chip(
            border: _gold.withValues(alpha: 0.7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.bedtime_outlined, size: 11, color: _gold),
              const SizedBox(width: 4),
              if (narrow)
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  title,
                  const SizedBox(height: 1),
                  bonus,
                ])
              else ...[
                title,
                const SizedBox(width: 8),
                bonus,
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final Widget child;
  final Color border;
  final Color? fill;
  final double borderWidth;
  const _Chip({
    required this.child,
    this.border = Colors.white24,
    this.fill,
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: HudLayout.chipPadding,
        decoration: BoxDecoration(
          color: fill ?? Colors.black.withValues(alpha: 0.6),
          border: Border.all(color: border, width: borderWidth),
          borderRadius: BorderRadius.circular(HudLayout.isTouch ? 4 : 5),
        ),
        child: child,
      );
}

/// Opens the journal tablet (in-game hub). Filled Signal Teal so it won't read as a status chip.
class _MenuChip extends StatelessWidget {
  const _MenuChip();

  @override
  Widget build(BuildContext context) {
    final pad = HudLayout.chipPadding;
    return GestureDetector(
      onTap: Journal.show,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: pad.horizontal / 2 + 2,
          vertical: pad.vertical / 2 + 1,
        ),
        decoration: BoxDecoration(
          color: _teal,
          borderRadius: BorderRadius.circular(HudLayout.isTouch ? 4 : 5),
          boxShadow: [
            BoxShadow(
              color: _teal.withValues(alpha: 0.35),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Text('MENU',
            style: TextStyle(
                color: const Color(0xFF06060F),
                fontSize: HudLayout.chipFont,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2)),
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
      animation: Listenable.merge(
          [Interaction.info, Interaction.progress, Journal.open, Equipment.open, Shop.open],
      ),
      builder: (_, __) {
        final info = Interaction.info.value;
        if (info == null ||
            Journal.open.value ||
            Equipment.open.value ||
            Shop.open.value) {
          return const SizedBox.shrink();
        }
        final screen = MediaQuery.sizeOf(context);
        if (!info.enabled) {
          return Positioned(
            bottom: HudLayout.promptBottom(screen),
            left: 24,
            right: 24,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  key: const ValueKey('hud-prompt'),
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (itemIconAsset(info.item) != null) ...[
                      ItemIcon(info.item!, size: 16, dim: true),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(info.note,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 10, fontStyle: FontStyle.italic, height: 1.3)),
                    ),
                  ]),
                ),
              ),
            ),
          );
        }
        final hold = info.hold > 0;
        final action = hold ? 'HOLD  ${info.label}' : info.label;
        final label = _isTouch ? action : 'E  $action';
        return Positioned(
          bottom: HudLayout.promptBottom(screen),
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
                key: const ValueKey('hud-prompt'),
                constraints: BoxConstraints(maxWidth: screen.width - 32),
                padding: EdgeInsets.symmetric(horizontal: _isTouch ? 28 : 14, vertical: _isTouch ? 14 : 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  border: Border.all(color: _teal),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (itemIconAsset(info.item) != null) ...[
                      ItemIcon(info.item!, size: _isTouch ? 24 : 16),
                      SizedBox(width: _isTouch ? 8 : 6),
                    ],
                    Flexible(
                      child: Text(label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _teal,
                              fontSize: _isTouch ? 16 : 12,
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold)),
                    ),
                  ]),
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
        if (m == null) {
          return const Positioned(left: 0, right: 0, bottom: 0, child: SizedBox.shrink());
        }
        final compact = m.compact;
        return Positioned(
          bottom: HudLayout.toastBottom(MediaQuery.sizeOf(context), compact: compact),
          left: 12,
          right: 12,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Align(
                    key: ValueKey(m.id),
                    alignment: Alignment.bottomCenter,
                    child: GestureDetector(
                      key: const ValueKey('hud-toast'),
                      onTap: () => GameToast.current.value = null,
                      child: Container(
                        constraints: BoxConstraints(maxWidth: compact ? 300 : 340),
                        padding: EdgeInsets.symmetric(
                            horizontal: compact ? 10 : 12, vertical: compact ? 6 : 9),
                        decoration: BoxDecoration(
                          color: _ink.withValues(alpha: compact ? 0.72 : 0.82),
                          border: Border.all(color: m.color.withValues(alpha: compact ? 0.45 : 0.55)),
                          borderRadius: BorderRadius.circular(compact ? 6 : 8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (m.portrait == null && itemIconAsset(m.item) != null) ...[
                            ItemIcon(m.item!, size: compact ? 16 : 32),
                            SizedBox(width: compact ? 6 : 10),
                          ],
                          if (m.portrait != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.asset(m.portrait!, width: 44, height: 44, filterQuality: FilterQuality.none),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (m.title.isNotEmpty)
                                  Text(m.title,
                                      style: TextStyle(
                                          color: m.color.withValues(alpha: compact ? 0.9 : 1),
                                          fontSize: compact ? 10 : 11,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: compact ? 1 : 1.5)),
                                if (m.body.isNotEmpty) ...[
                                  if (m.title.isNotEmpty) SizedBox(height: compact ? 2 : 3),
                                  Text(m.body,
                                      maxLines: compact ? 2 : 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: Colors.white.withValues(
                                              alpha: m.title.isEmpty
                                                  ? (compact ? 0.75 : 0.85)
                                                  : (compact ? 0.55 : 0.65)),
                                          fontSize: compact ? 10 : 11,
                                          height: 1.35)),
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


/// The creature journal: a handheld field tablet with a grid of entries
/// (silhouette until seen, sketch when seen, portrait + lore when befriended)
/// and a detail pane with the set-companion button. Wide layouts split list |
/// detail on one screen; narrow stacks them.
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
  late int _tab = (Journal.focusTab ?? Journal.activeTab).clamp(0, Journal.tabSystem);

  @override
  void initState() {
    super.initState();
    Journal.activeTab = _tab;
    Journal.tabTick.addListener(_onTabTick);
  }

  @override
  void dispose() {
    Journal.tabTick.removeListener(_onTabTick);
    super.dispose();
  }

  void _onTabTick() {
    final t = Journal.focusTab;
    if (t == null || !mounted) return;
    setState(() {
      _tab = t.clamp(0, Journal.tabSystem);
      Journal.activeTab = _tab;
    });
  }

  void _setTab(int i) {
    setState(() {
      _tab = i;
      Journal.activeTab = i;
      Journal.focusTab = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.78),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920, maxHeight: 640),
              child: ValueListenableBuilder<int>(
                valueListenable: Bonds.revision,
                builder: (_, __, ___) => LayoutBuilder(builder: (context, box) {
                  final wide =
                      box.maxWidth > box.maxHeight * 1.15 && box.maxWidth >= 560;
                  return _TabletShell(
                    child: switch (_tab) {
                      Journal.tabQuests => _questsBody(wide: wide),
                      Journal.tabItems => _itemsBody(wide: wide),
                      Journal.tabMemories => _memoriesBody(wide: wide),
                      Journal.tabSystem => _systemBody(wide: wide),
                      _ => _creaturesBody(wide: wide),
                    },
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemsBody({required bool wide}) {
    return Column(children: [
      _header(close: true),
      const Expanded(child: EquipmentBody()),
    ]);
  }

  Widget _creaturesBody({required bool wide}) {
    final grid = _grid(wide ? 3 : 2);
    final detail = _Detail(id: _sel);
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          flex: 5,
          child: Column(children: [
            _header(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: grid,
              ),
            ),
          ]),
        ),
        const _TabletDivider(),
        Expanded(
          flex: 4,
          child: Stack(children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 36, 8),
              child: detail,
            ),
            Positioned(right: 0, top: 0, child: _closeButton()),
          ]),
        ),
      ]);
    }
    return Column(children: [
      _header(close: true),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Column(children: [
            grid,
            const SizedBox(height: 12),
            const _TabletHairline(),
            const SizedBox(height: 12),
            detail,
          ]),
        ),
      ),
    ]);
  }

  Widget _questsBody({required bool wide}) {
    final list = _questsPage(close: !wide);
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: 5, child: list),
        const _TabletDivider(),
        Expanded(
          flex: 4,
          child: Stack(children: [
            const SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(12, 8, 36, 8),
              child: _QuestsHint(),
            ),
            Positioned(right: 0, top: 0, child: _closeButton()),
          ]),
        ),
      ]);
    }
    return list;
  }

  Widget _memoriesBody({required bool wide}) {
    final list = _memoriesPage(close: !wide);
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: 5, child: list),
        const _TabletDivider(),
        Expanded(
          flex: 4,
          child: Stack(children: [
            const SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(12, 8, 36, 8),
              child: _MemoriesHint(),
            ),
            Positioned(right: 0, top: 0, child: _closeButton()),
          ]),
        ),
      ]);
    }
    return list;
  }

  Widget _systemBody({required bool wide}) {
    final page = _systemPage(close: !wide);
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: 5, child: page),
        const _TabletDivider(),
        Expanded(
          flex: 4,
          child: Stack(children: [
            const SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(12, 8, 36, 8),
              child: _SystemHint(),
            ),
            Positioned(right: 0, top: 0, child: _closeButton()),
          ]),
        ),
      ]);
    }
    return page;
  }

  Widget _closeButton() => IconButton(
        tooltip: 'Close',
        onPressed: Journal.hide,
        icon: Icon(Icons.close, color: _inkSoft.withValues(alpha: 0.9)),
      );

  Widget _tabs() {
    Widget chip(String label, int i) {
      final on = _tab == i;
      return GestureDetector(
        onTap: () => _setTab(i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: on ? _teal.withValues(alpha: 0.15) : Colors.transparent,
            border: Border.all(color: on ? _teal : _inkSoft.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? _teal : _inkSoft,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
        ),
      );
    }

    return Wrap(spacing: 6, runSpacing: 4, children: [
      chip('CREATURES', Journal.tabCreatures),
      chip('QUESTS', Journal.tabQuests),
      chip('ITEMS', Journal.tabItems),
      chip('MEMORIES', Journal.tabMemories),
      chip('SYSTEM', Journal.tabSystem),
    ]);
  }

  Widget _header({bool close = false}) {
    const count = TextStyle(color: _inkSoft, fontSize: 12, fontWeight: FontWeight.w600);
    final jobs = Quests.activeJobs.length;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('MENU',
                style: TextStyle(color: _inkDark, fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 3)),
          ),
          const SizedBox(height: 4),
          _tabs(),
          const SizedBox(height: 4),
          Wrap(spacing: 10, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Befriended ${Bonds.befriendedCount}/${Bonds.total}', style: count),
            Text('Memories ${Memories.progressLabel}', style: count),
            Text('Jobs $jobs · ${Quests.turnedInCount} done', style: count),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/images/ui/crystal_16@2x.png',
                  width: 14, height: 14, filterQuality: FilterQuality.none),
              const SizedBox(width: 3),
              Text('${Bonds.glimmer} glimmer', style: count),
            ]),
          ]),
        ]),
      ),
      if (close) _closeButton(),
    ]);
  }

  Widget _questsPage({bool close = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(close: close),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8, bottom: 8, right: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('JOBS',
                style: TextStyle(color: _inkDark, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 6),
            if (Quests.activeJobs.isEmpty && Quests.turnedInCount == 0)
              const Text(
                'Lantern Town\'s job board posts woods and city errands. Spend glimmer at Mira\'s stall for gear.',
                style: TextStyle(color: _inkSoft, fontSize: 12, height: 1.55),
              )
            else ...[
              for (final q in Quests.catalog)
                if (Quests.status(q.id) != QuestStatus.available &&
                    Quests.status(q.id) != QuestStatus.locked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '· ${q.title} — ${switch (Quests.status(q.id)) {
                        QuestStatus.accepted => q.acceptedJournalLabel,
                        QuestStatus.done => 'ready to turn in',
                        QuestStatus.turnedIn => 'done',
                        _ => '',
                      }}',
                      style: const TextStyle(color: _inkSoft, fontSize: 12, height: 1.4),
                    ),
                  ),
            ],
          ]),
        ),
      ),
    ]);
  }

  Widget _memoriesPage({bool close = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(close: close),
      Expanded(
        child: AnimatedBuilder(
          animation: Memories.foundNotifier,
          builder: (_, __) {
            final found = Memories.found;
            return SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8, bottom: 8, right: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('COLLECTED  ·  ${Memories.progressLabel}',
                    style: const TextStyle(
                        color: _inkDark, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 10),
                if (found == 0)
                  const Text(
                    'No memories yet. Seek glowing fragments across Elysium.',
                    style: TextStyle(color: _inkSoft, fontSize: 12, height: 1.55),
                  )
                else
                  for (var i = 1; i <= Memories.total; i++)
                    _JournalMemoryRow(
                      index: i,
                      unlocked: Memories.has(i),
                      onPlay: Memories.has(i) ? () => Memories.replay(i) : null,
                    ),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  Widget _systemPage({bool close = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(close: close),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8, bottom: 8, right: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('HUB',
                style: TextStyle(color: _inkDark, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 8),
            _SystemBtn(
              label: 'RESUME',
              filled: true,
              onTap: Journal.hide,
            ),
            const SizedBox(height: 8),
            _SystemBtn(
              label: 'ITEMS',
              color: const Color(0xFFFFE08A),
              onTap: () => _setTab(Journal.tabItems),
            ),
            const SizedBox(height: 8),
            _SystemBtn(
              label: 'TITLE SCREEN',
              color: _inkSoft,
              onTap: () async {
                final go = Journal.returnToTitle;
                if (go == null) return;
                await go(context);
              },
            ),
            const SizedBox(height: 16),
            const _JournalAudioPanel(),
            const SizedBox(height: 12),
            const AppVersionLabel(fontSize: 10),
          ]),
        ),
      ),
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

class _QuestsHint extends StatelessWidget {
  const _QuestsHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('FIELD WORK',
            style: TextStyle(color: _inkDark, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
        SizedBox(height: 8),
        Text(
          'Accept jobs at Lantern Town\'s board. Turn them in there when ready. Salvage and key items live under Items (I).',
          style: TextStyle(color: _inkSoft, fontSize: 12, height: 1.55),
        ),
      ]),
    );
  }
}

class _MemoriesHint extends StatelessWidget {
  const _MemoriesHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ECHOES',
            style: TextStyle(color: _inkDark, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
        SizedBox(height: 8),
        Text(
          'Recovered memory fragments can be replayed here. Seek purple crystals in the world to fill this log.',
          style: TextStyle(color: _inkSoft, fontSize: 12, height: 1.55),
        ),
      ]),
    );
  }
}

class _SystemHint extends StatelessWidget {
  const _SystemHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('FIELD SLATE',
            style: TextStyle(color: _inkDark, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
        SizedBox(height: 8),
        Text(
          'This tablet is your Menu. Esc / J closes it. Items (I) holds salvage and key items. Title Screen saves and leaves the run.',
          style: TextStyle(color: _inkSoft, fontSize: 12, height: 1.55),
        ),
      ]),
    );
  }
}

class _JournalMemoryRow extends StatelessWidget {
  final int index;
  final bool unlocked;
  final Future<void> Function()? onPlay;
  const _JournalMemoryRow({required this.index, required this.unlocked, this.onPlay});

  @override
  Widget build(BuildContext context) {
    final roman = ['I', 'II', 'III', 'IV', 'V'][index - 1];
    final title = unlocked ? Memories.titleFor(index) : '??????';
    const accent = Color(0xFF88CCFF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPlay == null ? null : () => onPlay!(),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _cardFace,
              border: Border.all(color: unlocked ? accent.withValues(alpha: 0.45) : _screenEdge),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Text(roman,
                    style: TextStyle(
                        color: unlocked ? accent : _inkSoft.withValues(alpha: 0.45),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          color: unlocked ? _inkDark : _inkSoft.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontStyle: unlocked ? FontStyle.normal : FontStyle.italic,
                          letterSpacing: 0.5)),
                ),
                if (unlocked)
                  const Text('REPLAY',
                      style: TextStyle(
                          color: accent, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final Color color;
  const _SystemBtn({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.color = _teal,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: filled ? color : color.withValues(alpha: 0.7)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: TextStyle(
                  color: filled ? _ink : color,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  fontSize: 13)),
        ),
      ),
    );
  }
}

class _JournalAudioPanel extends StatelessWidget {
  const _JournalAudioPanel();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AudioSettings.musicVolume,
        AudioSettings.sfxVolume,
        AudioSettings.musicOn,
        AudioSettings.sfxOn,
      ]),
      builder: (_, __) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        decoration: BoxDecoration(
          color: _cardFace,
          border: Border.all(color: _screenEdge),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('AUDIO',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _inkSoft, fontSize: 10, letterSpacing: 2.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _JournalAudioRow(
              label: 'MUSIC',
              volume: AudioSettings.musicVolume.value,
              enabled: AudioSettings.musicOn.value,
              color: _teal,
              onVolume: AudioSettings.setMusicVolume,
              onEnabled: AudioSettings.setMusicOn,
            ),
            const SizedBox(height: 4),
            _JournalAudioRow(
              label: 'SFX',
              volume: AudioSettings.sfxVolume.value,
              enabled: AudioSettings.sfxOn.value,
              color: const Color(0xFFFFE08A),
              onVolume: AudioSettings.setSfxVolume,
              onEnabled: AudioSettings.setSfxOn,
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalAudioRow extends StatelessWidget {
  final String label;
  final double volume;
  final bool enabled;
  final Color color;
  final ValueChanged<double> onVolume;
  final ValueChanged<bool> onEnabled;

  const _JournalAudioRow({
    required this.label,
    required this.volume,
    required this.enabled,
    required this.color,
    required this.onVolume,
    required this.onEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (volume * 100).round();
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label,
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () => onEnabled(!enabled),
          icon: Icon(enabled ? Icons.volume_up : Icons.volume_off,
              size: 18, color: enabled ? color : _inkSoft),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: color.withValues(alpha: enabled ? 0.9 : 0.25),
              inactiveTrackColor: _inkSoft.withValues(alpha: 0.25),
              thumbColor: enabled ? color : _inkSoft,
            ),
            child: Slider(
              value: volume.clamp(0.0, 1.0),
              onChanged: enabled ? onVolume : null,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('$pct%',
              textAlign: TextAlign.right,
              style: TextStyle(color: _inkSoft.withValues(alpha: 0.9), fontSize: 10)),
        ),
      ],
    );
  }
}

// Journal palette: teal HUD on dark glass (matches Echoes HUD `#00FFCC`).
const _inkDark = Color(0xFFE6F7F3);
const _inkSoft = Color(0xFF8AABB0);
const _inkGreen = _teal;
const _screenEdge = Color(0xFF1A2A34);
const _bezelHi = Color(0xFF3A4555);
const _bezelLo = Color(0xFF0A0C12);
const _glass = Color(0xFF0B1218);
const _cardFace = Color(0xFF121A22);

/// Single handheld field tablet: dark metal bezel + cool glass screen.
/// Content insets: 14 / 12 / 14 / 12 inside the screen bed.
class _TabletShell extends StatelessWidget {
  final Widget child;
  const _TabletShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A303C), Color(0xFF141820), _bezelLo],
        ),
        border: Border.all(color: _bezelHi, width: 2),
        boxShadow: [
          BoxShadow(color: _teal.withValues(alpha: 0.1), blurRadius: 28, spreadRadius: 1),
          BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 18, offset: const Offset(0, 10)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(children: [
        // Camera / speaker strip
        Container(
          width: 40,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0xFF151820),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: _bezelHi.withValues(alpha: 0.5)),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 4),
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _teal.withValues(alpha: 0.55),
              boxShadow: [BoxShadow(color: _teal.withValues(alpha: 0.35), blurRadius: 4)],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0E1820), _glass],
              ),
              border: Border.all(color: _teal.withValues(alpha: 0.22)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: child,
          ),
        ),
        const SizedBox(height: 8),
        // Home indicator
        Container(
          width: 52,
          height: 4,
          decoration: BoxDecoration(
            color: _bezelHi.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ]),
    );
  }
}

class _TabletDivider extends StatelessWidget {
  const _TabletDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      color: _teal.withValues(alpha: 0.22),
    );
  }
}

class _TabletHairline extends StatelessWidget {
  const _TabletHairline();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: _screenEdge);
  }
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
      child: LayoutBuilder(builder: (context, box) {
        final small = box.maxWidth < 100;
        return Stack(children: [
          Container(
            padding: small ? const EdgeInsets.fromLTRB(6, 6, 6, 8) : const EdgeInsets.fromLTRB(8, 8, 8, 10),
            decoration: BoxDecoration(
              color: _cardFace,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? _teal : _screenEdge,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AspectRatio(
                aspectRatio: 1,
                child:
                    Image.asset(s.portraitAsset(_variant(id)), fit: BoxFit.contain, filterQuality: FilterQuality.none),
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
          if (companion)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: _teal.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(3)),
                child: const Text('WITH YOU',
                    style: TextStyle(color: Color(0xFF06060F), fontSize: 7, fontWeight: FontWeight.bold)),
              ),
            ),
        ]);
      }),
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
    final statusCol = friend ? _inkGreen : (known ? const Color(0xFFE0B050) : _inkSoft.withValues(alpha: 0.7));
    TextStyle label() =>
        TextStyle(color: _inkSoft.withValues(alpha: 0.9), fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold);
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
        Text(s.lore, style: body.copyWith(color: _teal.withValues(alpha: 0.85))),
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
              backgroundColor: companion ? _teal.withValues(alpha: 0.12) : _teal,
              side: BorderSide(color: companion ? _inkSoft : const Color(0xFF00C9A0)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: Text(companion ? 'SEND HOME' : 'SET AS COMPANION',
                style: TextStyle(
                    color: companion ? _inkDark : _ink,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    fontSize: 12)),
          ),
          if (companion)
            const Text('Walking with you',
                style: TextStyle(color: _inkGreen, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
    ]);
  }
}

/// Pixel-art key item icon (`sprites/items/<id>.png`, see [itemIconAsset]).
/// Uses the 16px variant when drawn at 20px or smaller. Draws an empty box
/// for items without art.
class ItemIcon extends StatelessWidget {
  final String id;
  final double size;
  final bool dim;

  const ItemIcon(this.id, {super.key, this.size = 32, this.dim = false});

  @override
  Widget build(BuildContext context) {
    final path = itemIconAsset(id, small: size <= 20);
    if (path == null) return SizedBox(width: size, height: size);
    return Opacity(
      opacity: dim ? 0.7 : 1,
      child: Image.asset(path,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          errorBuilder: (_, __, ___) => SizedBox(width: size, height: size)),
    );
  }
}
