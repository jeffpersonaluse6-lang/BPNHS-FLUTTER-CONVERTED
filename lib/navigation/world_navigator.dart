import 'dart:math' as math;
import '../models/map_item.dart';
import '../models/map_scene.dart';
import '../models/math_helper.dart';
import 'collision.dart';
import 'stairs.dart';
import 'stair_waypoint_guides.dart';
import 'floor_transform.dart';
import 'runtime_index.dart';
import 'same_floor_pathfinder.dart';
import 'hazard.dart';

const String campus = 'Campus';
const double transitionThreshold = 0.05;

enum TransitionPhase {
  onFloor,
  enteringStairs,
  transitioning,
  arrived,
  waitForExit,
}

class FloorTransition {
  final StairSection section;
  final int source;
  final int target;
  double progress;

  FloorTransition(this.section, this.source, this.target, this.progress);
}

/// A same-floor walking leg that ends inside a staircase which can move the
/// player toward a requested floor.
class StairRouteLeg {
  final StairSection section;
  final List<List<double>> path;

  const StairRouteLeg({required this.section, required this.path});

  int get sourceFloor => section.source;
  int get targetFloor => section.target;
  List<double> get entryPoint => path.last;
}

class EvacuationGateOption {
  final String kind;
  final double score;
  final List<List<double>> previewRoute;

  const EvacuationGateOption({
    required this.kind,
    required this.score,
    this.previewRoute = const [],
  });
}

class WorldNavigator {
  StairSection? lastCompletedStair;

  final MapScene scene;
  double markerX;
  double markerY;
  double collisionRadius;
  double playerSpeed;
  double stairSpeedMultiplier;

  MapItem? parent;
  FloorTransition? transition;
  int currentFloor = 1;
  TransitionPhase phase = TransitionPhase.onFloor;
  String? buildingName;
  String view = 'campus';

  List<double>? previousPoint;
  List<double>? previousWorldPoint;

  List<PolygonBarrier> exitAreas = [];
  int? waitFloor;
  final Set<String> lockedSections = {};

  // Simulation hazards are runtime-only. They do not modify the saved map.
  final List<HazardZone> hazards = <HazardZone>[];
  int _nextHazardId = 1;

  final Map<String, List<MapItem>> _stairObjects = {};
  final Map<String, RuntimeIndex<StairSection>> _stairIndices = {};
  final Map<String, List<PolygonBarrier>> _roofAreas = {};
  final Map<String, List<PolygonBarrier>> _entryAreas = {};
  final Map<String, FloorTransform> _transforms = {};

  final Map<String, (List<Barrier>, (double, double, double, double))>
  _colliders = {};
  final Map<String, RuntimeIndex<Barrier>> _collisionIndices = {};
  final Map<String, List<StairSection>> _connections = {};
  final Map<String, RuntimeIndex<StairSection>> _sectionIndices = {};
  final Map<String, StairSection> _sectionsById = {};

  late List<Barrier> groundBarriers;
  late List<PolygonBarrier> campusPreferredAreas;
  late RuntimeIndex<Barrier> groundIndex;
  late RuntimeIndex<MapItem> parentIndex;
  late RuntimeIndex<MapItem> roofIndex;

  double physicsStep = 1;

  WorldNavigator(
    this.scene, {
    this.markerX = 1510,
    this.markerY = 620,
    this.collisionRadius = 26,
    this.playerSpeed = 120,
    this.stairSpeedMultiplier = 0.65,
  }) {
    _buildIndex();
  }

  HazardZone addFireHazard(double x, double y, {double radius = 40}) {
    final zone = HazardZone(
      id: 'fire_${_nextHazardId++}',
      kind: HazardKind.fire,
      x: x,
      y: y,
      radius: radius,
      buildingId: parent?.id,
      floor: parent == null ? 1 : currentFloor,
    );
    hazards.add(zone);
    return zone;
  }

  HazardZone addEarthquakeHazard(double x, double y, {double radius = 55}) {
    final zone = HazardZone(
      id: 'earthquake_${_nextHazardId++}',
      kind: HazardKind.earthquake,
      x: x,
      y: y,
      radius: radius,
      buildingId: parent?.id,
      floor: parent == null ? 1 : currentFloor,
    );
    hazards.add(zone);
    return zone;
  }

  /// Adds a manually reported unsafe/restricted area for
  /// active-shooter simulation. This does not track a person.
  HazardZone addActiveShooterHazard(double x, double y, {double radius = 70}) {
    final zone = HazardZone(
      id: 'active_shooter_${_nextHazardId++}',
      kind: HazardKind.activeShooter,
      x: x,
      y: y,
      radius: radius,
      buildingId: parent?.id,
      floor: parent == null ? 1 : currentFloor,
    );
    hazards.add(zone);
    return zone;
  }

  HazardZone? hazardById(String id) {
    for (final hazard in hazards) {
      if (hazard.id == id) return hazard;
    }
    return null;
  }

  bool removeHazard(String id) {
    final before = hazards.length;
    hazards.removeWhere((hazard) => hazard.id == id);
    return hazards.length != before;
  }

  bool moveHazard(String id, double x, double y) {
    final hazard = hazardById(id);
    if (hazard == null) return false;

    hazard.x = x.clamp(0.0, scene.width).toDouble();
    hazard.y = y.clamp(0.0, scene.height).toDouble();
    return true;
  }

  void clearHazards() {
    hazards.clear();
  }

  List<HazardZone> get visibleHazards {
    final activeBuilding = parent?.id;
    final activeFloor = parent == null ? 1 : currentFloor;
    return hazards
        .where((h) => h.matchesSurface(activeBuilding, activeFloor))
        .toList(growable: false);
  }

  List<Barrier> _hazardBarriersForSurface(
    String? buildingId,
    int floor, {
    double safetyMargin = hazardSafetyClearance,
  }) {
    return <Barrier>[
      for (final hazard in hazards)
        if (hazard.matchesSurface(buildingId, floor))
          ...hazard.routingBarriers(safetyMargin: safetyMargin),
    ];
  }

  bool _pathClearOfSurfaceHazards(
    List<List<double>> path,
    String? buildingId,
    int floor,
  ) {
    if (path.length < 2) return true;

    final hazardBarriers = _hazardBarriersForSurface(buildingId, floor);
    if (hazardBarriers.isEmpty) return true;

    final checker = SameFloorPathfinder(
      barriers: hazardBarriers,
      playerRadius: collisionRadius,
      width: scene.width,
      height: scene.height,
    );

    for (var i = 1; i < path.length; i++) {
      if (!checker.lineIsWalkable(path[i - 1], path[i])) {
        return false;
      }
    }
    return true;
  }

  bool _isCourtBuilding(MapItem building) {
    final identity = '${building.id} ${building.opens ?? ''} ${building.kind}'
        .toLowerCase();

    if (identity.contains('court')) return true;

    // Court buildings are reliably identifiable from their floor content.
    for (final item in scene.floorItems(building.id, 1)) {
      if (item.kind == 'court_roof' || item.kind == 'court') {
        return true;
      }
    }

    return false;
  }

