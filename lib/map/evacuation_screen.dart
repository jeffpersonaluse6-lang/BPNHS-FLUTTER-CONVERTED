import 'dart:async';
import 'package:flutter/material.dart';
import '../models/map_scene.dart';
import '../models/math_helper.dart';
import '../camera/smooth_camera.dart';
import '../navigation/world_navigator.dart';
import 'map_painter.dart';

class EvacuationScreen extends StatefulWidget {
  final MapScene scene;

  const EvacuationScreen({super.key, required this.scene});

  @override
  State<EvacuationScreen> createState() => _EvacuationScreenState();
}

class _EvacuationScreenState extends State<EvacuationScreen> {
  late WorldNavigator navigator;
  late SmoothCamera camera;
  Timer? _ticker;
  DateTime? _lastTime;

  double playerSize = 20;
  double get collisionRadius => playerSize / 2;

  double joystickX = 0;
  double joystickY = 0;
  bool moveMode = false;
  bool followActive = false;

  // Stage 2 route visualization. This stays same-floor only until stair routing
  // is added in a later stage.
  List<List<double>> routePoints = const [];
  bool routeSelectionMode = false;
  String? routeStatus;
  String? routeBuildingId;
  int? routeFloor;
  int? routeTargetFloor;
  bool _stairTurnaroundActive = false;
  bool _routeAcrossBuildingExit = false;
  List<double>? _campusRouteDestination;
  String? _evacuationGateKind;
  String? _evacuationRouteRole;
  double _routeRefreshElapsed = 0;

