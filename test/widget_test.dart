import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/navigation/floor_transform.dart';
import 'package:flutter_runtime/navigation/collision.dart';
import 'package:flutter_runtime/navigation/stairs.dart';
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
          kind: 'building', x: 0, y: 0, width: 100, height: 100, id: 'a');
      final parent90 = MapItem(
          kind: 'building', x: 0, y: 0, width: 100, height: 100, rotation: 90, id: 'b');
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
}
