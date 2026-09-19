import 'dart:math' as math;

import 'collision.dart';
import 'runtime_index.dart';

/// Same-floor A* routing over the runtime collision geometry.
///
/// This is intentionally independent from stairs, hazards and rendering so the
/// same route engine can be reused by later evacuation-simulation stages.
class RouteRiskZone {
  final double x;
  final double y;

  /// Mandatory blocked radius, including configured safety clearance.
  final double radius;

  const RouteRiskZone({required this.x, required this.y, required this.radius});
}

class SameFloorPathfinder {
  final List<Barrier> barriers;
  final double playerRadius;
  final double width;
  final double height;
  final double cornerPadding;

  /// Optional walkable regions that should be preferred, such as campus roads.
  /// They affect route cost only; collision geometry remains authoritative.
  final List<PolygonBarrier> preferredAreas;

  /// Maximum cost discount for a segment fully inside a preferred area.
  /// 0.35 means road travel costs 65% of the same off-road distance.
  final double preferredAreaDiscount;

  /// Dynamic hazard zones used as a continuous A* risk field.
  final List<RouteRiskZone> riskZones;

  /// Strength of the hazard-distance penalty.
  final double riskWeight;

  /// Distance outside a risk zone where proximity still affects route cost.
  final double riskInfluenceDistance;

  /// Emergency mode: use a valid preferred-road route directly.
  final bool forcePreferredRoute;

  late final RuntimeIndex<Barrier> _barrierIndex;
  late final RuntimeIndex<PolygonBarrier>? _preferredAreaIndex;

  SameFloorPathfinder({
    required List<Barrier> barriers,
    required this.playerRadius,
    required this.width,
    required this.height,
    this.cornerPadding = 2,
    List<PolygonBarrier> preferredAreas = const [],
    this.preferredAreaDiscount = 0.35,
    this.forcePreferredRoute = false,
    List<RouteRiskZone> riskZones = const [],
    this.riskWeight = 0,
    this.riskInfluenceDistance = 320,
  }) : assert(
         preferredAreaDiscount >= 0 && preferredAreaDiscount < 1,
         'preferredAreaDiscount must be in [0, 1)',
       ),
       preferredAreas = List<PolygonBarrier>.unmodifiable(preferredAreas),
       riskZones = List<RouteRiskZone>.unmodifiable(riskZones),
       barriers = List<Barrier>.unmodifiable(barriers) {
    _barrierIndex = RuntimeIndex<Barrier>(
      this.barriers,
      this.barriers.map((b) => b.bounds).toList(),
    );
    _preferredAreaIndex = this.preferredAreas.isEmpty
        ? null
        : RuntimeIndex<PolygonBarrier>(
            this.preferredAreas,
            this.preferredAreas.map((area) => area.box).toList(),
          );
  }

