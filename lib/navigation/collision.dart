import 'dart:math' as math;
import '../models/map_item.dart';
import '../models/math_helper.dart' as helper;

/// Barrier — matches Python Barrier from collision.py.
class Barrier {
  final double startX, startY, endX, endY;
  final double radius;
  final bool flat;

  const Barrier({
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.radius,
    this.flat = false,
  });

  bool blocks(double px, double py, double playerRadius) {
    final ax = startX;
    final ay = startY;
    final dx = endX - ax;
    final dy = endY - ay;
    final length2 = dx * dx + dy * dy;

    if (flat && length2 > 0) {
      final length = math.sqrt(length2);
      final along = ((px - ax) * dx + (py - ay) * dy) / length;
      final across = ((px - ax) * dy - (py - ay) * dx).abs() / length;
      if (playerRadius == 0) {
        return along > 0 && along < length && across < radius;
      }
      return helper.hypot(
              math.max(0.0, math.max(-along, along - length)),
              math.max(0.0, across - radius)) <
          playerRadius - 1e-7;
    }

    final t = length2 > 0
        ? math.max(0.0,
            math.min(1.0, ((px - ax) * dx + (py - ay) * dy) / length2))
        : 0.0;
    return helper.hypot(px - ax - t * dx, py - ay - t * dy) <
        radius + playerRadius - 1e-7;
  }

  (double, double, double, double) get bounds => (
        math.min(startX, endX) - radius,
        math.min(startY, endY) - radius,
        math.max(startX, endX) + radius,
        math.max(startY, endY) + radius,
      );
}

/// PolygonBarrier — matches Python PolygonBarrier from collision.py.
class PolygonBarrier {
  final List<List<double>> points;
  late final List<(double, double)> boundsRect;

  PolygonBarrier(this.points) {
    double minX = double.infinity,
        minY = double.infinity,
        maxX = double.negativeInfinity,
        maxY = double.negativeInfinity;
    for (final p in points) {
      if (p[0] < minX) minX = p[0];
      if (p[1] < minY) minY = p[1];
      if (p[0] > maxX) maxX = p[0];
      if (p[1] > maxY) maxY = p[1];
    }
    boundsRect = [(minX, maxX), (minY, maxY)];
  }

  bool blocks(double px, double py, double playerRadius) {
    if (px < boundsRect[0].$1 - playerRadius ||
        px > boundsRect[0].$2 + playerRadius ||
        py < boundsRect[1].$1 - playerRadius ||
        py > boundsRect[1].$2 + playerRadius) {
      return false;
    }

    bool inside = false;
    var prev = points.last;
    for (final current in points) {
      final ax = prev[0];
      final ay = prev[1];
      final bx = current[0];
      final by = current[1];
      if ((ay > py) != (by > py) &&
          px < (bx - ax) * (py - ay) / (by - ay) + ax) {
        inside = !inside;
      }
      final dx = bx - ax;
      final dy = by - ay;
      final length2 = dx * dx + dy * dy;
      final t = length2 > 0
          ? math.max(0.0,
              math.min(1.0, ((px - ax) * dx + (py - ay) * dy) / length2))
          : 0.0;
    if (helper.hypot(px - ax - t * dx, py - ay - t * dy) <
        playerRadius - 1e-7) {
      return true;
    }
    prev = current;
    }
    return inside;
  }

  (double, double, double, double) get box => (
        boundsRect[0].$1,
        boundsRect[1].$1,
        boundsRect[0].$2,
        boundsRect[1].$2,
      );
}

/// Ellipse points — matches Python ellipse_points from drafting/circular.py.
List<List<double>> ellipsePoints(double w, double h,
    {double start = 0, double end = 2 * math.pi, double error = 0.025}) {
  final radius = math.max(w, h) / 2;
  final acosVal = math.acos(math.max(-1.0, 1 - error / radius));
  final count = math.max(
      1,
      math.min(4096, ((end - start) / math.max(0.001, 2 * acosVal)).ceil()));
  final points = <List<double>>[];
  for (var n = 0; n <= count; n++) {
    final t = start + (end - start) * n / count;
    points.add([w / 2 + w / 2 * math.cos(t), h / 2 + h / 2 * math.sin(t)]);
  }
  return points;
}

