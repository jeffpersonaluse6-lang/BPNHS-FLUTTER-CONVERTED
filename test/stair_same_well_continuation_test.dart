import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/collision.dart';
import 'package:flutter_runtime/navigation/stairs.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';

MapItem makeBuilding({int floors = 4}) {
  return MapItem(
    kind: 'building',
    x: 0,
    y: 0,
    width: 300,
    height: 240,
    floorWidth: 300,
    floorHeight: 240,
    floorCount: floors,
    text: 'Test Building',
    id: 'b1',
  );
}

MapItem upStair(String id, int from, int to, {double x = 220}) {
  return MapItem(
    kind: 'stairs',
    x: x,
    y: 40,
    width: 50,
    height: 140,
    stairDirection: 'up',
    stairFrom: from,
    stairTo: to,
    stairEnabled: true,
    id: id,
  );
}

MapItem downStair(String id, int from, int to, {double x = 220}) {
  return MapItem(
    kind: 'stairs',
    x: x,
    y: 40,
    width: 50,
    height: 140,
    stairDirection: 'down',
    stairFrom: from,
    stairTo: to,
    stairEnabled: true,
    id: id,
  );
}

MapItem sideStair(String id, int from, int to) {
  return MapItem(
    kind: 'stairs',
    x: 40,
    y: 40,
    width: 50,
    height: 140,
    stairDirection: 'up',
    stairFrom: from,
    stairTo: to,
    stairEnabled: true,
    id: id,
  );
}

