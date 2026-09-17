import 'dart:math' as math;

import 'collision.dart';

const double hazardSafetyClearance = 45.0;
const double hazardComfortClearance = 110.0;
const double hazardRiskPenaltyWeight = 8.0;

enum HazardKind { fire, activeShooter }

class HazardZone {
  final String id;
  final HazardKind kind;
  double x;
  double y;
  double radius;
  final String? buildingId;
  final int floor;

  HazardZone({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.radius,
    required this.buildingId,
    required this.floor,
  });

  bool matchesSurface(String? activeBuildingId, int activeFloor) {
    return buildingId == activeBuildingId && floor == activeFloor;
  }

  /// An octagonal blocked perimeter is used by the pathfinder.
  /// This makes fire an unsafe no-route zone while still giving A* corners
  /// it can route around.
  List<Barrier> routingBarriers({double safetyMargin = 0}) {
    final margin = safetyMargin < 0 ? 0.0 : safetyMargin;
    return <Barrier>[
      Barrier(startX: x, startY: y, endX: x, endY: y, radius: radius + margin),
    ];
  }

  double edgeDistanceTo(double px, double py) {
    final dx = px - x;
    final dy = py - y;
    return math.sqrt(dx * dx + dy * dy) - radius;
  }

  double proximityRisk(
    double px,
    double py, {
    double safetyClearance = hazardSafetyClearance,
    double comfortClearance = hazardComfortClearance,
  }) {
    final edge = edgeDistanceTo(px, py);
    if (edge <= safetyClearance) return 1.0;
    if (edge >= comfortClearance) return 0.0;

    final span = comfortClearance - safetyClearance;
    if (span <= 1e-9) return 0.0;

    final normalized = 1.0 - ((edge - safetyClearance) / span);
    return normalized * normalized;
  }
}
