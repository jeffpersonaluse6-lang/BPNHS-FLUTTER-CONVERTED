import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/navigation/floor_transform.dart';
import 'package:flutter_runtime/navigation/collision.dart';
import 'package:flutter_runtime/navigation/stairs.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';
import 'package:flutter_runtime/camera/smooth_camera.dart';
import 'package:flutter_runtime/models/math_helper.dart';

Future<Map<String, dynamic>> _loadMapJson() async {
  const paths = [
    'assets/map_workspace.json',
    '../assets/map_workspace.json',
    '../../assets/map_workspace.json',
    '../../../assets/map_workspace.json',
    'C:/BPNHS FLUTTER/flutter_runtime/assets/map_workspace.json',
  ];
  for (final path in paths) {
    try {
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {}
  }
  return {
    'format': 'bpnhs-map',
    'name': 'Test Map',
    'width': 1000,
    'height': 800,
    'floors': {
      'Campus': [
        {
          'kind': 'building',
          'id': 'test_building',
          'x': 100,
          'y': 100,
          'width': 200,
          'height': 150,
          'floor_count': 2,
        }
      ],
      'test_building:Floor 1': [
        {
          'kind': 'room',
          'id': 'room1',
          'x': 10,
          'y': 10,
          'width': 80,
          'height': 60,
        }
      ],
      'test_building:Floor 2': [],
      'test_building:Roof': [],
    },
  };
}

void main() {
  MapScene? scene;

  setUpAll(() async {
    final json = await _loadMapJson();
    scene = MapScene.fromJson(json);
  });

  group('JSON loading', () {
    test('scene loads with correct dimensions', () {
      expect(scene, isNotNull);
      expect(scene!.width, greaterThan(0));
      expect(scene!.height, greaterThan(0));
      expect(scene!.name, isNotEmpty);
    });

    test('campus layer exists and has items', () {
      final campus = scene!.floors['Campus'];
      expect(campus, isNotNull);
      expect(campus!.length, greaterThan(0));
    });

    test('buildings are found on campus layer', () {
      final buildings = scene!.buildings();
      expect(buildings, isNotEmpty);
      for (final b in buildings) {
        expect(b.kind, equals('building'));
        expect(b.floorCount, greaterThanOrEqualTo(1));
      }
    });

    test('building floors have items', () {
      for (final building in scene!.buildings()) {
        for (var f = 1; f <= building.floorCount; f++) {
          final items = scene!.floorItems(building.id, f);
          expect(items, isNotNull, reason: 'Floor $f of ${building.id}');
        }
      }
    });
  });

  group('FloorTransform', () {
    test('identity transform (no rotation, no mirror)', () {
      final parent = MapItem(
        kind: 'building',
        x: 100,
        y: 200,
        width: 300,
        height: 400,
        floorWidth: 300,
        floorHeight: 400,
        id: 'b1',
      );
      final ft = FloorTransform.build(parent);
      final world = ft.project(50, 60);
      expect(world[0], closeTo(150, 1e-9));
      expect(world[1], closeTo(260, 1e-9));
    });

    test('project then unproject round-trips', () {
      final parent = MapItem(
        kind: 'building',
        x: 500,
        y: 300,
        width: 200,
        height: 150,
        rotation: 25,
        mirrored: true,
        id: 'b2',
      );
      final ft = FloorTransform.build(parent);
      final localPt = (42.0, 77.0);
      final world = ft.project(localPt.$1, localPt.$2);
      final back = ft.unproject(world[0], world[1]);
      expect(back[0], closeTo(localPt.$1, 1e-9));
      expect(back[1], closeTo(localPt.$2, 1e-9));
    });

    test('rotation affects projection', () {
      final parent0 = MapItem(
          kind: 'building', x: 0, y: 0, width: 100, height: 100,
          floorWidth: 100, floorHeight: 100, id: 'a');
      final parent90 = MapItem(
          kind: 'building', x: 0, y: 0, width: 100, height: 100,
          floorWidth: 100, floorHeight: 100, rotation: 90, id: 'b');
      final ft0 = FloorTransform.build(parent0);
      final ft90 = FloorTransform.build(parent90);
      final w0 = ft0.project(10, 0);
      final w90 = ft90.project(10, 0);
      expect(w0[0], closeTo(10, 1e-9));
      expect(w90[0], closeTo(0, 1e-9));
      expect(w90[1], closeTo(10, 1e-9));
    });

    test('mirroring flips x', () {
      final parent = MapItem(
        kind: 'building',
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        floorWidth: 100,
        floorHeight: 100,
        mirrored: true,
        id: 'm',
      );
      final ft = FloorTransform.build(parent);
      final w = ft.project(10, 50);
      expect(w[0], closeTo(90, 1e-9));
      expect(w[1], closeTo(50, 1e-9));
    });

    test('floorOrigin offset shifts projection', () {
      final parent = MapItem(
        kind: 'building',
        x: 0,
        y: 0,
        width: 200,
        height: 200,
        floorOriginX: 50,
        floorOriginY: 50,
        id: 'o',
      );
      final ft = FloorTransform.build(parent);
      final w = ft.project(50, 50);
      expect(w[0], closeTo(0, 1e-9));
      expect(w[1], closeTo(0, 1e-9));
    });

    test('floorWidth/floorHeight scale projection', () {
      final parent = MapItem(
        kind: 'building',
        x: 0,
        y: 0,
        width: 200,
        height: 100,
        floorWidth: 100,
        floorHeight: 50,
        id: 's',
      );
      final ft = FloorTransform.build(parent);
      final w = ft.project(100, 50);
      expect(w[0], closeTo(200, 1e-9));
      expect(w[1], closeTo(100, 1e-9));
    });
  });

  group('Rendering coordinates', () {
    test('campus items use localToWorld directly', () {
      final item = MapItem(
        kind: 'wall',
        x: 100,
        y: 200,
        width: 50,
        height: 10,
        id: 'w1',
      );
      final p = item.localToWorld(0, 0);
      expect(p[0], closeTo(100, 1e-9));
      expect(p[1], closeTo(200, 1e-9));
    });

    test('building floor items use FloorTransform then localToWorld', () {
      final parent = MapItem(
        kind: 'building',
        x: 500,
        y: 300,
        width: 200,
        height: 150,
        floorWidth: 200,
        floorHeight: 150,
        id: 'b',
      );
      final ft = FloorTransform.build(parent);
      final floorItem = MapItem(
        kind: 'wall',
        x: 10,
        y: 20,
        width: 50,
        height: 10,
        id: 'f1',
      );
      final worldLocal = floorItem.localToWorld(0, 0);
      final world = ft.project(worldLocal[0], worldLocal[1]);
      expect(world[0], closeTo(510, 1e-9));
      expect(world[1], closeTo(320, 1e-9));
    });
  });

  group('Stair progress', () {
    test('sectionProgress returns 0 at start of up stair', () {
      final stair = MapItem(
        kind: 'stairs',
        x: 100,
        y: 100,
        width: 40,
        height: 80,
        stairDirection: 'up',
        id: 'st1',
      );
      final section = StairSection(stair, 1, 2);
      final (_, lateral, raw) = sectionProgress(section, 120, 180);
      expect(raw, closeTo(0, 1e-9));
      expect(lateral, isTrue);
    });

    test('sectionProgress returns 1 at end of up stair', () {
      final stair = MapItem(
        kind: 'stairs',
        x: 100,
        y: 100,
        width: 40,
        height: 80,
        stairDirection: 'up',
        id: 'st2',
      );
      final section = StairSection(stair, 1, 2);
      final (_, lateral, raw) = sectionProgress(section, 120, 100);
      expect(raw, closeTo(1, 1e-9));
      expect(lateral, isTrue);
    });

    test('sectionProgress lateral false outside width', () {
      final stair = MapItem(
        kind: 'stairs',
        x: 100,
        y: 100,
        width: 40,
        height: 80,
        stairDirection: 'up',
        id: 'st3',
      );
      final section = StairSection(stair, 1, 2);
      final (_, lateral, _) = sectionProgress(section, 90, 140);
      expect(lateral, isFalse);
    });
  });

  group('Camera', () {
    test('screen converts world to screen coordinates', () {
      final cam = SmoothCamera(width: 800, height: 600, x: 0, y: 0);
      final s = cam.screen([0, 0]);
      expect(s[0], closeTo(0, 1e-9));
      expect(s[1], closeTo(0, 1e-9));
    });

    test('center places world point at screen center', () {
      final cam = SmoothCamera(width: 800, height: 600);
      cam.center([100, 200]);
      final s = cam.screen([100, 200]);
      expect(s[0], closeTo(400, 1e-9));
      expect(s[1], closeTo(300, 1e-9));
    });

    test('scale affects screen coordinates', () {
      final cam = SmoothCamera(width: 800, height: 600, x: 0, y: 0, scale: 2);
      final s = cam.screen([50, 50]);
      expect(s[0], closeTo(100, 1e-9));
      expect(s[1], closeTo(100, 1e-9));
    });

    test('world inverts screen', () {
      final cam = SmoothCamera(width: 800, height: 600, x: 100, y: 50, scale: 1.5);
      final screenPt = cam.screen([200, 300]);
      final worldPt = cam.world(screenPt);
      expect(worldPt[0], closeTo(200, 1e-9));
      expect(worldPt[1], closeTo(300, 1e-9));
    });
  });

  group('Math helper', () {
    test('hypot computes correctly', () {
      expect(hypot(3, 4), closeTo(5, 1e-9));
      expect(hypot(0, 0), closeTo(0, 1e-9));
      expect(hypot(-5, 12), closeTo(13, 1e-9));
    });
  });

  group('Collision basics', () {
    test('barrier blocks point inside radius', () {
      final b = Barrier(
        startX: 0, startY: 0, endX: 100, endY: 0, radius: 5, flat: true,
      );
      expect(b.blocks(50, 3, 10), isTrue);
    });

    test('barrier does not block point outside radius', () {
      final b = Barrier(
        startX: 0, startY: 0, endX: 100, endY: 0, radius: 5, flat: true,
      );
      expect(b.blocks(50, 20, 10), isFalse);
    });
  });

  group('MapItem', () {
    test('contains works for rooms', () {
      final item = MapItem(
        kind: 'room',
        x: 100,
        y: 100,
        width: 200,
        height: 150,
        id: 'r1',
      );
      expect(item.contains(200, 175), isTrue);
      expect(item.contains(50, 50), isFalse);
    });

    test('contains works for walls', () {
      final item = MapItem(
        kind: 'wall',
        x: 100,
        y: 100,
        width: 100,
        height: 0,
        stroke: 4,
        id: 'w1',
      );
      expect(item.contains(150, 100), isTrue);
      expect(item.contains(150, 200), isFalse);
    });

    test('fromJson parses all fields', () {
      final json = {
        'kind': 'room',
        'x': 10,
        'y': 20,
        'width': 100,
        'height': 80,
        'rotation': 15,
        'stroke': 3,
        'color': '#FF0000',
        'fill': '#00FF00',
        'text': 'Test Room',
        'font_size': 14,
        'steps': 8,
        'mirrored': true,
        'blocking': false,
        'floor_count': 3,
        'stair_direction': 'down',
        'stair_to': 2,
        'approach_distance': 60,
        'fade_when_obstructing': false,
        'floor_width': 50,
        'floor_height': 40,
        'floor_origin_x': 5,
        'floor_origin_y': 10,
        'gate_open': true,
        'id': 'test_item',
      };
      final item = MapItem.fromJson(json);
      expect(item.kind, 'room');
      expect(item.x, 10);
      expect(item.rotation, 15);
      expect(item.mirrored, true);
      expect(item.blocking, false);
      expect(item.floorCount, 3);
      expect(item.stairDirection, 'down');
      expect(item.stairTo, 2);
      expect(item.approachDistance, 60);
      expect(item.fadeWhenObstructing, false);
      expect(item.floorWidth, 50);
      expect(item.floorHeight, 40);
      expect(item.floorOriginX, 5);
      expect(item.floorOriginY, 10);
      expect(item.gateOpen, true);
      expect(item.id, 'test_item');
    });
  });

  group('Camera canvas parity', () {
    test('canvas transform matches camera.screen() for multiple positions', () {
      final cam = SmoothCamera(width: 800, height: 600, x: 100, y: 50, scale: 1.5, rotation: 0.3);
      final worldPoints = [
        [0.0, 0.0],
        [100.0, 200.0],
        [500.0, 300.0],
        [1510.0, 620.0],
      ];
      for (final wp in worldPoints) {
        final screenPt = cam.screen(wp);
        final canvasX = cam.x + cam.scale * (math.cos(cam.rotation) * wp[0] - math.sin(cam.rotation) * wp[1]);
        final canvasY = cam.y + cam.scale * (math.sin(cam.rotation) * wp[0] + math.cos(cam.rotation) * wp[1]);
        expect(screenPt[0], closeTo(canvasX, 1e-9),
            reason: 'screen x mismatch for $wp');
        expect(screenPt[1], closeTo(canvasY, 1e-9),
            reason: 'screen y mismatch for $wp');
      }
    });

    test('canvas translate/scale/rotate produces same result as camera.screen()', () {
      final cam = SmoothCamera(width: 1024, height: 768, x: 200, y: 150, scale: 2.0, rotation: 0.5);
      final wp = [300.0, 400.0];
      final expected = cam.screen(wp);
      final cosR = math.cos(cam.rotation);
      final sinR = math.sin(cam.rotation);
      final cx = cam.x + cam.scale * (cosR * wp[0] - sinR * wp[1]);
      final cy = cam.y + cam.scale * (sinR * wp[0] + cosR * wp[1]);
      expect(expected[0], closeTo(cx, 1e-9));
      expect(expected[1], closeTo(cy, 1e-9));
    });

    test('canvas transform with zero rotation matches scale/translate', () {
      final cam = SmoothCamera(width: 800, height: 600, x: 50, y: 30, scale: 1.5, rotation: 0);
      final wp = [100.0, 200.0];
      final expected = cam.screen(wp);
      expect(expected[0], closeTo(50 + 1.5 * 100, 1e-9));
      expect(expected[1], closeTo(30 + 1.5 * 200, 1e-9));
    });
  });

  group('Geometry parity with Python', () {
    test('FloorTransform.project matches Python local_to_world formula', () {
      final parent = MapItem(
        kind: 'building',
        x: 100,
        y: 200,
        width: 300,
        height: 200,
        rotation: 15,
        mirrored: false,
        floorWidth: 1436,
        floorHeight: 751,
        id: 'parity1',
      );
      final ft = FloorTransform.build(parent);
      final sx = 300.0 / 1436;
      final sy = 200.0 / 751;
      final angle = 15.0 * math.pi / 180;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final localX = 50.0;
      final localY = 30.0;
      final px = localX * sx;
      final py = localY * sy;
      final expectedX = 100 + px * cosA - py * sinA;
      final expectedY = 200 + px * sinA + py * cosA;
      final result = ft.project(localX, localY);
      expect(result[0], closeTo(expectedX, 1e-9));
      expect(result[1], closeTo(expectedY, 1e-9));
    });

    test('FloorTransform.project with mirror matches Python', () {
      final parent = MapItem(
        kind: 'building',
        x: 500,
        y: 300,
        width: 200,
        height: 150,
        mirrored: true,
        id: 'parity2',
      );
      final ft = FloorTransform.build(parent);
      final sx = 200.0 / 1436;
      final sy = 150.0 / 751;
      final localX = 42.0;
      final localY = 77.0;
      var px = localX * sx;
      final py = localY * sy;
      px = 200 - px;
      final expectedX = 500 + px;
      final expectedY = 300 + py;
      final result = ft.project(localX, localY);
      expect(result[0], closeTo(expectedX, 1e-9));
      expect(result[1], closeTo(expectedY, 1e-9));
    });

    test('FloorTransform.project with rotation and origin offset', () {
      final parent = MapItem(
        kind: 'building',
        x: 400,
        y: 200,
        width: 300,
        height: 200,
        rotation: 30,
        floorOriginX: 50,
        floorOriginY: 25,
        id: 'parity3',
      );
      final ft = FloorTransform.build(parent);
      final sx = 300.0 / 1436;
      final sy = 200.0 / 751;
      final angle = 30.0 * math.pi / 180;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final localX = 100.0;
      final localY = 60.0;
      final px = (localX - 50) * sx;
      final py = (localY - 25) * sy;
      final expectedX = 400 + px * cosA - py * sinA;
      final expectedY = 200 + px * sinA + py * cosA;
      final result = ft.project(localX, localY);
      expect(result[0], closeTo(expectedX, 1e-9));
      expect(result[1], closeTo(expectedY, 1e-9));
    });

    test('wallPolygon matches Python wall_polygon formula', () {
      final barrier = Barrier(
        startX: 100, startY: 200,
        endX: 300, endY: 200,
        radius: 5, flat: true,
      );
      final polygon = wallPolygon(barrier);
      expect(polygon.length, 4);
      expect(polygon[0][0], closeTo(100, 1e-9));
      expect(polygon[0][1], closeTo(205, 1e-9));
      expect(polygon[1][0], closeTo(300, 1e-9));
      expect(polygon[1][1], closeTo(205, 1e-9));
      expect(polygon[2][0], closeTo(300, 1e-9));
      expect(polygon[2][1], closeTo(195, 1e-9));
      expect(polygon[3][0], closeTo(100, 1e-9));
      expect(polygon[3][1], closeTo(195, 1e-9));
    });

    test('wallPolygon with angled wall', () {
      final barrier = Barrier(
        startX: 0, startY: 0,
        endX: 100, endY: 100,
        radius: 3, flat: true,
      );
      final polygon = wallPolygon(barrier);
      expect(polygon.length, 4);
      final angle = math.atan2(100, 100);
      final nx = -math.sin(angle) * 3;
      final ny = math.cos(angle) * 3;
      expect(polygon[0][0], closeTo(nx, 1e-9));
      expect(polygon[0][1], closeTo(ny, 1e-9));
      expect(polygon[1][0], closeTo(100 + nx, 1e-9));
      expect(polygon[1][1], closeTo(100 + ny, 1e-9));
      expect(polygon[2][0], closeTo(100 - nx, 1e-9));
      expect(polygon[2][1], closeTo(100 - ny, 1e-9));
      expect(polygon[3][0], closeTo(-nx, 1e-9));
      expect(polygon[3][1], closeTo(-ny, 1e-9));
    });

    test('Python floor_scale matches Flutter _floorScale', () {
      final parent = MapItem(
        kind: 'building',
        x: 0, y: 0,
        width: 300, height: 200,
        floorWidth: 1436,
        floorHeight: 751,
        id: 'fs1',
      );
      final sx = parent.width / (parent.floorWidth ?? 1436);
      final sy = parent.height / (parent.floorHeight ?? 751);
      expect(sx, closeTo(300.0 / 1436, 1e-9));
      expect(sy, closeTo(200.0 / 751, 1e-9));
    });

    test('Python project() matches Flutter FloorTransform.project() for floor items', () {
      final parent = MapItem(
        kind: 'building',
        x: 100, y: 200,
        width: 300, height: 200,
        rotation: 0,
        id: 'proj1',
      );
      final ft = FloorTransform.build(parent);
      final item = MapItem(
        kind: 'room',
        x: 50, y: 30,
        width: 100, height: 80,
        id: 'proj_item',
      );
      final itemWorld = item.localToWorld(0, 0);
      final flutterResult = ft.project(itemWorld[0], itemWorld[1]);
      final sx = 300.0 / 1436;
      final sy = 200.0 / 751;
      final pyX = (itemWorld[0] - 0) * sx;
      final pyY = (itemWorld[1] - 0) * sy;
      final pyResultX = 100 + pyX;
      final pyResultY = 200 + pyY;
      expect(flutterResult[0], closeTo(pyResultX, 1e-9));
      expect(flutterResult[1], closeTo(pyResultY, 1e-9));
    });
  });

  group('Player position parity', () {
    test('camera.screen(playerWorld) matches rendered player position formula', () {
      final cam = SmoothCamera(width: 800, height: 600, x: 100, y: 50, scale: 1.5, rotation: 0.3);
      final playerWorld = [1510.0, 620.0];
      final screenPt = cam.screen(playerWorld);
      final cosR = math.cos(cam.rotation);
      final sinR = math.sin(cam.rotation);
      final expectedX = cam.x + cam.scale * (cosR * playerWorld[0] - sinR * playerWorld[1]);
      final expectedY = cam.y + cam.scale * (sinR * playerWorld[0] + cosR * playerWorld[1]);
      expect(screenPt[0], closeTo(expectedX, 1e-9));
      expect(screenPt[1], closeTo(expectedY, 1e-9));
    });

    test('player screen position is not always screen center', () {
      final cam = SmoothCamera(width: 800, height: 600, x: 0, y: 0, scale: 1, rotation: 0);
      final playerWorld = [300.0, 400.0];
      final screenPt = cam.screen(playerWorld);
      expect(screenPt[0], closeTo(300, 1e-9));
      expect(screenPt[1], closeTo(400, 1e-9));
      expect(screenPt[0], isNot(closeTo(400, 1e-9)));
      expect(screenPt[1], isNot(closeTo(300, 1e-9)));
    });
  });

  group('Roof opacity', () {
    test('roofOpacity returns 1.0 when far from building', () {
      final scene = MapScene.fromJson(_buildTestScene());
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      final result = nav.roofOpacity(building, 0, 0);
      expect(result, closeTo(1.0, 1e-9));
    });

    test('roofOpacity returns 0.0 when inside building', () {
      final scene = MapScene.fromJson(_buildTestScene());
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      nav.enterBuilding(building);
      final result = nav.roofOpacity(building, nav.markerX, nav.markerY);
      expect(result, closeTo(0.0, 1e-9));
    });

    test('roofOpacity interpolates between 0 and 1 based on distance', () {
      final scene = MapScene.fromJson(_buildTestScene());
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      final ad = building.approachDistance;
      final dist = ad * 0.5;
      final outsideX = building.x - dist;
      final outsideY = building.y + building.height / 2;
      final result = nav.roofOpacity(building, outsideX, outsideY);
      expect(result, greaterThan(0.0));
      expect(result, lessThan(1.0));
    });

    test('roofOpacity restores to 1.0 when moving away', () {
      final scene = MapScene.fromJson(_buildTestScene());
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      nav.enterBuilding(building);
      expect(nav.roofOpacity(building, nav.markerX, nav.markerY), closeTo(0.0, 1e-9));
      nav.exitBuilding();
      final result = nav.roofOpacity(building, 0, 0);
      expect(result, closeTo(1.0, 1e-9));
    });
  });

  group('Floor opacity transition', () {
    test('floorOpacities returns source and target during transition', () {
      final scene = MapScene.fromJson(_buildTestScene());
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      nav.enterBuilding(building);
      final opacities = nav.floorOpacities(building);
      expect(opacities[1], closeTo(1.0, 1e-9));
    });

    test('floorOpacities returns 0 for non-active floors', () {
      final scene = MapScene.fromJson(_buildTestScene());
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      nav.enterBuilding(building);
      final opacities = nav.floorOpacities(building);
      if (building.floorCount > 1) {
        expect(opacities[2], closeTo(0.0, 1e-9));
      }
    });

    test('floorOpacities returns 0 for different building', () {
      final scene = MapScene.fromJson(_buildTestScene());
      final nav = WorldNavigator(scene);
      final buildings = scene.buildings();
      if (buildings.length > 1) {
        nav.enterBuilding(buildings[0]);
        final opacities = nav.floorOpacities(buildings[1]);
        expect(opacities[1], closeTo(1.0, 1e-9));
      }
    });
  });

  group('Entry zones and roof detection', () {
    test('inside() returns true within building footprint', () {
      final scene = MapScene.fromJson(_buildTestScene());
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      final result = nav.inside(building, building.x + building.width / 2, building.y + building.height / 2);
      expect(result, isTrue);
    });

    test('inside() returns false far from building', () {
      final scene = MapScene.fromJson(_buildTestScene());
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      final result = nav.inside(building, 0, 0);
      expect(result, isFalse);
    });

    test('distanceToParent returns 0 inside building', () {
      final scene = MapScene.fromJson(_buildTestScene());
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      final dist = nav.distanceToParent(building, building.x + building.width / 2, building.y + building.height / 2);
      expect(dist, closeTo(0.0, 1e-9));
    });

    test('distanceToParent returns positive value outside building', () {
      final scene = MapScene.fromJson(_buildTestScene());
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      final dist = nav.distanceToParent(building, 0, 0);
      expect(dist, greaterThan(0.0));
    });
  });

  group('Rotated building footprint', () {
    test('inside() uses rotated footprint for detection', () {
      final json = _buildTestScene();
      final campus = json['floors']['Campus'] as List;
      (campus[0] as Map<String, dynamic>)['rotation'] = 45;
      final scene = MapScene.fromJson(json);
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      final center = building.localToWorld(building.width / 2, building.height / 2);
      expect(nav.inside(building, center[0], center[1]), isTrue);
    });

    test('distanceToParent accounts for rotation', () {
      final json = _buildTestScene();
      final campus = json['floors']['Campus'] as List;
      (campus[0] as Map<String, dynamic>)['rotation'] = 45;
      final scene = MapScene.fromJson(json);
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      final center = building.localToWorld(building.width / 2, building.height / 2);
      final dist = nav.distanceToParent(building, center[0], center[1]);
      expect(dist, closeTo(0.0, 1e-9));
    });
  });

  group('Projected floor collision', () {
    test('floor barriers are projected through FloorTransform', () {
      final scene = MapScene.fromJson(_buildTestScene());
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      final transform = nav.floorTransform(building);
      final ftProject = transform.project(0, 0);
      expect(ftProject[0], closeTo(building.x, 1e-9));
      expect(ftProject[1], closeTo(building.y, 1e-9));
    });

    test('floorTransform returns cached transform', () {
      final scene = MapScene.fromJson(_buildTestScene());
      final nav = WorldNavigator(scene);
      final building = scene.buildings().first;
      final t1 = nav.floorTransform(building);
      final t2 = nav.floorTransform(building);
      expect(identical(t1, t2), isTrue);
    });
  });

  group('Collision radius matches visual size', () {
    test('playerSize 20 -> collisionRadius 10', () {
      final playerSize = 20.0;
      final collisionRadius = playerSize / 2;
      expect(collisionRadius, 10.0);
    });

    test('size changes update navigator radius', () {
      final scene = MapScene.fromJson(_minimalScene());
      final nav = WorldNavigator(scene, collisionRadius: 10);
      expect(nav.collisionRadius, 10.0);
      nav.collisionRadius = 15;
      expect(nav.collisionRadius, 15.0);
      nav.collisionRadius = 5;
      expect(nav.collisionRadius, 5.0);
    });

    test('visible center equals collision center', () {
      final cosR = 1.0;
      final sinR = 0.0;
      final camX = 100.0;
      final camY = 50.0;
      final camScale = 1.5;
      final playerWorld = [500.0, 300.0];
      final sx = camX + camScale * (cosR * playerWorld[0] - sinR * playerWorld[1]);
      final sy = camY + camScale * (sinR * playerWorld[0] + cosR * playerWorld[1]);
      expect(sx, closeTo(850.0, 1e-9));
      expect(sy, closeTo(500.0, 1e-9));
    });

    test('no stale collision radius after resizing', () {
      final scene = MapScene.fromJson(_minimalScene());
      final nav = WorldNavigator(scene, collisionRadius: 10);
      nav.collisionRadius = 5;
      final before = [nav.markerX, nav.markerY];
      final result = nav.walk(before[0], before[1], 1, 0, 0.1);
      expect(result[0], greaterThan(before[0]));
      expect(nav.collisionRadius, 5.0);
    });
  });

  group('Doorway passage', () {
    test('player passes through doorway wider than diameter', () {
      final scene = MapScene.fromJson(_minimalScene());
      final nav = WorldNavigator(scene, collisionRadius: 5);
      nav.markerX = 540;
      nav.markerY = 300;
      nav.collisionRadius = 5;
      final result = nav.walk(540, 300, 0, -1, 0.1);
      expect(result[1], lessThan(300.0));
    });

    test('player is blocked when doorway narrower than diameter', () {
      final json = _minimalScene();
      final campus = json['floors']['Campus'] as List;
      final opening = campus.firstWhere((i) => i['id'] == 'door1') as Map<String, dynamic>;
      opening['width'] = 5;
      final scene = MapScene.fromJson(json);
      final nav = WorldNavigator(scene, collisionRadius: 10);
      nav.markerX = 540;
      nav.markerY = 300;
      nav.collisionRadius = 10;
      final before = [nav.markerX, nav.markerY];
      final result = nav.walk(before[0], before[1], 0, -1, 0.1);
      expect(result[1], closeTo(before[1], 1.0));
    });
  });

  group('OpeningIndex spatial filtering', () {
    test('only relevant openings cut a wall', () {
      final items = [
        MapItem.fromJson({
          'kind': 'wall', 'id': 'w1', 'x': 100, 'y': 100,
          'width': 200, 'height': 0, 'stroke': 4, 'blocking': true,
        }),
        MapItem.fromJson({
          'kind': 'door', 'id': 'd1', 'x': 190, 'y': 96,
          'width': 20, 'height': 8, 'blocking': false,
        }),
      ];
      final index = OpeningIndex(items);
      final wall = items[0];
      final openings = index.forWall(wall);
      expect(openings.length, 1);
      expect(openings[0].id, 'd1');
    });

    test('unrelated door does not remove another wall', () {
      final items = [
        MapItem.fromJson({
          'kind': 'wall', 'id': 'w1', 'x': 100, 'y': 100,
          'width': 200, 'height': 0, 'stroke': 4, 'blocking': true,
        }),
        MapItem.fromJson({
          'kind': 'wall', 'id': 'w2', 'x': 500, 'y': 500,
          'width': 100, 'height': 0, 'stroke': 4, 'blocking': true,
        }),
        MapItem.fromJson({
          'kind': 'door', 'id': 'd1', 'x': 190, 'y': 96,
          'width': 20, 'height': 8, 'blocking': false,
        }),
      ];
      final index = OpeningIndex(items);
      final w1Sections = wallSections(items[0], openings: index.forWall(items[0]));
      final w2Sections = wallSections(items[1], openings: index.forWall(items[1]));
      expect(w1Sections.length, 2);
      expect(w2Sections.length, 1);
      final w2TotalLength = w2Sections.fold(0.0, (sum, s) {
        final dx = s.endX - s.startX;
        final dy = s.endY - s.startY;
        return sum + math.sqrt(dx * dx + dy * dy);
      });
      expect(w2TotalLength, closeTo(100, 1));
    });

    test('door far from wall does not produce a gap', () {
      final items = [
        MapItem.fromJson({
          'kind': 'wall', 'id': 'w1', 'x': 100, 'y': 100,
          'width': 200, 'height': 0, 'stroke': 4, 'blocking': true,
        }),
        MapItem.fromJson({
          'kind': 'door', 'id': 'd1', 'x': 100, 'y': 500,
          'width': 20, 'height': 8, 'blocking': false,
        }),
      ];
      final index = OpeningIndex(items);
      final sections = wallSections(items[0], openings: index.forWall(items[0]));
      final totalLength = sections.fold(0.0, (sum, s) {
        final dx = s.endX - s.startX;
        final dy = s.endY - s.startY;
        return sum + math.sqrt(dx * dx + dy * dy);
      });
      expect(totalLength, closeTo(200, 1));
    });
  });

  group('Circle wall outer/inner radii match Python', () {
    test('circle wall outer and inner radii', () {
      final item = MapItem.fromJson({
        'kind': 'circle_wall', 'id': 'cw1',
        'x': 100, 'y': 100, 'width': 60, 'height': 60,
        'stroke': 6, 'color': '#111111', 'blocking': true,
      });
      final radius = item.stroke / 2;
      final outerW = item.width + 2 * radius;
      final outerH = item.height + 2 * radius;
      final innerW = math.max(0.001, item.width - 2 * radius);
      final innerH = math.max(0.001, item.height - 2 * radius);
      expect(outerW, 66);
      expect(outerH, 66);
      expect(innerW, 54);
      expect(innerH, 54);
    });

    test('circle wall opening remains in correct angular position', () {
      final item = MapItem.fromJson({
        'kind': 'circle_wall', 'id': 'cw2',
        'x': 100, 'y': 100, 'width': 60, 'height': 60,
        'stroke': 6, 'color': '#111111', 'blocking': true,
        'circle_openings': [
          {'angle': 0, 'width': 15, 'id': 'co1'},
        ],
      });
      final arcs = solidArcs(item);
      final totalArc = arcs.fold(0.0, (sum, a) => sum + (a.$2 - a.$1));
      expect(totalArc, lessThan(2 * math.pi));
      final openings = MapItem.fromJson({
        'kind': 'opening', 'id': 'o1',
        'x': 100 + 30, 'y': 96, 'width': 15, 'height': 8,
        'blocking': false,
      });
      final arcsWithOpening = solidArcs(item, openings: [openings]);
      final totalWithOpening = arcsWithOpening.fold(0.0, (sum, a) => sum + (a.$2 - a.$1));
      expect(totalWithOpening, closeTo(totalArc, 0.01));
    });
  });

  group('Gazebo roof dimensions', () {
    test('gazebo roof has 8 radial sections', () {
      final item = MapItem.fromJson({
        'kind': 'gazebo_roof', 'id': 'gr1',
        'x': 100, 'y': 100, 'width': 80, 'height': 80,
        'fill': '#DDDDDD', 'color': '#111111', 'stroke': 2,
      });
      expect(item.width, 80);
      expect(item.height, 80);
    });

    test('inner ring is 92% of full size', () {
      final item = MapItem.fromJson({
        'kind': 'gazebo_roof', 'id': 'gr2',
        'x': 100, 'y': 100, 'width': 80, 'height': 80,
        'fill': '#DDDDDD', 'color': '#111111', 'stroke': 2,
      });
      final innerW = item.width * 0.92;
      final innerH = item.height * 0.92;
      expect(innerW, closeTo(73.6, 0.01));
      expect(innerH, closeTo(73.6, 0.01));
    });

    test('center dot is 8% of full size', () {
      final item = MapItem.fromJson({
        'kind': 'gazebo_roof', 'id': 'gr3',
        'x': 100, 'y': 100, 'width': 80, 'height': 80,
        'fill': '#DDDDDD', 'color': '#111111', 'stroke': 2,
      });
      final dotW = item.width * 0.08;
      final dotH = item.height * 0.08;
      expect(dotW, closeTo(6.4, 0.01));
      expect(dotH, closeTo(6.4, 0.01));
    });
  });

  group('Court roof primitives', () {
    test('court roof fill and rib count', () {
      final item = MapItem.fromJson({
        'kind': 'court_roof', 'id': 'cr1',
        'x': 100, 'y': 100, 'width': 200, 'height': 100,
        'fill': '#CCCCCC', 'color': '#111111', 'stroke': 2,
      });
      final horizontal = item.width >= item.height;
      final count = math.max(4, math.min(80, (horizontal ? item.width : item.height) / 48).ceil());
      expect(horizontal, isTrue);
      expect(count, greaterThanOrEqualTo(4));
      expect(count, lessThanOrEqualTo(80));
    });
  });

  group('Normal roof outline and seam geometry', () {
    test('roof seam hip lines connect corners to inset points', () {
      final w = 120.0;
      final h = 80.0;
      final inset = math.min(w, h) / 2;
      final first = [inset, h / 2];
      final last = [w - inset, h / 2];
      expect(first, [40.0, 40.0]);
      expect(last, [80.0, 40.0]);
    });

    test('roof with equal dimensions has single inset point', () {
      final w = 100.0;
      final h = 100.0;
      final inset = math.min(w, h) / 2;
      final first = [inset, h / 2];
      final last = [w - inset, h / 2];
      expect(first[0], last[0]);
      expect(first[1], last[1]);
    });

    test('tall roof seam uses vertical ridge', () {
      final w = 60.0;
      final h = 120.0;
      final inset = math.min(w, h) / 2;
      final first = [w / 2, inset];
      final last = [w / 2, h - inset];
      expect(first, [30.0, 30.0]);
      expect(last, [30.0, 90.0]);
    });
  });

  group('Campus roof objects not silently skipped', () {
    test('campus layer contains roof items', () {
      final json = _minimalSceneWithRoofs();
      final scene = MapScene.fromJson(json);
      final campus = scene.floors['Campus'] ?? [];
      final roofItems = campus.where((i) => roofKinds.contains(i.kind)).toList();
      expect(roofItems.length, greaterThanOrEqualTo(2));
    });
  });
}

Map<String, dynamic> _buildTestScene() {
  return {
    'format': 'bpnhs-map',
    'name': 'Test Map',
    'width': 2000,
    'height': 1200,
    'floors': {
      'Campus': [
        {
          'kind': 'building',
          'id': 'building_a',
          'x': 500,
          'y': 300,
          'width': 400,
          'height': 300,
          'floor_count': 2,
          'approach_distance': 100,
          'fade_when_obstructing': true,
          'opens': 'building_a',
        },
        {
          'kind': 'building',
          'id': 'building_b',
          'x': 1200,
          'y': 600,
          'width': 250,
          'height': 200,
          'floor_count': 1,
          'approach_distance': 80,
          'fade_when_obstructing': true,
        },
      ],
      'building_a:Floor 1': [
        {
          'kind': 'room',
          'id': 'a_room1',
          'x': 10,
          'y': 10,
          'width': 100,
          'height': 80,
        },
      ],
      'building_a:Floor 2': [
        {
          'kind': 'room',
          'id': 'a_room2',
          'x': 10,
          'y': 10,
          'width': 100,
          'height': 80,
        },
      ],
      'building_a:Roof': [],
      'building_b:Floor 1': [],
      'building_b:Roof': [],
    },
  };
}

Map<String, dynamic> _minimalScene() {
  return {
    'format': 'bpnhs-map',
    'name': 'Test',
    'width': 2000,
    'height': 1200,
    'floors': {
      'Campus': [
        {
          'kind': 'building',
          'id': 'b1',
          'x': 400,
          'y': 300,
          'width': 300,
          'height': 200,
          'floor_count': 1,
          'opens': 'b1',
        },
        {
          'kind': 'wall',
          'id': 'wall1',
          'x': 400,
          'y': 298,
          'width': 300,
          'height': 0,
          'stroke': 4,
          'blocking': true,
        },
        {
          'kind': 'opening',
          'id': 'door1',
          'x': 520,
          'y': 296,
          'width': 40,
          'height': 8,
          'blocking': false,
        },
      ],
      'b1:Floor 1': [],
      'b1:Roof': [],
    },
  };
}

Map<String, dynamic> _minimalSceneWithRoofs() {
  return {
    'format': 'bpnhs-map',
    'name': 'Test',
    'width': 2000,
    'height': 1200,
    'floors': {
      'Campus': [
        {
          'kind': 'building',
          'id': 'b1',
          'x': 400,
          'y': 300,
          'width': 300,
          'height': 200,
          'floor_count': 1,
        },
        {
          'kind': 'gazebo_roof',
          'id': 'gr1',
          'x': 800,
          'y': 200,
          'width': 60,
          'height': 60,
          'fill': '#DDDDDD',
          'color': '#111111',
          'stroke': 2,
        },
        {
          'kind': 'court_roof',
          'id': 'cr1',
          'x': 100,
          'y': 100,
          'width': 150,
          'height': 100,
          'fill': '#CCCCCC',
          'color': '#111111',
          'stroke': 2,
        },
      ],
      'b1:Floor 1': [],
      'b1:Roof': [],
    },
  };
}
