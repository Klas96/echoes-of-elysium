import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/building.dart';
import '../components/building_masks.dart';
import '../components/custom_player.dart';
import '../creatures/gate_components.dart';
import '../creatures/interaction.dart';
import '../creatures/obstacle_masks.dart';
import '../creatures/obstacles.dart';
import 'click_pathfinder.dart';
import 'debug_walk_grid.dart';
import 'game_debug.dart';
import 'game_state.dart';
import 'tileset_masks.dart';

enum _MaskKind { gate, building, tile, stump }

/// In-game block-mask editor (GameDebug). **Click** any solid to select it,
/// drag yellow boxes, F5/S saves. Gates, buildings, tileset props/tiles, stump.
class DebugMaskEditor extends GameComponent {
  static DebugMaskEditor? instance;
  static bool _hwInstalled = false;

  _MaskKind? _kind;
  ObstacleMaskId? gateId;
  Building? building;
  SweetrootStump? stump;
  GameComponent? host;
  String? tilesetName;
  int? tileLocalId;
  String? propName;
  bool editingOpen = false;
  int selectedRect = 0;

  _DragKind _drag = _DragKind.none;
  int _dragCorner = 0;
  Rect _dragStartRect = Rect.zero;
  Vector2 _dragStartWorld = Vector2.zero();

  static const _handle = 6.0;
  static const _hitSlop = 12.0;

  bool get hasSelection => host != null && _kind != null;

  String get selectionLabel {
    switch (_kind) {
      case _MaskKind.building:
        return building?.id ?? 'building';
      case _MaskKind.stump:
        return 'sweetroot_stump';
      case _MaskKind.tile:
        final p = propName ?? 'tile';
        return '$tilesetName#$tileLocalId $p';
      case _MaskKind.gate:
        return '${gateId?.name ?? "gate"}${editingOpen ? " open" : " closed"}';
      case null:
        return '?';
    }
  }

  static void installKeys() {
    if (_hwInstalled) return;
    _hwInstalled = true;
    HardwareKeyboard.instance.addHandler(_hwKey);
  }

  static bool _hwKey(KeyEvent event) {
    final ed = instance;
    if (ed == null || !GameDebug.isOn || !ed.hasSelection) return false;
    return ed.handleKey(event);
  }

  @override
  Future<void> onLoad() async {
    instance = this;
    installKeys();
    await ObstacleMasks.ensureLoaded();
    BuildingMasks.loadFromDisk();
    return super.onLoad();
  }

  @override
  void onRemove() {
    if (instance == this) instance = null;
    super.onRemove();
  }

  @override
  bool get isVisible => true;

  @override
  int get priority => LayerPriority.getAbovePriority(950);

  double get _artWidth {
    final h = host;
    if (h is Building) return h.def.w;
    if (h is AbilityGate) return h.artWidth;
    if (h is Boulder) return 96;
    if (h is HiddenPath || h is SweetrootStump) return 64;
    if (_kind == _MaskKind.tile) return 32;
    return switch (gateId) {
      ObstacleMaskId.bramble => 64.0,
      _ => 96.0,
    };
  }

  double get _k {
    final h = host;
    if (h == null) return 1;
    return h.size.x / _artWidth;
  }

  List<Rect> get _rects {
    switch (_kind) {
      case _MaskKind.building:
        return building == null ? const [] : [building!.def.collision];
      case _MaskKind.stump:
        return [SweetrootStump.collider];
      case _MaskKind.tile:
        return _localHitRects(host);
      case _MaskKind.gate:
        final id = gateId;
        if (id == null) return const [];
        return List.of(ObstacleMasks.rects(id, openState: editingOpen));
      case null:
        return const [];
    }
  }

  List<Rect> _localHitRects(GameComponent? c) {
    if (c == null) return const [];
    final out = <Rect>[];
    for (final h in c.children.whereType<ShapeHitbox>()) {
      if (!h.isSolid) continue;
      out.add(Rect.fromLTWH(h.position.x, h.position.y, h.size.x, h.size.y));
    }
    return out;
  }

