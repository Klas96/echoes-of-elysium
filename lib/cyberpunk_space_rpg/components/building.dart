import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../audio/sfx_manager.dart';
import '../creatures/bonds.dart';
import '../creatures/interaction.dart';
import '../game/adventure.dart';
import '../game/game_state.dart';
import '../game/story_beats.dart';
import '../interiors/room_scene.dart';
import '../interiors/room_services.dart';
import '../interiors/room_text.dart';

/// Sprite size, collision box and door point of a placeable building, in px
/// from the sprite's top-left. Generated from tools/buildings/<name>.json
/// (buildings_v2); keep in sync with tools/buildings/buildings.tsj.
class BuildingDef {
  final double w, h;
  final Rect collision;
  final Offset door;

  /// Shown when Kaela examines the door.
  final String flavour;

  const BuildingDef(this.w, this.h, this.collision, this.door, this.flavour);
}

const buildingDefs = <String, BuildingDef>{
  'noodle_shop': BuildingDef(128, 128, Rect.fromLTWH(12, 60, 104, 64), Offset(61, 124),
      'Noodle Shop · Closed for the night. The broth still smells warm.'),
  'tea_house': BuildingDef(128, 128, Rect.fromLTWH(10, 60, 108, 64), Offset(64, 124),
      'Tea House · Closed. A kettle hums somewhere inside.'),
  'greenhouse': BuildingDef(128, 128, Rect.fromLTWH(12, 60, 104, 64), Offset(63, 124),
      'Greenhouse · Locked. The plants lean towards the glass.'),
  'apartment_block': BuildingDef(160, 160, Rect.fromLTWH(0, 78, 160, 64), Offset(80, 142),
      'Apartments · The door wants a resident keycard.'),
  'archive_library': BuildingDef(160, 160, Rect.fromLTWH(8, 82, 142, 64), Offset(80, 146),
      'Archive Library · Sealed. The Archivist keeps the key.'),
  'ranger_cabin': BuildingDef(128, 128, Rect.fromLTWH(6, 54, 108, 64), Offset(63, 118),
      'Ranger Cabin · Locked. Someone left the stove warm.'),
  'ruin_shrine': BuildingDef(128, 160, Rect.fromLTWH(16, 88, 96, 64), Offset(64, 152),
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

  bool get _archiveOpen => Adventure.flag('archive_opened');

  @override
  Future<void> onLoad() {
    RoomDay.ensure();
    return super.onLoad();
  }

  /// Locked-door line (#31, GameConcept), else the building's own.
  String get flavour => RoomText.lockedDoors[id] ?? def.flavour;

  @override
  Vector2 get interactPoint => position + Vector2(def.door.dx, def.door.dy + 8);

  @override
  double get interactRadius => 28;

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
    return const PromptInfo('EXAMINE');
  }

  @override
  void interact() {
    if (Interiors.canEnter(id)) {
      Interiors.enter(this);
      return;
    }
    if (id == 'archive_library') {
      if (_archiveOpen) return;
      if (!Bonds.hasItem('archive_seal')) return;
      Bonds.useItem('archive_seal');
      Adventure.setFlag('archive_opened');
      Adventure.discover('archive_first_memory');
      Adventure.discover('asha_on_archive');
      Bonds.addGlimmer(12);
      SfxManager().playChime();
      GameToast.show('ARCHIVE OPENED', body: '+12 glimmer · clue logged',
          color: const Color(0xFFFFDD44), compact: true);
      StoryBeats.onArchiveOpened();
      return;
    }
    if (id == 'ruin_shrine') {
      final first = Adventure.discover('shrine_note');
      GameState.onShrineExamined();
      if (first) Bonds.addGlimmer(8);
      SfxManager().playChime();
      GameToast.show(first ? 'SHRINE · +8 GLIMMER · CLUE LOGGED' : 'SHRINE',
          body: flavour, color: const Color(0xFFCC88FF));
      return;
    }
    GameToast.show('DOOR', body: flavour, color: const Color(0xFFAACCEE));
  }
}
