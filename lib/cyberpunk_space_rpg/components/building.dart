import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../audio/sfx_manager.dart';
import '../creatures/bonds.dart';
import '../creatures/interaction.dart';
import '../game/adventure.dart';
import '../game/game_state.dart';
import '../interiors/room_scene.dart';
import '../interiors/room_services.dart';

/// Sprite size, collision box and door point of a placeable building, in px
/// from the sprite's top-left. Generated from tools/buildings/<name>.json
/// (buildings_v2); keep in sync with tools/buildings/buildings.tsj.
/// [collision] is mutable for the in-game mask editor.
class BuildingDef {
  final double w, h;
  Rect collision;
  final Offset door;

  /// Shown when Kaela examines the door.
  final String flavour;

  BuildingDef(this.w, this.h, this.collision, this.door, this.flavour);
}

final buildingDefs = <String, BuildingDef>{
  'noodle_shop': BuildingDef(128, 128, const Rect.fromLTWH(12, 60, 104, 64), const Offset(61, 124),
      'Noodle Shop · Closed for the night. The broth still smells warm.'),
  'tea_house': BuildingDef(128, 128, const Rect.fromLTWH(10, 60, 108, 64), const Offset(64, 124),
      'Tea House · Closed. A kettle hums somewhere inside.'),
  'greenhouse': BuildingDef(128, 128, const Rect.fromLTWH(12, 60, 104, 64), const Offset(63, 124),
      'Greenhouse · Locked. The plants lean towards the glass.'),
  'apartment_block': BuildingDef(160, 160, const Rect.fromLTWH(0, 78, 160, 64), const Offset(80, 142),
      'Apartments · The door wants a resident keycard.'),
  'archive_library': BuildingDef(160, 160, const Rect.fromLTWH(8, 82, 142, 64), const Offset(80, 146),
      'Archive Library · Sealed. The Archivist keeps the key.'),
  'ranger_cabin': BuildingDef(128, 128, const Rect.fromLTWH(6, 54, 108, 64), const Offset(63, 118),
      'Ranger Cabin · Locked. Someone left the stove warm.'),
  'ruin_shrine': BuildingDef(128, 160, const Rect.fromLTWH(16, 88, 96, 64), const Offset(64, 152),
      'Aetherian Shrine · The portal is dormant. For now.'),
};

/// A building placed as a Tiled tile object named "building" (property
/// building=<id>) in the gameplay layer. [position] is the sprite's top-left.
///
/// The solid box only covers the wall base, so Kaela can walk behind the
/// roof. Doors are [Interactable]: EXAMINE for flavour, and the archive can
/// be opened with the Archivist's seal.
class Building extends GameDecorationWithCollision with Interactable {
  final String id;
  final BuildingDef def;

  Building(Vector2 position, {required this.id, required this.def})
      : super.withSprite(
          sprite: Sprite.load('maps/buildings/$id.png'),
          position: position,
          size: Vector2(def.w, def.h),
          collisions: [
            RectangleHitbox(
              position: Vector2(def.collision.left, def.collision.top),
              size: Vector2(def.collision.width, def.collision.height),
              isSolid: true,
            ),
          ],
        ) {
    // GameDecoration grows sprites by a "bleeding pixel" (here 2 px, shifted
    // 1 px up-left) to hide tile seams. Buildings are free-standing pixel
    // art, so keep them pixel-exact and the hitbox where the map expects it.
    this.position = position;
    size = Vector2(def.w, def.h);
    paint.filterQuality = FilterQuality.none;
  }

  /// Sort on the wall foot-line so Kaela in front of the door draws over the
  /// facade (default hitbox fold can leave her under the lower wall art).
  @override
  int get priority => LayerPriority.getComponentPriority(
        (position.y + def.collision.bottom).floor(),
      );

  @override
  Future<void> onLoad() {
    RoomDay.ensure();
    return super.onLoad();
  }

  /// Live hitbox from [def.collision] (mask editor / after JSON load).
  void applyColliderRects(List<Rect> rects) {
    if (rects.isEmpty) return;
    def.collision = rects.first;
    for (final h in children.whereType<RectangleHitbox>().toList()) {
      h.removeFromParent();
    }
    final r = def.collision;
    add(RectangleHitbox(
      position: Vector2(r.left, r.top),
      size: Vector2(r.width, r.height),
      isSolid: true,
    ));
  }

  void refreshColliders() => applyColliderRects([def.collision]);

  @override
  Vector2 get interactPoint => position + Vector2(def.door.dx, def.door.dy + 8);

  @override
  double get interactRadius => id == 'archive_library' ? 36 : 28;

  /// Skip inert locked doors so walk-by note prompts don't fire for no reason.
  @override
  bool get canFocus {
    if (Interiors.canEnter(id)) return true;
    if (id == 'archive_library') return true;
    if (id == 'ruin_shrine' && !Adventure.hasClue('shrine_note')) return true;
    return false;
  }

  @override
  PromptInfo get prompt {
    if (Interiors.canEnter(id)) return const PromptInfo('ENTER');
    if (id == 'archive_library') {
      if (Bonds.hasItem('archive_seal')) return const PromptInfo('USE SEAL', item: 'archive_seal');
      return const PromptInfo.note('Archive · Sealed. Needs the Archivist\'s seal.', item: 'archive_seal');
    }
    if (id == 'ruin_shrine' && !Adventure.hasClue('shrine_note')) {
      return const PromptInfo('EXAMINE');
    }
    return const PromptInfo.note('');
  }

  @override
  void interact() {
    // Already unlocked rooms (tea house, open archive, ranger cabin, …).
    if (Interiors.canEnter(id)) {
      Interiors.enter(this);
      return;
    }
    if (id == 'archive_library') {
      // Seal → unlock → walk in. The Asha cutscene waits on the draft inside.
      if (!Bonds.hasItem('archive_seal')) return;
      Bonds.useItem('archive_seal');
      Adventure.setFlag('archive_opened');
      SfxManager().playChime();
      GameToast.show('ARCHIVE UNLOCKED',
          body: 'The seal accepts. The stacks are open.',
          color: const Color(0xFFFFDD44),
          compact: true);
      Interiors.enter(this);
      return;
    }
    if (id == 'ruin_shrine') {
      final first = Adventure.discover('shrine_note');
      GameState.onShrineExamined();
      if (!first) return;
      Bonds.addGlimmer(8);
      SfxManager().playChime();
      GameToast.show('SHRINE · +8 GLIMMER · CLUE LOGGED',
          color: const Color(0xFFCC88FF), compact: true);
      return;
    }
  }
}
