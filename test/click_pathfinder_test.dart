import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/custom_player.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/gate_components.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/obstacle_masks.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/click_pathfinder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('path clearance matches Kaela feet hitbox', () {
    expect(ClickPathfinder.clearWidth, CustomPlayer.feetWidth);
    expect(ClickPathfinder.clearHeight, CustomPlayer.feetHeight);
  });

  test('open boulder collider leaves the left-lane passage clear', () {
    ObstacleMasks.loadFromDisk();
    // Art is 96×64; passage is x 0–64. Feet (~12 wide) need margin after
    // Minkowski so A* still finds a walkable cell beside the turned stone.
    const passageRight = 64.0;
    final open = GateArt.boulderOpenColliders.single;
    expect(open.left, greaterThanOrEqualTo(passageRight));
    expect(passageRight - ClickPathfinder.clearWidth, greaterThan(8));
  });
}
