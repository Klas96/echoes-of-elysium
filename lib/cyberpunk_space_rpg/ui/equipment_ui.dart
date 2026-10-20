import 'package:flutter/material.dart';

import '../creatures/bonds.dart';
import '../game/adventure.dart';
import '../game/progression.dart';

const _teal = Color(0xFF00FFCC);
const _amber = Color(0xFFFFE08A);
const _ink = Color(0xFF06060F);

/// Salvage gear + key items. Prefer the Menu tablet Items tab; [show]/[toggle]
/// redirect there when [openInMenu] is wired by the map host.
class Equipment {
  static final open = ValueNotifier<bool>(false);
  static void Function(bool open)? onOpenChanged;

  /// Optional: close the journal (or other overlays) without resuming.
  static void Function()? dismissOthers;

  /// When set, opens the Menu Items tab instead of the legacy overlay.
  static void Function()? openInMenu;
  static void Function()? toggleInMenu;
  static void Function()? hideInMenu;

  static void show() {
    if (openInMenu != null) {
      openInMenu!();
      return;
    }
    dismissOthers?.call();
    if (open.value) return;
    open.value = true;
    onOpenChanged?.call(true);
  }

  static void hide() {
    if (hideInMenu != null && !open.value) {
      hideInMenu!();
      return;
    }
    if (!open.value) return;
    open.value = false;
    onOpenChanged?.call(false);
  }

  static void toggle() {
    if (toggleInMenu != null) {
      toggleInMenu!();
      return;
    }
    open.value ? hide() : show();
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

class _EquipmentPanel extends StatelessWidget {
  const _EquipmentPanel();

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
              child: Container(
                decoration: BoxDecoration(
                  color: _ink,
                  border: Border.all(color: _teal.withValues(alpha: 0.45), width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ITEMS',
                                    style: TextStyle(
                                        color: _amber,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 3)),
                                SizedBox(height: 2),
                                Text('Salvage · Key items · Equip',
                                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: Equipment.hide,
                            icon: const Icon(Icons.close, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    const Expanded(child: EquipmentBody()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slots + salvage inventory + key items (embedded in Menu Items tab).
class EquipmentBody extends StatefulWidget {
  const EquipmentBody({super.key});

  @override
  State<EquipmentBody> createState() => _EquipmentBodyState();
}

class _EquipmentBodyState extends State<EquipmentBody> {
  String? _sel;
  /// True when [_sel] is a story key item (`Bonds.items`), not salvage gear.
  bool _selKey = false;

  @override
  void initState() {
    super.initState();
    final inv = Progression.inventory;
    if (inv.isNotEmpty) {
      _sel = inv.first;
      _selKey = false;
    } else {
      final keys = Bonds.items.toList()..sort();
      if (keys.isNotEmpty) {
        _sel = keys.first;
        _selKey = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([Progression.revision, Bonds.revision]),
      builder: (_, __) {
        final inv = Progression.inventory;
        final keys = Bonds.items.toList()..sort();
        if (_selKey) {
          if (_sel == null || !keys.contains(_sel)) {
            _selKey = false;
            _sel = inv.isNotEmpty ? inv.first : (keys.isNotEmpty ? keys.first : null);
            if (_sel != null && !inv.contains(_sel)) _selKey = true;
          }
        } else if (_sel != null && !inv.contains(_sel)) {
          _sel = inv.isNotEmpty
              ? inv.first
              : (keys.isNotEmpty ? keys.first : null);
          _selKey = _sel != null && !inv.contains(_sel);
        }
        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 480;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: _slotsPane()),
                Container(width: 1, color: Colors.white12),
                Expanded(flex: 6, child: _inventoryPane(inv, keys)),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(10),
            children: [
              _slotsPane(scrollable: false),
              const SizedBox(height: 12),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              _inventoryPane(inv, keys, scrollable: false),
            ],
          );
        });
      },
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
                if (eq != null) {
                  setState(() {
                    _sel = eq.id;
                    _selKey = false;
                  });
                }
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

  Widget _inventoryPane(List<String> inv, List<String> keys, {bool scrollable = true}) {
    final gearDetail =
        (!_selKey && _sel != null) ? Progression.catalog[_sel!] : null;
    final kids = <Widget>[
      const Text('INVENTORY',
          style: TextStyle(color: _teal, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      if (inv.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
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
                selected: !_selKey && id == _sel,
                equipped: Progression.equipped.values.contains(id),
                onTap: () => setState(() {
                  _sel = id;
                  _selKey = false;
                }),
              ),
          ],
        ),
      if (keys.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Text('KEY ITEMS',
            style: TextStyle(color: _amber, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in keys)
              _KeyItemTile(
                id: id,
                selected: _selKey && id == _sel,
                onTap: () => setState(() {
                  _sel = id;
                  _selKey = true;
                }),
              ),
          ],
        ),
      ],
      if (gearDetail != null) ...[
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
              Text(gearDetail.name,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(Progression.slotLabel(gearDetail.slot),
                  style: const TextStyle(color: _teal, fontSize: 10, letterSpacing: 2)),
              const SizedBox(height: 8),
              Text(gearDetail.blurb,
                  style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4)),
              const SizedBox(height: 8),
              Text(Progression.statsLine(gearDetail),
                  style: const TextStyle(color: _amber, fontSize: 12, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (Progression.equipped[gearDetail.slot.name] == gearDetail.id)
                    _ActionBtn(
                      label: 'UNEQUIP',
                      color: Colors.white54,
                      onTap: () => Progression.unequip(gearDetail.slot),
                    )
                  else
                    _ActionBtn(
                      label: 'EQUIP',
                      color: _teal,
                      onTap: () => Progression.equip(gearDetail.id),
                    ),
                ],
              ),
            ],
          ),
        ),
      ] else if (_selKey && _sel != null) ...[
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            border: Border.all(color: _amber.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(itemLabels[_sel!] ?? _sel!,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('KEY ITEM',
                  style: TextStyle(color: _amber, fontSize: 10, letterSpacing: 2)),
              const SizedBox(height: 8),
              const Text(
                'Story item — use it at locked doors, terminals, and creatures in the world. Cannot be equipped.',
                style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
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

class _KeyItemTile extends StatelessWidget {
  final String id;
  final bool selected;
  final VoidCallback onTap;

  const _KeyItemTile({required this.id, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final path = itemIconAsset(id);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? _amber.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
          border: Border.all(color: selected ? _amber : Colors.white24),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: path == null
                  ? const Center(
                      child: Text('·', style: TextStyle(color: Colors.white38, fontSize: 14)))
                  : Image.asset(path, fit: BoxFit.contain, filterQuality: FilterQuality.none),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(itemLabels[id] ?? id,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
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
