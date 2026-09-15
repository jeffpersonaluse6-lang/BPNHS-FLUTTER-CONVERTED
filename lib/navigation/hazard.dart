import 'collision.dart';

enum HazardKind { fire }

class HazardZone {
  final String id;
  final HazardKind kind;
  final double x;
  final double y;
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
  List<Barrier> routingBarriers() {
    // A zero-length Barrier is treated by the existing collision math as a
    // circular blocked disk. This blocks the WHOLE fire zone, not just an
    // octagonal perimeter, and gives A* clean radial detour candidates.
    return <Barrier>[
      Barrier(startX: x, startY: y, endX: x, endY: y, radius: radius),
    ];
  }
}
