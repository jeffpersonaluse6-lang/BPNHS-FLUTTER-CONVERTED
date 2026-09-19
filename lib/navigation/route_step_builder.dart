import 'dart:math' as math;
import '../models/math_helper.dart';

class RouteStep {
  final String instruction;
  final String? detail;
  final String icon;

  const RouteStep({
    required this.instruction,
    this.detail,
    required this.icon,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteStep &&
          instruction == other.instruction &&
          detail == other.detail &&
          icon == other.icon;

  @override
  int get hashCode => instruction.hashCode ^ detail.hashCode ^ icon.hashCode;
}

class RouteStepBuilder {
  static const double _turnAngleThreshold = 30 * math.pi / 180;
  static const double _uTurnAngleThreshold = 150 * math.pi / 180;

  static RouteStep? buildCurrentStep({
    required List<List<double>> routePoints,
    required List<double> playerPosition,
    required String? routeStatus,
    required bool isStairTurnaround,
    required bool isMultiFloor,
    required bool isCampusExit,
    required String? evacuationGateKind,
    required int? currentFloor,
    required int? targetFloor,
  }) {
    if (routeStatus == null) return null;

    final lower = routeStatus.toLowerCase();

    if (lower.contains('no valid') ||
        lower.contains('no safe route') ||
        lower.contains('no route') ||
        lower.contains('all modeled evacuation exits are blocked') ||
        lower.contains('stay at your current position')) {
      return const RouteStep(
        instruction: 'No safe route found',
        detail: 'Stay at your current position and wait for assistance.',
        icon: 'blocked',
      );
    }

    if (lower.contains('no same-floor route found')) {
      return const RouteStep(
        instruction: 'No route found',
        detail: 'Cannot reach this destination from your current position.',
        icon: 'blocked',
      );
    }

    if (lower.contains('destination reached') ||
        lower.contains('campus destination reached') ||
        lower.contains('main gate reached') ||
        lower.contains('secondary gate reached')) {
      final gateLabel = lower.contains('main gate')
          ? 'Main Gate'
          : lower.contains('secondary gate')
              ? 'Secondary Gate'
              : null;
      return RouteStep(
        instruction: gateLabel != null
            ? '$gateLabel reached'
            : 'Destination reached',
        detail: 'You have arrived at your evacuation destination.',
        icon: 'destination',
      );
    }

    if (lower.contains('finish the stair transition first')) {
      return const RouteStep(
        instruction: 'Finish stair transition',
        detail: 'Complete the current stair movement before rerouting.',
        icon: 'stairs',
      );
    }

    if (lower.contains('on stairs to floor')) {
      final floorMatch = RegExp(r'floor\s+(\d+)').firstMatch(lower);
      final target = floorMatch?.group(1);
      return RouteStep(
        instruction: target != null
            ? 'Using stairs to Floor $target'
            : 'Using stairs',
        detail: 'Continue straight through the stairwell.',
        icon: 'stairs',
      );
    }

    if (lower.contains('go to stairs')) {
      final floorMatch = RegExp(r'floor\s+(\d+)\s*→\s*(\d+)').firstMatch(lower);
      if (floorMatch != null) {
        final from = floorMatch.group(1);
        final to = floorMatch.group(2);
        return RouteStep(
          instruction: 'Head to stairs: Floor $from → $to',
          detail: 'Follow the path to the stairwell entrance.',
          icon: 'stairs',
        );
      }
      return const RouteStep(
        instruction: 'Head to the stairs',
        detail: 'Follow the path to the stairwell entrance.',
        icon: 'stairs',
      );
    }

    if (lower.contains('enter the stairs')) {
      return const RouteStep(
        instruction: 'Enter the stairs',
        detail: 'Step into the stairwell and begin ascending or descending.',
        icon: 'stairs',
      );
    }

    if (lower.contains('turn around outside the stairs')) {
      return const RouteStep(
        instruction: 'Turn around',
        detail: 'Exit the stairwell and reverse direction to continue.',
        icon: 'turn_around',
      );
    }

    if (lower.contains('continue through the stairs')) {
      return const RouteStep(
        instruction: 'Continue through the stairs',
        detail: 'Keep moving through the stairwell.',
        icon: 'stairs',
      );
    }

    if (lower.contains('follow stair waypoint')) {
      final goingDown = targetFloor != null && currentFloor != null &&
          targetFloor < currentFloor;
      final direction = goingDown ? 'down' : 'up';
      return RouteStep(
        instruction: 'Go $direction the stairs',
        detail: 'Keep moving through the stairwell.',
        icon: 'stairs',
      );
    }

    if (lower.contains('reached floor')) {
      final floorMatch = RegExp(r'floor\s+(\d+)').firstMatch(lower);
      final floor = floorMatch?.group(1);
      return RouteStep(
        instruction: floor != null ? 'Arrived at Floor $floor' : 'Floor reached',
        detail: 'You have reached the target floor.',
        icon: 'floor_arrived',
      );
    }

    if (lower.contains('exit building')) {
      final gateLabel = lower.contains('main gate')
          ? 'Main Gate'
          : lower.contains('secondary gate')
              ? 'Secondary Gate'
              : null;
      if (gateLabel != null) {
        return RouteStep(
          instruction: 'Head to $gateLabel',
          detail: 'Follow the evacuation route toward the gate.',
          icon: 'exit',
        );
      }
      return const RouteStep(
        instruction: 'Leave the building',
        detail: 'Head toward the nearest exit.',
        icon: 'exit',
      );
    }

    if (lower.contains('entered') && lower.contains('return to floor 1')) {
      final buildingMatch = RegExp(r'entered\s+(.+?)\s*·').firstMatch(lower);
      final building = buildingMatch?.group(1);
      return RouteStep(
        instruction: 'Return to Floor 1',
        detail: building != null
            ? 'You entered $building. Go back to Floor 1 to continue.'
            : 'Return to Floor 1 to continue evacuation.',
        icon: 'exit',
      );
    }

    if (lower.contains('recalculating') || lower.contains('recalculat')) {
      return const RouteStep(
        instruction: 'Recalculating route',
        detail: 'Finding a new path around obstacles.',
        icon: 'recalculating',
      );
    }

    if (lower.contains('route updated around') ||
        lower.contains('route recalculated')) {
      return const RouteStep(
        instruction: 'Route updated',
        detail: 'New path found around the hazard.',
        icon: 'updated',
      );
    }

    if (lower.contains('route cleared after changing')) {
      return const RouteStep(
        instruction: 'Route cleared',
        detail: 'Route was cleared due to floor or area change.',
        icon: 'cleared',
      );
    }

    if (lower.contains('multi-floor route cancelled') ||
        lower.contains('campus route cancelled')) {
      return const RouteStep(
        instruction: 'Route cancelled',
        detail: 'The route was cancelled. Request a new route.',
        icon: 'cleared',
      );
    }

    if (lower.contains('no meaningfully different alternative')) {
      return const RouteStep(
        instruction: 'No alternative route',
        detail: 'Only one evacuation path is available from your position.',
        icon: 'blocked',
      );
    }

    if (lower.contains('route') &&
        (lower.contains('evacuation route') || lower.contains('campus route'))) {
      if (isStairTurnaround) {
        return const RouteStep(
          instruction: 'Turn around to continue',
          detail: 'Exit the stairwell and reverse direction.',
          icon: 'turn_around',
        );
      }
    }

    if (routePoints.length < 2) return null;

    final step = _buildNavigationStep(
      routePoints: routePoints,
      playerPosition: playerPosition,
      isCampusExit: isCampusExit,
      evacuationGateKind: evacuationGateKind,
    );

    return step;
  }

  static RouteStep _buildNavigationStep({
    required List<List<double>> routePoints,
    required List<double> playerPosition,
    required bool isCampusExit,
    required String? evacuationGateKind,
  }) {
    final turnInfo = _findNextTurn(
      routePoints: routePoints,
      playerPosition: playerPosition,
    );

    if (turnInfo == null) {
      final gateLabel = evacuationGateKind == 'secondary_gate'
          ? 'Secondary Gate'
          : evacuationGateKind == 'main_gate'
              ? 'Main Gate'
              : null;

      if (gateLabel != null) {
        return RouteStep(
          instruction: 'Walk toward $gateLabel',
          icon: 'straight',
        );
      }

      return const RouteStep(
        instruction: 'Walk straight',
        icon: 'straight',
      );
    }

    final turnName = _turnName(turnInfo.angleChange);

    return RouteStep(
      instruction: turnName,
      detail: _turnDetail(turnInfo.angleChange),
      icon: turnInfo.angleChange > 0 ? 'turn_right' : 'turn_left',
    );
  }

  static _TurnInfo? _findNextTurn({
    required List<List<double>> routePoints,
    required List<double> playerPosition,
  }) {
    if (routePoints.length < 3) return null;

    var playerIdx = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < routePoints.length - 1; i++) {
      final dist = _pointToSegmentDistance(
        playerPosition,
        routePoints[i],
        routePoints[i + 1],
      );
      if (dist < bestDist) {
        bestDist = dist;
        playerIdx = i;
      }
    }

    for (var i = playerIdx; i < routePoints.length - 2; i++) {
      final a = routePoints[i];
      final b = routePoints[i + 1];
      final c = routePoints[i + 2];

      final angleChange = _signedAngleChange(a, b, c);

      if (angleChange.abs() >= _turnAngleThreshold) {
        final playerDist = _segmentDistance(playerPosition, b);
        final adjustedStart = i == playerIdx ? playerPosition : a;

        return _TurnInfo(
          turnPoint: b,
          angleChange: angleChange,
          distance: playerDist,
          playerSegmentStart: adjustedStart,
          turnIndex: i + 1,
        );
      }
    }

    return null;
  }

  static double _signedAngleChange(
    List<double> a,
    List<double> b,
    List<double> c,
  ) {
    final d1x = b[0] - a[0];
    final d1y = b[1] - a[1];
    final d2x = c[0] - b[0];
    final d2y = c[1] - b[1];

    final cross = d1x * d2y - d1y * d2x;
    final dot = d1x * d2x + d1y * d2y;

    return math.atan2(cross, dot);
  }

  static String _turnName(double angleChange) {
    final absAngle = angleChange.abs();

    if (absAngle >= _uTurnAngleThreshold) {
      return 'Make a U-turn';
    }

    if (absAngle >= _turnAngleThreshold * 2) {
      return angleChange > 0 ? 'Turn sharp right' : 'Turn sharp left';
    }

    return angleChange > 0 ? 'Turn right' : 'Turn left';
  }

  static String _turnDetail(double angleChange) {
    final absAngle = angleChange.abs();
    if (absAngle >= _uTurnAngleThreshold) {
      return 'Reverse direction and follow the path.';
    }
    if (absAngle >= _turnAngleThreshold * 2) {
      return 'Follow the turn carefully.';
    }
    return 'Follow the path around the corner.';
  }

  static double _segmentDistance(List<double> a, List<double> b) {
    return hypot(b[0] - a[0], b[1] - a[1]);
  }

  static double _totalRouteDistance(List<List<double>> points) {
    var total = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      total += _segmentDistance(points[i], points[i + 1]);
    }
    return total;
  }

