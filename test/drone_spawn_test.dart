import 'package:bonfire/bonfire.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/drone_spawn.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/components/uec_drone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pad sits at area centre and starts alive', () {
    final pad = DroneSpawnPoint(
      Vector2(100, 200),
      Vector2(96, 80),
      saveId: 'world:dronespawn:test',
      kind: DroneKind.swarm,
      interval: 5,
      maxAlive: 3,
      hp: 60,
    );
    expect(pad.isDead, isFalse);
    expect(pad.areaSize.x, 96);
    expect(pad.areaSize.y, 80);
    expect(pad.padCenter, Vector2(100 + 48, 200 + 40));
    expect(pad.maxHp, 60);
    expect(pad.kind, DroneKind.swarm);
    expect(pad.maxAlive, 3);
  });

  test('area is at least padSize even if tiled rect is tiny', () {
    final pad = DroneSpawnPoint(
      Vector2.zero(),
      Vector2(10, 10),
      saveId: 'tiny',
    );
    expect(pad.areaSize.x, DroneSpawnPoint.padSize);
    expect(pad.areaSize.y, DroneSpawnPoint.padSize);
  });
}
