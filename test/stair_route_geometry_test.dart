import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/stairs.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';

void main() {
  test(
    'multi-floor route follows stair from source side to transition level',
    () {
      final building = MapItem(
        kind: 'building',
        x: 0,
        y: 0,
        width: 300,
        height: 220,
        floorWidth: 300,
        floorHeight: 220,
        floorCount: 3,
        id: 'b1',
      );
      final stair = MapItem(
        kind: 'stairs',
        x: 220,
        y: 40,
        width: 50,
        height: 140,
        stairDirection: 'down',
        stairFrom: 3,
        stairTo: 2,
        stairEnabled: true,
        id: 's32',
      );
      final nextStair = MapItem(
        kind: 'stairs',
        x: 220,
        y: 40,
        width: 50,
        height: 140,
        stairDirection: 'down',
        stairFrom: 2,
        stairTo: 1,
        stairEnabled: true,
        id: 's21',
      );

      final scene = MapScene(
        name: 'stair geometry',
        width: 500,
        height: 400,
        floors: {
          'Campus': [building],
          'b1:Floor 1': const [],
          'b1:Floor 2': [nextStair],
          'b1:Floor 3': [stair],
          'b1:Roof': const [],
        },
      );

      final navigator = WorldNavigator(
        scene,
        markerX: 80,
        markerY: 110,
        collisionRadius: 5,
      );
      navigator.enterBuilding(building);
      navigator.currentFloor = 3;

      final leg = navigator.findRouteTowardFloor(1);
      expect(leg, isNotNull);

      final floorTransform = navigator.floorTransform(building);
      final raws = <double>[];

      for (final point in leg!.path) {
        final local = floorTransform.unproject(point[0], point[1]);
        final progress = sectionProgress(leg.section, local[0], local[1]);
        if (progress.$2 && progress.$3 >= 0 && progress.$3 <= 1) {
          raws.add(progress.$3);
        }
      }

      expect(
        raws.any((raw) => raw <= 0.08),
        isTrue,
        reason: 'route must enter the source side of the stair first',
      );
      expect(
        raws.any((raw) => raw >= 0.94),
        isTrue,
        reason: 'route must continue to the actual transition level',
      );
    },
  );
}
