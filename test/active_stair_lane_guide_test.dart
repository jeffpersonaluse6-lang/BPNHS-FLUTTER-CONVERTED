import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/stairs.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';

void main() {
  test('active stair guide stays on the player current lane', () {
    final building = MapItem(
      kind: 'building',
      x: 0,
      y: 0,
      width: 300,
      height: 220,
      floorWidth: 300,
      floorHeight: 220,
      floorCount: 2,
      id: 'b1',
    );
    final stair = MapItem(
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
      name: 'stair lane',
      width: 500,
      height: 400,
      floors: {
        'Campus': [building],
        'b1:Floor 1': const [],
        'b1:Floor 2': [stair],
        'b1:Roof': const [],
      },
    );

    final navigator = WorldNavigator(
      scene,
      markerX: 0,
      markerY: 0,
      collisionRadius: 5,
    );
    navigator.enterBuilding(building);
    navigator.currentFloor = 2;

    final section = StairSection(stair, 2, 1);
    navigator.transition = FloorTransition(section, 2, 1, 0.35);

    // Place player on LEFT side of the active stair. Previous behavior forced
    // DOWN guidance to the right lane, making the first blue segment cross the
    // center railing.
    final floorPoint = stair.localToWorld(10, 70); // 20% of stair width
    final worldPoint = navigator
        .floorTransform(building)
        .project(floorPoint[0], floorPoint[1]);
    navigator.markerX = worldPoint[0];
    navigator.markerY = worldPoint[1];

    final guide = navigator.activeStairRouteGuide();
    expect(guide.length, greaterThan(1));

    for (final point in guide.skip(1)) {
      final floorLocal = navigator
          .floorTransform(building)
          .unproject(point[0], point[1]);
      final stairLocal = stair.worldToLocal(floorLocal[0], floorLocal[1]);

      expect(
        stairLocal[0] / stair.width,
        closeTo(0.20, 0.001),
        reason: 'future stair guide points must stay on the player lane',
      );
    }
  });
}
