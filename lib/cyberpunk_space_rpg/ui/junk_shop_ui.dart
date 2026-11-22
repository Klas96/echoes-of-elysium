import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../creatures/bonds.dart';
import '../game/trade.dart';

bool get _isTouch =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

const _teal = Color(0xFF00FFCC);
const _olive = Color(0xFFB8C48A);
const _ink = Color(0xFF06060F);

/// Elias's Canal Works junk stall (EOE-110): sell / trash drone salvage,
/// buy back dumped and recently sold junk.
class JunkShop {
  static final open = ValueNotifier<bool>(false);
  static void Function(bool open)? onOpenChanged;
  static void Function()? dismissOthers;

  /// 0 = BUY (stock + junk buyback), 1 = SELL / TRASH.
  static final tab = ValueNotifier<int>(0);

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

class JunkShopOverlay extends StatelessWidget {
  const JunkShopOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: JunkShop.open,
      builder: (_, open, __) =>
          open ? const _JunkShopPanel() : const SizedBox.shrink(),
    );
  }
}

class _JunkShopPanel extends StatelessWidget {
  const _JunkShopPanel();

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
                border: Border.all(color: _olive.withValues(alpha: 0.7), width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  Bonds.revision,
                  Trade.revision,
                  JunkShop.tab,
                ]),
                builder: (_, __) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'ELIAS\' JUNK STALL',
                            style: TextStyle(
                              color: _olive,
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
                          onPressed: JunkShop.hide,
                          icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                        ),
                      ],
                    ),
                    Text(
                      JunkShop.tab.value == 0
                          ? 'Buy back what you dumped or sold. Canal Works scrap only.'
                          : 'Sell junk for glimmer, or trash it onto Elias\'s pile for free.',
                      style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      _tabButton('BUY', 0),
                      const SizedBox(width: 8),
                      _tabButton('SELL', 1),
                    ]),
                    const SizedBox(height: 12),
                    if (JunkShop.tab.value == 0) ..._buySection() else ..._sellSection(),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: JunkShop.hide,
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
    final on = JunkShop.tab.value == index;
    return Expanded(
      child: TextButton(
        onPressed: () => JunkShop.tab.value = index,
        style: TextButton.styleFrom(
          backgroundColor: _olive.withValues(alpha: on ? 0.16 : 0.03),
          side: BorderSide(color: _olive.withValues(alpha: on ? 0.8 : 0.2)),
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        child: Text(label,
            style: TextStyle(
                color: on ? _olive : Colors.white38,
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

  List<Widget> _buySection() {
    final stock = Trade.eliasStock;
    final junkIdx = Trade.junkBuybackIndices;
    return [
      _heading('TRASHED PILE'),
      if (stock.isEmpty) _empty('Nothing dumped yet. Trash junk on the SELL tab.'),
      for (var i = 0; i < stock.length; i++)
        _tradeRow(
          title: Trade.nameOf(stock[i]),
          blurb: 'Dumped scrap · Elias kept it',
          button: '${stock[i].price}◆',
          onPressed: Bonds.glimmer >= stock[i].price ? () => Trade.buyEliasStock(i) : null,
        ),
      _heading('RECENT SALES'),
      if (junkIdx.isEmpty) _empty('Sold junk waits here for a while.'),
      for (var j = 0; j < junkIdx.length; j++)
        _tradeRow(
          title: Trade.nameOf(Trade.buyback[junkIdx[j]]),
          blurb: 'Sold scrap · buy it back',
          button: '${Trade.buyback[junkIdx[j]].price}◆',
          onPressed: Bonds.glimmer >= Trade.buyback[junkIdx[j]].price
              ? () => Trade.buyBackJunk(j)
              : null,
        ),
    ];
  }

  List<Widget> _sellSection() {
    final junk = Trade.junk;
    return [
      Row(children: [
        Expanded(child: _heading('YOUR JUNK')),
        if (junk.isNotEmpty)
          TextButton(
            onPressed: Trade.sellAllJunk,
            child: Text('SELL ALL  +${Trade.junkValue}◆',
                style: const TextStyle(
                    color: _olive, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
      ]),
      if (junk.isEmpty) _empty('No junk. Downed drones drop salvage.'),
      for (final e in junk.entries) ...[
        _tradeRow(
          title: '${Trade.junkCatalog[e.key]!.name}  ×${e.value}',
          blurb: Trade.junkCatalog[e.key]!.blurb,
          button: 'SELL  ${Trade.junkCatalog[e.key]!.value}◆',
          onPressed: () => Trade.sellJunk(e.key),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Trade.trashJunk(e.key),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.04),
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
              child: const Text('TRASH → ELIAS',
                  style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
            ),
          ),
        ),
      ],
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
              backgroundColor: _olive.withValues(alpha: on ? 0.18 : 0.06),
              side: BorderSide(color: _olive.withValues(alpha: on ? 0.8 : 0.25)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: Text(button,
                style: TextStyle(
                    color: on ? _olive : Colors.white24,
                    fontWeight: FontWeight.bold,
                    fontSize: 11)),
          ),
        ]),
      ),
    );
  }
}
