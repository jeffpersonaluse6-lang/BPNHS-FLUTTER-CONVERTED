import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/collision.dart';
import 'package:flutter_runtime/navigation/same_floor_pathfinder.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';

Barrier wall(double x1, double y1, double x2, double y2, {double radius = 2}) {
  return Barrier(
    startX: x1,
    startY: y1,
    endX: x2,
    endY: y2,
    radius: radius,
    flat: true,
  );
}

void main() {
  group('SameFloorPathfinder', () {
    test('returns a straight route in open space', () {
      final pathfinder = SameFloorPathfinder(
        barriers: const [],
        playerRadius: 5,
        width: 200,
        height: 200,
      );

      final route = pathfinder.findPath([20, 20], [180, 180]);

      expect(route, hasLength(2));
      expect(route.first, equals([20.0, 20.0]));
      expect(route.last, equals([180.0, 180.0]));
    });

    test('routes around a blocking wall', () {
      final pathfinder = SameFloorPathfinder(
        barriers: [wall(100, 30, 100, 170)],
        playerRadius: 5,
        width: 200,
        height: 200,
      );

      final route = pathfinder.findPath([40, 100], [160, 100]);

      expect(route, isNotEmpty);
      expect(route.length, greaterThan(2));
      expect(route.any((p) => p[1] < 30 || p[1] > 170), isTrue);
    });

    test('uses a doorway gap instead of crossing wall segments', () {
      final pathfinder = SameFloorPathfinder(
        barriers: [wall(100, 0, 100, 80), wall(100, 120, 100, 200)],
        playerRadius: 5,
        width: 200,
        height: 200,
      );

      final route = pathfinder.findPath([40, 100], [160, 100]);

      expect(route, hasLength(2));
      expect(pathfinder.lineIsWalkable(route.first, route.last), isTrue);
    });

    test('every returned segment is collision-free', () {
      final pathfinder = SameFloorPathfinder(
        barriers: [wall(90, 30, 90, 150), wall(90, 150, 150, 150)],
        playerRadius: 5,
        width: 220,
        height: 220,
      );

      final route = pathfinder.findPath([30, 100], [180, 100]);

      expect(route, isNotEmpty);
      for (var i = 0; i < route.length - 1; i++) {
        expect(
          pathfinder.lineIsWalkable(route[i], route[i + 1]),
          isTrue,
          reason: 'segment $i crossed a collision barrier',
        );
      }
    });

    test('returns no route when a wall seals the whole surface', () {
      final pathfinder = SameFloorPathfinder(
        barriers: [wall(100, 0, 100, 200, radius: 3)],
        playerRadius: 5,
        width: 200,
        height: 200,
      );

      final route = pathfinder.findPath([40, 100], [160, 100]);

      expect(route, isEmpty);
    });

    test('WorldNavigator exposes current same-floor routing', () {
      final scene = MapScene(
        name: 'route test',
        width: 200,
        height: 200,
        floors: {
          'Campus': [
            const MapItem(
              kind: 'wall',
              x: 100,
              y: 30,
              width: 0,
              height: 140,
              collisionThickness: 4,
              id: 'wall',
            ),
          ],
        },
      );
      final navigator = WorldNavigator(
        scene,
        markerX: 40,
        markerY: 100,
        collisionRadius: 5,
      );

      final route = navigator.findSameFloorRoute(160, 100);

      expect(route, isNotEmpty);
      expect(route.first[0], closeTo(40, 1e-9));
      expect(route.first[1], closeTo(100, 1e-9));
      expect(route.last[0], closeTo(160, 1e-9));
      expect(route.last[1], closeTo(100, 1e-9));
    });
  });
}