  List<Barrier> _campusBuildingFootprintBarriers() {
    final barriers = <Barrier>[];
    final currentBuildingId = parent?.id;

    for (final building in scene.buildings()) {
      // The route may begin inside the building the user currently occupies,
      // so do not seal that building until the route exits it.
      if (building.id == currentBuildingId) continue;

      // Courts are intentionally traversable evacuation space.
      if (_isCourtBuilding(building)) continue;

      final points = <List<double>>[
        building.localToWorld(0, 0),
        building.localToWorld(building.width, 0),
        building.localToWorld(building.width, building.height),
        building.localToWorld(0, building.height),
      ];

      for (var i = 0; i < points.length; i++) {
        final a = points[i];
        final b = points[(i + 1) % points.length];
        barriers.add(
          Barrier(
            startX: a[0],
            startY: a[1],
            endX: b[0],
            endY: b[1],
            radius: 1.0,
          ),
        );
      }
    }

    return barriers;
  }

  List<Barrier> _campusRoutingBaseBarriers() {
    return <Barrier>[...groundBarriers, ..._campusBuildingFootprintBarriers()];
  }

  List<Barrier> _groundRoutingBarriers() {
    return <Barrier>[
      ..._campusRoutingBaseBarriers(),
      // Floor-1 routes can pass from the current building into campus, so
      // include every Floor-1 hazard. Building footprints are routing-only;
      // manual movement/collision behavior is unchanged.
      for (final hazard in hazards)
        if (hazard.floor == 1)
          ...hazard.routingBarriers(safetyMargin: hazardSafetyClearance),
    ];
  }

  List<Barrier> _currentSurfaceRoutingBarriers(List<Barrier> base) {
    if (currentFloor == 1) return _groundRoutingBarriers();

    return <Barrier>[
      ...base,
      ..._hazardBarriersForSurface(parent?.id, currentFloor),
    ];
  }

  void _buildIndex() {
    final parents = scene.buildings();
    final parentBoxes = <(double, double, double, double)>[];
    final roofBoxes = <(double, double, double, double)>[];
    final campusLayerItems = scene.floors[campus] ?? const <MapItem>[];

    groundBarriers = barriersFor(campusLayerItems);
    campusPreferredAreas = [
      for (final item in campusLayerItems)
        if (item.kind == 'road')
          PolygonBarrier([
            item.localToWorld(0, 0),
            item.localToWorld(item.width, 0),
            item.localToWorld(item.width, item.height),
            item.localToWorld(0, item.height),
          ]),
    ];
    physicsStep = 4;

    for (final parent in parents) {
      final transform = FloorTransform.build(parent);
      _transforms[parent.id] = transform;

      final fw = parent.floorWidth ?? 1436;
      final fh = parent.floorHeight ?? 751;
      final bscale = math.min(parent.width / fw, parent.height / fh);

      final footprintPoints = <List<double>>[];
      for (final (lx, ly) in [
        (0.0, 0.0),
        (parent.width, 0.0),
        (parent.width, parent.height),
        (0.0, parent.height),
      ]) {
        footprintPoints.add(parent.localToWorld(lx, ly));
      }
      final footprint = PolygonBarrier(footprintPoints);

      final campusItems = scene.floors[campus] ?? [];
      final campusZones = campusItems
          .where((i) => i.kind == 'entry_zone' && i.parentId == parent.id)
          .toList();
      final floor1Items = scene.floorItems(parent.id, 1);
      final floor1Zones = floor1Items
          .where((i) => i.kind == 'entry_zone')
          .toList();

      final entryAreaList = <PolygonBarrier>[footprint];
      final roofAreaList = <PolygonBarrier>[];

      for (final zone in campusZones) {
        final points = <List<double>>[];
        for (final (lx, ly) in [
          (0.0, 0.0),
          (zone.width, 0.0),
          (zone.width, zone.height),
          (0.0, zone.height),
        ]) {
          points.add(zone.localToWorld(lx, ly));
        }
        final area = PolygonBarrier(points);
        entryAreaList.add(area);
        roofAreaList.add(area);
      }

      for (final zone in floor1Zones) {
        final points = <List<double>>[];
        for (final (lx, ly) in [
          (0.0, 0.0),
          (zone.width, 0.0),
          (zone.width, zone.height),
          (0.0, zone.height),
        ]) {
          final w = zone.localToWorld(lx, ly);
          points.add(transform.project(w[0], w[1]));
        }
        final area = PolygonBarrier(points);
        entryAreaList.add(area);
        roofAreaList.add(area);
      }

      _entryAreas[parent.id] = entryAreaList;
      _roofAreas[parent.id] = roofAreaList.isNotEmpty
          ? roofAreaList
          : [footprint];

      double minX = double.infinity,
          minY = double.infinity,
          maxX = double.negativeInfinity,
          maxY = double.negativeInfinity;
      for (final area in entryAreaList) {
        final b = area.box;
        if (b.$1 < minX) minX = b.$1;
        if (b.$2 < minY) minY = b.$2;
        if (b.$3 > maxX) maxX = b.$3;
        if (b.$4 > maxY) maxY = b.$4;
      }
      parentBoxes.add((minX, minY, maxX, maxY));
      roofBoxes.add((
        minX - parent.approachDistance,
        minY - parent.approachDistance,
        maxX + parent.approachDistance,
        maxY + parent.approachDistance,
      ));

      for (var floor = 1; floor <= parent.floorCount; floor++) {
        final key = '${parent.id}:$floor';
        final items = scene.floorItems(parent.id, floor);
        final stairItems = items
            .where((i) => stairKinds.contains(i.kind))
            .toList();
        final stairSections = <StairSection>[];
        for (final stair in stairItems) {
          stairSections.addAll(transitions(stair, floor, parent.floorCount));
        }
        _stairObjects[key] = stairItems;
        _stairIndices[key] = _buildStairIndex(stairSections, parent);

        final conns = <StairSection>[];
        for (final stair in stairItems) {
          conns.addAll(transitions(stair, floor, parent.floorCount));
        }
        _connections[key] = conns;
        for (final s in conns) {
          _sectionsById[s.id] = s;
        }
        _sectionIndices[key] = _buildSectionIndex(conns, parent);

        final rawBarriers = barriersFor(items);
        final barriers = rawBarriers.map((b) {
          final s = transform.project(b.startX, b.startY);
          final e = transform.project(b.endX, b.endY);
          return Barrier(
            startX: s[0],
            startY: s[1],
            endX: e[0],
            endY: e[1],
            radius: b.radius * bscale,
            flat: b.flat,
          );
        }).toList();
        final box = barrierBounds(barriers);
        _colliders[key] = (barriers, box ?? (0, 0, 0, 0));
        _collisionIndices[key] = _buildCollisionIndex(barriers);

        if (floor == 1) groundBarriers.addAll(barriers);
      }
    }

    groundIndex = RuntimeIndex(
      groundBarriers,
      groundBarriers.map((b) => b.bounds).toList(),
    );
    parentIndex = RuntimeIndex(parents, parentBoxes);
    roofIndex = RuntimeIndex(parents, roofBoxes);
  }

  FloorTransform floorTransform(MapItem building) {
    return _transforms[building.id] ?? FloorTransform.build(building);
  }

  /// Stage 1 auto-pathing: route on the player's current surface only.
  ///
  /// Stairs/multi-floor routing are deliberately deferred to the next stage.
  /// During an active stair transition this returns no route.
  List<Barrier> _floorOneHazardBarriers({
    double safetyMargin = hazardSafetyClearance,
  }) {
    return <Barrier>[
      for (final hazard in hazards)
        if (hazard.floor == 1)
          ...hazard.routingBarriers(safetyMargin: hazardSafetyClearance),
    ];
  }