void main() {
  group('Same-well stair continuation', () {
    test('hasSameWellNextStair detects same-position consecutive stairs', () {
      final b = makeBuilding();
      final s12 = upStair('s12', 1, 2);
      final s23 = upStair('s23', 2, 3);
      final scene = MapScene(
        name: 'same well',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': [s12],
          'b1:Floor 2': [s23],
          'b1:Floor 3': const [],
          'b1:Floor 4': const [],
        },
      );

      final nav = WorldNavigator(scene, collisionRadius: 5);
      nav.enterBuilding(b);
      // After transitioning from Floor 1→2, currentFloor is 2.
      nav.currentFloor = 2;

      final section12 = StairSection(s12, 1, 2);
      expect(nav.hasSameWellNextStair(section12), isTrue,
          reason: 's23 at same position as s12 should be detected as same-well');
    });

    test('hasSameWellNextStair returns false for different-position stairs', () {
      final b = makeBuilding();
      final s12 = upStair('s12', 1, 2, x: 220);
      final s23 = sideStair('s23', 2, 3); // different position
      final scene = MapScene(
        name: 'diff well',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': [s12],
          'b1:Floor 2': [s23],
          'b1:Floor 3': const [],
          'b1:Floor 4': const [],
        },
      );

      final nav = WorldNavigator(scene, collisionRadius: 5);
      nav.enterBuilding(b);
      nav.currentFloor = 2;

      final section12 = StairSection(s12, 1, 2);
      expect(nav.hasSameWellNextStair(section12), isFalse,
          reason: 's23 at different position should not be same-well');
    });

    test('hasSameWellNextStair returns false when no next stair exists', () {
      final b = makeBuilding();
      final s12 = upStair('s12', 1, 2);
      final scene = MapScene(
        name: 'no next',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': [s12],
          'b1:Floor 2': const [],
          'b1:Floor 3': const [],
          'b1:Floor 4': const [],
        },
      );

      final nav = WorldNavigator(scene, collisionRadius: 5);
      nav.enterBuilding(b);
      nav.currentFloor = 2;

      final section12 = StairSection(s12, 1, 2);
      expect(nav.hasSameWellNextStair(section12), isFalse,
          reason: 'no stair on Floor 2 means no same-well continuation');
    });

    test('hasSameWellNextStair returns false for opposite direction', () {
      final b = makeBuilding();
      final s12 = upStair('s12', 1, 2);
      final s21 = downStair('s21', 2, 1);
      final scene = MapScene(
        name: 'opposite',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': [s12],
          'b1:Floor 2': [s21],
          'b1:Floor 3': const [],
          'b1:Floor 4': const [],
        },
      );

      final nav = WorldNavigator(scene, collisionRadius: 5);
      nav.enterBuilding(b);
      nav.currentFloor = 2;

      final section12 = StairSection(s12, 1, 2);
      expect(nav.hasSameWellNextStair(section12), isFalse,
          reason: 'down stair should not match up direction');
    });

    test('clearStairLockForSameWell clears exitAreas, phase, previousPoint, and unlocks next stair', () {
      final b = makeBuilding();
      final s12 = upStair('s12', 1, 2);
      final s23 = upStair('s23', 2, 3);
      final scene = MapScene(
        name: 'lock clear',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': [s12],
          'b1:Floor 2': [s23],
          'b1:Floor 3': const [],
          'b1:Floor 4': const [],
        },
      );

      final nav = WorldNavigator(scene, collisionRadius: 5);
      nav.enterBuilding(b);
      nav.currentFloor = 2;

      // Simulate post-transition state: completed stair 1→2
      nav.exitAreas = [PolygonBarrier(const [[0, 0], [10, 0], [10, 10], [0, 10]])];
      nav.waitFloor = 2;
      nav.phase = TransitionPhase.arrived;
      nav.previousPoint = [10.0, 10.0];
      nav.lastCompletedStair = StairSection(s12, 1, 2);
      // Simulate _lockOverlapping locking the next stair (s23) by accident
      nav.lockedSections.add('s23');

      nav.clearStairLockForSameWell();

      expect(nav.exitAreas, isEmpty);
      expect(nav.waitFloor, isNull);
      expect(nav.phase, TransitionPhase.onFloor);
      expect(nav.previousPoint, isNull,
          reason: 'previousPoint must be reset for fresh source-boundary detection');
      expect(nav.lockedSections.contains('s23'), isFalse,
          reason: 'next stair must be unlocked so it can be armed');
      expect(nav.lockedSections.contains('s12'), isFalse,
          reason: 'completed stair lock is also cleared (only matters for same-floor re-entry)');
    });

    test('1→2→3 continuous progression: findRouteTowardFloor returns legs on each floor', () {
      final b = makeBuilding();
      final s12 = upStair('s12', 1, 2);
      final s23 = upStair('s23', 2, 3);
      final s34 = upStair('s34', 3, 4);
      final scene = MapScene(
        name: 'continuous up',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': [s12],
          'b1:Floor 2': [s23],
          'b1:Floor 3': [s34],
          'b1:Floor 4': const [],
        },
      );

      final nav = WorldNavigator(scene, markerX: 60, markerY: 100, collisionRadius: 5);
      nav.enterBuilding(b);

      // Floor 1: route toward Floor 4
      nav.currentFloor = 1;
      final leg1 = nav.findRouteTowardFloor(4);
      expect(leg1, isNotNull, reason: 'Floor 1 should find stair to Floor 2');
      expect(leg1!.sourceFloor, 1);
      expect(leg1.targetFloor, 2);

      // Simulate transition to Floor 2
      nav.currentFloor = 2;
      nav.clearStairLockForSameWell();
      final leg2 = nav.findRouteTowardFloor(4);
      expect(leg2, isNotNull, reason: 'Floor 2 should find stair to Floor 3');
      expect(leg2!.sourceFloor, 2);
      expect(leg2.targetFloor, 3);

      // Simulate transition to Floor 3
      nav.currentFloor = 3;
      nav.clearStairLockForSameWell();
      final leg3 = nav.findRouteTowardFloor(4);
      expect(leg3, isNotNull, reason: 'Floor 3 should find stair to Floor 4');
      expect(leg3!.sourceFloor, 3);
      expect(leg3.targetFloor, 4);
    });

    test('3→2→1 downward progression: findRouteTowardFloor returns legs on each floor', () {
      final b = makeBuilding();
      final s32 = downStair('s32', 3, 2);
      final s21 = downStair('s21', 2, 1);
      final scene = MapScene(
        name: 'continuous down',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': const [],
          'b1:Floor 2': [s21],
          'b1:Floor 3': [s32],
          'b1:Floor 4': const [],
        },
      );

      final nav = WorldNavigator(scene, markerX: 60, markerY: 100, collisionRadius: 5);
      nav.enterBuilding(b);

      // Floor 3: route toward Floor 1
      nav.currentFloor = 3;
      final leg1 = nav.findRouteTowardFloor(1);
      expect(leg1, isNotNull, reason: 'Floor 3 should find stair to Floor 2');
      expect(leg1!.sourceFloor, 3);
      expect(leg1.targetFloor, 2);

      // Simulate transition to Floor 2
      nav.currentFloor = 2;
      nav.clearStairLockForSameWell();
      final leg2 = nav.findRouteTowardFloor(1);
      expect(leg2, isNotNull, reason: 'Floor 2 should find stair to Floor 1');
      expect(leg2!.sourceFloor, 2);
      expect(leg2.targetFloor, 1);
    });

    test('wrong stair (source != currentFloor) does not instantly change floors', () {
      final b = makeBuilding();
      final s32 = downStair('s32', 3, 2);
      final s21 = downStair('s21', 2, 1);
      final scene = MapScene(
        name: 'wrong stair',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': const [],
          'b1:Floor 2': [s21],
          'b1:Floor 3': [s32],
          'b1:Floor 4': const [],
        },
      );

      final nav = WorldNavigator(scene, markerX: 60, markerY: 100, collisionRadius: 5);
      nav.enterBuilding(b);
      nav.currentFloor = 2;

      // Floor 2→1 stair should NOT be found when routing toward Floor 4 (going up)
      final leg = nav.findRouteTowardFloor(4);
      expect(leg, isNull,
          reason: 'down stair on Floor 2 should not route toward Floor 4');
    });

    test('route entry point matches stair entrance that transition detector accepts', () {
      final b = makeBuilding();
      final s12 = upStair('s12', 1, 2);
      final s23 = upStair('s23', 2, 3);
      final s34 = upStair('s34', 3, 4);
      final scene = MapScene(
        name: 'entry match',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': [s12],
          'b1:Floor 2': [s23],
          'b1:Floor 3': [s34],
          'b1:Floor 4': const [],
        },
      );

      final nav = WorldNavigator(scene, markerX: 60, markerY: 100, collisionRadius: 5);
      nav.enterBuilding(b);
      nav.currentFloor = 1;

      final leg = nav.findRouteTowardFloor(4);
      expect(leg, isNotNull);

      // The entry point is path.last — the target end of the stair lane,
      // which is where the player steps onto the staircase.
      final ft = nav.floorTransform(b);
      final entryLocal = ft.unproject(leg!.entryPoint[0], leg.entryPoint[1]);
      final progress = sectionProgress(leg.section, entryLocal[0], entryLocal[1]);
      expect(progress.$3, greaterThan(0.85),
          reason: 'entry point must be near the target end of the stair');
      expect(progress.$2, isTrue,
          reason: 'entry point must be laterally inside the stair');
    });

    test('same-well route does not require exiting stair footprint', () {
      final b = makeBuilding();
      final s12 = upStair('s12', 1, 2);
      final s23 = upStair('s23', 2, 3);
      final scene = MapScene(
        name: 'no exit needed',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': [s12],
          'b1:Floor 2': [s23],
          'b1:Floor 3': const [],
          'b1:Floor 4': const [],
        },
      );

      final nav = WorldNavigator(scene, markerX: 60, markerY: 100, collisionRadius: 5);
      nav.enterBuilding(b);
      nav.currentFloor = 2;

      final section12 = StairSection(s12, 1, 2);
      expect(nav.hasSameWellNextStair(section12), isTrue);

      // After clearStairLockForSameWell, the next stair should be findable
      nav.clearStairLockForSameWell();
      final leg = nav.findRouteTowardFloor(3);
      expect(leg, isNotNull,
          reason: 'after clearing same-well lock, next stair should be findable');
      expect(leg!.targetFloor, 3);
    });

    test('downward same-well detection works for DOWN stairs', () {
      final b = makeBuilding();
      final s43 = downStair('s43', 4, 3);
      final s32 = downStair('s32', 3, 2);
      final scene = MapScene(
        name: 'down same well',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': const [],
          'b1:Floor 2': const [],
          'b1:Floor 3': [s32],
          'b1:Floor 4': [s43],
        },
      );

      final nav = WorldNavigator(scene, collisionRadius: 5);
      nav.enterBuilding(b);
      nav.currentFloor = 3;

      final section43 = StairSection(s43, 4, 3);
      expect(nav.hasSameWellNextStair(section43), isTrue,
          reason: 's32 at same position as s43 should be same-well for DOWN');
    });

    test('downward different-well stairs are not same-well', () {
      final b = makeBuilding();
      final s43 = downStair('s43', 4, 3, x: 220);
      final s32 = sideStair('s32', 3, 2);
      final scene = MapScene(
        name: 'down diff well',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': const [],
          'b1:Floor 2': const [],
          'b1:Floor 3': [s32],
          'b1:Floor 4': [s43],
        },
      );

      final nav = WorldNavigator(scene, collisionRadius: 5);
      nav.enterBuilding(b);
      nav.currentFloor = 3;

      final section43 = StairSection(s43, 4, 3);
      expect(nav.hasSameWellNextStair(section43), isFalse,
          reason: 's32 at different position should not be same-well for DOWN');
    });

    test('after same-well completion, next stair arms without re-entry', () {
      final b = makeBuilding();
      final s43 = downStair('s43', 4, 3);
      final s32 = downStair('s32', 3, 2);
      final scene = MapScene(
        name: 'arms immediately',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': const [],
          'b1:Floor 2': const [],
          'b1:Floor 3': [s32],
          'b1:Floor 4': [s43],
        },
      );

      final nav = WorldNavigator(scene, markerX: 245, markerY: 42, collisionRadius: 5);
      nav.enterBuilding(b);
      nav.currentFloor = 3;

      // Simulate having just completed 4→3 on the same well.
      nav.lastCompletedStair = StairSection(s43, 4, 3);
      nav.exitAreas = [PolygonBarrier(const [[220, 40], [270, 40], [270, 180], [220, 180]])];
      nav.waitFloor = 3;
      nav.phase = TransitionPhase.arrived;
      nav.previousPoint = [245.0, 178.0];

      // Same-well continuation clears exit state so the next stair can be armed.
      nav.clearStairLockForSameWell();
      expect(nav.exitAreas, isEmpty);
      expect(nav.previousPoint, isNull);

      // Player is positioned just inside the source end of s32 (top of DOWN stair).
      // update() should detect entry and arm the 3→2 transition immediately.
      final changed = nav.update(245, 42);
      expect(changed, isFalse, reason: 'floor should not change until player walks through');
      expect(nav.transition, isNotNull,
          reason: 'next same-well stair should be armed without walking away');
      expect(nav.transition!.target, 2,
          reason: 'armed transition should target Floor 2');
    });

    test('after same-well completion, anti-bounce still prevents returning to completed stair', () {
      final b = makeBuilding();
      final s43 = downStair('s43', 4, 3);
      final s32 = downStair('s32', 3, 2);
      final scene = MapScene(
        name: 'anti-bounce',
        width: 500,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': const [],
          'b1:Floor 2': const [],
          'b1:Floor 3': [s32],
          'b1:Floor 4': [s43],
        },
      );

      final nav = WorldNavigator(scene, markerX: 245, markerY: 42, collisionRadius: 5);
      nav.enterBuilding(b);
      nav.currentFloor = 3;

      nav.lastCompletedStair = StairSection(s43, 4, 3);
      // Simulate _lockOverlapping having locked both overlapping stairs
      nav.lockedSections.add('s43');
      nav.lockedSections.add('s32');

      nav.clearStairLockForSameWell();

      // The completed stair s43 should still be locked (anti-bounce protection).
      expect(nav.lockedSections.contains('s43'), isTrue,
          reason: 'completed stair should remain locked to prevent bounce-back');

      // The next stair s32 should be unlocked for same-well continuation.
      expect(nav.lockedSections.contains('s32'), isFalse,
          reason: 'next stair must be unlocked for same-well continuation');
    });
  });
}
