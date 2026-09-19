import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/stairs.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';

void main() {
  test('completed stair turnaround exits the completed stair footprint', () {
    final building = MapItem(
      kind: 'building',
      x: 0,
      y: 0,
      width: 320,
      height: 240,
      floorWidth: 320,
      floorHeight: 240,
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
    final scene = MapScene(
      name: 'turnaround',
      width: 500,
      height: 400,
      floors: {
        'Campus': [building],
        'b1:Floor 1': const [],
        'b1:Floor 2': const [],
        'b1:Floor 3': [stair],
        'b1:Roof': const [],
      },
    );

    final navigator = WorldNavigator(
      scene,
      markerX: 250,
      markerY: 175,
      collisionRadius: 5,
    );
    navigator.enterBuilding(building);
    navigator.currentFloor = 2;
    navigator.lastCompletedStair = StairSection(stair, 3, 2);

    final guide = navigator.completedStairTurnaroundGuide();
    expect(guide.length, greaterThanOrEqualTo(2));

    final ft = navigator.floorTransform(building);
    final finalFloorLocal = ft.unproject(guide.last[0], guide.last[1]);
    final finalProgress = sectionProgress(
      navigator.lastCompletedStair!,
      finalFloorLocal[0],
      finalFloorLocal[1],
    ).$3;
    expect(
      finalProgress,
      greaterThan(1),
      reason: 'turnaround must finish beyond the completed target side',
    );
  });
}
