import 'dart:math' as math;

import 'collision.dart';
import 'runtime_index.dart';

/// Same-floor A* routing over the runtime collision geometry.
///
/// This is intentionally independent from stairs, hazards and rendering so the
/// same route engine can be reused by later evacuation-simulation stages.
class SameFloorPathfinder {
  final List<Barrier> barriers;
  final double playerRadius;
  final double width;
  final double height;
  final double cornerPadding;

  late final RuntimeIndex<Barrier> _barrierIndex;

  SameFloorPathfinder({
    required List<Barrier> barriers,
    required this.playerRadius,
    required this.width,
    required this.height,
    this.cornerPadding = 2,
  }) : barriers = List<Barrier>.unmodifiable(barriers) {
    _barrierIndex = RuntimeIndex<Barrier>(
      this.barriers,
      this.barriers.map((b) => b.bounds).toList(),
    );
  }

  /// Find a collision-free route from [start] to [goal].
  ///
  /// Points are world-space `[x, y]` pairs. An empty list means there is no
  /// route on the current surface.
  List<List<double>> findPath(List<double> start, List<double> goal) {
    if (!_validPoint(start) || !_validPoint(goal)) return const [];
    if (!_pointWalkable(start) || !_pointWalkable(goal)) return const [];

    if (lineIsWalkable(start, goal)) {
      return [List<double>.from(start), List<double>.from(goal)];
    }

    final nodes = _buildNodes(start, goal);
    if (nodes.length < 2) return const [];

    final path = _aStar(nodes);
    if (path.isEmpty) return const [];
    return _simplify(path);
  }

  /// True when a player's center can travel directly from [a] to [b] without
  /// crossing any runtime collision barrier.
  bool lineIsWalkable(List<double> a, List<double> b) {
    if (!_validPoint(a) || !_validPoint(b)) return false;
    if (!_withinBounds(a[0], a[1]) || !_withinBounds(b[0], b[1])) {
      return false;
    }

    final nearby = _barrierIndex.query(
      a[0],
      a[1],
      px2: b[0],
      py2: b[1],
      padding: playerRadius + cornerPadding,
    );

    for (final barrier in nearby) {
      final distance = _segmentDistance(
        a[0],
        a[1],
        b[0],
        b[1],
        barrier.startX,
        barrier.startY,
        barrier.endX,
        barrier.endY,
      );
      if (distance < barrier.radius + playerRadius - 1e-7) return false;
    }
    return true;
  }

  List<_RoutePoint> _buildNodes(List<double> start, List<double> goal) {
    final nodes = <_RoutePoint>[
      _RoutePoint(start[0], start[1]),
      _RoutePoint(goal[0], goal[1]),
    ];

    // Quantization only deduplicates near-identical corner candidates. It does
    // not turn the map into a navigation grid.
    final quantum = math.max(1.0, math.min(8.0, playerRadius / 2));
    final seen = <String>{
      _pointKey(start[0], start[1], quantum),
      _pointKey(goal[0], goal[1], quantum),
    };

    void add(double x, double y) {
      if (!_withinBounds(x, y)) return;
      final point = <double>[x, y];
      if (!_pointWalkable(point)) return;
      final key = _pointKey(x, y, quantum);
      if (!seen.add(key)) return;
      nodes.add(_RoutePoint(x, y));
    }

    for (final barrier in barriers) {
      final dx = barrier.endX - barrier.startX;
      final dy = barrier.endY - barrier.startY;
      final length = math.sqrt(dx * dx + dy * dy);
      final clearance = barrier.radius + playerRadius + cornerPadding;

      if (length < 1e-9) {
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          add(
            barrier.startX + math.cos(angle) * clearance,
            barrier.startY + math.sin(angle) * clearance,
          );
        }
        continue;
      }

      final ux = dx / length;
      final uy = dy / length;
      final nx = -uy;
      final ny = ux;

      // Four points just beyond each wall end. Door/opening cuts split walls
      // into segments, so their endpoints naturally create doorway candidates.
      add(
        barrier.startX - ux * clearance + nx * clearance,
        barrier.startY - uy * clearance + ny * clearance,
      );
      add(
        barrier.startX - ux * clearance - nx * clearance,
        barrier.startY - uy * clearance - ny * clearance,
      );
      add(
        barrier.endX + ux * clearance + nx * clearance,
        barrier.endY + uy * clearance + ny * clearance,
      );
      add(
        barrier.endX + ux * clearance - nx * clearance,
        barrier.endY + uy * clearance - ny * clearance,
      );
    }

