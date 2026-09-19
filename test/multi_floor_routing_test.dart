import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/stairs.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';

MapItem makeBuilding({int floors = 3}) {
  return MapItem(
    kind: 'building',
    x: 0,
    y: 0,
    width: 300,
    height: 200,
    floorWidth: 300,
    floorHeight: 200,
    floorCount: floors,
    text: 'Test Building',
    id: 'b1',
  );
}

MapItem downStair(String id, int from, int to, {double x = 220}) {
  return MapItem(
    kind: 'stairs',
    x: x,
    y: 50,
    width: 40,
    height: 100,
    stairDirection: 'down',
    stairFrom: from,
    stairTo: to,
    stairEnabled: true,
    id: id,
  );
}

void main() {
  group('Stage 3 multi-floor stair routing', () {
    test('routes toward a stair chain that reaches Floor 1', () {
      final b = makeBuilding();
      final scene = MapScene(
        name: 'multi-floor',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': const [],
          'b1:Floor 2': [downStair('s21', 2, 1)],
          'b1:Floor 3': [downStair('s32', 3, 2)],
          'b1:Roof': const [],
        },
      );
      final navigator = WorldNavigator(
        scene,
        markerX: 60,
        markerY: 100,
        collisionRadius: 5,
      );
      navigator.enterBuilding(b);
      navigator.currentFloor = 3;

      final leg = navigator.findRouteTowardFloor(1);

      expect(leg, isNotNull);
      expect(leg!.sourceFloor, 3);
      expect(leg.targetFloor, 2);
      expect(leg.path, isNotEmpty);
      expect(leg.path.first[0], closeTo(60, 1e-9));
      expect(leg.path.first[1], closeTo(100, 1e-9));

      // Adjacent source floors alternate stair lanes. Floor 3 uses the
      // left-hand flight while direction controls longitudinal travel.
      final floorLocal = navigator
          .floorTransform(b)
          .unproject(leg.entryPoint[0], leg.entryPoint[1]);
      final progress = sectionProgress(
        leg.section,
        floorLocal[0],
        floorLocal[1],
      );
      expect(progress.$3, greaterThanOrEqualTo(0.94));

      final localEntry = leg.section.stair.worldToLocal(
        floorLocal[0],
        floorLocal[1],
      );
      expect(localEntry[0], lessThan(leg.section.width / 2));
    });

    test('after arriving on Floor 2 the next leg targets Floor 1', () {
      final b = makeBuilding();
      final scene = MapScene(
        name: 'multi-floor',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': const [],
          'b1:Floor 2': [downStair('s21', 2, 1)],
          'b1:Floor 3': [downStair('s32', 3, 2)],
          'b1:Roof': const [],
        },
      );
      final navigator = WorldNavigator(
        scene,
        markerX: 60,
        markerY: 100,
        collisionRadius: 5,
      );
      navigator.enterBuilding(b);
      navigator.currentFloor = 2;

      final leg = navigator.findRouteTowardFloor(1);

      expect(leg, isNotNull);
      expect(leg!.sourceFloor, 2);
      expect(leg.targetFloor, 1);
    });

    test('returns null when no stair chain reaches the target floor', () {
      final b = makeBuilding();
      final scene = MapScene(
        name: 'blocked floors',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': const [],
          'b1:Floor 2': const [],
          'b1:Floor 3': [downStair('s32', 3, 2)],
          'b1:Roof': const [],
        },
      );
      final navigator = WorldNavigator(
        scene,
        markerX: 60,
        markerY: 100,
        collisionRadius: 5,
      );
      navigator.enterBuilding(b);
      navigator.currentFloor = 3;

      expect(navigator.findRouteTowardFloor(1), isNull);
    });
  });
}
