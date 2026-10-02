import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'checkpoint.dart';

/// Sprite size, collision box and door point of a placeable building, in px
/// from the sprite's top-left. Generated from tools/buildings/<name>.json
/// (buildings_v2); keep in sync with tools/buildings/buildings.tsj.
class BuildingDef {
  final double w, h;
  final Rect collision;
  final Offset door;

  /// Shown in the HUD toast when Kaela steps up to the (closed) door.
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
  'apartment_block': BuildingDef(160, 160, Rect.fromLTWH(8, 78, 144, 64), Offset(80, 142),
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
/// roof: Bonfire y-sorts components by the bottom of their hitboxes, which
/// draws her behind the building while she's north of the box and in front of
/// it once she's south of it. The door is decorative; standing at it shows a
/// short flavour line in the HUD toast.
class Building extends GameDecorationWithCollision {
  static const double _doorRadius = 18;

  final String id;
  final BuildingDef def;
  bool _atDoor = false;

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

  @override
  void update(double dt) {
    super.update(dt);
    final player = gameRef.player;
    if (player == null) return;
    // Kaela's feet vs a point just in front of the door.
    final feet = Vector2(player.rectCollision.center.dx, player.rectCollision.bottom);
    final door = position + Vector2(def.door.dx, def.door.dy + 8);
    final d = feet.distanceTo(door);
    if (!_atDoor && d < _doorRadius) {
      _atDoor = true;
      final text = def.flavour;
      Checkpoint.toast.value = text;
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (Checkpoint.toast.value == text) Checkpoint.toast.value = null;
      });
    } else if (_atDoor && d > _doorRadius * 2.5) {
      _atDoor = false;
    }
  }
}
