import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/navigation/hazard.dart';
import 'package:flutter_runtime/navigation/same_floor_pathfinder.dart';

void main() {
  test('fire hazard is scoped to the floor/building where it was placed', () {
    final fire = HazardZone(
      id: 'fire_1',
      kind: HazardKind.fire,
      x: 500,
      y: 300,
      radius: 60,
      buildingId: 'building_a',
      floor: 3,
    );

    expect(fire.matchesSurface('building_a', 3), isTrue);
    expect(fire.matchesSurface('building_a', 2), isFalse);
    expect(fire.matchesSurface(null, 3), isFalse);
  });

  test('fire hazard blocks the direct path and A* routes around it', () {
    final fire = HazardZone(
      id: 'fire_1',
      kind: HazardKind.fire,
      x: 500,
      y: 300,
      radius: 70,
      buildingId: null,
      floor: 1,
    );

    final pathfinder = SameFloorPathfinder(
      barriers: fire.routingBarriers(),
      playerRadius: 10,
      width: 1000,
      height: 700,
    );

    final route = pathfinder.findPath(<double>[100, 300], <double>[900, 300]);

    expect(route, isNotEmpty);
    expect(
      route.length,
      greaterThan(2),
      reason: 'The route should detour around the fire hazard.',
    );
    expect(
      route.any((p) => (p[1] - 300).abs() > 20),
      isTrue,
      reason: 'The detour should visibly leave the blocked center line.',
    );
  });
  test('fire barrier blocks the center of the entire danger disk', () {
    final fire = HazardZone(
      id: 'fire_disk',
      kind: HazardKind.fire,
      x: 500,
      y: 300,
      radius: 70,
      buildingId: null,
      floor: 1,
    );

    final barriers = fire.routingBarriers();
    expect(barriers, hasLength(1));
    expect(barriers.single.blocks(500, 300, 10), isTrue);
    expect(barriers.single.blocks(550, 300, 10), isTrue);
    expect(barriers.single.blocks(590, 300, 10), isFalse);
  });
  test('fire hazard radius can be resized', () {
    final fire = HazardZone(
      id: 'resizable_fire',
      kind: HazardKind.fire,
      x: 500,
      y: 300,
      radius: 40,
      buildingId: null,
      floor: 1,
    );

    fire.radius = 90;

    final barrier = fire.routingBarriers().single;
    expect(fire.radius, 90);
    expect(barrier.blocks(575, 300, 10), isTrue);
    expect(barrier.blocks(610, 300, 10), isFalse);
  });
}
