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
  double _routeRefreshElapsed = 0;

  static const double joystickBaseSize = 148;
  static const double joystickKnobSize = 56;
  Offset joystickKnobPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    navigator = WorldNavigator(
      widget.scene,
      collisionRadius: collisionRadius,
    );
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
        navigator.markerX, navigator.markerY, joystickX, joystickY, dt,
      );
      navigator.markerX = result[0];
      navigator.markerY = result[1];
      final moved = result[0] != before[0] || result[1] != before[1];
      camera.follow([navigator.markerX, navigator.markerY], dt,
          moving: moved, diameter: playerSize);
      navigator.update(navigator.markerX, navigator.markerY);
      _updateLiveRoute(dt);
      setState(() {});
    } else if (followActive) {
      final changed = camera.follow(
          [navigator.markerX, navigator.markerY], dt,
          moving: false, diameter: playerSize);
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
      subtitle =
          '${navigator.parent!.text} - Floor ${navigator.currentFloor}';
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
                  Positioned(
                    right: 30,
                    bottom: 30,
                    child: _buildJoystick(),
                  ),
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
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  routeSelectionMode
                      ? 'ROUTE TEST - tap a destination on the current floor.'
                      : moveMode
                          ? 'MOVE USER MODE - use the joystick.'
                          : 'MAP MODE - drag to pan; pinch to zoom.',
                  style: const TextStyle(
                      color: Color(0xFFDCE8F7), fontSize: 13),
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
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF183B56))),
                Text(status,
                    style: const TextStyle(
                        color: Color(0xFF31475E), fontSize: 14)),
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
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
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
              backgroundColor:
                  moveMode ? const Color(0xFFD9E8FF) : Colors.white,
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
                border: Border.all(
                    color: const Color(0xFF155EEF), width: 3),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Text('MOVE',
                      style: TextStyle(
                          color: Color(0xFF12345A),
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
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
                      child: const Icon(Icons.open_with,
                          color: Colors.white, size: 26),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text('Joystick',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const Text('Hold and drag',
              style: TextStyle(fontSize: 11, color: Color(0xFF476582))),
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

  void _updateLiveRoute(double dt) {
    if (routePoints.length < 2) return;

    final currentBuildingId = navigator.parent?.id;

    // Stage 2 is intentionally same-surface only. If the player changes
    // building/floor or starts a stair transition, keep the behavior safe and
    // wait for the multi-floor routing stage instead of drawing a false route.
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

    // Anchor the visible route to the player's exact live position every frame,
    // so the blue line moves with the blue player dot instead of staying at the
    // position where the route was first created.
    routePoints = <List<double>>[
      current,
      for (var i = 1; i < routePoints.length; i++)
        List<double>.from(routePoints[i]),
    ];

    // Re-run A* at a controlled cadence while the user walks. This removes
    // waypoints already passed and safely reroutes if the user deviates, without
    // doing a full path search at 60 FPS.
    _routeRefreshElapsed += dt;
    final nearNextWaypoint = routePoints.length > 2 &&
        hypot(
              routePoints[1][0] - current[0],
              routePoints[1][1] - current[1],
            ) <=
            (collisionRadius * 2.5).clamp(18.0, 50.0);

    if (_routeRefreshElapsed < 0.25 && !nearNextWaypoint) return;
    _routeRefreshElapsed = 0;

    final refreshed =
        navigator.findSameFloorRoute(destination[0], destination[1]);
    if (refreshed.isNotEmpty) {
      routePoints = refreshed;
      routeStatus = 'Route ready';
    }
  }

  void _clearRoute() {
    routePoints = const [];
    _routeRefreshElapsed = 0;
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

    // Until multi-floor/building transitions are implemented, a route started
    // inside a building must stay inside that same building footprint.
    if (navigator.parent != null &&
        !navigator.inside(navigator.parent!, targetX, targetY)) {
      setState(() {
        routeStatus = 'Choose a point on this building floor';
      });
      return;
    }

    final route = navigator.findSameFloorRoute(targetX, targetY);
    setState(() {
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
    _gestureAnchor =
        camera.world([details.focalPoint.dx, details.focalPoint.dy]);
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