    return nodes;
  }

  List<List<double>> _aStar(List<_RoutePoint> nodes) {
    final count = nodes.length;
    final gScore = List<double>.filled(count, double.infinity);
    final fScore = List<double>.filled(count, double.infinity);
    final cameFrom = List<int>.filled(count, -1);
    final closed = List<bool>.filled(count, false);
    final neighborCache = List<List<_RouteEdge>?>.filled(count, null);
    final heap = _MinHeap();

    gScore[0] = 0;
    fScore[0] = _distance(nodes[0], nodes[1]);
    heap.push(_HeapEntry(0, fScore[0]));

    while (heap.isNotEmpty) {
      final entry = heap.pop();
      final current = entry.index;
      if (closed[current]) continue;
      if (entry.score > fScore[current] + 1e-9) continue;

      if (current == 1) {
        final indices = <int>[1];
        var cursor = 1;
        while (cameFrom[cursor] >= 0) {
          cursor = cameFrom[cursor];
          indices.add(cursor);
        }
        if (indices.last != 0) return const [];
        return indices.reversed
            .map((i) => <double>[nodes[i].x, nodes[i].y])
            .toList();
      }

      closed[current] = true;
      final neighbors =
          neighborCache[current] ??= _neighbors(current, nodes);
      for (final edge in neighbors) {
        final next = edge.index;
        if (closed[next]) continue;
        final tentative = gScore[current] + edge.cost;
        if (tentative + 1e-9 >= gScore[next]) continue;
        cameFrom[next] = current;
        gScore[next] = tentative;
        fScore[next] = tentative + _distance(nodes[next], nodes[1]);
        heap.push(_HeapEntry(next, fScore[next]));
      }
    }

    return const [];
  }

  List<_RouteEdge> _neighbors(int index, List<_RoutePoint> nodes) {
    final source = nodes[index];
    final candidates = <int>[];

    if (nodes.length <= 300) {
      for (var i = 0; i < nodes.length; i++) {
        if (i != index) candidates.add(i);
      }
    } else {
      // Sparse visibility graph for the full campus: retain several nearby
      // candidates in every direction instead of generating all-pairs edges.
      const sectorCount = 24;
      const perSector = 3;
      final sectors =
          List.generate(sectorCount, (_) => <_NeighborCandidate>[]);

      for (var i = 0; i < nodes.length; i++) {
        if (i == index) continue;
        final dx = nodes[i].x - source.x;
        final dy = nodes[i].y - source.y;
        final distance2 = dx * dx + dy * dy;
        var normalized =
            (math.atan2(dy, dx) + math.pi) / (2 * math.pi);
        if (normalized >= 1) normalized = 0;
        final sector = (normalized * sectorCount)
            .floor()
            .clamp(0, sectorCount - 1)
            .toInt();
        final bucket = sectors[sector];
        bucket.add(_NeighborCandidate(i, distance2));
        bucket.sort((a, b) => a.distance2.compareTo(b.distance2));
        if (bucket.length > perSector) bucket.removeLast();
      }

      final seen = <int>{};
      for (final bucket in sectors) {
        for (final candidate in bucket) {
          if (seen.add(candidate.index)) candidates.add(candidate.index);
        }
      }
      if (index != 1 && seen.add(1)) candidates.add(1);
    }

    final result = <_RouteEdge>[];
    final a = <double>[source.x, source.y];
    for (final next in candidates) {
      final target = nodes[next];
      final b = <double>[target.x, target.y];
      if (!lineIsWalkable(a, b)) continue;
      result.add(_RouteEdge(next, _distance(source, target)));
    }
    return result;
  }

  List<List<double>> _simplify(List<List<double>> path) {
    if (path.length <= 2) return path;
    final simplified = <List<double>>[path.first];
    var anchor = 0;
    while (anchor < path.length - 1) {
      var furthest = anchor + 1;
      for (var i = path.length - 1; i > anchor + 1; i--) {
        if (lineIsWalkable(path[anchor], path[i])) {
          furthest = i;
          break;
        }
      }
      simplified.add(path[furthest]);
      anchor = furthest;
    }
    return simplified;
  }

  bool _pointWalkable(List<double> point) {
    if (!_withinBounds(point[0], point[1])) return false;
    final nearby = _barrierIndex.query(
      point[0],
      point[1],
      padding: playerRadius,
    );
    return !nearby.any(
      (b) => b.blocks(point[0], point[1], playerRadius),
    );
  }

  bool _validPoint(List<double> point) {
    return point.length >= 2 && point[0].isFinite && point[1].isFinite;
  }

  bool _withinBounds(double x, double y) {
    return x >= playerRadius &&
        y >= playerRadius &&
        x <= width - playerRadius &&
        y <= height - playerRadius;
  }

  String _pointKey(double x, double y, double quantum) {
    return '${(x / quantum).round()}:${(y / quantum).round()}';
  }

  double _distance(_RoutePoint a, _RoutePoint b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _segmentDistance(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy,
    double dx,
    double dy,
  ) {
    if (_segmentsIntersect(ax, ay, bx, by, cx, cy, dx, dy)) return 0;
    return math.min(
      math.min(
        _pointSegmentDistance(ax, ay, cx, cy, dx, dy),
        _pointSegmentDistance(bx, by, cx, cy, dx, dy),
      ),
      math.min(
        _pointSegmentDistance(cx, cy, ax, ay, bx, by),
        _pointSegmentDistance(dx, dy, ax, ay, bx, by),
      ),
    );
  }

  double _pointSegmentDistance(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax;
    final dy = by - ay;
    final length2 = dx * dx + dy * dy;
    if (length2 < 1e-18) {
      final ex = px - ax;
      final ey = py - ay;
      return math.sqrt(ex * ex + ey * ey);
    }
    final t = (((px - ax) * dx + (py - ay) * dy) / length2)
        .clamp(0.0, 1.0);
    final qx = ax + t * dx;
    final qy = ay + t * dy;
    final ex = px - qx;
    final ey = py - qy;
    return math.sqrt(ex * ex + ey * ey);
  }

  bool _segmentsIntersect(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy,
    double dx,
    double dy,
  ) {
    const eps = 1e-9;

    double cross(
      double px,
      double py,
      double qx,
      double qy,
      double rx,
      double ry,
    ) {
      return (qx - px) * (ry - py) -
          (qy - py) * (rx - px);
    }

    bool onSegment(
      double px,
      double py,
      double qx,
      double qy,
      double rx,
      double ry,
    ) {
      return qx >= math.min(px, rx) - eps &&
          qx <= math.max(px, rx) + eps &&
          qy >= math.min(py, ry) - eps &&
          qy <= math.max(py, ry) + eps;
    }

    final o1 = cross(ax, ay, bx, by, cx, cy);
    final o2 = cross(ax, ay, bx, by, dx, dy);
    final o3 = cross(cx, cy, dx, dy, ax, ay);
    final o4 = cross(cx, cy, dx, dy, bx, by);

    if (((o1 > eps && o2 < -eps) ||
            (o1 < -eps && o2 > eps)) &&
        ((o3 > eps && o4 < -eps) ||
            (o3 < -eps && o4 > eps))) {
      return true;
    }
    if (o1.abs() <= eps &&
        onSegment(ax, ay, cx, cy, bx, by)) {
      return true;
    }
    if (o2.abs() <= eps &&
        onSegment(ax, ay, dx, dy, bx, by)) {
      return true;
    }
    if (o3.abs() <= eps &&
        onSegment(cx, cy, ax, ay, dx, dy)) {
      return true;
    }
    if (o4.abs() <= eps &&
        onSegment(cx, cy, bx, by, dx, dy)) {
      return true;
    }
    return false;
  }
}

