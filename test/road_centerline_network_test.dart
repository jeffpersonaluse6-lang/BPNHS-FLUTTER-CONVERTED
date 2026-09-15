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

void main() {
  test('road network route stays centered and turns at T junction', () {
    final horizontal = rect(100, 270, 700, 60);
    final vertical = rect(270, 270, 60, 330);

    final pathfinder = SameFloorPathfinder(
      barriers: const [],
      playerRadius: 10,
      width: 1000,
      height: 700,
      preferredAreas: [horizontal, vertical],
    );

    final route = pathfinder.findPath([790, 180], [300, 620]);

    expect(route, isNotEmpty);
    expect(route.any((p) => (p[1] - 300).abs() < 1e-6), isTrue);
    expect(
      route.any((p) => (p[0] - 300).abs() < 1e-6 && (p[1] - 300).abs() < 1e-6),
      isTrue,
    );
  });

  test('straight road produces a straight centered road segment', () {
    final road = rect(100, 270, 800, 60);
    final pathfinder = SameFloorPathfinder(
      barriers: const [],
      playerRadius: 10,
      width: 1000,
      height: 700,
      preferredAreas: [road],
    );

    final route = pathfinder.findPath([150, 200], [850, 400]);
    expect(route, isNotEmpty);

    final centerPoints = route.where((p) => (p[1] - 300).abs() < 1e-6).toList();
    expect(centerPoints.length, greaterThanOrEqualTo(2));
  });
  test('touching road rectangles form a T junction', () {
    final horizontal = rect(100, 270, 700, 60);
    final vertical = rect(270, 330, 60, 270);

    final pathfinder = SameFloorPathfinder(
      barriers: const [],
      playerRadius: 10,
      width: 1000,
      height: 700,
      preferredAreas: [horizontal, vertical],
    );

    final route = pathfinder.findPath([760, 200], [300, 620]);

    expect(route, isNotEmpty);
    expect(
      route.any((p) => (p[1] - 300).abs() < 1e-6),
      isTrue,
      reason: 'Route should use the horizontal road center.',
    );
    expect(
      route.any((p) => (p[0] - 300).abs() < 1e-6 && p[1] >= 300),
      isTrue,
      reason: 'Route should turn into the vertical road at the T junction.',
    );
  });
}