  static const double joystickBaseSize = 148;
  static const double joystickKnobSize = 56;
  Offset joystickKnobPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    navigator = WorldNavigator(widget.scene, collisionRadius: collisionRadius);
    camera = SmoothCamera();
    camera.center([navigator.markerX, navigator.markerY]);
    _startTicker();
  }

  void _startTicker() {
    _lastTime = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final now = DateTime.now();
      final dt = now.difference(_lastTime!).inMicroseconds / 1e6;
      _lastTime = now;
      if (dt > 0 && dt < 0.5) _tick(dt);
    });
  }

  void _tick(double dt) {
    if (moveMode && (joystickX != 0 || joystickY != 0)) {
      final before = [navigator.markerX, navigator.markerY];
      final result = navigator.walk(
        navigator.markerX,
        navigator.markerY,
        joystickX,
        joystickY,
        dt,
      );
      navigator.markerX = result[0];
      navigator.markerY = result[1];
      final moved = result[0] != before[0] || result[1] != before[1];
      camera.follow(
        [navigator.markerX, navigator.markerY],
        dt,
        moving: moved,
        diameter: playerSize,
      );
      navigator.update(navigator.markerX, navigator.markerY);
      _updateLiveRoute(dt);
      setState(() {});
    } else if (followActive) {
      final changed = camera.follow(
        [navigator.markerX, navigator.markerY],
        dt,
        moving: false,
        diameter: playerSize,
      );
      if (changed) setState(() {});
      final screen = camera.screen([navigator.markerX, navigator.markerY]);
      if (hypot(screen[0] - camera.width / 2, screen[1] - camera.height / 2) <
          0.05) {
        followActive = false;
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String status =
        'Walking on campus. Walk through a building doorway to enter.';
    String subtitle = 'Campus overview';
    if (navigator.parent != null) {
      subtitle = '${navigator.parent!.text} - Floor ${navigator.currentFloor}';
      status = subtitle;
      if (navigator.transition != null) {
        final t = navigator.transition!;
        status =
            '${navigator.parent!.text} · Floor ${t.source} → ${t.target} · stairs ${(t.progress * 100).toStringAsFixed(0)}%';
      }
    }
    if (routeStatus != null) {
      status = '$status · $routeStatus';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Column(
        children: [
          _buildHeader(),
          _buildActionBar(subtitle, status),
          Expanded(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: const Color(0xFFD5DEE8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          camera.width = constraints.maxWidth;
                          camera.height = constraints.maxHeight;
                          return GestureDetector(
                            onTapUp: _onMapTap,
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            child: CustomPaint(
                              painter: MapPainter(
                                scene: widget.scene,
                                navigator: navigator,
                                cameraX: camera.x,
                                cameraY: camera.y,
                                cameraScale: camera.scale,
                                cameraRotation: camera.rotation,
                                playerCenter: [
                                  navigator.markerX,
                                  navigator.markerY,
                                ],
                                playerSize: playerSize,
                                collisionRadius: collisionRadius,
                                routePoints: routePoints,
                              ),
                              size: Size.infinite,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (moveMode)
                  Positioned(right: 30, bottom: 30, child: _buildJoystick()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: const Color(0xFF12345A),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.route, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BPNHS Evacuation Navigator',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  routeSelectionMode
                      ? 'ROUTE TEST - tap a destination on the current floor.'
                      : moveMode
                      ? 'MOVE USER MODE - use the joystick.'
                      : 'MAP MODE - drag to pan; pinch to zoom.',
                  style: const TextStyle(
                    color: Color(0xFFDCE8F7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Reset view',
            onPressed: () {
              camera.scale = 1;
              camera.rotation = 0;
              camera.center([navigator.markerX, navigator.markerY]);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(String subtitle, String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF183B56),
                  ),
                ),
                Text(
                  status,
                  style: const TextStyle(
                    color: Color(0xFF31475E),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Player size', style: TextStyle(fontSize: 12)),
              SizedBox(
                width: 140,
                child: Slider(
                  min: 8,
                  max: 52,
                  value: playerSize,
                  onChanged: (v) {
                    playerSize = v;
                    navigator.collisionRadius = collisionRadius;
                    _clearRoute();
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          if (navigator.parent != null && navigator.currentFloor > 1) ...[
            ElevatedButton.icon(
              onPressed: _startRouteToFloorOne,
              icon: const Icon(Icons.stairs),
              label: Text(
                routeTargetFloor == 1 ? 'Routing to F1' : 'To Floor 1',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: routeTargetFloor == 1
                    ? const Color(0xFFD9E8FF)
                    : Colors.white,
                foregroundColor: const Color(0xFF12345A),
              ),
            ),
            const SizedBox(width: 8),
          ],
          ElevatedButton.icon(
            onPressed: () =>
                _startRecommendedEvacuationRoute(alternative: false),
            icon: const Icon(Icons.exit_to_app),
            label: const Text('Main route'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _evacuationRouteRole == 'main'
                  ? const Color(0xFFD9E8FF)
                  : Colors.white,
              foregroundColor: const Color(0xFF12345A),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () =>
                _startRecommendedEvacuationRoute(alternative: true),
            icon: const Icon(Icons.alt_route),
            label: const Text('Alternative'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _evacuationRouteRole == 'alternative'
                  ? const Color(0xFFFFE8CC)
                  : Colors.white,
              foregroundColor: const Color(0xFF8A4B08),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                routeTargetFloor = null;
                routeSelectionMode = !routeSelectionMode;
                if (routeSelectionMode) {
                  moveMode = false;
                  joystickX = 0;
                  joystickY = 0;
                  routeStatus = 'Tap a destination';
                } else if (routePoints.isEmpty) {
                  routeStatus = null;
                }
              });
            },
            icon: Icon(routeSelectionMode ? Icons.close : Icons.alt_route),
            label: Text(routeSelectionMode ? 'Cancel route' : 'Set route'),
            style: ElevatedButton.styleFrom(
              backgroundColor: routeSelectionMode
                  ? const Color(0xFFD9E8FF)
                  : Colors.white,
              foregroundColor: const Color(0xFF12345A),
            ),
          ),
          if (routePoints.isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                setState(_clearRoute);
              },
              tooltip: 'Clear route',
              icon: const Icon(Icons.route_outlined),
              color: const Color(0xFF12345A),
            ),
          ],
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              moveMode = !moveMode;
              routeSelectionMode = false;
              followActive = true;
              if (!moveMode) {
                joystickX = 0;
                joystickY = 0;
              }
              setState(() {});
            },
            icon: Icon(moveMode ? Icons.check : Icons.open_with),
            label: Text(moveMode ? 'Finish moving' : 'Move user'),
            style: ElevatedButton.styleFrom(
              backgroundColor: moveMode
                  ? const Color(0xFFD9E8FF)
                  : Colors.white,
              foregroundColor: const Color(0xFF12345A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoystick() {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.91),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC7D4E2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onPanStart: _onJoystickStart,
            onPanUpdate: _onJoystickUpdate,
            onPanEnd: _onJoystickEnd,
            child: Container(
              width: joystickBaseSize,
              height: joystickBaseSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.91),
                border: Border.all(color: const Color(0xFF155EEF), width: 3),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Text(
                    'MOVE',
                    style: TextStyle(
                      color: Color(0xFF12345A),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Positioned(
                    left: joystickKnobPosition.dx,
                    top: joystickKnobPosition.dy,
                    child: Container(
                      width: joystickKnobSize,
                      height: joystickKnobSize,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF155EEF),
                      ),
                      child: const Icon(
                        Icons.open_with,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Joystick',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Hold and drag',
            style: TextStyle(fontSize: 11, color: Color(0xFF476582)),
          ),
        ],
      ),
    );
  }

  void _onJoystickStart(DragStartDetails details) {
    _updateJoystickPosition(details.localPosition);
  }

  void _onJoystickUpdate(DragUpdateDetails details) {
    _updateJoystickPosition(details.localPosition);
  }

  void _onJoystickEnd(DragEndDetails details) {
    setState(() {
      joystickX = 0;
      joystickY = 0;
      _centerJoystickKnob();
    });
  }

  void _updateJoystickPosition(Offset localPosition) {
    final center = joystickBaseSize / 2;
    final dx = localPosition.dx - center;
    final dy = localPosition.dy - center;
    final distance = hypot(dx, dy);
    if (distance < 8) {
      setState(() {
        joystickX = 0;
        joystickY = 0;
        _centerJoystickKnob();
      });
      return;
    }
    final radius = joystickBaseSize / 2;
    final clampedDx = distance > radius ? dx / distance * radius : dx;
    final clampedDy = distance > radius ? dy / distance * radius : dy;
    setState(() {
      joystickX = clampedDx / radius;
      joystickY = clampedDy / radius;
      final maxKnob = joystickBaseSize - joystickKnobSize;
      joystickKnobPosition = Offset(
        (center + clampedDx - joystickKnobSize / 2).clamp(0.0, maxKnob),
        (center + clampedDy - joystickKnobSize / 2).clamp(0.0, maxKnob),
      );
    });
  }

  void _centerJoystickKnob() {
    final center = (joystickBaseSize - joystickKnobSize) / 2;
    joystickKnobPosition = Offset(center, center);
  }

  String _gateLabel(String kind) =>
      kind == 'secondary_gate' ? 'Secondary Gate' : 'Main Gate';

  String _evacuationRoleLabel() =>
      _evacuationRouteRole == 'alternative' ? 'Alternative' : 'Main';

  void _startRecommendedEvacuationRoute({required bool alternative}) {
    if (navigator.transition != null) {
      setState(() {
        routeStatus = 'Finish the stair transition first';
        routeSelectionMode = false;
      });
      return;
    }

    final ranked = navigator.rankEvacuationGates();
    final index = alternative ? 1 : 0;

    if (ranked.length <= index) {
      setState(() {
        routeStatus = alternative
            ? 'No meaningfully different alternative evacuation route is available'
            : 'No valid campus evacuation route is available';
        _evacuationGateKind = null;
        _evacuationRouteRole = null;
      });
      return;
    }

    _startEvacuationRoute(
      ranked[index].kind,
      role: alternative ? 'alternative' : 'main',
    );
  }

  void _startEvacuationRoute(String gateKind, {required String role}) {
    if (navigator.transition != null) {
      setState(() {
        routeStatus = 'Finish the stair transition first';
        routeSelectionMode = false;
      });
      return;
    }

    final destination = navigator.campusGateApproach(gateKind);
    if (destination == null) {
      setState(() {
        routeStatus =
            '${_gateLabel(gateKind)} is not configured on the campus map';
        _evacuationGateKind = null;
        _evacuationRouteRole = null;
      });
      return;
    }

    final building = navigator.parent;

    setState(() {
      routeSelectionMode = false;
      moveMode = false;
      joystickX = 0;
      joystickY = 0;
      _evacuationGateKind = gateKind;
      _evacuationRouteRole = role;
      _routeAcrossBuildingExit = true;
      _campusRouteDestination = destination;
      _routeRefreshElapsed = 0;
      _stairTurnaroundActive = false;
      routeBuildingId = building?.id;
      routeFloor = navigator.currentFloor;

      if (building != null && navigator.currentFloor > 1) {
        routeTargetFloor = 1;
        _refreshMultiFloorLeg();
        routeStatus =
            '${_evacuationRoleLabel()} evacuation route → ${_gateLabel(gateKind)} · first go to Floor 1';
        return;
      }

      routeTargetFloor = null;
      if (building != null) {
        _beginCampusExitLeg();
        return;
      }

      final route = navigator.findCampusGateRoute(gateKind);
      routePoints = route;
      if (route.isEmpty) {
        routeStatus = 'No route to ${_gateLabel(gateKind)}';
        _routeAcrossBuildingExit = false;
        _campusRouteDestination = null;
        _evacuationGateKind = null;
        _evacuationRouteRole = null;
        routeBuildingId = null;
        routeFloor = null;
      } else {
        routeStatus =
            '${_evacuationRoleLabel()} evacuation route → ${_gateLabel(gateKind)}';
        routeFloor = 1;
      }
    });
  }

  void _startRouteToFloorOne() {
    final building = navigator.parent;
    if (building == null || navigator.currentFloor <= 1) return;

    setState(() {
      routeSelectionMode = false;
      routeTargetFloor = 1;
      _stairTurnaroundActive = false;
      routeBuildingId = building.id;
      routeFloor = navigator.currentFloor;
      _routeRefreshElapsed = 0;
      _refreshMultiFloorLeg();
    });
  }

  void _beginCampusExitLeg() {
    final destination = _campusRouteDestination;
    if (destination == null || navigator.parent == null) {
      _routeAcrossBuildingExit = false;
      routePoints = const [];
      routeStatus = 'Campus route cancelled';
      return;
    }

    routeTargetFloor = null;
    _stairTurnaroundActive = false;
    routeFloor = 1;
    _routeRefreshElapsed = 0;

    final route = navigator.findFloor1CampusRoute(
      destination[0],
      destination[1],
    );
    routePoints = route;
    if (route.isEmpty) {
      _routeAcrossBuildingExit = false;
      _campusRouteDestination = null;
      _evacuationGateKind = null;
      _evacuationRouteRole = null;
      routeStatus = 'No valid building exit route found';
      routeBuildingId = null;
      routeFloor = null;
    } else {
      routeStatus = _evacuationGateKind == null
          ? 'Exit building → campus'
          : 'Exit building → ${_gateLabel(_evacuationGateKind!)}';
    }
  }

  void _refreshMultiFloorLeg() {
    final targetFloor = routeTargetFloor;
    final building = navigator.parent;
    if (targetFloor == null || building == null) return;

    if (routeBuildingId != building.id) {
      routePoints = const [];
      routeStatus = 'Multi-floor route cancelled';
      routeTargetFloor = null;
      routeBuildingId = null;
      routeFloor = null;
      return;
    }

    if (navigator.transition != null) {
      routePoints = const [];
      routeFloor = navigator.currentFloor;
      routeStatus = 'On stairs to Floor ${navigator.transition!.target}';
      return;
    }

    if (navigator.currentFloor == targetFloor) {
      routePoints = const [];
      routeFloor = navigator.currentFloor;
      routeTargetFloor = null;
      routeStatus = 'Reached Floor $targetFloor';
      return;
    }

    final leg = navigator.findRouteTowardFloor(targetFloor);
    if (leg == null) {
      routePoints = const [];
      routeFloor = navigator.currentFloor;
      routeStatus =
          'No stair route from Floor ${navigator.currentFloor} to Floor $targetFloor';
      return;
    }

    routePoints = leg.path;
    routeFloor = navigator.currentFloor;
    _routeRefreshElapsed = 0;
    routeStatus = 'Go to stairs: Floor ${leg.sourceFloor} → ${leg.targetFloor}';
  }

  bool _shortRouteConnectorIsWalkable(List<double> a, List<double> b) {
    final dx = b[0] - a[0];
    final dy = b[1] - a[1];
    final distance = hypot(dx, dy);
    if (distance < 1e-6) return true;

    // Cheap collision validation for the short player -> route connector.
    // This uses the navigator's existing collision index and does NOT rerun A*.
    final spacing = (collisionRadius * 0.45).clamp(4.0, 10.0);
    final steps = (distance / spacing).ceil().clamp(2, 24);

    for (var i = 1; i < steps; i++) {
      final t = i / steps;
      final point = <double>[a[0] + dx * t, a[1] + dy * t];
      if (!navigator.allowed(point)) return false;
    }
    return true;
  }

  List<double> _closestPointOnRouteSegment(
    List<double> point,
    List<double> a,
    List<double> b,
  ) {
    final dx = b[0] - a[0];
    final dy = b[1] - a[1];
    final length2 = dx * dx + dy * dy;
    if (length2 < 1e-9) return List<double>.from(a);

    final t = (((point[0] - a[0]) * dx + (point[1] - a[1]) * dy) / length2)
        .clamp(0.0, 1.0);

    return <double>[a[0] + dx * t, a[1] + dy * t];
  }

  void _consumeReachedRouteWaypoints(List<double> current) {
    final threshold = (collisionRadius * 2.5).clamp(18.0, 50.0);

    while (routePoints.length > 2) {
      final next = routePoints[1];
      final distance = hypot(next[0] - current[0], next[1] - current[1]);
      if (distance > threshold) break;

      routePoints = <List<double>>[
        current,
        for (var i = 2; i < routePoints.length; i++)
          List<double>.from(routePoints[i]),
      ];
    }

    if (routePoints.length < 3) return;

    // If the player is already beside/on a later road segment, snap the visible
    // blue line to the nearest reachable point on that segment immediately
    // instead of forcing the player to walk back to a stale waypoint.
    final maxSegment = (routePoints.length - 2).clamp(1, 5).toInt();
    final snapDistance = (collisionRadius * 5.0).clamp(40.0, 95.0);

    var bestSegment = -1;
    var bestDistance = double.infinity;
    List<double>? bestPoint;

    for (var i = 1; i <= maxSegment; i++) {
      final projection = _closestPointOnRouteSegment(
        current,
        routePoints[i],
        routePoints[i + 1],
      );
      final distance = hypot(
        projection[0] - current[0],
        projection[1] - current[1],
      );

      if (distance >= bestDistance || distance > snapDistance) continue;
      if (!_shortRouteConnectorIsWalkable(current, projection)) continue;

      bestDistance = distance;
      bestSegment = i;
      bestPoint = projection;
    }

    if (bestSegment < 0 || bestPoint == null) return;

    final snapped = <List<double>>[current];

    if (bestDistance > 1.0) {
      snapped.add(bestPoint);
    }

    for (var i = bestSegment + 1; i < routePoints.length; i++) {
      snapped.add(List<double>.from(routePoints[i]));
    }

    routePoints = snapped;
  }

  void _updateLiveRoute(double dt) {
    final currentBuildingId = navigator.parent?.id;

    if (routeTargetFloor != null) {
      if (currentBuildingId == null || currentBuildingId != routeBuildingId) {
        routePoints = const [];
        routeTargetFloor = null;
        routeBuildingId = null;
        routeFloor = null;
        routeStatus = 'Multi-floor route cancelled';
        return;
      }

      if (navigator.transition != null) {
        routePoints = navigator.activeStairRouteGuide();
        routeFloor = navigator.currentFloor;
        routeStatus = 'On stairs to Floor ${navigator.transition!.target}';
        return;
      }

      if (navigator.currentFloor == routeTargetFloor) {
        if (_routeAcrossBuildingExit &&
            _campusRouteDestination != null &&
            navigator.currentFloor == 1) {
          if (routeFloor != navigator.currentFloor) {
            _stairTurnaroundActive = true;
            routeFloor = navigator.currentFloor;
          }

          if (_stairTurnaroundActive) {
            if (navigator.completedStairTurnaroundReached()) {
              _stairTurnaroundActive = false;
              _beginCampusExitLeg();
            } else {
              routePoints = navigator.completedStairTurnaroundGuide();
              routeStatus = 'Turn around outside the stairs';
            }
            return;
          }

          _beginCampusExitLeg();
          return;
        }

        final reached = routeTargetFloor!;
        routePoints = const [];
        routeTargetFloor = null;
        _stairTurnaroundActive = false;
        routeFloor = navigator.currentFloor;
        routeStatus = 'Reached Floor $reached';
        return;
      }

      if (routeFloor != navigator.currentFloor) {
        _stairTurnaroundActive = true;
        routeFloor = navigator.currentFloor;
      }

      if (_stairTurnaroundActive) {
        if (navigator.completedStairTurnaroundReached()) {
          _stairTurnaroundActive = false;
          _refreshMultiFloorLeg();
        } else {
          routePoints = navigator.completedStairTurnaroundGuide();
          routeStatus = 'Turn around outside the stairs';
        }
        return;
      }

      if (routePoints.length < 2) {
        _refreshMultiFloorLeg();
        return;
      }

      final current = <double>[navigator.markerX, navigator.markerY];
      final stairEntry = List<double>.from(routePoints.last);
      final distanceToStair = hypot(
        stairEntry[0] - current[0],
        stairEntry[1] - current[1],
      );

      routePoints = <List<double>>[
        current,
        for (var i = 1; i < routePoints.length; i++)
          List<double>.from(routePoints[i]),
      ];

      if (distanceToStair <= (collisionRadius * 1.6).clamp(12.0, 32.0)) {
        routeStatus = 'Enter the stairs';
      }

      _routeRefreshElapsed += dt;
      final nearNextWaypoint =
          routePoints.length > 2 &&
          hypot(
                routePoints[1][0] - current[0],
                routePoints[1][1] - current[1],
              ) <=
              (collisionRadius * 2.5).clamp(18.0, 50.0);

      if (_routeRefreshElapsed < 0.25 && !nearNextWaypoint) return;
      _routeRefreshElapsed = 0;

      final refreshedLeg = navigator.findRouteTowardFloor(routeTargetFloor!);
      if (refreshedLeg != null) {
        routePoints = refreshedLeg.path;
        routeFloor = navigator.currentFloor;
        routeStatus =
            'Go to stairs: Floor ${refreshedLeg.sourceFloor} → ${refreshedLeg.targetFloor}';
      }
      return;
    }

    if (_routeAcrossBuildingExit &&
        routeTargetFloor == null &&
        _campusRouteDestination != null) {
      final destination = _campusRouteDestination!;
      final current = <double>[navigator.markerX, navigator.markerY];
      final distanceToDestination = hypot(
        destination[0] - current[0],
        destination[1] - current[1],
      );

      if (distanceToDestination <= (collisionRadius * 1.5).clamp(10.0, 30.0)) {
        routePoints = const [];
        _routeAcrossBuildingExit = false;
        _campusRouteDestination = null;
        _routeRefreshElapsed = 0;
        routeBuildingId = null;
        routeFloor = null;
        routeStatus = _evacuationGateKind == null
            ? 'Campus destination reached'
            : '${_gateLabel(_evacuationGateKind!)} reached';
        _evacuationGateKind = null;
        _evacuationRouteRole = null;
        return;
      }

      if (currentBuildingId == null) {
        if (routeBuildingId != null || routePoints.length < 2) {
          routeBuildingId = null;
          routeFloor = 1;
          final campusRoute = navigator.findSameFloorRoute(
            destination[0],
            destination[1],
          );
          if (campusRoute.isNotEmpty) {
            routePoints = campusRoute;
            routeStatus = _evacuationGateKind == null
                ? 'Campus route'
                : '${_evacuationRoleLabel()} evacuation route → ${_gateLabel(_evacuationGateKind!)}';
          }
        }
      } else if (navigator.currentFloor != 1) {
        // Do not cancel an evacuation route if the user enters another
        // building and goes upstairs. Recover by routing back to Floor 1,
        // then continue toward the same campus gate.
        routeBuildingId = currentBuildingId;
        routeFloor = navigator.currentFloor;
        routeTargetFloor = 1;
        _stairTurnaroundActive = false;
        routePoints = const [];
        _refreshMultiFloorLeg();
        routeStatus =
            'Entered ${navigator.parent?.text ?? 'building'} · return to Floor 1, then continue evacuation';
        return;
      } else if (routeBuildingId != currentBuildingId) {
        // The player entered a different Floor-1 building (for example the
        // court) while following the campus route. Keep the evacuation target
        // and immediately reroute through a valid exit instead of cancelling.
        routeBuildingId = currentBuildingId;
        routeFloor = 1;
        final recoveryRoute = navigator.findFloor1CampusRoute(
          destination[0],
          destination[1],
        );
        if (recoveryRoute.isNotEmpty) {
          routePoints = recoveryRoute;
          routeStatus = _evacuationGateKind == null
              ? 'Exit building → campus'
              : 'Continue evacuation → ${_gateLabel(_evacuationGateKind!)}';
        } else {
          routePoints = const [];
          routeStatus =
              'Find a building exit to continue toward ${_evacuationGateKind == null ? 'the campus route' : _gateLabel(_evacuationGateKind!)}';
        }
      }

      // Following an already planned evacuation route should be almost free.
      // Consume reached road waypoints instead of rerunning weighted A* every
      // time the player gets close to one.
      _consumeReachedRouteWaypoints(current);

      if (routePoints.length >= 2) {
        routePoints = <List<double>>[
          current,
          for (var i = 1; i < routePoints.length; i++)
            List<double>.from(routePoints[i]),
        ];
      }

      // Official evacuation routes do NOT need a timer-based A* refresh while
      // the campus geometry is static. The previous 1.5-second recalculation
      // caused a visible FPS spike exactly when the blue line changed.
      //
      // Floor/building transitions above already force an immediate reroute,
      // and future hazards can explicitly request one when hazard state changes.
      if (_evacuationGateKind != null) {
        _routeRefreshElapsed = 0;
        return;
      }

      // Keep live refresh only for manually selected campus destinations.
      _routeRefreshElapsed += dt;
      if (_routeRefreshElapsed < 0.5) return;

      _routeRefreshElapsed = 0;
      final refreshed = currentBuildingId == null
          ? navigator.findSameFloorRoute(destination[0], destination[1])
          : navigator.findFloor1CampusRoute(destination[0], destination[1]);
      if (refreshed.isNotEmpty) {
        routePoints = refreshed;
      }
      return;
    }

    if (routePoints.length < 2) return;

    if (navigator.transition != null ||
        currentBuildingId != routeBuildingId ||
        navigator.currentFloor != routeFloor) {
      routePoints = const [];
      _routeRefreshElapsed = 0;
      routeBuildingId = null;
      routeFloor = null;
      routeStatus = 'Route cleared after changing floor/area';
      return;
    }

    final current = <double>[navigator.markerX, navigator.markerY];
    final destination = List<double>.from(routePoints.last);
    final dx = destination[0] - current[0];
    final dy = destination[1] - current[1];
    final distanceToDestination = hypot(dx, dy);

    if (distanceToDestination <= (collisionRadius * 1.5).clamp(10.0, 30.0)) {
      routePoints = const [];
      _routeRefreshElapsed = 0;
      routeBuildingId = null;
      routeFloor = null;
      routeStatus = 'Destination reached';
      return;
    }

    routePoints = <List<double>>[
      current,
      for (var i = 1; i < routePoints.length; i++)
        List<double>.from(routePoints[i]),
    ];

    _routeRefreshElapsed += dt;
    final nearNextWaypoint =
        routePoints.length > 2 &&
        hypot(routePoints[1][0] - current[0], routePoints[1][1] - current[1]) <=
            (collisionRadius * 2.5).clamp(18.0, 50.0);

    if (_routeRefreshElapsed < 0.25 && !nearNextWaypoint) return;
    _routeRefreshElapsed = 0;

    final refreshed = navigator.findSameFloorRoute(
      destination[0],
      destination[1],
    );
    if (refreshed.isNotEmpty) {
      routePoints = refreshed;
      routeStatus = 'Route ready';
    }
  }

  void _clearRoute() {
    routePoints = const [];
    _routeRefreshElapsed = 0;
    routeTargetFloor = null;
    _stairTurnaroundActive = false;
    _routeAcrossBuildingExit = false;
    _campusRouteDestination = null;
    _evacuationGateKind = null;
    _evacuationRouteRole = null;
    routeStatus = null;
    routeBuildingId = null;
    routeFloor = null;
    routeSelectionMode = false;
  }

  void _onMapTap(TapUpDetails details) {
    if (!routeSelectionMode || moveMode) return;

    if (navigator.transition != null) {
      setState(() {
        routeStatus = 'Finish the stair transition first';
        routeSelectionMode = false;
      });
      return;
    }

    final world = camera.world([
      details.localPosition.dx,
      details.localPosition.dy,
    ]);
    final targetX = world[0];
    final targetY = world[1];

    final building = navigator.parent;
    if (building != null && !navigator.inside(building, targetX, targetY)) {
      setState(() {
        routeSelectionMode = false;
        _evacuationGateKind = null;
        _evacuationRouteRole = null;
        _routeAcrossBuildingExit = true;
        _campusRouteDestination = [targetX, targetY];
        routeBuildingId = building.id;
        routeFloor = navigator.currentFloor;
        _routeRefreshElapsed = 0;

        if (navigator.currentFloor > 1) {
          routeTargetFloor = 1;
          _stairTurnaroundActive = false;
          _refreshMultiFloorLeg();
          routeStatus = 'Route to Campus: first go to Floor 1';
        } else {
          _beginCampusExitLeg();
        }
      });
      return;
    }

    final route = navigator.findSameFloorRoute(targetX, targetY);
    setState(() {
      routeTargetFloor = null;
      _stairTurnaroundActive = false;
      _routeAcrossBuildingExit = false;
      _campusRouteDestination = null;
      _evacuationGateKind = null;
      _evacuationRouteRole = null;
      routePoints = route;
      routeSelectionMode = false;
      _routeRefreshElapsed = 0;
      if (route.isEmpty) {
        routeStatus = 'No same-floor route found';
        routeBuildingId = null;
        routeFloor = null;
      } else {
        routeStatus = 'Route ready';
        routeBuildingId = navigator.parent?.id;
        routeFloor = navigator.currentFloor;
      }
    });
  }

  List<double>? _gestureAnchor;
  double _gestureScale = 1;

  void _onScaleStart(ScaleStartDetails details) {
    if (moveMode) return;
    _gestureAnchor = camera.world([
      details.focalPoint.dx,
      details.focalPoint.dy,
    ]);
    _gestureScale = camera.scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (moveMode || _gestureAnchor == null) return;
    camera.scale = (_gestureScale * details.scale).clamp(0.3, 3.0);
    final focal = [details.focalPoint.dx, details.focalPoint.dy];
    final current = camera.screen(_gestureAnchor!);
    camera.x += focal[0] - current[0];
    camera.y += focal[1] - current[1];
    setState(() {});
  }
}
