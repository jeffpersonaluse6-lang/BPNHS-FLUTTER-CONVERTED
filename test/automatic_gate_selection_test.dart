import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';
import 'multi_floor_routing_test.dart' show makeBuilding, downStair;

MapItem gate(String kind, double x) => MapItem(
  kind: kind,
  x: x,
  y: 540,
  width: 120,
  height: 24,
  stroke: kind == 'main_gate' ? 10 : 8,
  color: '#1F2937',
  fill: 'none',
  text: kind == 'main_gate' ? 'Main Gate' : 'Secondary Gate',
  blocking: true,
  gateOpen: false,
  id: '$kind-$x',
);

MapScene twoGateScene() => MapScene(
  name: 'Automatic gate ranking',
  width: 1200,
  height: 600,
  floors: {
    'Campus': [gate('secondary_gate', 100), gate('main_gate', 950)],
  },
);

void main() {
  test('authored SHS Faculty is a reachable fallback from the SHS campus', () {
    final scene = MapScene.fromJson(
      jsonDecode(File('assets/map_workspace.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final faculty = scene.buildings().singleWhere(
      (item) => item.text == 'SHS-FACULTY',
    );
    final start = faculty.localToWorld(faculty.width / 2, faculty.height + 50);
    final nav = WorldNavigator(
      scene,
      markerX: start[0],
      markerY: start[1],
      collisionRadius: 4,
    );
    for (final kind in ['main_gate', 'secondary_gate']) {
      final target = nav.campusGateApproach(kind)!;
      nav.addFireHazard(target[0], target[1], radius: 30);
    }
    final fallback = nav.facultyFallback();
    expect(fallback?.kind, 'faculty:${faculty.id}');
    expect(fallback?.previewRoute, isNotEmpty);
  });
  test(
    'both exits blocked selects nearer SHS Faculty instead of first JHS',
    () {
      final scene = twoGateScene();
      scene.floors['Campus']!.addAll([
        const MapItem(
          kind: 'building',
          x: 1000,
          y: 80,
          width: 100,
          height: 80,
          text: 'JHS-FACULTY',
          id: 'jhs-faculty',
        ),
        const MapItem(
          kind: 'building',
          x: 550,
          y: 80,
          width: 100,
          height: 80,
          text: 'SHS-FACULTY',
          id: 'shs-faculty',
        ),
      ]);
      final nav = WorldNavigator(
        scene,
        markerX: 500,
        markerY: 250,
        collisionRadius: 10,
      );
      for (final kind in ['main_gate', 'secondary_gate']) {
        final target = nav.campusGateApproach(kind)!;
        nav.addEarthquakeHazard(target[0], target[1], radius: 30);
      }
      final fallback = nav.facultyFallback();
      expect(fallback?.kind, 'faculty:shs-faculty');
      expect(fallback?.previewRoute, isNotEmpty);
      nav.addActiveShooterHazard(600, 120, radius: 20);
      expect(nav.facultyFallback()?.kind, 'faculty:jhs-faculty');
      nav.addFireHazard(1050, 120, radius: 120);
      expect(nav.facultyFallback(), isNull);
    },
  );
  test('Faculty fallback preserves upper-floor stair descent', () {
    final building = makeBuilding();
    final scene = twoGateScene();
    scene.floors['Campus']!.addAll([
      building,
      const MapItem(
        kind: 'building',
        x: 650,
        y: 100,
        width: 150,
        height: 80,
        text: 'JHS-FACULTY',
        id: 'faculty',
      ),
    ]);
    scene.floors['b1:Floor 1'] = [];
    scene.floors['b1:Floor 2'] = [downStair('s21', 2, 1)];
    scene.floors['b1:Floor 3'] = [downStair('s32', 3, 2)];
    final nav = WorldNavigator(
      scene,
      markerX: 60,
      markerY: 100,
      collisionRadius: 5,
    );
    for (final kind in ['main_gate', 'secondary_gate']) {
      final target = nav.campusGateApproach(kind)!;
      nav.addFireHazard(target[0], target[1], radius: 30);
    }
    nav.enterBuilding(building);
    nav.currentFloor = 3;
    expect(nav.facultyFallback()?.kind, 'faculty:faculty');
    expect(nav.findRouteTowardFloor(1)?.targetFloor, 2);
    nav.currentFloor = 1;
    expect(nav.facultyFallback()?.previewRoute, isNotEmpty);
  });
  for (final label in ['JHS-FACULTY', 'SHS-FACULTY']) {
    for (final blockedCount in [1, 2, 3]) {
      test('$label fallback with $blockedCount blocked destinations', () {
        final scene = twoGateScene();
        scene.floors['Campus']!.add(
          MapItem(
            kind: 'building',
            x: 650,
            y: 100,
            width: 150,
            height: 80,
            text: label,
            id: 'faculty',
            blocking: true,
          ),
        );
        final nav = WorldNavigator(
          scene,
          markerX: 500,
          markerY: 250,
          collisionRadius: 10,
        );
        final main = nav.campusGateApproach('main_gate')!;
        nav.addFireHazard(main[0], main[1], radius: 30);
        if (blockedCount >= 2) {
          final secondary = nav.campusGateApproach('secondary_gate')!;
          nav.addEarthquakeHazard(secondary[0], secondary[1], radius: 30);
        }
        if (blockedCount == 3) {
          nav.addFireHazard(725, 140, radius: 180);
        }
        final fallback = nav.facultyFallback();
        if (blockedCount == 2) {
          expect(fallback, isNotNull);
          expect(fallback!.kind, 'faculty:faculty');
          expect(fallback.previewRoute, isNotEmpty);
          expect(nav.findCampusDestinationRoute(fallback.kind), isNotEmpty);
        } else {
          expect(fallback, isNull);
          if (blockedCount == 1) {
            expect(nav.rankEvacuationGates().single.kind, 'secondary_gate');
          }
        }
      });
    }
  }
  test('closest valid complete gate route becomes Main route', () {
    final nav = WorldNavigator(
      twoGateScene(),
      markerX: 180,
      markerY: 250,
      collisionRadius: 10,
    );

    final ranked = nav.rankEvacuationGates();

    expect(ranked, hasLength(2));
    expect(ranked.first.kind, 'secondary_gate');
    expect(ranked[1].kind, 'main_gate');
    expect(nav.recommendedEvacuationGateKind(), 'secondary_gate');
    expect(nav.recommendedEvacuationGateKind(alternative: true), 'main_gate');
  });

  test('ranking flips when Main Gate is the better complete route', () {
    final nav = WorldNavigator(
      twoGateScene(),
      markerX: 930,
      markerY: 250,
      collisionRadius: 10,
    );

    final ranked = nav.rankEvacuationGates();

    expect(ranked, hasLength(2));
    expect(ranked.first.kind, 'main_gate');
    expect(ranked[1].kind, 'secondary_gate');
  });

  test('alternative is unavailable when only one official gate exists', () {
    final scene = MapScene(
      name: 'Single gate',
      width: 1200,
      height: 600,
      floors: {
        'Campus': [gate('main_gate', 950)],
      },
    );
    final nav = WorldNavigator(
      scene,
      markerX: 500,
      markerY: 250,
      collisionRadius: 10,
    );

    expect(nav.rankEvacuationGates(), hasLength(1));
    expect(nav.recommendedEvacuationGateKind(), 'main_gate');
    expect(nav.recommendedEvacuationGateKind(alternative: true), isNull);
  });

  test('Main and Alternative always point at different official gates', () {
    final nav = WorldNavigator(
      twoGateScene(),
      markerX: 500,
      markerY: 250,
      collisionRadius: 10,
    );

    final main = nav.recommendedEvacuationGateKind();
    final alternative = nav.recommendedEvacuationGateKind(alternative: true);

    expect(main, isNotNull);
    expect(alternative, isNotNull);
    expect(main, isNot(equals(alternative)));
  });

  test('all hazard-blocked official gates produce no evacuation option', () {
    final nav = WorldNavigator(
      twoGateScene(),
      markerX: 500,
      markerY: 250,
      collisionRadius: 10,
    );

    final main = nav.campusGateApproach('main_gate')!;
    final secondary = nav.campusGateApproach('secondary_gate')!;
    nav.addFireHazard(main[0], main[1]);
    nav.addEarthquakeHazard(secondary[0], secondary[1]);

    expect(nav.allEvacuationGatesBlocked, isTrue);
    expect(nav.rankEvacuationGates(), isEmpty);
    expect(nav.recommendedEvacuationGateKind(), isNull);
  });
}
