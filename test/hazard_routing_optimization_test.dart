import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/same_floor_pathfinder.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';

void main() {
  group('Risk-zone direct-path optimization', () {
    test('direct shortcut used when segment avoids all risk zones', () {
      final pathfinder = SameFloorPathfinder(
        barriers: const [],
        playerRadius: 5,
        width: 500,
        height: 400,
        riskZones: [
          RouteRiskZone(x: 250, y: 50, radius: 30),
        ],
        riskWeight: 5.0,
        riskInfluenceDistance: 100,
      );

      // Segment from (10, 200) to (490, 200) runs horizontally through the
      // middle — well below the risk zone at (250, 50) with radius 30.
      final route = pathfinder.findPath([10.0, 200.0], [490.0, 200.0]);
      expect(route.length, 2,
          reason: 'should take the fast two-point shortcut');
    });

    test('A* used when segment passes through risk zone core', () {
      final pathfinder = SameFloorPathfinder(
        barriers: const [],
        playerRadius: 5,
        width: 500,
        height: 400,
        riskZones: [
          RouteRiskZone(x: 250, y: 200, radius: 30),
        ],
        riskWeight: 10.0,
        riskInfluenceDistance: 100,
      );

      // Segment from (10, 200) to (490, 200) passes directly through the
      // zone at (250, 200). A* should find a detour.
      final route = pathfinder.findPath([10.0, 200.0], [490.0, 200.0]);
      expect(route.length, greaterThan(2),
          reason: 'A* should detour around the risk zone');
    });

    test('direct shortcut used when segment is near but not through zone', () {
      final pathfinder = SameFloorPathfinder(
        barriers: const [],
        playerRadius: 5,
        width: 500,
        height: 400,
        riskZones: [
          RouteRiskZone(x: 250, y: 100, radius: 30),
        ],
        riskWeight: 10.0,
        riskInfluenceDistance: 100,
      );

      // Segment at y=200 is outside the zone at y=100 with radius 30.
      // Closest point distance is 70, zone radius is 30, so no crossing.
      final route = pathfinder.findPath([10.0, 200.0], [490.0, 200.0]);
      expect(route.length, 2,
          reason: 'should use shortcut since segment does not enter zone core');
    });
  });

  group('Hazard pathfinder cache', () {
    test('hazard pathfinder cache invalidated on addFireHazard', () {
      final b = MapItem(
        kind: 'building', x: 0, y: 0, width: 300, height: 240,
        floorWidth: 300, floorHeight: 240, floorCount: 1, id: 'b1',
      );
      final scene = MapScene(
        name: 'cache', width: 500, height: 400,
        floors: {'Campus': [b], 'b1:Floor 1': const []},
      );
      final nav = WorldNavigator(scene, collisionRadius: 5);
      nav.enterBuilding(b);
      nav.currentFloor = 1;

      // Place a hazard so the pathfinder cache is populated.
      nav.addFireHazard(100, 100);
      nav.addFireHazard(200, 200);

      // Remove a hazard — cache should be invalidated.
      nav.removeHazard('fire_1');

      // A routing call should succeed (not crash with stale cache).
      final route = nav.findSameFloorRoute(10, 10);
      expect(route, isA<List>());

      // Move a hazard — cache should be invalidated.
      nav.moveHazard('fire_2', 50, 50);
      final route2 = nav.findSameFloorRoute(10, 10);
      expect(route2, isA<List>());

      // Clear all hazards — cache should be invalidated.
      nav.clearHazards();
      final route3 = nav.findSameFloorRoute(10, 10);
      expect(route3, isA<List>());
    });

    test('footprint barrier cache key includes current building', () {
      final b1 = MapItem(
        kind: 'building', x: 0, y: 0, width: 100, height: 100,
        floorWidth: 100, floorHeight: 100, floorCount: 1, id: 'b1',
      );
      final b2 = MapItem(
        kind: 'building', x: 200, y: 200, width: 100, height: 100,
        floorWidth: 100, floorHeight: 100, floorCount: 1, id: 'b2',
      );
      final scene = MapScene(
        name: 'cache key', width: 500, height: 400,
        floors: {'Campus': [b1, b2], 'b1:Floor 1': const [], 'b2:Floor 1': const []},
      );
      final nav = WorldNavigator(scene, markerX: 50, markerY: 50, collisionRadius: 5);

      // Enter b1 — b1 should be excluded from footprint barriers.
      nav.enterBuilding(b1);
      nav.currentFloor = 1;
      final route1 = nav.findSameFloorRoute(250, 250);
      expect(route1, isA<List>());

      // Enter b2 — b2 should be excluded from footprint barriers.
      nav.enterBuilding(b2);
      nav.currentFloor = 1;
      final route2 = nav.findSameFloorRoute(50, 50);
      expect(route2, isA<List>());
    });
  });
}