  /// Find a collision-free route from [start] to [goal].
  ///
  /// Points are world-space `[x, y]` pairs. An empty list means there is no
  /// route on the current surface.
  List<List<double>> findPath(List<double> start, List<double> goal) {
    if (!_validPoint(start) || !_validPoint(goal)) return const [];
    if (!_pointWalkable(start) || !_pointWalkable(goal)) return const [];

    if (preferredAreas.isNotEmpty) {
      final roadRoute = _findPreferredCenterlinePath(start, goal);
      if (roadRoute.isNotEmpty) {
        if (forcePreferredRoute) return roadRoute;

        // Road preference must not become absolute. Compare the physical
        // centerline route against the ordinary shortest collision-safe route.
        // A fully road-based route may be about 1 / 0.65 ~= 1.54x longer and
        // still match the existing 35% road preference, but huge detours should
        // fall back to the normal route.
        final plainPathfinder = SameFloorPathfinder(
          barriers: barriers,
          playerRadius: playerRadius,
          width: width,
          height: height,
          cornerPadding: cornerPadding,
          riskZones: riskZones,
          riskWeight: riskWeight,
          riskInfluenceDistance: riskInfluenceDistance,
        );
        final plainRoute = plainPathfinder.findPath(start, goal);

        if (plainRoute.isEmpty) return roadRoute;

        final roadCost = _routeCost(roadRoute);
        final plainCost = _routeCost(plainRoute);

        // Cost sampling can make a diagonal that merely crosses a road look a
        // few percent cheaper than a route that deliberately follows its
        // centerline. Treat that small difference as a tie so road preference
        // remains stable, while still rejecting genuinely large detours.
        const roadTieTolerance = 1.05;
        return roadCost <= plainCost * roadTieTolerance
            ? roadRoute
            : plainRoute;
      }
    }

    // With no preference regions the original fast direct-path behavior
    // is preserved. When roads are configured, A* must be allowed to compare
    // the direct line against a slightly longer but preferred-road route.
    //
    // When risk zones are present, the direct shortcut is still safe if the
    // segment is geometrically walkable AND does not enter any risk zone's
    // core area. This avoids falling through to full A* for connector paths
    // that merely pass near (but not through) a hazard.
    if (preferredAreas.isEmpty && lineIsWalkable(start, goal)) {
      if (riskZones.isEmpty || !_segmentCrossesRiskZone(start, goal)) {
        return [List<double>.from(start), List<double>.from(goal)];
      }
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

  List<List<double>> _findPreferredCenterlinePath(
    List<double> start,
    List<double> goal,
  ) {
    final roads = <_RoadCenterline>[];
    for (var i = 0; i < preferredAreas.length; i++) {
      final area = preferredAreas[i];
      if (area.points.length != 4) continue;
      final line = _centerlineForArea(i, area);
      if (line != null) roads.add(line);
    }
    if (roads.isEmpty) return const [];

    final plain = SameFloorPathfinder(
      barriers: barriers,
      playerRadius: playerRadius,
      width: width,
      height: height,
      cornerPadding: cornerPadding,
      riskZones: riskZones,
      riskWeight: riskWeight,
      riskInfluenceDistance: riskInfluenceDistance,
    );

    final startAccess = _roadAccessCandidates(
      start,
      roads,
      plain,
      fromPoint: true,
    );
    final goalAccess = _roadAccessCandidates(
      goal,
      roads,
      plain,
      fromPoint: false,
    );
    if (startAccess.isEmpty || goalAccess.isEmpty) return const [];

    final graph = _buildRoadGraph(roads, [...startAccess, ...goalAccess]);

    List<List<double>>? best;
    var bestCost = double.infinity;

    for (final s in startAccess) {
      final sNode = graph.accessNode[s.key];
      if (sNode == null) continue;

      for (final g in goalAccess) {
        final gNode = graph.accessNode[g.key];
        if (gNode == null) continue;

        final roadPath = graph.shortestPath(sNode, gNode);
        if (roadPath.isEmpty) continue;

        // Prefer a short connection to the nearest sensible road.
        // Long diagonal jumps onto a farther road are deliberately expensive.
        const accessPenalty = 4.0;
        final total =
            _routeCost(s.path) * accessPenalty +
            _routeCost(roadPath) +
            _routeCost(g.path) * accessPenalty;

        if (total >= bestCost) continue;

        final combined = <List<double>>[
          for (final p in s.path) List<double>.from(p),
          for (var i = 1; i < roadPath.length; i++)
            List<double>.from(roadPath[i]),
          for (var i = 1; i < g.path.length; i++) List<double>.from(g.path[i]),
        ];

        if (!_routeSegmentsWalkable(combined)) continue;
        bestCost = total;
        best = _simplifyCollinear(combined);
      }
    }

    return best ?? const [];
  }

  _RoadCenterline? _centerlineForArea(int areaIndex, PolygonBarrier area) {
    if (area.points.length != 4) return null;

    List<double> midpoint(List<double> a, List<double> b) => <double>[
      (a[0] + b[0]) / 2,
      (a[1] + b[1]) / 2,
    ];

    double d2(List<double> a, List<double> b) {
      final dx = b[0] - a[0];
      final dy = b[1] - a[1];
      return dx * dx + dy * dy;
    }

    final p0 = area.points[0];
    final p1 = area.points[1];
    final p2 = area.points[2];
    final p3 = area.points[3];

    final a0 = midpoint(p0, p1);
    final a1 = midpoint(p2, p3);
    final b0 = midpoint(p1, p2);
    final b1 = midpoint(p3, p0);

    final useA = d2(a0, a1) >= d2(b0, b1);
    final start = useA ? a0 : b0;
    final end = useA ? a1 : b1;

    if (d2(start, end) < 1e-8) return null;
    return _RoadCenterline(areaIndex, area, start, end);
  }

  List<_RoadAccess> _roadAccessCandidates(
    List<double> point,
    List<_RoadCenterline> roads,
    SameFloorPathfinder plain, {
    required bool fromPoint,
  }) {
    final raw = <(_RoadCenterline, List<double>, double)>[];

    for (final road in roads) {
      final projection = _projectToSegment(point, road.start, road.end);
      final dx = projection[0] - point[0];
      final dy = projection[1] - point[1];
      raw.add((road, projection, dx * dx + dy * dy));
    }

    raw.sort((a, b) => a.$3.compareTo(b.$3));

    final result = <_RoadAccess>[];
    for (final entry in raw.take(8)) {
      final road = entry.$1;
      final projection = entry.$2;

      final path = fromPoint
          ? plain.findPath(point, projection)
          : plain.findPath(projection, point);
      if (path.isEmpty) continue;

      result.add(
        _RoadAccess(
          roadIndex: road.areaIndex,
          point: projection,
          path: path,
          key:
              '${fromPoint ? 's' : 'g'}:${road.areaIndex}:'
              '${projection[0].toStringAsFixed(3)}:'
              '${projection[1].toStringAsFixed(3)}',
        ),
      );
      if (result.length >= 3) break;
    }

    return result;
  }

  _RoadGraph _buildRoadGraph(
    List<_RoadCenterline> roads,
    List<_RoadAccess> access,
  ) {
    final graph = _RoadGraph();
    final perRoad = <int, List<(double, int)>>{};

    int addRoadPoint(_RoadCenterline road, List<double> p) {
      final node = graph.addNode(p);
      final t = _segmentParameter(p, road.start, road.end);
      perRoad.putIfAbsent(road.areaIndex, () => []).add((t, node));
      return node;
    }

    for (final road in roads) {
      addRoadPoint(road, road.start);
      addRoadPoint(road, road.end);
    }

    for (var i = 0; i < roads.length; i++) {
      for (var j = i + 1; j < roads.length; j++) {
        final first = roads[i];
        final second = roads[j];

        final hit = _segmentIntersection(
          first.start,
          first.end,
          second.start,
          second.end,
        );

        if (hit != null) {
          final node = graph.addNode(hit);
          perRoad.putIfAbsent(first.areaIndex, () => []).add((
            _segmentParameter(hit, first.start, first.end),
            node,
          ));
          perRoad.putIfAbsent(second.areaIndex, () => []).add((
            _segmentParameter(hit, second.start, second.end),
            node,
          ));
          continue;
        }

        // Map-editor roads can make a T-junction by touching rectangle edges.
        // In that case their centerlines do not literally intersect. Connect
        // the nearest centerline points only when the connector remains fully
        // inside the mapped road union.
        final bridge = _closestPointsBetweenSegments(
          first.start,
          first.end,
          second.start,
          second.end,
        );
        final a = bridge.$1;
        final b = bridge.$2;

        if (_pointDistance(a, b) < 1e-6) continue;
        if (!_segmentInsidePreferredRoads(a, b)) continue;
        if (!lineIsWalkable(a, b)) continue;

        final aNode = graph.addNode(a);
        final bNode = graph.addNode(b);

        perRoad.putIfAbsent(first.areaIndex, () => []).add((
          _segmentParameter(a, first.start, first.end),
          aNode,
        ));
        perRoad.putIfAbsent(second.areaIndex, () => []).add((
          _segmentParameter(b, second.start, second.end),
          bNode,
        ));

        graph.connect(aNode, bNode, _edgeCost(a, b));
      }
    }

    for (final a in access) {
      final road = roads.firstWhere((r) => r.areaIndex == a.roadIndex);
      final node = addRoadPoint(road, a.point);
      graph.accessNode[a.key] = node;
    }

    for (final road in roads) {
      final list = perRoad[road.areaIndex];
      if (list == null || list.length < 2) continue;

      list.sort((a, b) => a.$1.compareTo(b.$1));
      final seen = <int>{};
      final ordered = <int>[];
      for (final pair in list) {
        if (seen.add(pair.$2)) ordered.add(pair.$2);
      }

      for (var i = 1; i < ordered.length; i++) {
        final a = graph.points[ordered[i - 1]];
        final b = graph.points[ordered[i]];
        if (!lineIsWalkable(a, b)) continue;
        graph.connect(ordered[i - 1], ordered[i], _edgeCost(a, b));
      }
    }

    return graph;
  }

  List<double> _projectToSegment(
    List<double> point,
    List<double> a,
    List<double> b,
  ) {
    final dx = b[0] - a[0];
    final dy = b[1] - a[1];
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-12) return List<double>.from(a);

    final t = (((point[0] - a[0]) * dx + (point[1] - a[1]) * dy) / len2).clamp(
      0.0,
      1.0,
    );
    return <double>[a[0] + dx * t, a[1] + dy * t];
  }

  double _segmentParameter(List<double> p, List<double> a, List<double> b) {
    final dx = b[0] - a[0];
    final dy = b[1] - a[1];
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-12) return 0;
    return (((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2).clamp(0.0, 1.0);
  }

  List<double>? _segmentIntersection(
    List<double> a,
    List<double> b,
    List<double> c,
    List<double> d,
  ) {
    final rX = b[0] - a[0];
    final rY = b[1] - a[1];
    final sX = d[0] - c[0];
    final sY = d[1] - c[1];
    final denom = rX * sY - rY * sX;

    if (denom.abs() < 1e-9) return null;

    final cax = c[0] - a[0];
    final cay = c[1] - a[1];
    final t = (cax * sY - cay * sX) / denom;
    final u = (cax * rY - cay * rX) / denom;

    const eps = 1e-6;
    if (t < -eps || t > 1 + eps || u < -eps || u > 1 + eps) return null;

    return <double>[a[0] + t * rX, a[1] + t * rY];
  }

  (List<double>, List<double>) _closestPointsBetweenSegments(
    List<double> a,
    List<double> b,
    List<double> c,
    List<double> d,
  ) {
    final candidates = <(List<double>, List<double>)>[
      (a, _projectToSegment(a, c, d)),
      (b, _projectToSegment(b, c, d)),
      (_projectToSegment(c, a, b), c),
      (_projectToSegment(d, a, b), d),
    ];

    var best = candidates.first;
    var bestDistance = _pointDistance(best.$1, best.$2);

    for (final pair in candidates.skip(1)) {
      final distance = _pointDistance(pair.$1, pair.$2);
      if (distance < bestDistance) {
        best = pair;
        bestDistance = distance;
      }
    }
    return best;
  }

  bool _segmentInsidePreferredRoads(List<double> a, List<double> b) {
    const samples = 11;

    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final x = a[0] + (b[0] - a[0]) * t;
      final y = a[1] + (b[1] - a[1]) * t;

      final nearby = _preferredAreaIndex?.query(x, y);
      if (nearby == null || !nearby.any((area) => area.blocks(x, y, 1e-5))) {
        return false;
      }
    }
    return true;
  }

  bool _routeSegmentsWalkable(List<List<double>> path) {
    for (var i = 1; i < path.length; i++) {
      if (!lineIsWalkable(path[i - 1], path[i])) return false;
    }
    return true;
  }

  List<List<double>> _simplifyCollinear(List<List<double>> path) {
    if (path.length <= 2) return path;

    final out = <List<double>>[List<double>.from(path.first)];
    for (var i = 1; i < path.length - 1; i++) {
      final a = out.last;
      final b = path[i];
      final c = path[i + 1];

      final abx = b[0] - a[0];
      final aby = b[1] - a[1];
      final bcx = c[0] - b[0];
      final bcy = c[1] - b[1];
      final cross = (abx * bcy - aby * bcx).abs();
      final scale = math.max(
        1.0,
        math.sqrt(abx * abx + aby * aby) * math.sqrt(bcx * bcx + bcy * bcy),
      );

      if (cross / scale < 0.002 && lineIsWalkable(a, c)) {
        continue;
      }
      out.add(List<double>.from(b));
    }
    out.add(List<double>.from(path.last));
    return out;
  }

  double _routeCost(List<List<double>> path) {
    var total = 0.0;
    for (var i = 1; i < path.length; i++) {
      total += _edgeCost(path[i - 1], path[i]);
    }
    return total;
  }

  double _pointDistance(List<double> a, List<double> b) {
    final dx = b[0] - a[0];
    final dy = b[1] - a[1];
    return math.sqrt(dx * dx + dy * dy);
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

    // Roads are rectangular preferred regions. Use only the LONG-AXIS
    // centerline as navigation candidates so the blue evacuation route stays
    // visually straight and centered instead of zig-zagging between corners.
    for (final area in preferredAreas) {
      if (area.points.length != 4) continue;

      List<double> midpoint(List<double> a, List<double> b) => <double>[
        (a[0] + b[0]) / 2,
        (a[1] + b[1]) / 2,
      ];

      double distance2(List<double> a, List<double> b) {
        final dx = b[0] - a[0];
        final dy = b[1] - a[1];
        return dx * dx + dy * dy;
      }

      final p0 = area.points[0];
      final p1 = area.points[1];
      final p2 = area.points[2];
      final p3 = area.points[3];

      // Two possible centerlines connect opposite edge midpoints.
      final a0 = midpoint(p0, p1);
      final a1 = midpoint(p2, p3);
      final b0 = midpoint(p1, p2);
      final b1 = midpoint(p3, p0);

      final useA = distance2(a0, a1) >= distance2(b0, b1);
      final startCenter = useA ? a0 : b0;
      final endCenter = useA ? a1 : b1;
      final center = <double>[
        (startCenter[0] + endCenter[0]) / 2,
        (startCenter[1] + endCenter[1]) / 2,
      ];

      add(startCenter[0], startCenter[1]);
      add(center[0], center[1]);
      add(endCenter[0], endCenter[1]);
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

    // Risk-field waypoints give A* real alternatives farther away from danger
    // instead of only obstacle-corner points close to a hazard.
    for (final zone in riskZones) {
      for (final factor in const [0.45, 0.9]) {
        final ring = zone.radius + riskInfluenceDistance * factor;
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          add(zone.x + math.cos(angle) * ring, zone.y + math.sin(angle) * ring);
        }
      }
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
    fScore[0] = _heuristic(nodes[0], nodes[1]);
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
      final neighbors = neighborCache[current] ??= _neighbors(current, nodes);
      for (final edge in neighbors) {
        final next = edge.index;
        if (closed[next]) continue;
        final tentative = gScore[current] + edge.cost;
        if (tentative + 1e-9 >= gScore[next]) continue;
        cameFrom[next] = current;
        gScore[next] = tentative;
        fScore[next] = tentative + _heuristic(nodes[next], nodes[1]);
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
      final sectors = List.generate(sectorCount, (_) => <_NeighborCandidate>[]);

      for (var i = 0; i < nodes.length; i++) {
        if (i == index) continue;
        final dx = nodes[i].x - source.x;
        final dy = nodes[i].y - source.y;
        final distance2 = dx * dx + dy * dy;
        var normalized = (math.atan2(dy, dx) + math.pi) / (2 * math.pi);
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
      result.add(_RouteEdge(next, _edgeCost(a, b)));
    }
    return result;
  }

  List<List<double>> _simplify(List<List<double>> path) {
    if (path.length <= 2) return path;

    if (preferredAreas.isNotEmpty || riskZones.isNotEmpty) {
      final simplified = <List<double>>[path.first];
      var anchor = 0;

      while (anchor < path.length - 1) {
        var furthest = anchor + 1;
        var originalCost = 0.0;

        for (var i = anchor + 1; i < path.length; i++) {
          originalCost += _edgeCost(path[i - 1], path[i]);
          if (!lineIsWalkable(path[anchor], path[i])) break;

          final directCost = _edgeCost(path[anchor], path[i]);

          // Only collapse points if the direct segment is no more expensive
          // than the road-following geometry. This keeps road preference while
          // removing tiny centerline kinks.
          if (directCost <= originalCost * 1.02 + 1e-6) {
            furthest = i;
          }
        }

        simplified.add(path[furthest]);
        anchor = furthest;
      }
      return simplified;
    }

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
    return !nearby.any((b) => b.blocks(point[0], point[1], playerRadius));
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

  double _heuristic(_RoutePoint a, _RoutePoint b) {
    // Since preferred edges can be discounted, scale Euclidean distance by
    // the minimum possible multiplier to keep the A* heuristic admissible.
    return _distance(a, b) * (1 - preferredAreaDiscount);
  }

  double _edgeCost(List<double> a, List<double> b) {
    final dx = b[0] - a[0];
    final dy = b[1] - a[1];
    final length = math.sqrt(dx * dx + dy * dy);
    if (length <= 1e-9) return 0;

    var cost = length;

    if (preferredAreas.isNotEmpty) {
      final coverage = _preferredCoverage(a, b);
      cost *= 1 - preferredAreaDiscount * coverage;
    }

    if (riskZones.isEmpty || riskWeight <= 0) return cost;

    final samples = math.max(5, (length / 24).ceil());
    var accumulatedRisk = 0.0;

    for (var i = 0; i < samples; i++) {
      final t = (i + 0.5) / samples;
      final x = a[0] + dx * t;
      final y = a[1] + dy * t;

      var pointRisk = 0.0;
      for (final zone in riskZones) {
        final zx = x - zone.x;
        final zy = y - zone.y;
        final edgeDistance = math.sqrt(zx * zx + zy * zy) - zone.radius;

        if (edgeDistance >= riskInfluenceDistance) continue;

        final normalized = edgeDistance <= 0
            ? 1.0
            : (1.0 - edgeDistance / riskInfluenceDistance).clamp(0.0, 1.0);

        pointRisk += normalized * normalized * normalized;
      }

      accumulatedRisk += pointRisk;
    }

    final averageRisk = accumulatedRisk / samples;
    return cost + length * riskWeight * averageRisk;
  }

  /// Returns true when the segment from [a] to [b] enters the core of any
  /// risk zone. A segment "crosses" a zone if either endpoint is inside the
  /// zone or the closest point on the segment to the zone center is inside
  /// the zone radius. Segments that only pass through the influence halo
  /// (outside the core radius) are considered safe for the fast shortcut.
  bool _segmentCrossesRiskZone(List<double> a, List<double> b) {
    if (riskZones.isEmpty) return false;
    final dx = b[0] - a[0];
    final dy = b[1] - a[1];
    final length2 = dx * dx + dy * dy;

    for (final zone in riskZones) {
      // Quick check: either endpoint inside zone.
      final ea = (a[0] - zone.x);
      final eb = (b[0] - zone.x);
      if (ea * ea + (a[1] - zone.y) * (a[1] - zone.y) <= zone.radius * zone.radius) {
        return true;
      }
      if (eb * eb + (b[1] - zone.y) * (b[1] - zone.y) <= zone.radius * zone.radius) {
        return true;
      }

      if (length2 <= 1e-9) continue;

      // Closest point on segment to zone center.
      final t = (((zone.x - a[0]) * dx + (zone.y - a[1]) * dy) / length2)
          .clamp(0.0, 1.0)
          .toDouble();
      final cx = a[0] + dx * t;
      final cy = a[1] + dy * t;
      final distX = cx - zone.x;
      final distY = cy - zone.y;
      if (distX * distX + distY * distY <= zone.radius * zone.radius) {
        return true;
      }
    }
    return false;
  }

  double _preferredCoverage(List<double> a, List<double> b) {
    // Sample segment interiors instead of only endpoints. A spatial index keeps
    // this cheap even when the campus contains many road rectangles.
    final index = _preferredAreaIndex;
    if (index == null) return 0;

    const samples = 7;
    var preferred = 0;

    for (var i = 0; i < samples; i++) {
      final t = (i + 0.5) / samples;
      final x = a[0] + (b[0] - a[0]) * t;
      final y = a[1] + (b[1] - a[1]) * t;

      final nearby = index.query(x, y);
      if (nearby.any((area) => area.blocks(x, y, 0))) {
        preferred++;
      }
    }

    return preferred / samples;
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
    final t = (((px - ax) * dx + (py - ay) * dy) / length2).clamp(0.0, 1.0);
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
      return (qx - px) * (ry - py) - (qy - py) * (rx - px);
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

    if (((o1 > eps && o2 < -eps) || (o1 < -eps && o2 > eps)) &&
        ((o3 > eps && o4 < -eps) || (o3 < -eps && o4 > eps))) {
      return true;
    }
    if (o1.abs() <= eps && onSegment(ax, ay, cx, cy, bx, by)) {
      return true;
    }
    if (o2.abs() <= eps && onSegment(ax, ay, dx, dy, bx, by)) {
      return true;
    }
    if (o3.abs() <= eps && onSegment(cx, cy, ax, ay, dx, dy)) {
      return true;
    }
    if (o4.abs() <= eps && onSegment(cx, cy, bx, by, dx, dy)) {
      return true;
    }
    return false;
  }
}

class _RoadCenterline {
  final int areaIndex;
  final PolygonBarrier area;
  final List<double> start;
  final List<double> end;

  const _RoadCenterline(this.areaIndex, this.area, this.start, this.end);
}

class _RoadAccess {
  final int roadIndex;
  final List<double> point;
  final List<List<double>> path;
  final String key;

  const _RoadAccess({
    required this.roadIndex,
    required this.point,
    required this.path,
    required this.key,
  });
}

class _RoadGraph {
  final List<List<double>> points = [];
  final List<List<(int, double)>> edges = [];
  final Map<String, int> accessNode = {};
  final Map<String, int> _pointIndex = {};

  int addNode(List<double> point) {
    final key = '${point[0].toStringAsFixed(4)}:${point[1].toStringAsFixed(4)}';
    final existing = _pointIndex[key];
    if (existing != null) return existing;

    final index = points.length;
    points.add(List<double>.from(point));
    edges.add(<(int, double)>[]);
    _pointIndex[key] = index;
    return index;
  }

  void connect(int a, int b, double cost) {
    if (a == b) return;
    edges[a].add((b, cost));
    edges[b].add((a, cost));
  }

  List<List<double>> shortestPath(int start, int goal) {
    if (start == goal) return <List<double>>[List<double>.from(points[start])];

    final count = points.length;
    final dist = List<double>.filled(count, double.infinity);
    final prev = List<int>.filled(count, -1);
    final used = List<bool>.filled(count, false);

    dist[start] = 0;

    for (var step = 0; step < count; step++) {
      var current = -1;
      var best = double.infinity;
      for (var i = 0; i < count; i++) {
        if (!used[i] && dist[i] < best) {
          best = dist[i];
          current = i;
        }
      }

      if (current < 0 || !best.isFinite) break;
      if (current == goal) break;
      used[current] = true;

      for (final edge in edges[current]) {
        final next = edge.$1;
        final candidate = dist[current] + edge.$2;
        if (candidate < dist[next]) {
          dist[next] = candidate;
          prev[next] = current;
        }
      }
    }

    if (!dist[goal].isFinite) return const [];

    final indices = <int>[];
    var cursor = goal;
    while (cursor >= 0) {
      indices.add(cursor);
      if (cursor == start) break;
      cursor = prev[cursor];
    }
    if (indices.last != start) return const [];

    return indices.reversed.map((i) => List<double>.from(points[i])).toList();
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
      if (right < _items.length && _items[right].score < _items[left].score) {
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
