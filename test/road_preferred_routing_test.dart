import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/navigation/collision.dart';
import 'package:flutter_runtime/navigation/same_floor_pathfinder.dart';

PolygonBarrier rect(double x, double y, double w, double h) {
  return PolygonBarrier([
    [x, y],
    [x + w, y],
    [x + w, y + h],
    [x, y + h],
  ]);
}

bool inside(PolygonBarrier area, List<double> p) => area.blocks(p[0], p[1], 0);

void main() {
  test('original direct route remains direct without preferred areas', () {
    final pathfinder = SameFloorPathfinder(
      barriers: const [],
      playerRadius: 10,
      width: 1000,
      height: 700,
    );

    final route = pathfinder.findPath([100, 100], [900, 100]);
    expect(route, hasLength(2));
  });

  test(
    'reasonable road detour is preferred over cutting across open space',
    () {
      final road = rect(200, 200, 600, 60);
      final pathfinder = SameFloorPathfinder(
        barriers: const [],
        playerRadius: 10,
        width: 1000,
        height: 700,
        preferredAreas: [road],
      );

      final route = pathfinder.findPath([100, 100], [900, 100]);

      expect(route.length, greaterThan(2));
      expect(
        route.any((point) => inside(road, point)),
        isTrue,
        reason:
            'Route should use the mapped road when the detour is reasonable.',
      );
    },
  );

  test('road preference is not absolute when the road is a huge detour', () {
    final farRoad = rect(200, 500, 600, 60);
    final pathfinder = SameFloorPathfinder(
      barriers: const [],
      playerRadius: 10,
      width: 1000,
      height: 700,
      preferredAreas: [farRoad],
    );

    final route = pathfinder.findPath([100, 100], [900, 100]);

    expect(route, hasLength(2));
    expect(route.first, equals([100.0, 100.0]));
    expect(route.last, equals([900.0, 100.0]));
  });

  test('preferred areas never bypass collision barriers', () {
    final road = rect(200, 200, 600, 60);
    const wall = Barrier(
      startX: 500,
      startY: 150,
      endX: 500,
      endY: 320,
      radius: 8,
      flat: true,
    );
    final pathfinder = SameFloorPathfinder(
      barriers: const [wall],
      playerRadius: 10,
      width: 1000,
      height: 700,
      preferredAreas: [road],
    );

    final route = pathfinder.findPath([100, 100], [900, 100]);
    expect(route, isNotEmpty);

    for (var i = 1; i < route.length; i++) {
      expect(pathfinder.lineIsWalkable(route[i - 1], route[i]), isTrue);
    }
  });
}
