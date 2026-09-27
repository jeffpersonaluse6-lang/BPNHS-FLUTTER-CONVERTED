import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/emergency/emergency_report.dart';
import 'package:flutter_runtime/emergency/emergency_zone_registry.dart';
import 'package:flutter_runtime/emergency/remote_emergency_bridge.dart';
import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/hazard.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';

MapScene _sceneWithAcademicBuilding() {
  const building = MapItem(
    kind: 'building',
    x: 20,
    y: 30,
    width: 200,
    height: 100,
    text: 'SHS-ACADEMIC',
    floorCount: 4,
    floorWidth: 1000,
    floorHeight: 500,
    floorOriginX: 300,
    floorOriginY: 400,
    id: 'academic-id',
  );
  return MapScene(
    name: 'Test campus',
    width: 2000,
    height: 1200,
    floors: <String, List<MapItem>>{
      'Campus': <MapItem>[building],
      for (var floor = 1; floor <= 4; floor++)
        'academic-id:Floor $floor': const <MapItem>[],
    },
  );
}

void main() {
  test('parses an ESP32 snapshot containing multiple reports', () {
    final status = EmergencyStatus.fromJson(<String, dynamic>{
      'revision': 3,
      'hazards': <Map<String, dynamic>>[
        <String, dynamic>{
          'active': true,
          'hazard_id': 'fire_7',
          'type': 'fire',
          'zone': 'BUILDING_A_F2',
        },
        <String, dynamic>{
          'active': true,
          'hazard_id': 'blocked_8',
          'type': 'blocked_path',
          'zone': 'CAMPUS',
        },
      ],
    });
    final active = status.hazards.first;
    expect(active.type, EmergencyReportType.fire);
    expect(active.zone, 'BUILDING_A_F2');
    expect(status.hazards, hasLength(2));
  });

  test('BUILDING_A_F2 resolves into the authored second-floor canvas', () {
    final location = EmergencyZoneRegistry(
      _sceneWithAcademicBuilding(),
    ).resolve('BUILDING_A_F2');

    expect(location, isNotNull);
    expect(location!.buildingId, 'academic-id');
    expect(location.floor, 2);
    expect(location.x, 800);
    expect(location.y, 650);
  });

  test('remote report adds, replaces, and clears only its own hazard', () {
    final scene = _sceneWithAcademicBuilding();
    final navigator = WorldNavigator(scene);
    final manual = navigator.addFireHazard(50, 60);
    final bridge = RemoteEmergencyBridge(
      navigator: navigator,
      zones: EmergencyZoneRegistry(scene),
    );

    final applied = bridge.apply(
      const EmergencyStatus(
        revision: 1,
        hazards: <EmergencyReport>[
          EmergencyReport(
            active: true,
            hazardId: 'blocked_12',
            type: EmergencyReportType.blockedPath,
            zone: 'ignored_when_exact_location_exists',
            x: 725,
            y: 612,
            radius: 37,
            buildingId: 'academic-id',
            floor: 2,
            revision: 1,
          ),
        ],
      ),
    );
    expect(applied.changed, isTrue);
    final remote = navigator.hazardById(
      RemoteEmergencyBridge.remoteHazardId('blocked_12'),
    );
    expect(remote, isNotNull);
    expect(remote!.kind, HazardKind.earthquake);
    expect(remote.buildingId, 'academic-id');
    expect(remote.floor, 2);
    expect(remote.x, 725);
    expect(remote.y, 612);
    expect(remote.radius, 37);

    bridge.apply(const EmergencyStatus(revision: 2, hazards: []));
    expect(
      navigator.hazardById(RemoteEmergencyBridge.remoteHazardId('blocked_12')),
      isNull,
    );
    expect(navigator.hazardById(manual.id), isNotNull);
  });

  test(
    'staff sender reuses its exact local hazard instead of duplicating it',
    () {
      final scene = _sceneWithAcademicBuilding();
      final navigator = WorldNavigator(scene);
      final local = navigator.addFireHazard(125, 225, radius: 42);
      final bridge = RemoteEmergencyBridge(
        navigator: navigator,
        zones: EmergencyZoneRegistry(scene),
      );

      final update = bridge.apply(
        EmergencyStatus(
          revision: 1,
          hazards: <EmergencyReport>[
            EmergencyReport(
              active: true,
              hazardId: local.id,
              type: EmergencyReportType.fire,
              zone: 'CAMPUS',
              x: local.x,
              y: local.y,
              radius: local.radius,
              buildingId: local.buildingId,
              floor: local.floor,
              revision: 1,
            ),
          ],
        ),
      );

      expect(update.changed, isFalse);
      expect(navigator.hazardById(local.id), same(local));
      expect(
        navigator.hazardById(RemoteEmergencyBridge.remoteHazardId(local.id)),
        isNull,
      );
    },
  );

  test('new reports accumulate and one cleared ID removes only its copy', () {
    final scene = _sceneWithAcademicBuilding();
    final navigator = WorldNavigator(scene);
    final bridge = RemoteEmergencyBridge(
      navigator: navigator,
      zones: EmergencyZoneRegistry(scene),
    );
    const fire = EmergencyReport(
      active: true,
      hazardId: 'fire-a',
      type: EmergencyReportType.fire,
      zone: 'CAMPUS',
      x: 100,
      y: 200,
      radius: 40,
      floor: 1,
      revision: 1,
    );
    const blocked = EmergencyReport(
      active: true,
      hazardId: 'blocked-b',
      type: EmergencyReportType.blockedPath,
      zone: 'CAMPUS',
      x: 300,
      y: 400,
      radius: 55,
      floor: 1,
      revision: 2,
    );

    bridge.apply(const EmergencyStatus(revision: 2, hazards: [fire, blocked]));
    expect(navigator.hazards, hasLength(2));

    bridge.apply(const EmergencyStatus(revision: 3, hazards: [blocked]));
    expect(
      navigator.hazardById(RemoteEmergencyBridge.remoteHazardId('fire-a')),
      isNull,
    );
    expect(
      navigator.hazardById(RemoteEmergencyBridge.remoteHazardId('blocked-b')),
      isNotNull,
    );
  });

  test('same shooter ID moves one existing remote shooter', () {
    final scene = _sceneWithAcademicBuilding();
    final navigator = WorldNavigator(scene);
    final bridge = RemoteEmergencyBridge(
      navigator: navigator,
      zones: EmergencyZoneRegistry(scene),
    );

    EmergencyReport shooter(double x) => EmergencyReport(
      active: true,
      hazardId: 'shooter-stable',
      type: EmergencyReportType.activeThreat,
      zone: 'CAMPUS',
      x: x,
      y: 250,
      radius: 70,
      floor: 1,
      revision: x.toInt(),
      moving: true,
    );

    bridge.apply(EmergencyStatus(revision: 1, hazards: [shooter(100)]));
    bridge.apply(EmergencyStatus(revision: 2, hazards: [shooter(160)]));

    expect(navigator.hazards, hasLength(1));
    expect(
      navigator
          .hazardById(RemoteEmergencyBridge.remoteHazardId('shooter-stable'))!
          .x,
      160,
    );
  });

  test('path-only shooter update is treated as a shared map update', () {
    final scene = _sceneWithAcademicBuilding();
    final navigator = WorldNavigator(scene);
    final bridge = RemoteEmergencyBridge(
      navigator: navigator,
      zones: EmergencyZoneRegistry(scene),
    );
    EmergencyReport shooter(List<List<double>> path) => EmergencyReport(
      active: true,
      hazardId: 'shooter-with-path',
      type: EmergencyReportType.activeThreat,
      zone: 'CAMPUS',
      x: 120,
      y: 250,
      radius: 70,
      floor: 1,
      revision: 1,
      path: path,
    );

    final first = bridge.apply(
      EmergencyStatus(
        revision: 1,
        hazards: [
          shooter(const <List<double>>[
            <double>[120, 250],
            <double>[240, 250],
          ]),
        ],
      ),
    );
    final second = bridge.apply(
      EmergencyStatus(
        revision: 2,
        hazards: [
          shooter(const <List<double>>[
            <double>[120, 250],
            <double>[240, 250],
            <double>[360, 330],
          ]),
        ],
      ),
    );

    expect(first.changed, isTrue);
    expect(second.changed, isTrue);
    expect(navigator.hazards, hasLength(1));
  });
}
