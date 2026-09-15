import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';

MapItem _building() {
  return const MapItem(
    kind: 'building',
    x: 100,
    y: 100,
    width: 100,
    height: 100,
    floorWidth: 100,
    floorHeight: 100,
    floorOriginX: 0,
    floorOriginY: 0,
    floorCount: 1,
    freeBuild: true,
    id: 'b1',
  );
}

MapItem _room() {
  return const MapItem(
    kind: 'room',
    x: 0,
    y: 0,
    width: 100,
    height: 100,
    stroke: 4,
    blocking: true,
    id: 'room',
  );
}

MapItem _bottomDoor() {
  return const MapItem(
    kind: 'door',
    x: 40,
    y: 80,
    width: 20,
    height: 20,
    stroke: 2,
    blocking: false,
    id: 'door',
  );
}

void main() {
  group('Stage 4 building-to-campus routing', () {
    test('Floor 1 route exits through an actual doorway', () {
      final b = _building();
      final scene = MapScene(
        name: 'exit route',
        width: 400,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': [_room(), _bottomDoor()],
          'b1:Roof': const [],
        },
      );
      final navigator = WorldNavigator(
        scene,
        markerX: 150,
        markerY: 150,
        collisionRadius: 5,
      );
      navigator.enterBuilding(b);

      final route = navigator.findFloor1CampusRoute(150, 260);

      expect(route, isNotEmpty);
      expect(route.first[0], closeTo(150, 1e-9));
      expect(route.first[1], closeTo(150, 1e-9));
      expect(route.last[0], closeTo(150, 1e-9));
      expect(route.last[1], closeTo(260, 1e-9));
    });

    test('sealed Floor 1 cannot route through a wall', () {
      final b = _building();
      final scene = MapScene(
        name: 'sealed building',
        width: 400,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': [_room()],
          'b1:Roof': const [],
        },
      );
      final navigator = WorldNavigator(
        scene,
        markerX: 150,
        markerY: 150,
        collisionRadius: 5,
      );
      navigator.enterBuilding(b);

      expect(navigator.findFloor1CampusRoute(150, 260), isEmpty);
    });

    test('campus target must be outside the current building', () {
      final b = _building();
      final scene = MapScene(
        name: 'inside target',
        width: 400,
        height: 400,
        floors: {
          'Campus': [b],
          'b1:Floor 1': [_room(), _bottomDoor()],
          'b1:Roof': const [],
        },
      );
      final navigator = WorldNavigator(
        scene,
        markerX: 150,
        markerY: 150,
        collisionRadius: 5,
      );
      navigator.enterBuilding(b);

      expect(navigator.findFloor1CampusRoute(160, 160), isEmpty);
    });
  });
}
