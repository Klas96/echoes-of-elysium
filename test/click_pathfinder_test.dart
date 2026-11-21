import 'package:bonfire/bonfire.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/custom_player.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/gate_components.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/creatures/obstacle_masks.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/click_pathfinder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(ClickPathfinder.clearCache);

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

  test('city fountain is a solid A* barrier (EOE-111)', () async {
    // Plaza fountain stamped at tiles (25,5)–(27,7). Foot-shrinking used to
    // leave the middle row walkable for pathfinding while physics blocked.
    await ClickPathfinder.primeFromAsset('maps/world2.tmj');
    expect(ClickPathfinder.hasGrid, isTrue);

    final barriers = ClickPathfinder.tileBarriersView;
    // Center tile of the fountain (26,6) — both half-cells must be blocked.
    const tile = 32.0;
    final mid = ClickPathfinder.cellOf(
      Vector2(26.5 * tile, 6.5 * tile),
    );
    expect(barriers.contains(mid), isTrue,
        reason: 'fountain center cell $mid must block A*');

    // Horizontal corridor through the basin (y≈6.25) must not be open.
    for (var tx = 25; tx <= 27; tx++) {
      final c = ClickPathfinder.cellOf(
        Vector2((tx + 0.5) * tile, 6.25 * tile),
      );
      expect(barriers.contains(c), isTrue,
          reason: 'fountain corridor cell $c (tile $tx,6) must be solid');
    }
  });
}