class _RoutePoint {
  final double x;
  final double y;
  const _RoutePoint(this.x, this.y);
}

class _RouteEdge {
  final int index;
  final double cost;
  const _RouteEdge(this.index, this.cost);
}

class _NeighborCandidate {
  final int index;
  final double distance2;
  const _NeighborCandidate(this.index, this.distance2);
}

class _HeapEntry {
  final int index;
  final double score;
  const _HeapEntry(this.index, this.score);
}

class _MinHeap {
  final List<_HeapEntry> _items = [];

  bool get isNotEmpty => _items.isNotEmpty;

  void push(_HeapEntry entry) {
    _items.add(entry);
    var index = _items.length - 1;
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (_items[parent].score <= entry.score) break;
      _items[index] = _items[parent];
      index = parent;
    }
    _items[index] = entry;
  }

  _HeapEntry pop() {
    final result = _items.first;
    final last = _items.removeLast();
    if (_items.isEmpty) return result;

    var index = 0;
    while (true) {
      final left = index * 2 + 1;
      if (left >= _items.length) break;
      final right = left + 1;
      var child = left;
      if (right < _items.length &&
          _items[right].score < _items[left].score) {
        child = right;
      }
      if (_items[child].score >= last.score) break;
      _items[index] = _items[child];
      index = child;
    }
    _items[index] = last;
    return result;
  }
}