  /// Apply edited rects. [preview] = drag frame: touch only the selection
  /// (no world-wide hitbox fan-out / walk-grid bake — that lagged hard).
  void _commit(List<Rect> next, {bool preview = false}) {
    switch (_kind) {
      case _MaskKind.building:
        if (building == null || next.isEmpty) return;
        building!.applyColliderRects(next);
        buildingDefs[building!.id]?.collision = next.first;
      case _MaskKind.stump:
        if (stump == null || next.isEmpty) return;
        stump!.applyColliderRects(next);
        if (!preview) {
          for (final s in gameRef.query<SweetrootStump>(onlyVisible: false)) {
            s.applyColliderRects(next);
          }
        }
      case _MaskKind.tile:
        if (preview) {
          final h = host;
          if (h != null) _setHostHitboxes(h, next);
        } else {
          _applyTileRects(next);
        }
      case _MaskKind.gate:
        final id = gateId;
        if (id == null) return;
        ObstacleMasks.setRects(id, openState: editingOpen, rects: next);
        if (preview) {
          _previewGateColliders();
        } else {
          applyLiveGates(gameRef);
          _previewGateColliders();
        }
      case null:
        break;
    }
    if (!preview) _invalidateWalkGrid();
  }

  void _invalidateWalkGrid() {
    if (!hasGameRef) return;
    for (final g in gameRef.query<DebugWalkGrid>()) {
      g.invalidate();
    }
  }

  void _applyTileRects(List<Rect> next) {
    // Same tileset tile / prop design → every instance shares the box
    // (e.g. all four standing_stone placements).
    for (final c in _matchingTileHosts()) {
      _setHostHitboxes(c, next);
    }
  }

  Iterable<GameComponent> _matchingTileHosts() sync* {
    final prop = propName;
    final tid = tileLocalId;
    for (final c in gameRef.query<GameDecorationWithCollision>(onlyVisible: false)) {
      if (_tileHostMatches(c, prop, tid)) yield c;
    }
    for (final c in gameRef.query<TileWithCollision>(onlyVisible: false)) {
      if (_tileHostMatches(c, prop, tid)) yield c;
    }
  }

  bool _tileHostMatches(GameComponent c, String? prop, int? tid) {
    final p = c.properties?['prop']?.toString();
    if (prop != null && prop.isNotEmpty && prop != 'unknown' && prop != 'tile') {
      return p == prop;
    }
    // Fall back: same resolved tile shape as the selection.
    if (tid == null || tid < 0 || identical(c, host)) return identical(c, host);
    final local = _localHitRects(c);
    final resolved = TilesetMasks.resolveTileId(
      tileset: tilesetName ?? TilesetMasks.tilesetForLevel(),
      propName: p,
      rects: local,
    );
    return resolved == tid;
  }

  void _setHostHitboxes(GameComponent c, List<Rect> next) {
    for (final box in c.children.whereType<ShapeHitbox>().toList()) {
      if (box.isSolid) box.removeFromParent();
    }
    for (final r in next) {
      c.add(RectangleHitbox(
        position: Vector2(r.left, r.top),
        size: Vector2(r.width, r.height),
        isSolid: true,
      ));
    }
  }

  static void applyLiveGates(BonfireGameInterface game) {
    for (final g in game.query<AbilityGate>(onlyVisible: false)) {
      g.refreshColliders();
    }
    for (final b in game.query<Boulder>(onlyVisible: false)) {
      b.refreshColliders();
    }
    for (final h in game.query<HiddenPath>(onlyVisible: false)) {
      h.refreshColliders();
    }
  }

  Vector2 _screenToWorld(Vector2 screen) {
    final camCenter = gameRef.camera.viewfinder.position;
    final screenCenter = gameRef.size / 2;
    final zoom = gameRef.camera.viewfinder.zoom;
    return camCenter + (screen - screenCenter) / zoom;
  }

  bool onScreenTap(Vector2 screen) {
    if (!GameDebug.isOn || !hasGameRef) return false;
    return onWorldTap(_screenToWorld(screen));
  }

  bool onScreenPanStart(Vector2 screen) {
    if (!GameDebug.isOn || !hasGameRef || !hasSelection) return false;
    return _beginDrag(_screenToWorld(screen));
  }

  void onScreenPanUpdate(Vector2 screen) {
    if (_drag == _DragKind.none || host == null) return;
    _updateDrag(_screenToWorld(screen));
  }

