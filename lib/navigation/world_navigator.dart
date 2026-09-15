import 'dart:math' as math;
import '../models/map_item.dart';
import '../models/map_scene.dart';
import '../models/math_helper.dart';
import 'collision.dart';
import 'stairs.dart';
import 'floor_transform.dart';
import 'runtime_index.dart';

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

class WorldNavigator {
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

  WorldNavigator(this.scene, {
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

      final footprint = PolygonBarrier([
        [parent.x, parent.y],
        [parent.x + parent.width, parent.y],
        [parent.x + parent.width, parent.y + parent.height],
        [parent.x, parent.y + parent.height],
      ]);
      _roofAreas[parent.id] = [footprint];
      parentBoxes.add(_parentBoundingBox(parent));
      roofBoxes.add((
        parent.x - parent.approachDistance,
        parent.y - parent.approachDistance,
        parent.x + parent.width + parent.approachDistance,
        parent.y + parent.height + parent.approachDistance,
      ));

      for (var floor = 1; floor <= parent.floorCount; floor++) {
        final key = '${parent.id}:$floor';
        final items = scene.floorItems(parent.id, floor);
        final stairItems =
            items.where((i) => stairKinds.contains(i.kind)).toList();
        final stairSections = <StairSection>[];
        for (final stair in stairItems) {
          stairSections.addAll(transitions(stair, floor, parent.floorCount));
        }
        _stairObjects[key] = stairItems;
        _stairIndices[key] = _buildStairIndex(stairSections);

        final conns = <StairSection>[];
        for (final stair in stairItems) {
          conns.addAll(transitions(stair, floor, parent.floorCount));
        }
        _connections[key] = conns;
        for (final s in conns) {
          _sectionsById[s.id] = s;
        }
        _sectionIndices[key] = _buildSectionIndex(conns);

        final barriers = barriersFor(items);
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

  (double, double, double, double) _parentBoundingBox(MapItem parent) {
    return (parent.x, parent.y, parent.x + parent.width, parent.y + parent.height);
  }

  RuntimeIndex<StairSection> _buildStairIndex(List<StairSection> stairs) {
    final boxes = stairs.map((s) {
      final area = _buildArea(s.stair, s.source);
      return area.box;
    }).toList();
    return RuntimeIndex(stairs, boxes);
  }

  RuntimeIndex<StairSection> _buildSectionIndex(List<StairSection> zones) {
    final boxes = zones.map((z) {
      final area = _buildArea(z.stair, z.source);
      return area.box;
    }).toList();
    return RuntimeIndex(zones, boxes);
  }

  RuntimeIndex<Barrier> _buildCollisionIndex(List<Barrier> barriers) {
    final boxes = barriers.map((b) => b.bounds).toList();
    return RuntimeIndex(barriers, boxes);
  }

  PolygonBarrier _buildArea(MapItem item, int floor) {
    final points = <List<double>>[];
    for (final (lx, ly) in [(0.0, 0.0), (item.width, 0.0),
        (item.width, item.height), (0.0, item.height)]) {
      final w = item.localToWorld(lx, ly);
      points.add([w[0], w[1]]);
    }
    return PolygonBarrier(points);
  }

  bool inside(MapItem parent, double px, double py) {
    final areas = _roofAreas[parent.id];
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
          ? math.max(0.0, math.min(1.0,
              ((px - prev[0]) * dx + (py - prev[1]) * dy) / length2))
          : 0.0;
      best = math.min(
          best,
          hypot(px - prev[0] - t * dx, py - prev[1] - t * dy));
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
      var ny = math.max(radius, math.min(scene.height - radius, y + dy / count));

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
    final distanceStep = math.max(0.01, math.min(physicsStep, collisionRadius / 2));

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
          py > box.$4 + radius) continue;
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
      return section == null || !section.contains(local[0], local[1], tolerance: 8);
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
        transition = FloorTransition(zone, currentFloor, zone.target, prog.$1[0]);
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
          !(-transitionThreshold <= prevRaw && prevRaw <= 1 + transitionThreshold) &&
          0 <= raw && raw <= 1 && lateral) {
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
    final sourceArea = _buildArea(completed.section.stair, completed.source);
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