List<(double, double)> ellipsePointPairs(double w, double h,
    {double start = 0, double end = 2 * math.pi, double error = 0.025}) {
  return ellipsePoints(w, h, start: start, end: end, error: error)
      .map((p) => (p[0], p[1]))
      .toList();
}

const double tau = 2 * math.pi;

/// solidArcs — cut walkable angular openings from the wall.
List<(double, double)> solidArcs(MapItem item, {List<MapItem>? openings}) {
  final rx = item.width / 2;
  final ry = item.height / 2;
  final cuts = <(double, double)>[];

  void cut(double angle, double half) {
    final center = angle % tau;
    for (final shift in [-tau, 0.0, tau]) {
      final lo = math.max(0.0, center - half + shift);
      final hi = math.min(tau, center + half + shift);
      if (hi > lo) cuts.add((lo, hi));
    }
  }

  for (final opening in item.circleOpenings) {
    final angle = opening.angle * math.pi / 180;
    final tangent = helper.hypot(rx * math.sin(angle), ry * math.cos(angle));
    cut(angle, math.asin(math.min(1.0, opening.width / (2 * tangent))));
  }

  if (openings != null) {
    for (final opening in openings) {
      if (opening.parentId != null && opening.parentId != item.id) continue;
      final openY = opening.height / 2;
      final aLocal = opening.localToWorld(0, openY);
      final bLocal = opening.localToWorld(opening.width, openY);
      final a = item.worldToLocal(aLocal[0], aLocal[1]);
      final b = item.worldToLocal(bLocal[0], bLocal[1]);
      final cx = (a[0] + b[0]) / 2 - rx;
      final cy = (a[1] + b[1]) / 2 - ry;
      final angle = math.atan2(cy / ry, cx / rx);
      final rimX = rx * math.cos(angle);
      final rimY = ry * math.sin(angle);
      final reach = opening.height / 2;
      if (helper.hypot(cx - rimX, cy - rimY) >
          math.max(0.5, item.stroke / 2) + reach + 1e-7) continue;
      final dx = b[0] - a[0];
      final dy = b[1] - a[1];
      final length = helper.hypot(dx, dy);
      final tx = -rx * math.sin(angle);
      final ty = ry * math.cos(angle);
      final tangent = helper.hypot(tx, ty);
      if (length == 0 ||
          (dx * ty - dy * tx).abs() / (length * tangent) > 0.2) {
        continue;
      }
      final half = math.asin(math.min(1.0, length / (2 * tangent)));
      cut(angle, half);
    }
  }

  cuts.sort((a, b) => a.$1.compareTo(b.$1));
  final arcs = <(double, double)>[];
  double cursor = 0;
  for (final cutEntry in cuts) {
    final lo = cutEntry.$1;
    final hi = cutEntry.$2;
    if (lo > cursor + 1e-9) arcs.add((cursor, lo));
    cursor = math.max(cursor, hi);
  }
  if (cursor < tau - 1e-9) arcs.add((cursor, tau));
  return arcs;
}

double collisionThickness(MapItem item) {
  if (item.collisionThickness != null) return item.collisionThickness!;
  if (item.kind == 'railing') return item.stroke + 4;
  return math.max(1, item.stroke);
}

List<Barrier> wallSections(MapItem item, {List<MapItem>? openings}) {
  if (item.kind == 'circle_wall') {
    return _circularWallSections(
        item, openings, math.max(0.5, item.stroke / 2));
  }
  final sections = <Barrier>[];
  for (final edge in wallEdges(item)) {
    sections.addAll(_solidSections(edge.start, edge.end, edge.radius, openings));
  }
  return sections;
}

List<Barrier> collisionWallSections(MapItem item, {List<MapItem>? openings}) {
  final radius = collisionThickness(item) / 2;
  if (item.kind == 'circle_wall') {
    return _circularWallSections(item, openings, radius);
  }
  final sections = <Barrier>[];
  for (final edge in wallEdges(item, collision: true)) {
    sections.addAll(_solidSections(edge.start, edge.end, radius, openings));
  }
  return sections;
}