  bool _routePassesHazardGuard(
    List<List<double>> path,
    List<HazardZone> routeHazards,
    double safetyMargin,
  ) {
    if (path.length < 2) return false;
    if (routeHazards.isEmpty) return true;

    final hazardOnly = SameFloorPathfinder(
      barriers: <Barrier>[
        for (final hazard in routeHazards)
          ...hazard.routingBarriers(safetyMargin: safetyMargin),
      ],
      playerRadius: collisionRadius,
      width: scene.width,
      height: scene.height,
    );

    for (var i = 1; i < path.length; i++) {
      if (!hazardOnly.lineIsWalkable(path[i - 1], path[i])) {
        return false;
      }
    }
    return true;
  }

  List<List<double>> _findCampusRoadRouteWithHazards(
    List<double> start,
    List<double> goal,
  ) {
    final campusBaseBarriers = _campusRoutingBaseBarriers();
    final floorHazards = hazards
        .where((hazard) => hazard.floor == 1)
        .toList(growable: false);

    if (floorHazards.isEmpty) {
      return SameFloorPathfinder(
        barriers: campusBaseBarriers,
        playerRadius: collisionRadius,
        width: scene.width,
        height: scene.height,
        preferredAreas: campusPreferredAreas,
      ).findPath(start, goal);
    }

    final hardBarriers = <Barrier>[
      ...campusBaseBarriers,
      ..._floorOneHazardBarriers(safetyMargin: hazardSafetyClearance),
    ];

    final riskZones = <RouteRiskZone>[
      for (final hazard in floorHazards)
        if (hazard.kind != HazardKind.earthquake)
          RouteRiskZone(
            x: hazard.x,
            y: hazard.y,
            radius: hazard.radius + hazardSafetyClearance,
          ),
    ];

    final route = SameFloorPathfinder(
      barriers: hardBarriers,
      playerRadius: collisionRadius,
      width: scene.width,
      height: scene.height,
      preferredAreas: campusPreferredAreas,
      riskZones: riskZones,
      riskWeight: 14.0,
      riskInfluenceDistance: 320.0,
    ).findPath(start, goal);

    if (route.length < 2) return const <List<double>>[];

    if (!_routePassesHazardGuard(route, floorHazards, hazardSafetyClearance)) {
      return const <List<double>>[];
    }

    return route;
  }

  List<List<double>> findSameFloorRoute(double targetX, double targetY) {
    if (transition != null) return const <List<double>>[];

    // Campus uses the normal centered road route with only LOCAL fire detours.
    if (parent == null) {
      return _findCampusRoadRouteWithHazards(
        <double>[markerX, markerY],
        <double>[targetX, targetY],
      );
    }

    final List<Barrier> barriers;
    if (currentFloor == 1) {
      barriers = groundBarriers;
    } else {
      final key = '${parent!.id}:$currentFloor';
      barriers = _colliders[key]?.$1 ?? const <Barrier>[];
    }

    // Indoor routing has no road-centerline network. Keep the normal A* route,
    // but include fire on the active floor so stairs/rooms can be avoided.
    final pathfinder = SameFloorPathfinder(
      barriers: _currentSurfaceRoutingBarriers(barriers),
      playerRadius: collisionRadius,
      width: scene.width,
      height: scene.height,
    );
    return pathfinder.findPath(
      <double>[markerX, markerY],
      <double>[targetX, targetY],
    );
  }

  /// Stage 3: choose a reachable staircase on the current floor that moves the
  /// player toward [targetFloor], then return a collision-safe A* walking leg
  /// to that staircase.
  ///
  /// The route is intentionally computed one floor at a time. After the player
  /// completes the physical stair transition, call this again on the new floor.
  StairWaypointGuide? _routeWaypointGuideForSection(
    MapItem building,
    StairSection section,
    int fromFloor,
    int toFloor,
  ) {
    final sections =
        (_connections['${building.id}:$fromFloor'] ?? const <StairSection>[])
            .where((candidate) => candidate.target == toFloor)
            .toList();

    if (sections.isEmpty) return null;

    StairWaypointGuide? bestGuide;
    var bestDistance = double.infinity;

    for (final guide in stairWaypointGuides) {
      if (guide.buildingId != building.id ||
          !guide.connects(fromFloor, toFloor)) {
        continue;
      }

      final guidePoints = _routeWaypointWorldPoints(
        building,
        guide,
        fromFloor,
        toFloor,
      );
      if (guidePoints.isEmpty) continue;

      final guideStart = guidePoints.first;

      // Bind each authored guide to the PHYSICAL staircase whose source-side
      // stair entry is nearest to the guide's first point. This allows two or
      // more waypoint guides between the same floor pair without all stair
      // candidates incorrectly reusing the first guide.
      StairSection? nearestSection;
      var nearestDistance = double.infinity;

      for (final candidate in sections) {
        final laneRoutes = _stairLaneRoutes(building, candidate);
        if (laneRoutes.isEmpty || laneRoutes.first.isEmpty) continue;

        final stairEntry = laneRoutes.first.first;
        final distance = hypot(
          guideStart[0] - stairEntry[0],
          guideStart[1] - stairEntry[1],
        );

        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestSection = candidate;
        }
      }

      if (nearestSection?.id != section.id) continue;

      if (nearestDistance < bestDistance) {
        bestDistance = nearestDistance;
        bestGuide = guide;
      }
    }

