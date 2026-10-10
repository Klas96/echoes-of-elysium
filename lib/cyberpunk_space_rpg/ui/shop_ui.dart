import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../creatures/bonds.dart';
import '../game/progression.dart';
import '../game/trade.dart';

bool get _isTouch =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

const _teal = Color(0xFF00FFCC);
const _amber = Color(0xFFFFE08A);
const _ink = Color(0xFF06060F);

/// A glimmer shop listing (Mira in Lantern Town).
class ShopOffer {
  final String itemId;
  final int price;
  const ShopOffer(this.itemId, this.price);
}

class Shop {
  static final open = ValueNotifier<bool>(false);
  static void Function(bool open)? onOpenChanged;
  static void Function()? dismissOthers;

  /// 0 = BUY, 1 = SELL (junk, spare gear, buyback).
  static final tab = ValueNotifier<int>(0);

  static const offers = <ShopOffer>[
    ShopOffer('scrap_plating', 8),
    ShopOffer('pulse_optic', 12),
    ShopOffer('swarm_thrusters', 10),
    ShopOffer('barrier_coil', 16),
    ShopOffer('lantern_charm', 20),
  ];

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

class ShopOverlay extends StatelessWidget {
  const ShopOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Shop.open,
      builder: (_, open, __) =>
          open ? const _ShopPanel() : const SizedBox.shrink(),
    );
  }
}

class _ShopPanel extends StatelessWidget {
  const _ShopPanel();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
              decoration: BoxDecoration(
                color: _ink.withValues(alpha: 0.96),
                border: Border.all(color: _amber.withValues(alpha: 0.7), width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedBuilder(
                animation: Listenable.merge(
                    [Bonds.revision, Progression.revision, Trade.revision, Shop.tab]),
                builder: (_, __) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'MIRA\'S STALL',
                            style: TextStyle(
                              color: _amber,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                        Text(
                          '${Bonds.glimmer} glimmer',
                          style: const TextStyle(color: _teal, fontSize: 12, letterSpacing: 1),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: Shop.hide,
                          icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                        ),
                      ],
                    ),
                    Text(
                      Shop.tab.value == 0
                          ? 'Salvage and colony trinkets. Pay in glimmer.'
                          : 'Mira buys drone junk and spare kit. Changed your mind? Buy it back.',
                      style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      _tabButton('BUY', 0),
                      const SizedBox(width: 8),
                      _tabButton('SELL', 1),
                    ]),
                    const SizedBox(height: 12),
                    if (Shop.tab.value == 0) ...Shop.offers.map(_offerRow) else ..._sellSection(),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: Shop.hide,
                        child: Text(
                          _isTouch ? 'DONE' : 'DONE  (Esc)',
                          style: const TextStyle(color: Colors.white38, letterSpacing: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final on = Shop.tab.value == index;
    return Expanded(
      child: TextButton(
        onPressed: () => Shop.tab.value = index,
        style: TextButton.styleFrom(
          backgroundColor: _amber.withValues(alpha: on ? 0.16 : 0.03),
          side: BorderSide(color: _amber.withValues(alpha: on ? 0.8 : 0.2)),
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        child: Text(label,
            style: TextStyle(
                color: on ? _amber : Colors.white38,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 2)),
      ),
    );
  }

  static Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(text,
            style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
      );

  static Widget _empty(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(color: Colors.white24, fontSize: 11)),
      );

  List<Widget> _sellSection() {
    final junk = Trade.junk;
    final spare = Trade.spareGear;
    final back = Trade.buyback;
    return [
      Row(children: [
        Expanded(child: _heading('JUNK')),
        if (junk.isNotEmpty)
          TextButton(
            onPressed: Trade.sellAllJunk,
            child: Text('SELL ALL  +${Trade.junkValue}◆',
                style: const TextStyle(
                    color: _amber, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
      ]),
      if (junk.isEmpty) _empty('No junk. Downed drones drop salvage.'),
      for (final e in junk.entries)
        _tradeRow(
          title: '${Trade.junkCatalog[e.key]!.name}  ×${e.value}',
          blurb: Trade.junkCatalog[e.key]!.blurb,
          button: 'SELL  ${Trade.junkCatalog[e.key]!.value}◆',
          onPressed: () => Trade.sellJunk(e.key),
        ),
      _heading('SPARE GEAR'),
      if (spare.isEmpty) _empty('Nothing spare. Equipped gear is never sold.'),
      for (final id in spare)
        _tradeRow(
          title: Progression.catalog[id]!.name,
          blurb: Progression.statsLine(Progression.catalog[id]!),
          button: 'SELL  ${Trade.gearSellPrice(id)}◆',
          onPressed: () => Trade.sellGear(id),
        ),
      _heading('BUYBACK'),
      if (back.isEmpty) _empty('Sold items wait here for a while.'),
      for (var i = 0; i < back.length; i++)
        _tradeRow(
          title: Trade.nameOf(back[i]),
          blurb: back[i].kind == 'gear' ? 'Gear' : 'Junk',
          button: '${back[i].price}◆',
          onPressed: Bonds.glimmer >= back[i].price ? () => Trade.buyBack(i) : null,
        ),
    ];
  }

  Widget _tradeRow({
    required String title,
    required String blurb,
    required String button,
    required VoidCallback? onPressed,
  }) {
    final on = onPressed != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 2),
              Text(blurb, style: const TextStyle(color: Colors.white54, fontSize: 10, height: 1.3)),
            ]),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              backgroundColor: _amber.withValues(alpha: on ? 0.18 : 0.06),
              side: BorderSide(color: _amber.withValues(alpha: on ? 0.8 : 0.25)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: Text(button,
                style: TextStyle(
                    color: on ? _amber : Colors.white24,
                    fontWeight: FontWeight.bold,
                    fontSize: 11)),
          ),
        ]),
      ),
    );
  }

  Widget _offerRow(ShopOffer offer) {
    final item = Progression.catalog[offer.itemId];
    if (item == null) return const SizedBox.shrink();
    final owned = Progression.inventory.contains(offer.itemId);
    final canBuy = !owned && Bonds.glimmer >= offer.price;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(item.blurb,
                      style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.3)),
                  const SizedBox(height: 4),
                  Text(Progression.statsLine(item),
                      style: const TextStyle(color: _teal, fontSize: 10, letterSpacing: 0.5)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            owned
                ? const Text('OWNED',
                    style: TextStyle(color: Colors.white24, fontSize: 11, letterSpacing: 1))
                : TextButton(
                    onPressed: canBuy
                        ? () => Progression.buyWithGlimmer(offer.itemId, offer.price)
                        : null,
                    style: TextButton.styleFrom(
                      backgroundColor: _amber.withValues(alpha: canBuy ? 0.18 : 0.06),
                      side: BorderSide(color: _amber.withValues(alpha: canBuy ? 0.8 : 0.25)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    child: Text(
                      '${offer.price}◆',
                      style: TextStyle(
                        color: canBuy ? _amber : Colors.white24,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
