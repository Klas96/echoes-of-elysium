import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../creatures/bonds.dart';
import '../game/progression.dart';

bool get _isTouch =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

const _teal = Color(0xFF00FFCC);
const _amber = Color(0xFFFFE08A);
const _ink = Color(0xFF06060F);

/// Inventory / equipment panel. Pauses the game like the journal.
class Equipment {
  static final open = ValueNotifier<bool>(false);
  static void Function(bool open)? onOpenChanged;

  /// Optional: close the journal (or other overlays) without resuming.
  static void Function()? dismissOthers;

  static void show() {
    dismissOthers?.call();
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

class EquipmentButton extends StatelessWidget {
  const EquipmentButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: Equipment.show,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          border: Border.all(color: _amber.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _isTouch ? 'GEAR' : 'I  GEAR',
          style: const TextStyle(
            color: _amber,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

class EquipmentOverlay extends StatelessWidget {
  const EquipmentOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Equipment.open,
      builder: (_, open, __) =>
          open ? const _EquipmentPanel() : const SizedBox.shrink(),
    );
  }
}

class _EquipmentPanel extends StatefulWidget {
  const _EquipmentPanel();

  @override
  State<_EquipmentPanel> createState() => _EquipmentPanelState();
}

class _EquipmentPanelState extends State<_EquipmentPanel> {
  String? _sel;

  @override
  void initState() {
    super.initState();
    final inv = Progression.inventory;
    _sel = inv.isNotEmpty ? inv.first : null;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<int>(
                valueListenable: Progression.revision,
                builder: (_, __, ___) {
                  final inv = Progression.inventory;
                  if (_sel != null && !inv.contains(_sel)) {
                    _sel = inv.isNotEmpty ? inv.first : null;
                  }
                  return Container(
                    decoration: BoxDecoration(
                      color: _ink,
                      border: Border.all(color: _teal.withValues(alpha: 0.45), width: 1.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        _header(),
                        const Divider(height: 1, color: Colors.white12),
                        Expanded(
                          child: LayoutBuilder(builder: (context, box) {
                            final wide = box.maxWidth >= 520;
                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 5, child: _slotsPane()),
                                  Container(width: 1, color: Colors.white12),
                                  Expanded(flex: 6, child: _inventoryPane(inv)),
                                ],
                              );
                            }
                            return ListView(
                              padding: const EdgeInsets.all(14),
                              children: [
                                _slotsPane(scrollable: false),
                                const SizedBox(height: 12),
                                const Divider(color: Colors.white12),
                                const SizedBox(height: 8),
                                _inventoryPane(inv, scrollable: false),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GEAR',
                    style: TextStyle(
                        color: _amber,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3)),
                SizedBox(height: 2),
                Text('Salvage · Equip · Survive',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: Bonds.revision,
            builder: (_, __, ___) => Text(
              '${Bonds.glimmer} glimmer',
              style: const TextStyle(color: _amber, fontSize: 11, letterSpacing: 1),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Close',
            onPressed: Equipment.hide,
            icon: const Icon(Icons.close, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _slotsPane({bool scrollable = true}) {
    final body = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('KAELA  ·  LV ${Progression.level}',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            '+${Progression.bonusDamage} DMG   ·   '
            '+${Progression.bonusHealth} HP   ·   '
            'RATE ${(Progression.fireCooldownMult * 100).round()}%',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 14),
          for (final slot in GearSlot.values) ...[
            _SlotCard(
              slot: slot,
              item: Progression.equippedIn(slot),
              selected: _sel != null && Progression.equipped[slot.name] == _sel,
              onTap: () {
                final eq = Progression.equippedIn(slot);
                if (eq != null) setState(() => _sel = eq.id);
              },
              onUnequip: () => Progression.unequip(slot),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
    return scrollable ? SingleChildScrollView(child: body) : body;
  }

  Widget _inventoryPane(List<String> inv, {bool scrollable = true}) {
    final detail = _sel == null ? null : Progression.catalog[_sel!];
    final kids = <Widget>[
      const Text('INVENTORY',
          style: TextStyle(color: _teal, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      if (inv.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No gear yet.\nDefeat UEC drones to salvage rifle parts, suit plating and relics.',
            style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
          ),
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in inv)
              _InvTile(
                item: Progression.catalog[id]!,
                selected: id == _sel,
                equipped: Progression.equipped.values.contains(id),
                onTap: () => setState(() => _sel = id),
              ),
          ],
        ),
      if (detail != null) ...[
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            border: Border.all(color: Colors.white12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(detail.name,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(Progression.slotLabel(detail.slot),
                  style: const TextStyle(color: _teal, fontSize: 10, letterSpacing: 2)),
              const SizedBox(height: 8),
              Text(detail.blurb,
                  style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4)),
              const SizedBox(height: 8),
              Text(Progression.statsLine(detail),
                  style: const TextStyle(color: _amber, fontSize: 12, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (Progression.equipped[detail.slot.name] == detail.id)
                    _ActionBtn(
                      label: 'UNEQUIP',
                      color: Colors.white54,
                      onTap: () => Progression.unequip(detail.slot),
                    )
                  else
                    _ActionBtn(
                      label: 'EQUIP',
                      color: _teal,
                      onTap: () => Progression.equip(detail.id),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ];

    final column = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: kids,
      ),
    );
    return scrollable ? SingleChildScrollView(child: column) : column;
  }
}

class _SlotCard extends StatelessWidget {
  final GearSlot slot;
  final GearItem? item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onUnequip;

  const _SlotCard({
    required this.slot,
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onUnequip,
  });

  @override
  Widget build(BuildContext context) {
    final filled = item != null;
    return InkWell(
      onTap: filled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? _teal.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: selected ? _teal : (filled ? Colors.white24 : Colors.white12),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: filled ? _amber.withValues(alpha: 0.5) : Colors.white12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                Progression.slotLabel(slot).substring(0, 1),
                style: TextStyle(
                  color: filled ? _amber : Colors.white24,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Progression.slotLabel(slot),
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10, letterSpacing: 2)),
                  const SizedBox(height: 2),
                  Text(
                    item?.name ?? 'Empty',
                    style: TextStyle(
                      color: filled ? Colors.white70 : Colors.white24,
                      fontSize: 13,
                      fontWeight: filled ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (item != null)
                    Text(Progression.statsLine(item!),
                        style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
            if (filled)
              TextButton(
                onPressed: onUnequip,
                child: const Text('×', style: TextStyle(color: Colors.white38, fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }
}

class _InvTile extends StatelessWidget {
  final GearItem item;
  final bool selected;
  final bool equipped;
  final VoidCallback onTap;

  const _InvTile({
    required this.item,
    required this.selected,
    required this.equipped,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? _teal.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
          border: Border.all(color: selected ? _teal : Colors.white24),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                if (equipped)
                  const Text('E',
                      style: TextStyle(color: _amber, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(Progression.slotLabel(item.slot),
                style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1.5)),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
