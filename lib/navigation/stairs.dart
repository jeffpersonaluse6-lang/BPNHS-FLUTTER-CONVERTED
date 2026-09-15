import '../models/map_item.dart';

/// StairSection — matches Python StairSection from navigation/stairs.py.
class StairSection {
  final MapItem stair;
  final int source;
  final int target;

  const StairSection(this.stair, this.source, this.target);

  String get id => '${stair.id}:stair';
  String get direction => stair.stairDirection;
  double get width => stair.width;
  double get height => stair.height;

  List<double> localToWorld(double x, double y) => stair.localToWorld(x, y);
  List<double> worldToLocal(double x, double y) => stair.worldToLocal(x, y);

  bool contains(double x, double y, {double tolerance = 0}) {
    final local = worldToLocal(x, y);
    return -tolerance <= local[0] &&
        local[0] <= width + tolerance &&
        -tolerance <= local[1] &&
        local[1] <= height + tolerance;
  }
}

/// Connection — determine target floor for a stair.
/// Matches Python connection from navigation/stairs.py.
int? connection(MapItem item, int section, int floor, int count) {
  if (item.stairFrom != null && item.stairFrom != floor) return null;
  if (item.kind != 'stairs' || section != 0 || !item.stairEnabled) return null;
  final direction = item.stairDirection;
  final explicit = item.stairTo;
  int target;
  if (explicit != null) {
    target = explicit;
  } else {
    target = floor + (direction == 'up' ? 1 : -1);
  }
  if (explicit == null && (target < 1 || target > count)) return null;
  return (target >= 1 &&
          target <= count &&
          target != floor &&
          (direction == 'up') == (target > floor))
      ? target
      : null;
}

/// Transitions — get stair sections for a building floor.
/// Matches Python transitions from navigation/stairs.py.
List<StairSection> transitions(MapItem item, int floor, int count) {
  if (item.kind != 'stairs') return [];
  final target = connection(item, 0, floor, count);
  return target != null ? [StairSection(item, floor, target)] : [];
}

/// Section progress — progress along a stair section.
/// Returns (progress, lateral, raw).
/// Matches Python section_progress from navigation/stairs.py.
(List<double>, bool, double) sectionProgress(
    StairSection section, double px, double py) {
  final local = section.worldToLocal(px, py);
  final raw = section.direction == 'up'
      ? (section.height - local[1]) / section.height
      : local[1] / section.height;
  final progress = raw.clamp(0.0, 1.0);
  final lateral = local[0] >= -1e-7 && local[0] <= section.width + 1e-7;
  return ([progress], lateral, raw);
}

/// All stair-related kinds.
const stairKinds = {'stairs'};
