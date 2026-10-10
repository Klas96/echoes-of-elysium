import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../creatures/interaction.dart';
import '../game/travel.dart';

/// Invisible strip on a map border: walk into it to leave for [destLevel].
/// No portal glow — adjacent maps should feel like roads, not warp pads.
class MapEdgeExit extends GameComponent {
  final int destLevel;
  final String entrySide;
  final bool Function() canExit;
  final String lockedTitle;
  final String lockedBody;

  /// A beat to play before leaving (the region farewell); null = none now.
  final Future<void> Function()? Function()? beforeExit;
  bool _fired = false;
  bool _beat = false;
  bool _lockedHint = false;

  MapEdgeExit(
    Vector2 position,
    Vector2 size, {
    required this.destLevel,
    required this.entrySide,
    bool Function()? canExit,
    this.lockedTitle = 'PATH CLOSED',
    this.lockedBody = 'Not yet.',
    this.beforeExit,
  })  : canExit = canExit ?? (() => true) {
    this.position = position;
    this.size = size;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final player = gameRef.player;
    if (player == null || _beat) return;
    final pc = player.position + player.size / 2;
    final inside = pc.x >= position.x &&
        pc.x <= position.x + size.x &&
        pc.y >= position.y &&
        pc.y <= position.y + size.y;

    if (!inside) {
      _fired = false;
      _lockedHint = false;
      return;
    }
    if (_fired) return;

    if (!canExit()) {
      if (!_lockedHint) {
        _lockedHint = true;
        GameToast.show(lockedTitle, body: lockedBody, color: const Color(0xFFFFAABB), compact: true);
      }
      return;
    }

    _fired = true;
    final beat = beforeExit?.call();
    if (beat != null) {
      _beat = true;
      beat().then((_) {
        _beat = false;
        if (isMounted) _travel();
      });
      return;
    }
    _travel();
  }

  void _travel() {
    Travel.requestEdge(destLevel, entrySide: entrySide);
    if (!gameRef.overlays.isActive('edgeTravel')) {
      gameRef.overlays.add('edgeTravel');
    }
  }

  @override
  void render(Canvas canvas) {
    // Soft dust line so the opening reads as a road, not a void.
    final midY = size.y * 0.55;
    canvas.drawRect(
      Rect.fromLTWH(2, midY, size.x - 4, 2),
      Paint()..color = const Color(0xFF88AACC).withValues(alpha: 0.18),
    );
  }
}

/// Marks where Kaela appears when arriving from [side] (north/south/east/west).
class MapEntryPoint extends GameComponent {
  static final Map<String, Vector2> bySide = {};

  final String side;

  MapEntryPoint(Vector2 position, {required this.side}) {
    this.position = position;
    size = Vector2.all(32);
  }

  @override
  Future<void> onLoad() async {
    bySide[side] = position.clone();
    return super.onLoad();
  }

  @override
  void onRemove() {
    if (bySide[side] == position) bySide.remove(side);
    super.onRemove();
  }
}
