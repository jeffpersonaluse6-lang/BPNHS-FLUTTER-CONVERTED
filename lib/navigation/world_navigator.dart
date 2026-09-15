import 'dart:math' as math;
import '../models/map_item.dart';
import '../models/map_scene.dart';
import '../models/math_helper.dart';
import 'collision.dart';
import 'stairs.dart';
import 'floor_transform.dart';
import 'runtime_index.dart';
import 'same_floor_pathfinder.dart';

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

  void _buildIndex() {
    final parents = scene.buildings();
    final parentBoxes = <(double, double, double, double)>[];
    final roofBoxes = <(double, double, double, double)>[];
    groundBarriers = barriersFor(scene.floors[campus] ?? []);
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
  List<List<double>> findSameFloorRoute(double targetX, double targetY) {
    if (transition != null) return const <List<double>>[];

    final List<Barrier> barriers;
    if (parent == null || currentFloor == 1) {
      // This exactly matches the collision source used by _allowed() on Campus
      // and Floor 1, including campus barriers and every projected Floor 1
      // barrier.
      barriers = groundBarriers;
    } else {
      final key = '${parent!.id}:$currentFloor';
      barriers = _colliders[key]?.$1 ?? const <Barrier>[];
    }

    final pathfinder = SameFloorPathfinder(
      barriers: barriers,
      playerRadius: collisionRadius,
      width: scene.width,
      height: scene.height,
    );
    return pathfinder.findPath([markerX, markerY], [targetX, targetY]);
  }

  /// Stage 3: choose a reachable staircase on the current floor that moves the
  /// player toward [targetFloor], then return a collision-safe A* walking leg
  /// to that staircase.
  ///
  /// The route is intentionally computed one floor at a time. After the player
  /// completes the physical stair transition, call this again on the new floor.
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
      barriers: barriers,
      playerRadius: collisionRadius,
      width: scene.width,
      height: scene.height,
    );

    StairRouteLeg? best;
    double bestCost = double.infinity;

    for (final section in eligible) {
      for (final stairLane in _stairLaneRoutes(building, section)) {
        if (stairLane.length < 2) continue;

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
    final localY = section.direction == 'up'
        ? section.height * (1 - raw)
        : section.height * raw;
    final local = section.stair.localToWorld(
      section.width * laneFactor,
      localY,
    );
    return transform.project(local[0], local[1]);
  }

  List<List<List<double>>> _stairLaneRoutes(
    MapItem building,
    StairSection section,
  ) {
    final preferredLane = section.direction == 'down' ? 0.78 : 0.22;
    final laneFactors = section.direction == 'down'
        ? <double>[preferredLane, 0.72, 0.84]
        : <double>[preferredLane, 0.28, 0.16];
    final completion = _stairCompletionRaw();

    // Start just inside the source side so the existing stair activator can
    // arm normally, then follow the stair longitudinally to the transition
    // completion level. These are progress levels, not fixed map coordinates.
    final rawLevels = <double>[0.035, 0.25, 0.50, 0.75, completion];

    return [
      for (final lane in laneFactors)
        [
          for (final raw in rawLevels)
            _stairWorldPoint(building, section, raw, lane),
        ],
    ];
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
    final section = lastCompletedStair;
    final building = parent;
    if (section == null || building == null) {
      return const <List<double>>[];
    }

    final preferredRight = section.direction == 'down';
    final clearance = math.max(14.0, collisionRadius + 8.0);
    final sourceRaw = -math.max(
      0.10,
      clearance / math.max(1.0, section.height),
    );
    final targetRaw =
        1.0 + math.max(0.10, clearance / math.max(1.0, section.height));
    final lane = section.direction == 'down' ? 0.78 : 0.22;

    List<List<double>> buildGuide(bool rightSide) {
      final outsideX = rightSide ? section.width + clearance : -clearance;
      final sourceY = section.direction == 'up'
          ? section.height * (1 - sourceRaw)
          : section.height * sourceRaw;
      final targetY = section.direction == 'up'
          ? section.height * (1 - targetRaw)
          : section.height * targetRaw;
      final sourceLaneX = section.width * lane;
      final targetLaneX = section.width * lane;

      final transform =
          _transforms[building.id] ?? FloorTransform.build(building);

      List<double> project(double x, double y) {
        final local = section.stair.localToWorld(x, y);
        return transform.project(local[0], local[1]);
      }

      return <List<double>>[
        [markerX, markerY],
        project(targetLaneX, targetY),
        project(outsideX, targetY),
        project(outsideX, sourceY),
        project(sourceLaneX, sourceY),
      ];
    }

    bool safe(List<List<double>> guide) {
      // The first point is the live player position. Check only future guide
      // points; route segments are intentionally outside the stair activator.
      for (var i = 1; i < guide.length; i++) {
        if (!allowed(guide[i])) return false;
      }
      return true;
    }

    final preferred = buildGuide(preferredRight);
    if (safe(preferred)) return preferred;

    final alternate = buildGuide(!preferredRight);
    if (safe(alternate)) return alternate;

    // If nearby walls make both full bypasses fail the generic collision test,
    // still prefer the direction matching the stair lane. The player movement
    // system remains authoritative and will prevent crossing real barriers.
    return preferred;
  }

  bool completedStairTurnaroundReached() {
    final section = lastCompletedStair;
    final building = parent;
    if (section == null || building == null) return true;

    final transform =
        _transforms[building.id] ?? FloorTransform.build(building);
    final floorLocal = transform.unproject(markerX, markerY);
    final raw = sectionProgress(section, floorLocal[0], floorLocal[1]).$3;

    // We are safely beyond the source side of the old activator. At this point
    // the next stair leg can start from raw ~= 0 in the correct direction.
    return raw <= -0.08 && exitAreas.isEmpty;
  }

  double _routeLength(List<List<double>> path) {
    double total = 0;
    for (var i = 1; i < path.length; i++) {
      total += hypot(path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]);
    }
    return total;
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

    final pathfinder = SameFloorPathfinder(
      barriers: groundBarriers,
      playerRadius: collisionRadius,
      width: scene.width,
      height: scene.height,
    );
    return pathfinder.findPath([markerX, markerY], [targetX, targetY]);
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
          py > box.$4 + radius)
        continue;
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