List<Barrier> _circularWallSections(
    MapItem item, List<MapItem>? openings, double radius) {
  final sections = <Barrier>[];
  for (final arcRange in solidArcs(item, openings: openings)) {
    final points = ellipsePoints(item.width, item.height,
        start: arcRange.$1, end: arcRange.$2);
    final worldPoints =
        points.map((p) => item.localToWorld(p[0], p[1])).toList();
    for (var i = 0; i < worldPoints.length - 1; i++) {
      sections.add(Barrier(
        startX: worldPoints[i][0],
        startY: worldPoints[i][1],
        endX: worldPoints[i + 1][0],
        endY: worldPoints[i + 1][1],
        radius: radius,
        flat: true,
      ));
    }
  }
  return sections;
}

/// Wall edge descriptor.
class WallEdge {
  final List<double> start;
  final List<double> end;
  final double radius;

  const WallEdge(this.start, this.end, this.radius);
}

List<WallEdge> wallEdges(MapItem item, {bool collision = false}) {
  final radius = collision
      ? collisionThickness(item) / 2
      : math.max(0.5, item.stroke / 2);

  if (item.kind == 'circle_wall') {
    final points = ellipsePoints(item.width, item.height)
        .map((p) => item.localToWorld(p[0], p[1]))
        .toList();
    return [
      for (var i = 0; i < points.length - 1; i++)
        WallEdge(points[i], points[i + 1], radius)
    ];
  }

  if (item.kind == 'wall') {
    final a = item.localToWorld(0, 0);
    final b = item.localToWorld(item.width, item.height);
    return [WallEdge(a, b, radius)];
  }

  // room
  final w = item.width;
  final h = item.height;
  return [
    WallEdge(item.localToWorld(-radius, 0), item.localToWorld(w + radius, 0), radius),
    WallEdge(item.localToWorld(w, -radius), item.localToWorld(w, h + radius), radius),
    WallEdge(item.localToWorld(w + radius, h), item.localToWorld(-radius, h), radius),
    WallEdge(item.localToWorld(0, h + radius), item.localToWorld(0, -radius), radius),
  ];
}

List<Barrier> _solidSections(
    List<double> start, List<double> end, double radius, List<MapItem>? openings) {
  final dx = end[0] - start[0];
  final dy = end[1] - start[1];
  final length = helper.hypot(dx, dy);
  if (length < 1e-9) return [];
  final ux = dx / length;
  final uy = dy / length;

  final cuts = <(double, double)>[];
  if (openings != null) {
    for (final opening in openings) {
      final openY = opening.height / 2;
      final aW = opening.localToWorld(0, openY);
      final bW = opening.localToWorld(opening.width, openY);
      final ox = bW[0] - aW[0];
      final oy = bW[1] - aW[1];
      final openingLength = helper.hypot(ox, oy);
      if (openingLength == 0 ||
          (ux * oy - uy * ox).abs() / openingLength > 1e-5) continue;
      final distA = ((aW[0] - start[0]) * uy - (aW[1] - start[1]) * ux).abs();
      final distB = ((bW[0] - start[0]) * uy - (bW[1] - start[1]) * ux).abs();
      if (math.max(distA, distB) > radius + 8 + 1e-7) continue;
      final posA = (aW[0] - start[0]) * ux + (aW[1] - start[1]) * uy;
      final posB = (bW[0] - start[0]) * ux + (bW[1] - start[1]) * uy;
      final lo = math.max(0.0, math.min(posA, posB));
      final hi = math.min(length, math.max(posA, posB));
      if (hi - lo > 1e-7) cuts.add((lo, hi));
    }
  }

  cuts.sort((a, b) => a.$1.compareTo(b.$1));
  final sections = <Barrier>[];
  double cursor = 0;
  for (final cutEntry in cuts) {
    final lo = cutEntry.$1;
    final hi = cutEntry.$2;
    if (lo > cursor + 1e-7) {
      sections.add(Barrier(
        startX: start[0] + cursor * ux,
        startY: start[1] + cursor * uy,
        endX: start[0] + lo * ux,
        endY: start[1] + lo * uy,
        radius: radius,
        flat: true,
      ));
    }
    cursor = math.max(cursor, hi);
  }
  if (cursor < length - 1e-7) {
    sections.add(Barrier(
      startX: start[0] + cursor * ux,
      startY: start[1] + cursor * uy,
      endX: start[0] + length * ux,
      endY: start[1] * 1.0 + length * uy,
      radius: radius,
      flat: true,
    ));
  }
  return sections;
}