    return bestGuide;
  }

  List<List<double>> _routeWaypointWorldPoints(
    MapItem building,
    StairWaypointGuide guide,
    int fromFloor,
    int toFloor,
  ) {
    final transform =
        _transforms[building.id] ?? FloorTransform.build(building);
    return [
      for (final p in guide.orderedPoints(fromFloor, toFloor))
        transform.project(p[0], p[1]),
    ];
  }

  String? authoredWaypointGuideKeyForSection(StairSection section) {
    final building = parent;
    if (building == null) return null;

    final guide = _routeWaypointGuideForSection(
      building,
      section,
      currentFloor,
      section.target,
    );

    if (guide != null) {
      return '${guide.id}:${section.id}:$currentFloor:${section.target}';
    }

    // Not every building has a hand-authored waypoint guide. In that case,
    // use the staircase's real generated lane as a waypoint guide instead.
    // This makes waypoint following work in every building while preserving
    // custom authored guides where they exist.
    final laneRoutes = _stairLaneRoutes(building, section);
    if (laneRoutes.isEmpty || laneRoutes.first.length < 2) return null;

    return 'auto:${building.id}:${section.id}:$currentFloor:${section.target}';
  }

  List<List<double>> authoredWaypointGuideForSection(StairSection section) {
    final building = parent;
    if (building == null) return const <List<double>>[];

    final guide = _routeWaypointGuideForSection(
      building,
      section,
      currentFloor,
      section.target,
    );

    if (guide != null) {
      return _routeWaypointWorldPoints(
        building,
        guide,
        currentFloor,
        section.target,
      );
    }

    // Generic fallback for buildings without a custom waypoint definition.
    // _stairLaneRoutes() is built from the actual staircase geometry for the
    // current building, so it remains aligned even when building size,
    // rotation, mirroring, or floor transform differs.
    final laneRoutes = _stairLaneRoutes(building, section);
    if (laneRoutes.isEmpty || laneRoutes.first.length < 2) {
      return const <List<double>>[];
    }

    return <List<double>>[
      for (final point in laneRoutes.first) <double>[point[0], point[1]],
    ];
  }

  List<List<double>> _remainingAuthoredWaypointGuide(
    MapItem building,
    StairSection section,
  ) {
    final guide = _routeWaypointGuideForSection(
      building,
      section,
      section.source,
      section.target,
    );
    if (guide == null) return const <List<double>>[];

    final points = _routeWaypointWorldPoints(
      building,
      guide,
      section.source,
      section.target,
    );
    if (points.length < 2) return const <List<double>>[];

    var nearest = 0;
    var best = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final distance = hypot(markerX - points[i][0], markerY - points[i][1]);
      if (distance < best) {
        best = distance;
        nearest = i;
      }
    }

    final start = nearest < points.length - 1 ? nearest + 1 : nearest;

    return <List<double>>[
      <double>[markerX, markerY],
      for (var i = start; i < points.length; i++)
        <double>[points[i][0], points[i][1]],
    ];
  }

  StairRouteLeg? findRouteTowardFloor(int targetFloor) {
    final building = parent;
    if (building == null || transition != null) return null;
    if (targetFloor < 1 || targetFloor > building.floorCount) return null;
    if (targetFloor == currentFloor) return null;

    final key = '${building.id}:$currentFloor';
    final candidates = _connections[key] ?? const <StairSection>[];
    if (candidates.isEmpty) return null;

    final goingDown = targetFloor < currentFloor;
    final eligible = candidates.where((section) {
      if (goingDown && section.target >= currentFloor) return false;
      if (!goingDown && section.target <= currentFloor) return false;
      return _floorCanReach(building.id, section.target, targetFloor);
    }).toList();
    if (eligible.isEmpty) return null;

    final List<Barrier> barriers;
    if (currentFloor == 1) {
      barriers = groundBarriers;
    } else {
      barriers = _colliders[key]?.$1 ?? const <Barrier>[];
    }

    final pathfinder = SameFloorPathfinder(
      barriers: _currentSurfaceRoutingBarriers(barriers),
      playerRadius: collisionRadius,
      width: scene.width,
      height: scene.height,
    );

    StairRouteLeg? best;
    double bestCost = double.infinity;

    for (final section in eligible) {
      final authoredGuide = _routeWaypointGuideForSection(
        building,
        section,
        currentFloor,
        section.target,
      );

      if (authoredGuide != null) {
        final guidePath = _routeWaypointWorldPoints(
          building,
          authoredGuide,
          currentFloor,
          section.target,
        );

        if (guidePath.length >= 2 &&
            _pathClearOfSurfaceHazards(guidePath, building.id, currentFloor)) {
          final approach = pathfinder.findPath(<double>[
            markerX,
            markerY,
          ], guidePath.first);

          if (approach.isNotEmpty) {
            final path = <List<double>>[
              ...approach,
              for (var i = 1; i < guidePath.length; i++) guidePath[i],
            ];

            final remainingHops = _floorHopDistance(
              building.id,
              section.target,
              targetFloor,
            );

            if (remainingHops != null) {
              final cost = _routeLength(path) + remainingHops * 150.0;
              if (cost < bestCost) {
                bestCost = cost;
                best = StairRouteLeg(section: section, path: path);
              }
            }
          }
        }

        // IMPORTANT: the authored guide changes route geometry only.
        // Stair activation/floor-transition logic remains unchanged.
        continue;
      }

      for (final stairLane in _stairLaneRoutes(building, section)) {
        if (stairLane.length < 2) continue;

        // The approach A* already avoids fire, but the staircase lane used to
        // be appended afterward without any hazard check. Reject this entire
        // stair option when fire overlaps the stair lane so another staircase
        // can be chosen.
        if (!_pathClearOfSurfaceHazards(stairLane, building.id, currentFloor)) {
          continue;
        }

        // A* only needs to reach the source-side entrance of the staircase.
        // From there, append the staircase lane itself. This prevents the blue
        // route from taking a diagonal shortcut through the stair graphic.
        final approach = pathfinder.findPath([
          markerX,
          markerY,
        ], stairLane.first);
        if (approach.isEmpty) continue;

        final path = <List<double>>[
          ...approach,
          for (var i = 1; i < stairLane.length; i++) stairLane[i],
        ];

        final walkingCost = _routeLength(path);
        final remainingHops = _floorHopDistance(
          building.id,
          section.target,
          targetFloor,
        );
        if (remainingHops == null) continue;

        final cost = walkingCost + remainingHops * 150.0;
        if (cost < bestCost) {
          bestCost = cost;
          best = StairRouteLeg(section: section, path: path);
        }
      }
    }

    return best;
  }

  bool _floorCanReach(String buildingId, int from, int target) {
    return _floorHopDistance(buildingId, from, target) != null;
  }

  int? _floorHopDistance(String buildingId, int from, int target) {
    if (from == target) return 0;
    final queue = <(int, int)>[(from, 0)];
    final visited = <int>{from};

    var cursor = 0;
    while (cursor < queue.length) {
      final (floor, hops) = queue[cursor++];
      final next = _connections['$buildingId:$floor'] ?? const <StairSection>[];
      for (final section in next) {
        if (!visited.add(section.target)) continue;
        if (section.target == target) return hops + 1;
        queue.add((section.target, hops + 1));
      }
    }
    return null;
  }

  double _stairCompletionRaw() {
    return math.min(0.995, 1.0 - transitionThreshold + 0.015);
  }

  List<double> _stairWorldPoint(
    MapItem building,
    StairSection section,
    double raw,
    double laneFactor,
  ) {
    final transform =
        _transforms[building.id] ?? FloorTransform.build(building);

    var longitudinal = section.direction == 'up' ? 1.0 - raw : raw;
    final localY = section.height * longitudinal;
    final local = section.stair.localToWorld(
      section.width * laneFactor,
      localY,
    );
    return transform.project(local[0], local[1]);
  }

  double _stairLaneFactor(StairSection section) {
    // The rendered stair has a center railing. Alternate only the LEFT/RIGHT
    // half on adjacent source floors. Do NOT reverse longitudinal progress here:
    // section.direction already defines the correct UP/DOWN travel direction.
    return section.source.isEven ? 0.72 : 0.28;
  }

  List<List<List<double>>> _stairLaneRoutes(
    MapItem building,
    StairSection section,
  ) {
    final lane = _stairLaneFactor(section);
    final completion = _stairCompletionRaw();

    // One deterministic flight per floor. Adjacent floors alternate both
    // longitudinal direction and left/right half of the same stairwell.
    final rawLevels = <double>[0.035, 0.25, 0.50, 0.75, completion];

    return [
      [
        for (final raw in rawLevels)
          _stairWorldPoint(building, section, raw, lane),
      ],
    ];
  }

  /// Find the next stair section that is in the same physical well as
  /// [completed] and continues in the same vertical direction.
  StairSection? _findNextSameWellStair(StairSection completed) {
    final building = parent;
    if (building == null) return null;

    final goingDown = completed.target < completed.source;
    final candidates =
        _connections['${building.id}:$currentFloor'] ?? const <StairSection>[];

    final completedCenter = completed.stair.localToWorld(
      completed.width / 2,
      completed.height / 2,
    );

    StairSection? best;
    var bestDistance = double.infinity;

    for (final candidate in candidates) {
      if (candidate.source != currentFloor) continue;

      // Skip the section we just completed — we need the NEXT one.
      if (candidate.stair.id == completed.stair.id &&
          candidate.source == completed.source &&
          candidate.target == completed.target) {
        continue;
      }

      final sameDirection = goingDown
          ? candidate.target < candidate.source
          : candidate.target > candidate.source;
      if (!sameDirection) continue;

      final center = candidate.stair.localToWorld(
        candidate.width / 2,
        candidate.height / 2,
      );
      final distance = hypot(
        center[0] - completedCenter[0],
        center[1] - completedCenter[1],
      );

      final sameWellTolerance = math.max(
        40.0,
        math.max(
              math.max(completed.width, completed.height),
              math.max(candidate.width, candidate.height),
            ) *
            0.65,
      );

      if (distance > sameWellTolerance || distance >= bestDistance) continue;

      final lanePath = _stairLaneRoutes(building, candidate).first;
      if (!_pathClearOfSurfaceHazards(lanePath, building.id, currentFloor)) {
        continue;
      }

      bestDistance = distance;
      best = candidate;
    }

    return best;
  }

  /// Returns true when the next stair after [completed] is in the same physical
  /// well and continues in the same direction, meaning the player can proceed
  /// directly to the next flight without a turnaround.
  bool hasSameWellNextStair(StairSection completed) {
    return _findNextSameWellStair(completed) != null;
  }

  /// Clear stair exit/lock state so that the next stair in the same well can be
  /// immediately armed and routed to. Only call this when same-well continuation
  /// is confirmed.
  void clearStairLockForSameWell() {
    exitAreas = [];
    waitFloor = null;
    phase = TransitionPhase.onFloor;

    // Reset previousPoint so _detectStairEntry can detect a fresh
    // source-boundary crossing for the next stair. Without this, prevRaw
    // stays at ≈0 (source end of the next stair) and the crossing check
    // `raw > prevRaw + 1e-9` never triggers when the player hasn't moved.
    previousPoint = null;

    // _lockOverlapping may have locked the NEXT stair's id (spatial index
    // order is not guaranteed). Unlock everything except the stair we just
    // completed so the next same-well stair can be armed immediately.
    final completedId = lastCompletedStair?.stair.id;
    lockedSections.removeWhere((id) => id != completedId);
  }

  /// Route geometry to show while the player is physically walking an active
  /// staircase. It starts at the player's live position and stays on the SAME
  /// physical stair lane the player is already using.
  ///
  /// Do not force a direction-based left/right lane here: on switchback stairs
  /// that can draw a blue segment straight through the center railing/wall.
  List<List<double>> activeStairRouteGuide() {
    final t = transition;
    final building = parent;
    if (t == null || building == null) return const <List<double>>[];

    final authoredActive = _remainingAuthoredWaypointGuide(building, t.section);
    if (authoredActive.length >= 2) return authoredActive;

    final transform =
        _transforms[building.id] ?? FloorTransform.build(building);
    final floorLocal = transform.unproject(markerX, markerY);
    final progress = sectionProgress(
      t.section,
      floorLocal[0],
      floorLocal[1],
    ).$3.clamp(0.0, 1.0).toDouble();

    // Convert the player's live floor position into THIS stair's own local
    // coordinates. The normalized X tells us which side/lane the player is
    // physically on. Keep future guide points on that lane so the route never
    // jumps laterally through a center railing.
    final stairLocal = t.section.stair.worldToLocal(
      floorLocal[0],
      floorLocal[1],
    );
    final lane = t.section.width <= 1e-9
        ? 0.5
        : (stairLocal[0] / t.section.width).clamp(0.12, 0.88).toDouble();

    final completion = _stairCompletionRaw();
    final endRaw = math.max(progress, completion);

    final guide = <List<double>>[
      [markerX, markerY],
    ];

    for (final fraction in [0.25, 0.50, 0.75, 1.0]) {
      final raw = progress + (endRaw - progress) * fraction;
      guide.add(_stairWorldPoint(building, t.section, raw, lane));
    }
    return guide;
  }

  /// Route the player around the OUTSIDE of a completed switchback stair before
  /// starting the next floor leg. This prevents immediately re-entering the
  /// same stair from its target side and accidentally going back up a floor.
  List<List<double>> completedStairTurnaroundGuide() {
    final completed = lastCompletedStair;
    final building = parent;
    if (completed == null || building == null) {
      return const <List<double>>[];
    }

    final transform =
        _transforms[building.id] ?? FloorTransform.build(building);

    final floorLocal = transform.unproject(markerX, markerY);
    final stairLocal = completed.stair.worldToLocal(
      floorLocal[0],
      floorLocal[1],
    );

    final currentLane = completed.width <= 1e-9
        ? _stairLaneFactor(completed)
        : (stairLocal[0] / completed.width).clamp(0.12, 0.88).toDouble();

    final nextSameWell = _findNextSameWellStair(completed);

    final nextLane = nextSameWell == null
        ? currentLane
        : _stairLaneFactor(nextSameWell);

    final clearance = math.max(14.0, collisionRadius + 8.0);
    final outsideRaw =
        1.0 + math.max(0.10, clearance / math.max(1.0, completed.height));

    final current = <double>[markerX, markerY];

    // First continue OUT of the completed flight at the same lane.
    final outsideCurrentLane = _stairWorldPoint(
      building,
      completed,
      outsideRaw,
      currentLane,
    );

    // Then cross the landing OUTSIDE the center railing to the half used by the
    // next floor. This is the small green-style U/crossover the user expects.
    final outsideNextLane = _stairWorldPoint(
      building,
      completed,
      outsideRaw,
      nextLane,
    );

    final guide = <List<double>>[current, outsideCurrentLane];

    if (hypot(
          outsideNextLane[0] - outsideCurrentLane[0],
          outsideNextLane[1] - outsideCurrentLane[1],
        ) >
        1.0) {
      guide.add(outsideNextLane);
    }

    return guide;
  }

  bool completedStairTurnaroundReached() {
    // _rearmAfterExit() clears exitAreas only after the player has physically
    // left the completed stair footprint. At that point the next alternating
    // flight may safely arm.
    return exitAreas.isEmpty;
  }

  double _routeLength(List<List<double>> path) {
    double total = 0;
    for (var i = 1; i < path.length; i++) {
      total += hypot(path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]);
    }
    return total;
  }

  /// Minimum modeled clearance from any Floor-1 hazard along a route.
  ///
  /// The value is measured from the VISIBLE hazard edge. A route that is
  /// farther from danger gets a larger value.
  double _routeMinimumHazardClearance(
    List<List<double>> path,
    List<HazardZone> routeHazards,
  ) {
    if (path.length < 2 || routeHazards.isEmpty) {
      return double.infinity;
    }

    var minimum = double.infinity;

    for (var i = 1; i < path.length; i++) {
      final a = path[i - 1];
      final b = path[i];
      final dx = b[0] - a[0];
      final dy = b[1] - a[1];
      final length = math.sqrt(dx * dx + dy * dy);
      final samples = math.max(1, (length / 12).ceil());

      for (var s = 0; s <= samples; s++) {
        final t = s / samples;
        final px = a[0] + dx * t;
        final py = a[1] + dy * t;

        for (final hazard in routeHazards) {
          minimum = math.min(minimum, hazard.edgeDistanceTo(px, py));
        }
      }
    }

    return minimum;
  }

  /// Integrated modeled hazard exposure along the route.
  ///
  /// This is a tie-break after minimum clearance. Lower is better.
  double _routeHazardExposure(
    List<List<double>> path,
    List<HazardZone> routeHazards,
  ) {
    if (path.length < 2 || routeHazards.isEmpty) return 0.0;

    var exposure = 0.0;

    for (var i = 1; i < path.length; i++) {
      final a = path[i - 1];
      final b = path[i];
      final dx = b[0] - a[0];
      final dy = b[1] - a[1];
      final length = math.sqrt(dx * dx + dy * dy);
      if (length <= 1e-9) continue;

      final samples = math.max(1, (length / 12).ceil());
      final sampleLength = length / samples;

      for (var s = 0; s <= samples; s++) {
        final t = s / samples;
        final px = a[0] + dx * t;
        final py = a[1] + dy * t;

        var localRisk = 0.0;
        for (final hazard in routeHazards) {
          localRisk = math.max(localRisk, hazard.proximityRisk(px, py));
        }
        exposure += localRisk * sampleLength;
      }
    }

    return exposure;
  }

  int _compareEvacuationOptionsBySafety(
    EvacuationGateOption a,
    EvacuationGateOption b,
    List<HazardZone> routeHazards,
  ) {
    if (routeHazards.isEmpty ||
        a.previewRoute.length < 2 ||
        b.previewRoute.length < 2) {
      final delta = a.score - b.score;
      if (delta.abs() > 1e-6) return delta < 0 ? -1 : 1;
      if (a.kind == b.kind) return 0;
      return a.kind == 'main_gate' ? -1 : 1;
    }

    const preferredSafetyClearance = 220.0;

    final aClearance = _routeMinimumHazardClearance(
      a.previewRoute,
      routeHazards,
    );
    final bClearance = _routeMinimumHazardClearance(
      b.previewRoute,
      routeHazards,
    );

    final aEffective = math.min(aClearance, preferredSafetyClearance);
    final bEffective = math.min(bClearance, preferredSafetyClearance);

    final clearanceDelta = aEffective - bEffective;

    // MAIN ROUTE is selected by modeled hazard clearance FIRST.
    if (clearanceDelta.abs() > 12.0) {
      return clearanceDelta > 0 ? -1 : 1;
    }

    final aExposure = _routeHazardExposure(a.previewRoute, routeHazards);
    final bExposure = _routeHazardExposure(b.previewRoute, routeHazards);

    final exposureDelta = aExposure - bExposure;
    if (exposureDelta.abs() > 1e-6) {
      return exposureDelta < 0 ? -1 : 1;
    }

    final lengthDelta = a.score - b.score;
    if (lengthDelta.abs() > 1e-6) {
      return lengthDelta < 0 ? -1 : 1;
    }

    if (a.kind == b.kind) return 0;
    return a.kind == 'main_gate' ? -1 : 1;
  }

  /// Stage 6B: rank official campus exits from best to fallback.
  ///
  /// On Campus/Floor 1 this uses the real road-aware collision-safe route.
  /// On upper floors the indoor descent cost is mostly shared by every gate,
  /// so a road-aware campus egress estimate is used until Floor 1 is reached.
  bool isCampusGateBlocked(String kind) {
    final target = campusGateApproach(kind);
    if (target == null) return true;

    for (final hazard in hazards) {
      if (hazard.floor != 1) continue;

      final dx = target[0] - hazard.x;
      final dy = target[1] - hazard.y;
      final distance = math.sqrt(dx * dx + dy * dy);

      // If the gate approach lies inside the modeled hazard + mandatory
      // clearance, that exit is unavailable and must not be selected.
      if (distance <= hazard.radius + hazardSafetyClearance + collisionRadius) {
        return true;
      }
    }

    return false;
  }

  bool get allEvacuationGatesBlocked {
    const kinds = <String>['main_gate', 'secondary_gate'];

    var configured = 0;
    var blocked = 0;

    for (final kind in kinds) {
      if (campusGateApproach(kind) == null) continue;
      configured++;
      if (isCampusGateBlocked(kind)) blocked++;
    }

    return configured > 0 && blocked == configured;
  }

  List<EvacuationGateOption> rankEvacuationGates() {
    if (transition != null) return const <EvacuationGateOption>[];

    final options = <EvacuationGateOption>[];
    for (final kind in const ['main_gate', 'secondary_gate']) {
      final target = campusGateApproach(kind);
      if (isCampusGateBlocked(kind)) continue;
      if (target == null) continue;

      if (parent == null || currentFloor == 1) {
        final route = findCampusGateRoute(kind);
        if (route.isEmpty) continue;
        options.add(
          EvacuationGateOption(
            kind: kind,
            score: _routeLength(route),
            previewRoute: route,
          ),
        );
        continue;
      }

      final estimate = _estimateUpperFloorGateCost(kind);
      if (estimate == null) continue;
      options.add(EvacuationGateOption(kind: kind, score: estimate));
    }

    final floorOneHazards = hazards
        .where((hazard) => hazard.floor == 1)
        .toList(growable: false);

    options.sort(
      (a, b) => _compareEvacuationOptionsBySafety(a, b, floorOneHazards),
    );
    return options;
  }

  String? recommendedEvacuationGateKind({bool alternative = false}) {
    final ranked = rankEvacuationGates();
    final index = alternative ? 1 : 0;
    if (ranked.length <= index) return null;
    return ranked[index].kind;
  }

  double? _estimateUpperFloorGateCost(String kind) {
    final building = parent;
    final target = campusGateApproach(kind);
    if (building == null || target == null || currentFloor <= 1) return null;

    // IMPORTANT: do not run campus A* here.
    //
    // This method is called for BOTH official gates when Main/Alternative is
    // pressed on an upper floor. The old implementation sampled many exterior
    // anchors and ran road A* for every sample, blocking Flutter's UI thread for
    // several seconds.
    //
    // On upper floors, stair descent is shared by both gate choices. A cheap
    // world-space estimate is enough to rank the gates. Once Floor 1 is reached,
    // the real collision-safe, road-aware route remains authoritative.
    final directCampusEstimate = hypot(
      target[0] - markerX,
      target[1] - markerY,
    );

    final floorPenalty = math.max(0, currentFloor - 1) * 150.0;

    // Small building egress allowance keeps this comparable with the previous
    // score without performing any path search.
    final egressAllowance = math.min(building.width, building.height) * 0.25;

    return directCampusEstimate + floorPenalty + egressAllowance;
  }

  /// Stage 5: find a configured campus evacuation gate.
  MapItem? campusGate(String kind) {
    if (kind != 'main_gate' && kind != 'secondary_gate') return null;
    for (final item in scene.floors[campus] ?? const <MapItem>[]) {
      if (item.kind == kind) return item;
    }
    return null;
  }

  /// Returns a walkable point immediately INSIDE the campus side of a gate.
  List<double>? campusGateApproach(String kind) {
    final gate = campusGate(kind);
    if (gate == null) return null;

    final clearance = math.max(
      18.0,
      collisionRadius + math.max(8.0, gate.stroke / 2 + 6.0),
    );

    final a = gate.localToWorld(gate.width / 2, -clearance);
    final b = gate.localToWorld(gate.width / 2, gate.height + clearance);

    final cx = scene.width / 2;
    final cy = scene.height / 2;

    bool inBounds(List<double> p) =>
        p[0] >= collisionRadius &&
        p[0] <= scene.width - collisionRadius &&
        p[1] >= collisionRadius &&
        p[1] <= scene.height - collisionRadius;

    double centerDistance(List<double> p) => hypot(p[0] - cx, p[1] - cy);

    final aValid = inBounds(a);
    final bValid = inBounds(b);
    if (aValid && !bValid) return a;
    if (bValid && !aValid) return b;
    return centerDistance(a) <= centerDistance(b) ? a : b;
  }

  /// Route the current Campus/Floor-1 position to a campus evacuation gate.
  List<List<double>> findCampusGateRoute(String kind) {
    if (isCampusGateBlocked(kind)) return const <List<double>>[];

    final target = campusGateApproach(kind);
    if (target == null || transition != null) {
      return const <List<double>>[];
    }
    if (parent == null) {
      return findSameFloorRoute(target[0], target[1]);
    }
    if (currentFloor == 1) {
      return findFloor1CampusRoute(target[0], target[1]);
    }
    return const <List<double>>[];
  }

  /// Stage 4: route from Floor 1 through a real collision opening and out onto
  /// the campus. The same ground collision geometry is used on both sides of
  /// the building boundary, so walls remain blocked and doors/openings remain
  /// walkable.
  List<List<double>> findFloor1CampusRoute(double targetX, double targetY) {
    final building = parent;
    if (building == null || currentFloor != 1 || transition != null) {
      return const <List<double>>[];
    }
    if (inside(building, targetX, targetY)) {
      return const <List<double>>[];
    }

    return _findCampusRoadRouteWithHazards(
      <double>[markerX, markerY],
      <double>[targetX, targetY],
    );
  }

  RuntimeIndex<StairSection> _buildStairIndex(
    List<StairSection> stairs,
    MapItem building,
  ) {
    final boxes = stairs.map((s) {
      final area = _buildArea(s.stair, s.source, building);
      return area.box;
    }).toList();
    return RuntimeIndex(stairs, boxes);
  }

  RuntimeIndex<StairSection> _buildSectionIndex(
    List<StairSection> zones,
    MapItem building,
  ) {
    final boxes = zones.map((z) {
      final area = _buildArea(z.stair, z.source, building);
      return area.box;
    }).toList();
    return RuntimeIndex(zones, boxes);
  }

  RuntimeIndex<Barrier> _buildCollisionIndex(List<Barrier> barriers) {
    final boxes = barriers.map((b) => b.bounds).toList();
    return RuntimeIndex(barriers, boxes);
  }

  PolygonBarrier _buildArea(MapItem item, int floor, [MapItem? building]) {
    final bldg = building ?? parent;
    if (bldg == null) return PolygonBarrier([]);
    final transform = _transforms[bldg.id] ?? FloorTransform.build(bldg);
    final points = <List<double>>[];
    for (final (lx, ly) in [
      (0.0, 0.0),
      (item.width, 0.0),
      (item.width, item.height),
      (0.0, item.height),
    ]) {
      final w = item.localToWorld(lx, ly);
      final projected = transform.project(w[0], w[1]);
      points.add(projected);
    }
    return PolygonBarrier(points);
  }

  bool inside(MapItem parent, double px, double py) {
    final areas = _entryAreas[parent.id];
    if (areas == null) return false;
    return areas.any((area) => area.blocks(px, py, 1e-6));
  }

  double distanceToParent(MapItem parent, double px, double py) {
    if (inside(parent, px, py)) return 0;
    final areas = _roofAreas[parent.id];
    if (areas == null) return double.infinity;
    double best = double.infinity;
    for (final area in areas) {
      best = math.min(best, _polygonDistance(area, px, py));
    }
    return best;
  }

  double _polygonDistance(PolygonBarrier area, double px, double py) {
    if (area.blocks(px, py, 0)) return 0;
    double best = double.infinity;
    var prev = area.points.last;
    for (final current in area.points) {
      final dx = current[0] - prev[0];
      final dy = current[1] - prev[1];
      final length2 = dx * dx + dy * dy;
      final t = length2 > 0
          ? math.max(
              0.0,
              math.min(
                1.0,
                ((px - prev[0]) * dx + (py - prev[1]) * dy) / length2,
              ),
            )
          : 0.0;
      best = math.min(
        best,
        hypot(px - prev[0] - t * dx, py - prev[1] - t * dy),
      );
      prev = current;
    }
    return best;
  }

  double roofOpacity(MapItem parent, double px, double py) {
    if (!parent.fadeWhenObstructing) return 1;
    if (this.parent != null && this.parent!.id == parent.id) return 0;
    final dist = distanceToParent(parent, px, py);
    if (parent.approachDistance <= 0) return dist > 0 ? 0 : 1;
    return math.min(1.0, dist / parent.approachDistance);
  }

  void enterBuilding(MapItem bldg) {
    parent = bldg;
    lastCompletedStair = null;
    transition = null;
    previousPoint = null;
    previousWorldPoint = null;
    phase = TransitionPhase.onFloor;
    exitAreas = [];
    waitFloor = null;
    lockedSections.clear();
    view = 'floor';
    buildingName = bldg.opens ?? bldg.id;
    currentFloor = 1;
  }

  void exitBuilding() {
    parent = null;
    lastCompletedStair = null;
    transition = null;
    previousPoint = null;
    previousWorldPoint = null;
    phase = TransitionPhase.onFloor;
    exitAreas = [];
    waitFloor = null;
    lockedSections.clear();
    view = 'campus';
    buildingName = null;
    currentFloor = 1;
  }

  Map<int, double> floorOpacities(MapItem parentBuilding) {
    final result = <int, double>{};
    for (var n = 1; n <= parentBuilding.floorCount; n++) {
      result[n] = 0;
    }
    if (parent == null || parent!.id != parentBuilding.id) {
      result[1] = 1;
    } else if (transition != null) {
      result[transition!.source] = 1 - transition!.progress;
      result[transition!.target] = transition!.progress;
    } else {
      result[currentFloor] = 1;
    }
    return result;
  }

  Map<int, double> activeFloorOpacities() {
    if (parent == null) return {};
    if (transition != null) {
      return {
        transition!.source: 1 - transition!.progress,
        transition!.target: transition!.progress,
      };
    }
    return {currentFloor: 1.0};
  }

  double walkingSpeed(double px, double py) {
    if (transition != null) {
      final multiplier = transition!.section.stair.stairSpeedMultiplier;
      return playerSpeed * (multiplier ?? stairSpeedMultiplier);
    }
    return playerSpeed;
  }

  List<double> move(double px, double py, double dx, double dy) {
    final step = math.max(0.01, math.min(collisionRadius / 2, physicsStep));
    final count = math.max(1, (hypot(dx, dy) / step).ceil());
    var x = px;
    var y = py;
    final radius = collisionRadius;

    for (var i = 0; i < count; i++) {
      var nx = math.max(radius, math.min(scene.width - radius, x + dx / count));
      var ny = math.max(
        radius,
        math.min(scene.height - radius, y + dy / count),
      );

      if (_allowed(nx, ny)) {
        x = nx;
        y = ny;
      } else {
        if (_allowed(nx, y)) x = nx;
        if (_allowed(x, ny)) y = ny;
      }
    }
    return [x, y];
  }

  List<double> walk(double px, double py, double jx, double jy, double dt) {
    if (dt <= 0 || (jx == 0 && jy == 0)) return [px, py];
    var length = hypot(jx, jy);
    if (length > 1) {
      jx /= length;
      jy /= length;
    }
    var x = px;
    var y = py;
    var remaining = dt;
    final distanceStep = math.max(
      0.01,
      math.min(physicsStep, collisionRadius / 2),
    );

    while (remaining > 1e-9) {
      final speed = walkingSpeed(x, y);
      final elapsed = math.min(remaining, distanceStep / speed);
      final moved = move(x, y, jx * speed * elapsed, jy * speed * elapsed);
      x = moved[0];
      y = moved[1];
      remaining -= elapsed;
    }
    return [x, y];
  }

  bool _allowed(double px, double py) {
    final floors = <int>{currentFloor};
    if (parent != null && transition != null) {
      final local = _transforms[parent!.id]!.unproject(px, py);
      final prog = sectionProgress(transition!.section, local[0], local[1]);
      final lateral = prog.$2;
      final raw = prog.$3;
      if (!lateral) return false;
      if (raw <= 0) {
        floors.clear();
        floors.add(transition!.source);
      } else if (raw >= 1) {
        floors.clear();
        floors.add(transition!.target);
      } else {
        floors.clear();
        floors.add(transition!.source);
        floors.add(transition!.target);
      }
    }

    final radius = collisionRadius;
    if (floors.contains(1)) {
      final nearby = groundIndex.query(px, py, padding: radius);
      if (nearby.any((b) => b.blocks(px, py, radius))) return false;
    }

    for (final floor in floors) {
      if (floor == 1 || parent == null) continue;
      final key = '${parent!.id}:$floor';
      final collider = _colliders[key];
      if (collider == null) continue;
      final barriers = collider.$1;
      final box = collider.$2;
      if (barriers.isEmpty) continue;
      if (px < box.$1 - radius ||
          px > box.$3 + radius ||
          py < box.$2 - radius ||
          py > box.$4 + radius) {
        continue;
      }
      final index = _collisionIndices[key];
      if (index != null) {
        final nearby = index.query(px, py, padding: radius);
        if (nearby.any((b) => b.blocks(px, py, radius))) return false;
      }
    }

    return true;
  }

  bool update(double px, double py) {
    final beforeFloor = currentFloor;
    final beforeName = buildingName;

    if (parent == null) {
      final nearby = parentIndex.query(px, py);
      for (var i = nearby.length - 1; i >= 0; i--) {
        if (inside(nearby[i], px, py)) {
          enterBuilding(nearby[i]);
          break;
        }
      }
    }

    if (parent == null) {
      previousWorldPoint = [px, py];
      return false;
    }

    final local = _transforms[parent!.id]!.unproject(px, py);

    if (_rearmAfterExit(px, py)) {
      previousPoint = local;
      previousWorldPoint = [px, py];
    }

    lockedSections.removeWhere((key) {
      final section = _sectionsById[key];
      return section == null ||
          !section.contains(local[0], local[1], tolerance: 8);
    });

    if (transition != null) {
      final t = transition!;
      final prog = sectionProgress(t.section, local[0], local[1]);
      final lateral = prog.$2;
      final raw = prog.$3;
      if (lateral) t.progress = raw.clamp(0.0, 1.0);
      phase = TransitionPhase.transitioning;

      if (lateral && raw >= 1 - transitionThreshold) {
        currentFloor = t.target;
        transition = null;
        _lockOverlapping(local);
        _waitForStairExit(t);
      } else if (!lateral || raw < -1e-9 || raw > 1 + 1e-9) {
        currentFloor = t.source;
        transition = null;
        _lockOverlapping(local);
        phase = TransitionPhase.onFloor;
      }
    } else {
      final zone = _detectStairEntry(local);
      if (zone != null) {
        final prog = sectionProgress(zone, local[0], local[1]);
        transition = FloorTransition(
          zone,
          currentFloor,
          zone.target,
          prog.$1[0],
        );
        phase = TransitionPhase.enteringStairs;
      }
    }

    previousPoint = local;
    previousWorldPoint = [px, py];

    if (currentFloor == 1 &&
        transition == null &&
        parent != null &&
        !inside(parent!, px, py)) {
      exitBuilding();
    }

    return currentFloor != beforeFloor || buildingName != beforeName;
  }

  StairSection? _detectStairEntry(List<double> local) {
    if (transition != null || exitAreas.isNotEmpty) return null;
    if (parent == null) return null;
    final worldPt = _transforms[parent!.id]!.project(local[0], local[1]);

    final key = '${parent!.id}:$currentFloor';
    final index = _sectionIndices[key];
    if (index == null) return null;

    final nearby = index.query(worldPt[0], worldPt[1], padding: 1e-7);
    for (final zone in nearby) {
      if (!_stairArmed(zone)) continue;
      final prog = sectionProgress(zone, local[0], local[1]);
      final lateral = prog.$2;
      final raw = prog.$3;
      if (raw < -transitionThreshold) continue;
      if (raw < 1 && !lateral) continue;

      final prevRaw = previousPoint != null
          ? sectionProgress(zone, previousPoint![0], previousPoint![1]).$3
          : null;

      if (prevRaw == null && lateral && raw <= transitionThreshold) {
        return zone;
      }
      if (prevRaw != null &&
          prevRaw <= transitionThreshold &&
          raw > prevRaw + 1e-9) {
        return zone;
      }
      if (prevRaw != null &&
          !(-transitionThreshold <= prevRaw &&
              prevRaw <= 1 + transitionThreshold) &&
          0 <= raw &&
          raw <= 1 &&
          lateral) {
        return zone;
      }
    }
    return null;
  }

  bool _stairArmed(StairSection zone) {
    return parent != null &&
        transition == null &&
        zone.source == currentFloor &&
        !lockedSections.contains(zone.id) &&
        exitAreas.isEmpty;
  }

  void _lockOverlapping(List<double> local) {
    final key = '${parent!.id}:$currentFloor';
    final index = _sectionIndices[key];
    if (index == null || parent == null) return;
    final worldPt = _transforms[parent!.id]!.project(local[0], local[1]);
    final nearby = index.query(worldPt[0], worldPt[1]);
    for (final zone in nearby) {
      if (zone.contains(local[0], local[1], tolerance: 3)) {
        lockedSections.add(zone.id);
        break;
      }
    }
  }

  void _waitForStairExit(FloorTransition completed) {
    lastCompletedStair = completed.section;
    final sourceArea = _buildArea(
      completed.section.stair,
      completed.source,
      parent,
    );
    exitAreas = [sourceArea];
    waitFloor = currentFloor;
    phase = TransitionPhase.arrived;
  }

  bool _rearmAfterExit(double px, double py) {
    final radius = collisionRadius + 3;
    if (exitAreas.isEmpty) return false;
    if (waitFloor != currentFloor ||
        !exitAreas.any((area) => area.blocks(px, py, radius))) {
      exitAreas = [];
      waitFloor = null;
      phase = TransitionPhase.onFloor;
      return true;
    }
    phase = TransitionPhase.waitForExit;
    return false;
  }

  bool allowed(List<double> point) => _allowed(point[0], point[1]);
}