  void onScreenPanEnd() {
    if (_drag != _DragKind.none && hasSelection) {
      // Fan out shared shapes + walk grid once per gesture.
      _commit(List.of(_rects));
    }
    _drag = _DragKind.none;
  }

  bool get isDragging => _drag != _DragKind.none;

  bool onWorldTap(Vector2 world) {
    // 1) If click hits current handles/rects → select that rect (pan will drag).
    if (hasSelection) {
      if (_hitCurrentArt(world) != null) {
        _beginDrag(world);
        _drag = _DragKind.none;
        return true;
      }
    }

    // 2) Click any solid under the cursor (primary select path — no Tab).
    final pick = _pickSolid(world);
    if (pick != null) {
      _applyPick(pick);
      return true;
    }

    // 3) Click empty → deselect so movement works.
    if (hasSelection) {
      _clearSelection();
      return false;
    }
    return false;
  }

  int? _hitCurrentArt(Vector2 world) {
    final art = _worldToArt(world);
    final rects = _rects;
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].inflate(6).contains(art)) return i;
    }
    // Corner handles in world space.
    if (rects.isEmpty) return null;
    final i = selectedRect.clamp(0, rects.length - 1);
    final wr = _artToWorld(rects[i]);
    for (final c in [wr.topLeft, wr.topRight, wr.bottomRight, wr.bottomLeft]) {
      if ((Offset(world.x, world.y) - c).distance < _hitSlop) return i;
    }
    return null;
  }

  void _clearSelection() {
    host = null;
    _kind = null;
    gateId = null;
    building = null;
    stump = null;
    tilesetName = null;
    tileLocalId = null;
    propName = null;
  }

  void _applyPick(_Pick pick) {
    host = pick.host;
    _kind = pick.kind;
    gateId = pick.gateId;
    building = pick.building;
    stump = pick.stump;
    tilesetName = pick.tilesetName;
    tileLocalId = pick.tileLocalId;
    propName = pick.propName;
    editingOpen = pick.editingOpen;
    selectedRect = 0;
    GameToast.show('MASK',
        body: selectionLabel,
        compact: true,
        color: const Color(0xFFFFAA44));
  }

  /// Closest solid hitbox under [world] (skip player / bullets).
  _Pick? _pickSolid(Vector2 world) {
    final point = Offset(world.x, world.y);
    _Pick? best;
    var bestDist = double.infinity;

    for (final hit in gameRef.collisions(onlyVisible: false)) {
      if (!hit.isSolid) continue;
      final abs = hit.toAbsoluteRect();
      if (!abs.inflate(14).contains(point)) continue;
      final parent = hit.hitboxParent;
      if (parent is! GameComponent) continue;
      if (parent is CustomPlayer || parent is Player) continue;
      final pick = _classify(parent);
      if (pick == null) continue;
      final d = (Offset(abs.center.dx, abs.center.dy) - point).distance;
      if (d < bestDist) {
        bestDist = d;
        best = pick;
      }
    }
    return best;
  }

  _Pick? _classify(GameComponent c) {
    if (c is Building) {
      return _Pick(host: c, kind: _MaskKind.building, building: c);
    }
    if (c is SweetrootStump) {
      return _Pick(host: c, kind: _MaskKind.stump, stump: c);
    }
    if (c is AbilityGate) {
      final mid = c.maskId;
      if (mid == null) return null;
      return _Pick(
          host: c, kind: _MaskKind.gate, gateId: mid, editingOpen: c.isOpen);
    }
    if (c is Boulder) {
      return _Pick(
          host: c,
          kind: _MaskKind.gate,
          gateId: ObstacleMaskId.boulder,
          editingOpen: c.pushed);
    }
    if (c is HiddenPath) {
      return _Pick(
          host: c,
          kind: _MaskKind.gate,
          gateId: ObstacleMaskId.bramble,
          editingOpen: c.revealed);
    }
    if (c is GameDecorationWithCollision || c is TileWithCollision) {
      final local = _localHitRects(c);
      if (local.isEmpty) return null;
      final prop = c.properties?['prop']?.toString();
      final tileset = TilesetMasks.tilesetForLevel(GameState.level);
      final tid = TilesetMasks.resolveTileId(
        tileset: tileset,
        propName: prop,
        rects: local,
      );
      if (tid == null) {
        // Still allow live edit; save may fail with a clear toast.
        return _Pick(
          host: c,
          kind: _MaskKind.tile,
          tilesetName: tileset,
          propName: prop ?? 'unknown',
          tileLocalId: -1,
        );
      }
      return _Pick(
        host: c,
        kind: _MaskKind.tile,
        tilesetName: tileset,
        propName: prop ?? 'tile',
        tileLocalId: tid,
      );
    }
    return null;
  }

  Offset _worldToArt(Vector2 world) {
    final h = host!;
    final k = _k;
    return Offset((world.x - h.position.x) / k, (world.y - h.position.y) / k);
  }

  Rect _artToWorld(Rect art) {
    final h = host!;
    final k = _k;
    return Rect.fromLTWH(
      h.position.x + art.left * k,
      h.position.y + art.top * k,
      art.width * k,
      art.height * k,
    );
  }

  bool _beginDrag(Vector2 world) {
    final rects = _rects;
    if (rects.isEmpty || host == null) return false;
    final i = selectedRect.clamp(0, rects.length - 1);
    final wr = _artToWorld(rects[i]);
    final corners = [wr.topLeft, wr.topRight, wr.bottomRight, wr.bottomLeft];
    for (var c = 0; c < 4; c++) {
      if ((Offset(world.x, world.y) - corners[c]).distance < _hitSlop) {
        _drag = _DragKind.resize;
        _dragCorner = c;
        _dragStartRect = rects[i];
        _dragStartWorld = world.clone();
        selectedRect = i;
        return true;
      }
    }
    if (wr.inflate(4).contains(Offset(world.x, world.y))) {
      _drag = _DragKind.move;
      _dragStartRect = rects[i];
      _dragStartWorld = world.clone();
      selectedRect = i;
      return true;
    }
    return false;
  }

  void _updateDrag(Vector2 world) {
    final rects = _rects;
    if (rects.isEmpty) return;
    final i = selectedRect.clamp(0, rects.length - 1);
    final k = _k;
    final dx = (world.x - _dragStartWorld.x) / k;
    final dy = (world.y - _dragStartWorld.y) / k;
    late Rect next;
    if (_drag == _DragKind.move) {
      next = _dragStartRect.shift(Offset(dx, dy));
    } else if (_drag == _DragKind.resize) {
      var l = _dragStartRect.left;
      var t = _dragStartRect.top;
      var r = _dragStartRect.right;
      var b = _dragStartRect.bottom;
      switch (_dragCorner) {
        case 0:
          l += dx;
          t += dy;
        case 1:
          r += dx;
          t += dy;
        case 2:
          r += dx;
          b += dy;
        case 3:
          l += dx;
          b += dy;
      }
      if (r - l < 2) r = l + 2;
      if (b - t < 2) b = t + 2;
      next = Rect.fromLTRB(l, t, r, b);
    } else {
      return;
    }
    final copy = List<Rect>.of(rects);
    copy[i] = next;
    _commit(copy, preview: true);
  }

  bool handleKey(KeyEvent event) {
    if (!GameDebug.isOn || event is! KeyDownEvent) return false;
    final key = event.logicalKey;

    // Tab still cycles, but click is the main path.
    if (key == LogicalKeyboardKey.tab) {
      _cycleNearby();
      return true;
    }
    if (!hasSelection) return false;

    if (key == LogicalKeyboardKey.keyO && _kind == _MaskKind.gate) {
      editingOpen = !editingOpen;
      selectedRect = 0;
      _previewGateColliders();
      GameToast.show('MASK',
          body: selectionLabel,
          compact: true,
          color: const Color(0xFFFFAA44));
      return true;
    }
    if (key == LogicalKeyboardKey.keyA &&
        (_kind == _MaskKind.gate || _kind == _MaskKind.tile)) {
      final rects = _rects;
      final base = rects.isEmpty
          ? const Rect.fromLTWH(4, 4, 16, 16)
          : rects[selectedRect.clamp(0, rects.length - 1)]
              .shift(const Offset(4, 4));
      final next = [...rects, base];
      selectedRect = next.length - 1;
      _commit(next);
      return true;
    }
    if ((key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace) &&
        (_kind == _MaskKind.gate || _kind == _MaskKind.tile)) {
      final rects = _rects;
      if (rects.length <= 1) return true;
      final i = selectedRect.clamp(0, rects.length - 1);
      final next = [...rects]..removeAt(i);
      selectedRect = min(i, next.length - 1);
      _commit(next);
      return true;
    }
    if (key == LogicalKeyboardKey.bracketLeft ||
        key == LogicalKeyboardKey.minus) {
      final n = _rects.length;
      if (n > 0) selectedRect = (selectedRect - 1 + n) % n;
      return true;
    }
    if (key == LogicalKeyboardKey.bracketRight ||
        key == LogicalKeyboardKey.equal) {
      final n = _rects.length;
      if (n > 0) selectedRect = (selectedRect + 1) % n;
      return true;
    }
    if (key == LogicalKeyboardKey.f5 || key == LogicalKeyboardKey.keyS) {
      _save();
      return true;
    }
    final step = HardwareKeyboard.instance.isShiftPressed ? 4.0 : 1.0;
    Offset? delta;
    if (key == LogicalKeyboardKey.arrowLeft) delta = Offset(-step, 0);
    if (key == LogicalKeyboardKey.arrowRight) delta = Offset(step, 0);
    if (key == LogicalKeyboardKey.arrowUp) delta = Offset(0, -step);
    if (key == LogicalKeyboardKey.arrowDown) delta = Offset(0, step);
    if (delta != null) {
      final rects = _rects;
      if (rects.isEmpty) return true;
      final i = selectedRect.clamp(0, rects.length - 1);
      final next = List<Rect>.of(rects);
      next[i] = next[i].shift(delta);
      _commit(next);
      return true;
    }
    return false;
  }

  void _previewGateColliders() {
    final id = gateId;
    final h = host;
    if (id == null || h == null || _kind != _MaskKind.gate) return;
    final rects = ObstacleMasks.rects(id, openState: editingOpen);
    if (h is AbilityGate) {
      h.applyColliderRects(rects);
    } else if (h is Boulder) {
      h.applyColliderRects(rects);
    } else if (h is HiddenPath) {
      h.applyColliderRects(rects);
    }
  }

  void _cycleNearby() {
    if (!hasGameRef) return;
    final cam = gameRef.camera.viewfinder.position;
    final view = gameRef.size / gameRef.camera.viewfinder.zoom;
    final area = Rect.fromCenter(
      center: Offset(cam.x, cam.y),
      width: view.x,
      height: view.y,
    );
    final picks = <_Pick>[];
    final seen = <int>{};
    for (final hit in gameRef.collisions(onlyVisible: true)) {
      if (!hit.isSolid) continue;
      final abs = hit.toAbsoluteRect();
      if (!area.overlaps(abs)) continue;
      final parent = hit.hitboxParent;
      if (parent is! GameComponent) continue;
      if (parent is CustomPlayer) continue;
      final id = identityHashCode(parent);
      if (!seen.add(id)) continue;
      final p = _classify(parent);
      if (p != null) picks.add(p);
    }
    if (picks.isEmpty) return;
    var idx = picks.indexWhere((e) => identical(e.host, host));
    idx = (idx + 1) % picks.length;
    _applyPick(picks[idx]);
  }

  Future<void> _save() async {
    if (!hasSelection) {
      GameToast.show('MASK',
          body: 'Click a solid block box, then F5',
          color: const Color(0xFFFFAA44),
          compact: true);
      return;
    }
    switch (_kind) {
      case _MaskKind.building:
        final err = await BuildingMasks.save(building!.id);
        _toastSave(err, BuildingMasks.savedPath);
        if (err == null && hasGameRef) {
          for (final b in gameRef.query<Building>(onlyVisible: false)) {
            final shared = buildingDefs[b.id]?.collision;
            if (shared != null) b.applyColliderRects([shared]);
          }
        }
      case _MaskKind.gate:
        final err = await ObstacleMasks.save(gateId!);
        _toastSave(err, ObstacleMasks.savedPath);
        if (err == null && hasGameRef) applyLiveGates(gameRef);
      case _MaskKind.stump:
        final err = await _saveStump();
        _toastSave(err, ObstacleMasks.projectRoot() == null
            ? null
            : '${ObstacleMasks.projectRoot()}/assets/images/obstacles/sweetroot_stump.json');
      case _MaskKind.tile:
        var tid = tileLocalId ?? -1;
        if (tid < 0) {
          tid = TilesetMasks.resolveTileId(
                tileset: tilesetName ?? TilesetMasks.tilesetForLevel(),
                propName: propName,
                rects: _rects,
              ) ??
              -1;
        }
        if (tid < 0) {
          GameToast.show('MASK SAVE FAIL',
              body: 'Could not match tileset tile — try a clearer prop',
              color: const Color(0xFFFF6688),
              compact: true);
          return;
        }
        tileLocalId = tid;
        final err = await TilesetMasks.save(
          tileset: tilesetName ?? TilesetMasks.tilesetForLevel(),
          tileId: tid,
          rects: _rects,
        );
        _toastSave(err, TilesetMasks.savedPath);
        if (err == null) {
          ClickPathfinder.clearCache();
          await ClickPathfinder.primeFromAsset(
              'maps/${GameState.mapIds[GameState.level] ?? 'world'}.tmj');
        }
      case null:
        break;
    }
  }

  Future<String?> _saveStump() async {
    try {
      final root = ObstacleMasks.projectRoot();
      if (root == null) return 'no project root';
      final path = '$root/assets/images/obstacles/sweetroot_stump.json';
      final r = SweetrootStump.collider;
      final j = {
        'name': 'sweetroot_stump',
        'collision': [
          [r.left, r.top, r.width, r.height]
        ],
      };
      await File(path).writeAsString(
          '${const JsonEncoder.withIndent(' ').convert(j)}\n');
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void _toastSave(String? err, String? path) {
    if (err == null) {
      GameToast.show('MASK SAVED',
          body: path ?? 'ok',
          color: const Color(0xFF66FFAA),
          compact: true,
          seconds: 3.5);
    } else {
      GameToast.show('MASK SAVE FAIL',
          body: err, color: const Color(0xFFFF6688), compact: true, seconds: 4);
    }
  }

  @override
  void render(Canvas canvas) {
    if (!GameDebug.isOn) return;

    // Soft outline on hovered? skip — just draw selection.
    if (!hasSelection) return;
    final rects = _rects;
    for (var i = 0; i < rects.length; i++) {
      final wr = _artToWorld(rects[i]);
      final selected = i == selectedRect;
      canvas.drawRect(
        wr,
        Paint()
          ..color = selected
              ? const Color(0x55FFCC44)
              : const Color(0x33FF6622),
      );
      canvas.drawRect(
        wr,
        Paint()
          ..color = selected
              ? const Color(0xFFFFCC44)
              : const Color(0xFFFF8844)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1.25,
      );
      if (selected) {
        for (final c in [
          wr.topLeft,
          wr.topRight,
          wr.bottomRight,
          wr.bottomLeft
        ]) {
          canvas.drawRect(
            Rect.fromCenter(center: c, width: _handle, height: _handle),
            Paint()..color = const Color(0xFFFFEE88),
          );
        }
      }
    }

    final h = host!;
    final label =
        '${selectionLabel.toUpperCase()}  · click · drag · F5 save · G grid';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFFFEEAA),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          shadows: [
            Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final plate = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        h.position.x,
        h.position.y - tp.height - 8,
        tp.width + 8,
        tp.height + 4,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(plate, Paint()..color = const Color(0xCC000000));
    tp.paint(canvas, Offset(h.position.x + 4, h.position.y - tp.height - 6));
    super.render(canvas);
  }
}

class _Pick {
  final GameComponent host;
  final _MaskKind kind;
  final ObstacleMaskId? gateId;
  final Building? building;
  final SweetrootStump? stump;
  final String? tilesetName;
  final int? tileLocalId;
  final String? propName;
  final bool editingOpen;

  _Pick({
    required this.host,
    required this.kind,
    this.gateId,
    this.building,
    this.stump,
    this.tilesetName,
    this.tileLocalId,
    this.propName,
    this.editingOpen = false,
  });
}

enum _DragKind { none, move, resize }
