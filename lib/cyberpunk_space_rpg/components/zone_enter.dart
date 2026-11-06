import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../ui/mmo_feedback.dart';

/// Invisible district rect: crossing in fires the enter-zone banner once per
/// entry (re-arms when Kaela leaves). Used for in-map sub-zones like East Market.
class ZoneEnter extends GameComponent {
  final String title;
  final String regionId;

  bool _inside = false;

  ZoneEnter(
    Vector2 position,
    Vector2 size, {
    required this.title,
    required this.regionId,
  }) {
    this.position = position;
    this.size = size;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final player = gameRef.player;
    if (player == null) return;
    final pc = player.position + player.size / 2;
    final zone = Rect.fromLTWH(position.x, position.y, size.x, size.y);
    final inside = zone.contains(Offset(pc.x, pc.y));
    if (inside && !_inside) {
      MmoFeedback.enterZone(title, regionId: regionId);
    }
    _inside = inside;
  }
}