  static double _pointToSegmentDistance(
    List<double> point,
    List<double> a,
    List<double> b,
  ) {
    final dx = b[0] - a[0];
    final dy = b[1] - a[1];
    final length2 = dx * dx + dy * dy;

    if (length2 <= 1e-9) {
      return hypot(point[0] - a[0], point[1] - a[1]);
    }

    final t = (((point[0] - a[0]) * dx + (point[1] - a[1]) * dy) / length2)
        .clamp(0.0, 1.0)
        .toDouble();

    final px = a[0] + dx * t;
    final py = a[1] + dy * t;
    return hypot(point[0] - px, point[1] - py);
  }

  static String _formatDistance(double distance) {
    if (distance < 15) return 'a few steps';
    if (distance < 50) return 'a short distance';
    if (distance < 120) return 'about 10 meters';
    if (distance < 250) return 'about 20 meters';
    if (distance < 500) return 'about 40 meters';
    return 'follow the route';
  }
}

class _TurnInfo {
  final List<double> turnPoint;
  final double angleChange;
  final double distance;
  final List<double> playerSegmentStart;
  final int turnIndex;

  const _TurnInfo({
    required this.turnPoint,
    required this.angleChange,
    required this.distance,
    required this.playerSegmentStart,
    required this.turnIndex,
  });
}