const openingKinds = {'door', 'double_door', 'opening'};

List<MapItem> _openingIndex(List<MapItem> items) {
  return items.where((i) => openingKinds.contains(i.kind)).toList();
}

List<Barrier> barriersFor(List<MapItem> items) {
  final openings = _openingIndex(items);
  final result = <Barrier>[];
  for (final item in items) {
    result.addAll(_barriersForItem(item, openings));
  }
  return result;
}

List<Barrier> _barriersForItem(MapItem item, List<MapItem> openings) {
  const gateKinds = {'main_gate', 'secondary_gate'};
  if (gateKinds.contains(item.kind)) {
    final radius = collisionThickness(item) / 2;
    final barriers = <Barrier>[
      Barrier(
        startX: item.localToWorld(0, 0)[0],
        startY: item.localToWorld(0, 0)[1],
        endX: item.localToWorld(0, item.height)[0],
        endY: item.localToWorld(0, item.height)[1],
        radius: radius,
        flat: true,
      ),
      Barrier(
        startX: item.localToWorld(item.width, 0)[0],
        startY: item.localToWorld(item.width, 0)[1],
        endX: item.localToWorld(item.width, item.height)[0],
        endY: item.localToWorld(item.width, item.height)[1],
        radius: radius,
        flat: true,
      ),
    ];
    if (!item.gateOpen) {
      barriers.add(Barrier(
        startX: item.localToWorld(0, item.height / 2)[0],
        startY: item.localToWorld(0, item.height / 2)[1],
        endX: item.localToWorld(item.width, item.height / 2)[0],
        endY: item.localToWorld(item.width, item.height / 2)[1],
        radius: radius,
        flat: true,
      ));
    }
    return barriers;
  }
  if (!item.blocking) return [];
  const wallKinds = {'wall', 'room', 'circle_wall'};
  if (wallKinds.contains(item.kind)) {
    return collisionWallSections(item, openings: openings);
  }
  if (item.kind == 'railing') {
    return [
      Barrier(
        startX: item.localToWorld(0, 0)[0],
        startY: item.localToWorld(0, 0)[1],
        endX: item.localToWorld(item.width, item.height)[0],
        endY: item.localToWorld(item.width, item.height)[1],
        radius: collisionThickness(item) / 2,
      )
    ];
  }
  if (item.kind == 'stairs' && item.collisionThickness != null) {
    return [
      Barrier(
        startX: item.localToWorld(0, 0)[0],
        startY: item.localToWorld(0, 0)[1],
        endX: item.localToWorld(0, item.height)[0],
        endY: item.localToWorld(0, item.height)[1],
        radius: item.collisionThickness! / 2,
        flat: true,
      ),
      Barrier(
        startX: item.localToWorld(item.width, 0)[0],
        startY: item.localToWorld(item.width, 0)[1],
        endX: item.localToWorld(item.width, item.height)[0],
        endY: item.localToWorld(item.width, item.height)[1],
        radius: item.collisionThickness! / 2,
        flat: true,
      ),
    ];
  }
  return [];
}

(double, double, double, double)? barrierBounds(List<Barrier> barriers) {
  if (barriers.isEmpty) return null;
  double minX = double.infinity,
      minY = double.infinity,
      maxX = double.negativeInfinity,
      maxY = double.negativeInfinity;
  for (final b in barriers) {
    final bb = b.bounds;
    if (bb.$1 < minX) minX = bb.$1;
    if (bb.$2 < minY) minY = bb.$2;
    if (bb.$3 > maxX) maxX = bb.$3;
    if (bb.$4 > maxY) maxY = bb.$4;
  }
  return (minX, minY, maxX, maxY);
}
