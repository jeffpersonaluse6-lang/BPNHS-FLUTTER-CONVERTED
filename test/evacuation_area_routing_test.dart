import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/hazard.dart';
import 'package:flutter_runtime/navigation/route_step_builder.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';
import 'package:flutter_test/flutter_test.dart';

MapItem area(
  String id,
  double x,
  double y, {
  String text = 'Assembly Area',
  String subtitle = '',
}) {
  return MapItem(
    kind: 'evacuation_area',
    x: x,
    y: y,
    width: 120,
    height: 100,
    color: '#15803D',
    fill: '#DCFCE7',
    text: text,
    subtitle: subtitle,
    blocking: false,
    id: id,
  );
}

MapItem mainGate() => const MapItem(
  kind: 'main_gate',
  x: 900,
  y: 650,
  width: 120,
  height: 24,
  text: 'Main Gate',
  blocking: true,
  gateOpen: true,
  id: 'main-gate',
);

MapScene destinationScene(List<MapItem> destinations) => MapScene(
  name: 'Assembly destination routing',
  width: 1200,
  height: 700,
  floors: <String, List<MapItem>>{'Campus': destinations},
);

void main() {
  test('fire and earthquake routing can select an assembly area', () {
    final assembly = area('assembly-a', 760, 100);
    final navigator = WorldNavigator(
      destinationScene(<MapItem>[assembly, mainGate()]),
      markerX: 180,
      markerY: 330,
      collisionRadius: 8,
    );

    for (final emergency in <HazardKind>[
      HazardKind.fire,
      HazardKind.earthquake,
    ]) {
      final ranked = navigator.rankEvacuationDestinations(
        emergencyKind: emergency,
      );
      expect(ranked, isNotEmpty);
      expect(ranked.first.kind, 'evacuation_area:assembly-a');
      expect(ranked.first.previewRoute, isNotEmpty);

      final target = navigator.campusDestinationApproach(ranked.first.kind)!;
      expect(target[0], closeTo(820, 1e-9));
      expect(target[1], closeTo(150, 1e-9));
      expect(ranked.first.previewRoute.last, equals(target));
    }
  });

  test('unsafe assembly area is removed and another destination is used', () {
    final first = area('assembly-a', 700, 100);
    final second = area('assembly-b', 700, 430);
    final navigator = WorldNavigator(
      destinationScene(<MapItem>[first, second, mainGate()]),
      markerX: 150,
      markerY: 350,
      collisionRadius: 8,
    );

    final firstKey = 'evacuation_area:${first.id}';
    final firstTarget = navigator.campusDestinationApproach(firstKey)!;
    navigator.addFireHazard(firstTarget[0], firstTarget[1], radius: 40);

    expect(navigator.isCampusEvacuationDestinationBlocked(firstKey), isTrue);

    final ranked = navigator.rankEvacuationDestinations(
      emergencyKind: HazardKind.fire,
    );
    expect(ranked, isNotEmpty);
    expect(ranked.map((option) => option.kind), isNot(contains(firstKey)));
    expect(
      ranked.map((option) => option.kind),
      contains('evacuation_area:assembly-b'),
    );
  });

  test(
    'active shooter uses only explicitly configured safe areas or gates',
    () {
      final ordinary = area('fire-only', 650, 90, text: 'Fire Assembly Area');
      final threatSafe = area(
        'threat-safe',
        780,
        320,
        text: 'Protected Safe Area',
        subtitle: 'Active shooter / active threat',
      );
      final navigator = WorldNavigator(
        destinationScene(<MapItem>[ordinary, threatSafe, mainGate()]),
        markerX: 160,
        markerY: 340,
        collisionRadius: 8,
      );

      final ranked = navigator.rankEvacuationDestinations(
        emergencyKind: HazardKind.activeShooter,
      );
      final keys = ranked.map((option) => option.kind).toList();

      expect(keys, isNot(contains('evacuation_area:fire-only')));
      expect(keys, contains('evacuation_area:threat-safe'));
      expect(keys, contains('main_gate'));
      expect(keys.first, 'evacuation_area:threat-safe');
    },
  );

  test('legacy gate-only ranking remains unchanged without an emergency', () {
    final assembly = area('assembly-a', 760, 100);
    final navigator = WorldNavigator(
      destinationScene(<MapItem>[assembly, mainGate()]),
      markerX: 180,
      markerY: 330,
      collisionRadius: 8,
    );

    final ranked = navigator.rankEvacuationGates();
    expect(ranked, hasLength(1));
    expect(ranked.single.kind, 'main_gate');
    expect(navigator.findCampusGateRoute('main_gate'), isNotEmpty);
  });

  test('assembly-area arrival produces a destination instruction', () {
    final step = RouteStepBuilder.buildCurrentStep(
      routePoints: const <List<double>>[],
      playerPosition: const <double>[820, 150],
      routeStatus: 'Assembly Area reached · Quadrangle',
      isStairTurnaround: false,
      isMultiFloor: false,
      isCampusExit: false,
      evacuationGateKind: null,
      currentFloor: 1,
      targetFloor: null,
    );

    expect(step, isNotNull);
    expect(step!.instruction, 'Assembly Area reached');
    expect(step.icon, 'destination');
  });
}
