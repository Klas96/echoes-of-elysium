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
                animation: Listenable.merge([Bonds.revision, Progression.revision]),
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
                    const Text(
                      'Salvage and colony trinkets. Pay in glimmer.',
                      style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    ...Shop.offers.map(_offerRow),
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
