import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/navigation/route_step_builder.dart';

RouteStep? build(String status, {
  List<List<double>> route = const [],
  List<double> pos = const [0, 0],
  bool turnaround = false,
  bool multiFloor = false,
  bool campusExit = false,
  String? gate,
}) => RouteStepBuilder.buildCurrentStep(
  routePoints: route,
  playerPosition: pos,
  routeStatus: status,
  isStairTurnaround: turnaround,
  isMultiFloor: multiFloor,
  isCampusExit: campusExit,
  evacuationGateKind: gate,
  currentFloor: null,
  targetFloor: null,
);

void main() {
  group('RouteStepBuilder.buildCurrentStep', () {
    test('returns null when routeStatus is null', () {
      expect(build(''), isNull);
      final s = RouteStepBuilder.buildCurrentStep(
        routePoints: const [],
        playerPosition: const [0, 0],
        routeStatus: null,
        isStairTurnaround: false,
        isMultiFloor: false,
        isCampusExit: false,
        evacuationGateKind: null,
        currentFloor: null,
        targetFloor: null,
      );
      expect(s, isNull);
    });

    test('blocked for no safe route', () {
      final step = build('No safe route to Floor 3', multiFloor: true);
      expect(step!.instruction, 'No safe route found');
      expect(step.icon, 'blocked');
    });

    test('blocked for all exits blocked', () {
      final step = build('All modeled evacuation exits are blocked');
      expect(step!.instruction, 'No safe route found');
      expect(step.icon, 'blocked');
    });

    test('destination reached for Main Gate', () {
      final step = build('Main Gate reached', gate: 'main_gate', campusExit: true);
      expect(step!.instruction, 'Main Gate reached');
      expect(step.icon, 'destination');
    });

    test('destination reached for Secondary Gate', () {
      final step = build('Secondary Gate reached', gate: 'secondary_gate', campusExit: true);
      expect(step!.instruction, 'Secondary Gate reached');
      expect(step.icon, 'destination');
    });

    test('destination reached generic', () {
      final step = build('Destination reached');
      expect(step!.instruction, 'Destination reached');
      expect(step.icon, 'destination');
    });

    test('campus destination reached', () {
      final step = build('Campus destination reached');
      expect(step!.instruction, 'Destination reached');
      expect(step.icon, 'destination');
    });

    test('on stairs to floor', () {
      final step = build('On stairs to Floor 2', multiFloor: true);
      expect(step!.instruction, 'Using stairs to Floor 2');
      expect(step.icon, 'stairs');
    });

    test('go to stairs with floor range', () {
      final step = build('Go to stairs: Floor 3 → 2', multiFloor: true);
      expect(step!.instruction, 'Head to stairs: Floor 3 → 2');
      expect(step.icon, 'stairs');
    });

    test('enter the stairs', () {
      final step = build('Enter the stairs', multiFloor: true);
      expect(step!.instruction, 'Enter the stairs');
      expect(step.icon, 'stairs');
    });

    test('turn around outside stairs', () {
      final step = build('Turn around outside the stairs', turnaround: true, multiFloor: true);
      expect(step!.instruction, 'Turn around');
      expect(step.icon, 'turn_around');
    });

    test('continue through stairs', () {
      final step = build('Continue through the stairs', multiFloor: true);
      expect(step!.instruction, 'Continue through the stairs');
      expect(step.icon, 'stairs');
    });

    test('follow stair waypoint shows go up/down', () {
      final step = build('Follow stair waypoint 2/5', multiFloor: true);
      expect(step!.instruction, contains('stairs'));
      expect(step.icon, 'stairs');
    });

    test('reached floor', () {
      final step = build('Reached Floor 1', multiFloor: true);
      expect(step!.instruction, 'Arrived at Floor 1');
      expect(step.icon, 'floor_arrived');
    });

    test('exit building with gate shows head to gate', () {
      final step = build('Exit building → Main Gate', gate: 'main_gate', campusExit: true);
      expect(step!.instruction, 'Head to Main Gate');
      expect(step.icon, 'exit');
    });

    test('exit building without gate shows leave building', () {
      final step = build('Exit building → campus', campusExit: true);
      expect(step!.instruction, 'Leave the building');
      expect(step.icon, 'exit');
    });

    test('recalculating', () {
      final step = build('Recalculating evacuation path…');
      expect(step!.instruction, 'Recalculating route');
      expect(step.icon, 'recalculating');
    });

    test('route updated', () {
      final step = build('Route updated around the simulated hazard');
      expect(step!.instruction, 'Route updated');
      expect(step.icon, 'updated');
    });

    test('no same-floor route', () {
      final step = build('No same-floor route found');
      expect(step!.instruction, 'No route found');
      expect(step.icon, 'blocked');
    });

    test('finish stair transition', () {
      final step = build('Finish the stair transition first');
      expect(step!.instruction, 'Finish stair transition');
      expect(step.icon, 'stairs');
    });

    test('entered building return to floor 1', () {
      final step = build('Entered Main Building · return to Floor 1, then continue evacuation');
      expect(step!.instruction, 'Return to Floor 1');
      expect(step.icon, 'exit');
    });

    test('route cleared', () {
      final step = build('Route cleared after changing floor/area');
      expect(step!.instruction, 'Route cleared');
      expect(step.icon, 'cleared');
    });

    test('multi-floor route cancelled', () {
      final step = build('Multi-floor route cancelled');
      expect(step!.instruction, 'Route cancelled');
      expect(step.icon, 'cleared');
    });

    test('no alternative route', () {
      final step = build('No meaningfully different alternative evacuation route is available');
      expect(step!.instruction, 'No alternative route');
      expect(step.icon, 'blocked');
    });
  });

  group('RouteStepBuilder turn detection', () {
    test('returns straight walk for a straight route', () {
      final step = build(
        'Route ready',
        route: const [[0, 0], [100, 0], [200, 0]],
        pos: const [10, 0],
      );
      expect(step, isNotNull);
      expect(step!.instruction, 'Walk straight');
      expect(step.icon, 'straight');
    });

    test('detects right turn', () {
      final step = build(
        'Route ready',
        route: const [[0, 0], [100, 0], [100, 100]],
        pos: const [10, 0],
      );
      expect(step, isNotNull);
      expect(step!.instruction, contains('right'));
      expect(step.icon, 'turn_right');
    });

    test('detects left turn', () {
      final step = build(
        'Route ready',
        route: const [[0, 0], [100, 0], [100, -100]],
        pos: const [10, 0],
      );
      expect(step, isNotNull);
      expect(step!.instruction, contains('left'));
      expect(step.icon, 'turn_left');
    });

    test('returns null for route with fewer than 2 points', () {
      final step = build(
        'Route ready',
        route: const [[0, 0]],
        pos: const [0, 0],
      );
      expect(step, isNull);
    });

    test('returns null for empty route', () {
      final step = build(
        'Route ready',
        route: const [],
        pos: const [0, 0],
      );
      expect(step, isNull);
    });

    test('shows evacuation gate for campus route', () {
      final step = build(
        'Route evacuation route → Main Gate',
        route: const [[0, 0], [100, 0], [200, 0]],
        pos: const [10, 0],
        gate: 'main_gate',
        campusExit: true,
      );
      expect(step, isNotNull);
      expect(step!.instruction, 'Walk toward Main Gate');
      expect(step.icon, 'straight');
    });

    test('detects u-turn', () {
      final step = build(
        'Route ready',
        route: const [[0, 0], [100, 0], [0, 1]],
        pos: const [10, 0],
      );
      expect(step, isNotNull);
      expect(step!.instruction.contains('U-turn'), isTrue);
    });
  });

  group('RouteStepBuilder distance formatting', () {
    test('formats short distance as a few steps', () {
      final step = build(
        'Route ready',
        route: const [[0, 0], [10, 0]],
        pos: const [0, 0],
      );
      expect(step, isNotNull);
      expect(step!.detail, 'a few steps');
    });

    test('formats medium distance', () {
      final step = build(
        'Route ready',
        route: const [[0, 0], [200, 0]],
        pos: const [0, 0],
      );
      expect(step, isNotNull);
      expect(step!.detail, 'about 20 meters');
    });
  });

  group('RouteStepBuilder gate labels', () {
    test('Main Gate label for main_gate kind', () {
      final step = build(
        'Exit building → Main Gate',
        gate: 'main_gate',
        campusExit: true,
      );
      expect(step!.instruction, 'Head to Main Gate');
    });

    test('Secondary Gate label for secondary_gate kind', () {
      final step = build(
        'Exit building → Secondary Gate',
        gate: 'secondary_gate',
        campusExit: true,
      );
      expect(step!.instruction, 'Head to Secondary Gate');
    });
  });

  group('RouteStepBuilder equality', () {
    test('RouteStep equals same values', () {
      const a = RouteStep(instruction: 'Go', icon: 'straight');
      const b = RouteStep(instruction: 'Go', icon: 'straight');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('RouteStep not equals different values', () {
      const a = RouteStep(instruction: 'Go', icon: 'straight');
      const b = RouteStep(instruction: 'Stop', icon: 'blocked');
      expect(a, isNot(equals(b)));
    });
  });
}
