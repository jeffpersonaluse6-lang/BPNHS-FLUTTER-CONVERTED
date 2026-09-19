import 'dart:async';
import 'package:flutter/material.dart';
import '../models/map_scene.dart';
import '../models/math_helper.dart';
import '../camera/smooth_camera.dart';
import '../navigation/route_step_builder.dart';
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

  double playerSize = 8;
  double get collisionRadius => playerSize / 2;

  double joystickX = 0;
  double joystickY = 0;
  bool moveMode = false;
  bool followActive = false;
  int _cameraSurfaceHoldFrames = 0;
  bool _routeNeedsFinalMovementRefresh = false;

  // Mobile invisible joystick: finger-down point is its center.
  Offset? _mobileMoveOrigin;
  static const double _mobileMoveRadius = 72;

  // Fire simulation placement mode. Hazards are runtime-only.
  bool _firePlacementMode = false;
  static const double _fireHazardRadius = 40;
  String? _selectedFireHazardId;

  // Earthquake simulation: manually marked debris/damaged/blocked pathways.
  bool _earthquakePlacementMode = false;
  static const double _earthquakeBlockageRadius = 55;
  String? _selectedEarthquakeHazardId;

  // Active-shooter simulation uses manually reported unsafe areas.
  bool _activeShooterPlacementMode = false;
  static const double _activeThreatRadius = 70;
  String? _selectedActiveShooterHazardId;

  // One simulated moving shooter. The hazard circle follows this actor.
  String? _activeShooterActorId;
  bool _activeShooterPathMode = false;
  List<List<double>> _activeShooterPath = const <List<double>>[];
  int _activeShooterPathIndex = 1;
  int _activeShooterPathDirection = 1;
  bool _activeShooterMoving = false;
  final double _activeShooterSpeed = 60;
  double _movingShooterRerouteElapsed = 0;
  static const double _movingShooterRerouteInterval = 0.50;
  /// Track total shooter displacement since last reroute to skip trivial moves.
  double _shooterDisplacementSinceReroute = 0;
  static const double _shooterRerouteMinDisplacement = 30.0;

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

  // One monotonic state for the currently selected authored stair guide.
  // _nextWaypointIndex may only move forward until this guide is replaced.
  String? _activeWaypointKey;
  List<List<double>> _activeWaypointPoints = const <List<double>>[];
  int _nextWaypointIndex = 0;
  List<double>? _previousWaypointPosition;

  // Route presentation UX. Calculations stay synchronous for now, but the map
  // hides the unfinished route behind a short loading state, then reveals the
  // completed polyline progressively from the player's position.
  bool _routeCalculating = false;
  double _routeCalculationHold = 0;
  bool _routeRevealAnimating = false;
  double _routeRevealProgress = 1;
  String _routeCalculationLabel = 'Calculating evacuation path…';

  static const double _routeLoadingMinSeconds = 0.22;
  static const double _routeRevealSeconds = 0.70;

  // Step-by-step evacuation guidance. The current instruction is regenerated
  // whenever the route changes and displayed as a persistent overlay.
  RouteStep? _currentStep;

  static const double joystickBaseSize = 148;
  static const double joystickKnobSize = 56;
  Offset joystickKnobPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    navigator = WorldNavigator(widget.scene, collisionRadius: collisionRadius);
    // Resolve the player's starting surface before the first frame. The saved
    // spawn point is inside a building; without this initial update, pressing
    // ROUTE before moving treats that building as an unrelated sealed campus
    // footprint and incorrectly reports that no evacuation route exists.
    navigator.update(navigator.markerX, navigator.markerY);
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

  double _cameraFollowDt(double dt) {
    if (navigator.transition == null || navigator.playerSpeed <= 1e-9) {
      return dt;
    }

    // Walking slows down on stairs. Slow the camera by the same ratio so it
    // does not suddenly catch up/offset when a stair transition starts.
    final stairSpeed = navigator.walkingSpeed(
      navigator.markerX,
      navigator.markerY,
    );
    final ratio = (stairSpeed / navigator.playerSpeed)
        .clamp(0.35, 1.0)
        .toDouble();
    return dt * ratio;
  }

  void _tick(double dt) {
    final routePresentationChanged = _updateRoutePresentation(dt);
    final shooterMoved = _updateActiveShooterMovement(dt);
    var routeFinalizedAfterMovement = false;

    // The live route is throttled while the joystick is held for performance.
    // Always do one authoritative refresh on the first stationary frame so a
    // waypoint calculated from the previous player position cannot remain as
    // a visible V-shaped backtrack after the joystick is released.
    if (_routeNeedsFinalMovementRefresh &&
        (!moveMode || (joystickX == 0 && joystickY == 0))) {
      _routeNeedsFinalMovementRefresh = false;
      _updateLiveRoute(1.0);
      _refreshCurrentStep();
      routeFinalizedAfterMovement = true;
    }

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
      if (moved && routePoints.length >= 2) {
        _routeNeedsFinalMovementRefresh = true;
      }

      // Update stair/floor state first so the camera uses the transition state
      // from this same frame instead of reacting one frame late.
      _updateNavigatorPreservingCamera();

      if (_cameraSurfaceHoldFrames > 0) {
        _cameraSurfaceHoldFrames--;
      } else {
        camera.follow(
          [navigator.markerX, navigator.markerY],
          _cameraFollowDt(dt),
          moving: moved,
          diameter: playerSize,
        );
      }
      _updateLiveRoute(dt);
      _refreshCurrentStep();
      setState(() {});
    } else if (followActive) {
      if (_cameraSurfaceHoldFrames > 0) {
        _cameraSurfaceHoldFrames--;
        if (routePresentationChanged ||
            shooterMoved ||
            routeFinalizedAfterMovement) {
          setState(() {});
        }
        return;
      }

      final changed = camera.follow(
        [navigator.markerX, navigator.markerY],
        _cameraFollowDt(dt),
        moving: false,
        diameter: playerSize,
      );
      if (shooterMoved) _updateLiveRoute(dt);
      _refreshCurrentStep();
      if (changed ||
          routePresentationChanged ||
          shooterMoved ||
          routeFinalizedAfterMovement) {
        setState(() {});
      }
      final screen = camera.screen([navigator.markerX, navigator.markerY]);
      if (hypot(screen[0] - camera.width / 2, screen[1] - camera.height / 2) <
          0.05) {
        followActive = false;
      }
    } else if (routePresentationChanged ||
        shooterMoved ||
        routeFinalizedAfterMovement) {
      // A moving shooter must repaint and keep the current evacuation route
      // updated even while the student is standing still.
      if (shooterMoved) _updateLiveRoute(dt);
      _refreshCurrentStep();
      setState(() {});
    }
  }

  void _updateNavigatorPreservingCamera() {
    final beforeBuildingId = navigator.parent?.id;
    final beforeFloor = navigator.currentFloor;
    final beforeView = navigator.view;

    final beforeCameraX = camera.x;
    final beforeCameraY = camera.y;

    navigator.update(navigator.markerX, navigator.markerY);

    final surfaceChanged =
        beforeBuildingId != navigator.parent?.id ||
        beforeFloor != navigator.currentFloor ||
        beforeView != navigator.view;

    if (surfaceChanged) {
      // The camera itself must not react during the transient frame where the
      // renderer switches between campus/building/floor layers.
      camera.x = beforeCameraX;
      camera.y = beforeCameraY;
      _cameraSurfaceHoldFrames = 2;
    }
  }

  void _beginRoutePresentation([String? label]) {
    _routeCalculating = true;
    _routeCalculationHold = 0;
    _routeRevealAnimating = false;
    _routeRevealProgress = 0;
    if (label != null) _routeCalculationLabel = label;
  }

  bool _updateRoutePresentation(double dt) {
    if (_routeCalculating) {
      _routeCalculationHold += dt;
      if (_routeCalculationHold >= _routeLoadingMinSeconds) {
        _routeCalculating = false;
        _routeCalculationHold = 0;

        if (routePoints.length >= 2) {
          _routeRevealAnimating = true;
          _routeRevealProgress = 0;
        } else {
          _routeRevealAnimating = false;
          _routeRevealProgress = 1;
        }
      }
      return true;
    }

    if (_routeRevealAnimating) {
      _routeRevealProgress = (_routeRevealProgress + dt / _routeRevealSeconds)
          .clamp(0.0, 1.0);
      if (_routeRevealProgress >= 1) {
        _routeRevealProgress = 1;
        _routeRevealAnimating = false;
      }
      return true;
    }

    return false;
  }

  bool get _showNoSafeRouteOverlay {
    if (_routeCalculating || routePoints.isNotEmpty) return false;

    final message = routeStatus?.toLowerCase();
    if (message == null || message.isEmpty) return false;

    // "No alternative route" does not mean the main/current route is unusable.
    if (message.contains('alternative') &&
        !message.contains('all modeled evacuation exits are blocked')) {
      return false;
    }

    return message.contains('no valid') ||
        message.contains('no safe route') ||
        message.contains('no available route') ||
        message.contains('no route') ||
        message.contains('all modeled evacuation exits are blocked') ||
        message.contains('stay at your current position');
  }

  Widget _buildNoSafeRouteOverlay() {
    final top = MediaQuery.paddingOf(context).top + 18;

    return Positioned(
      left: 18,
      right: 18,
      top: top,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE4E2).withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD92D20), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x28000000),
                  blurRadius: 16,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFB42318),
                  size: 28,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NO SAFEROUTE AVAILABLE',
                        style: TextStyle(
                          color: Color(0xFFB42318),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'No passable evacuation path was found. Stay at your current position.',
                        style: TextStyle(
                          color: Color(0xFF7A271A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRouteLoadingOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xF2FFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD8E2EC)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x24000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _routeCalculationLabel,
                        style: const TextStyle(
                          color: Color(0xFF183B56),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Finding a safety-prioritized path…',
                        style: TextStyle(
                          color: Color(0xFF5E7184),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    String subtitle = 'Campus overview';
    if (navigator.parent != null) {
      subtitle = '${navigator.parent!.text} - Floor ${navigator.currentFloor}';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Column(
        children: [
          if (!isMobile) _buildHeader(),
          if (!isMobile) _buildActionBar(subtitle),
          Expanded(
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.all(isMobile ? 0 : 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isMobile ? 0 : 12),
                    child: Container(
                      color: const Color(0xFFD5DEE8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          camera.width = constraints.maxWidth;
                          camera.height = constraints.maxHeight;

                          return GestureDetector(
                            onTapUp: _firePlacementMode
                                ? _onFireTap
                                : _earthquakePlacementMode
                                ? _onEarthquakeTap
                                : _activeShooterPlacementMode
                                ? _onActiveShooterTap
                                : _activeShooterPathMode
                                ? _onActiveShooterPathTap
                                : _onMapTap,
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            onScaleEnd: _onScaleEnd,
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
                                routePoints: _routeCalculating
                                    ? const <List<double>>[]
                                    : routePoints,
                                routeRevealProgress: _routeRevealProgress,
                              ),
                              size: Size.infinite,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (moveMode && !isMobile)
                  Positioned(right: 30, bottom: 30, child: _buildJoystick()),
                if (isMobile) _buildMobileFeatureTray(subtitle),
                if (_firePlacementMode || _selectedFireHazardId != null)
                  Positioned(
                    left: 30,
                    bottom: 30,
                    child: _buildFireResizePanel(),
                  ),
                if (_earthquakePlacementMode ||
                    _selectedEarthquakeHazardId != null)
                  Positioned(
                    left: 30,
                    bottom: 30,
                    child: _buildEarthquakeResizePanel(),
                  ),
                if (_activeShooterPlacementMode ||
                    _selectedActiveShooterHazardId != null)
                  Positioned(
                    right: 30,
                    bottom: 30,
                    child: _buildActiveShooterResizePanel(),
                  ),
                if (_showNoSafeRouteOverlay) _buildNoSafeRouteOverlay(),
                if (_routeCalculating) _buildRouteLoadingOverlay(),
                if (!_routeCalculating) _buildRouteStepOverlay(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileFeatureTray(String subtitle) {
    final bottom = MediaQuery.paddingOf(context).bottom + 10;

    return Positioned(
      left: 10,
      right: 10,
      bottom: bottom,
      child: Material(
        elevation: 5,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            border: Border.all(color: const Color(0xFFC7D4E2)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: const Color(0xFF12345A),
                child: const Text(
                  'FEATURES',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 3),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: FilledButton.icon(
                          onPressed: () {
                            setState(() {
                              moveMode = false;
                              joystickX = 0;
                              joystickY = 0;
                              _mobileMoveOrigin = null;
                              followActive = false;
                            });
                          },
                          icon: const Icon(Icons.visibility, size: 18),
                          label: const Text('VIEW'),
                          style: FilledButton.styleFrom(
                            backgroundColor: !moveMode
                                ? const Color(0xFF155EEF)
                                : const Color(0xFFEAF0F7),
                            foregroundColor: !moveMode
                                ? Colors.white
                                : const Color(0xFF12345A),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: FilledButton.icon(
                          onPressed: () {
                            setState(() {
                              moveMode = true;
                              routeSelectionMode = false;
                              joystickX = 0;
                              joystickY = 0;
                              _mobileMoveOrigin = null;
                              followActive = true;
                            });
                          },
                          icon: const Icon(Icons.directions_walk, size: 18),
                          label: const Text('MOVE'),
                          style: FilledButton.styleFrom(
                            backgroundColor: moveMode
                                ? const Color(0xFF155EEF)
                                : const Color(0xFFEAF0F7),
                            foregroundColor: moveMode
                                ? Colors.white
                                : const Color(0xFF12345A),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 3, 8, 5),
                child: SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: FilledButton.icon(
                    onPressed: _showEmergencySimulationMenu,
                    icon: const Icon(Icons.emergency, size: 19),
                    label: const Text('EMERGENCY SIMULATION'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB42318),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 92),

                child: _buildActionBar(subtitle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const SizedBox.shrink();
  }

  Future<void> _showEmergencySimulationMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Emergency Simulation',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('Choose a simulated emergency scenario'),
                ),
                ListTile(
                  leading: const Icon(Icons.local_fire_department),
                  title: const Text('Fire'),
                  onTap: () => Navigator.pop(sheetContext, 'fire'),
                ),
                ListTile(
                  leading: const Icon(Icons.vibration),
                  title: const Text('Earthquake'),
                  onTap: () => Navigator.pop(sheetContext, 'earthquake'),
                ),
                ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: const Text('Active Shooter'),
                  onTap: () => Navigator.pop(sheetContext, 'activeShooter'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || choice == null) return;

    if (choice == 'fire') {
      setState(() {
        _firePlacementMode = true;
        _selectedFireHazardId = null;
        _earthquakePlacementMode = false;
        _selectedEarthquakeHazardId = null;
        _activeShooterPlacementMode = false;
        _activeShooterPathMode = false;
        _activeShooterMoving = false;
        _selectedActiveShooterHazardId = null;
        routeSelectionMode = false;
        moveMode = false;
        joystickX = 0;
        joystickY = 0;
        routeStatus = 'Fire simulation: tap the hazard location';
      });
      return;
    }

    if (choice == 'earthquake') {
      setState(() {
        _firePlacementMode = false;
        _selectedFireHazardId = null;
        _earthquakePlacementMode = true;
        _selectedEarthquakeHazardId = null;
        _activeShooterPlacementMode = false;
        _activeShooterPathMode = false;
        _activeShooterMoving = false;
        _selectedActiveShooterHazardId = null;
        routeSelectionMode = false;
        moveMode = false;
        joystickX = 0;
        joystickY = 0;
        routeStatus =
            'Earthquake simulation: tap debris or a damaged/blocked pathway';
      });
      return;
    }

    if (choice == 'activeShooter') {
      setState(() {
        _firePlacementMode = false;
        _selectedFireHazardId = null;
        _earthquakePlacementMode = false;
        _selectedEarthquakeHazardId = null;
        _activeShooterPlacementMode = true;
        _activeShooterPathMode = false;
        _activeShooterMoving = false;
        _selectedActiveShooterHazardId = null;
        routeSelectionMode = false;
        moveMode = false;
        joystickX = 0;
        joystickY = 0;
        routeStatus = 'Active Shooter: tap the shooter starting location';
      });
    }
  }

  Widget _buildActionBar(String subtitle) {
    final isCompact = MediaQuery.sizeOf(context).width < 700;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 20,
        vertical: isCompact ? 8 : 10,
      ),
      color: isCompact ? Colors.transparent : Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (navigator.parent != null) ...[
              SizedBox(
                width: isCompact ? 240 : 320,
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF183B56),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
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
            if (!isCompact)
              ElevatedButton.icon(
                onPressed: _showEmergencySimulationMenu,
                icon: const Icon(Icons.emergency),
                label: const Text('Emergency Simulation'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFB42318),
                ),
              ),
            if (navigator.hazards.isNotEmpty) ...[
              const SizedBox(width: 6),
              IconButton(
                onPressed: _clearSimulationHazards,
                tooltip: 'Clear simulation hazards',
                icon: const Icon(Icons.delete_sweep_outlined),
                color: const Color(0xFFB42318),
              ),
            ],
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () =>
                  _startRecommendedEvacuationRoute(alternative: false),
              icon: const Icon(Icons.route),
              label: const Text('ROUTE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _evacuationRouteRole != null
                    ? const Color(0xFFD9E8FF)
                    : Colors.white,
                foregroundColor: const Color(0xFF12345A),
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
      ),
    );
  }

  Widget _buildFireResizePanel() {
    final placed = _selectedFireHazardId != null;

    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0A5A5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.local_fire_department,
            color: Color(0xFFB42318),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              placed ? 'Fire hazard marked' : 'Tap map to place fire',
              style: const TextStyle(
                color: Color(0xFF7A271A),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _firePlacementMode = false;
                _selectedFireHazardId = null;
              });
            },
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildEarthquakeResizePanel() {
    return Container(
      width: 230,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF9B8A70)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: Color(0xFF6B5B45),
            size: 20,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Blocked pathway',
              style: TextStyle(
                color: Color(0xFF4B4337),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          if (_selectedEarthquakeHazardId != null)
            IconButton(
              tooltip: 'Delete blockage',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                final id = _selectedEarthquakeHazardId;
                if (id == null) return;

                navigator.removeHazard(id);

                setState(() {
                  _selectedEarthquakeHazardId = null;
                  _earthquakePlacementMode = false;
                  routeStatus =
                      'Earthquake blockage removed · recalculating route';
                });

                _rerouteAfterHazardChange();
              },
              icon: const Icon(Icons.delete_outline, size: 19),
              color: const Color(0xFF6B5B45),
            ),
          IconButton(
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _selectedEarthquakeHazardId = null;
              });
            },
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveShooterResizePanel() {
    final placed = _selectedActiveShooterHazardId != null;
    final hasPath = _activeShooterPath.length >= 2;

    return Container(
      width: 270,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8B4FE)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFF6B21A8),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  placed ? 'Moving active threat' : 'Tap shooter location',
                  style: const TextStyle(
                    color: Color(0xFF581C87),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (placed)
                IconButton(
                  tooltip: 'Delete threat',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final id = _selectedActiveShooterHazardId;
                    if (id == null) return;
                    navigator.removeHazard(id);
                    setState(() {
                      _selectedActiveShooterHazardId = null;
                      if (_activeShooterActorId == id) {
                        _activeShooterActorId = null;
                      }
                      _activeShooterPlacementMode = false;
                      _activeShooterPathMode = false;
                      _activeShooterMoving = false;
                      _activeShooterPath = const <List<double>>[];
                      routeStatus =
                          'Active threat removed · recalculating route';
                    });
                    _rerouteAfterHazardChange();
                  },
                  icon: const Icon(Icons.delete_outline, size: 19),
                ),
              IconButton(
                tooltip: 'Close',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _activeShooterPlacementMode = false;
                    _activeShooterPathMode = false;
                    _selectedActiveShooterHazardId = null;
                  });
                },
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          if (placed) ...[
            const SizedBox(height: 4),
            Text(
              _activeShooterPathMode
                  ? 'Tap movement points, then press Finish path.'
                  : hasPath
                  ? 'Movement path ready.'
                  : 'Set a movement path.',
              style: const TextStyle(color: Color(0xFF6B5A73), fontSize: 10.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _activeShooterPathMode
                        ? _finishActiveShooterPath
                        : _beginActiveShooterPath,
                    icon: Icon(
                      _activeShooterPathMode ? Icons.check : Icons.timeline,
                      size: 17,
                    ),
                    label: Text(
                      _activeShooterPathMode ? 'Finish path' : 'Set path',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: hasPath ? _toggleActiveShooterMovement : null,
                    icon: Icon(
                      _activeShooterMoving ? Icons.pause : Icons.play_arrow,
                      size: 18,
                    ),
                    label: Text(_activeShooterMoving ? 'Pause' : 'Start'),
                  ),
                ),
                IconButton(
                  onPressed: hasPath ? _resetActiveShooterMovement : null,
                  tooltip: 'Reset',
                  icon: const Icon(Icons.replay),
                ),
              ],
            ),
          ],
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

  void _rerouteAfterHazardChange() {
    final activeRole = _evacuationRouteRole;

    if (activeRole != null) {
      _startRecommendedEvacuationRoute(
        alternative: activeRole == 'alternative',
      );
      return;
    }

    if (routeTargetFloor != null && navigator.parent != null) {
      setState(() {
        _resetActiveWaypointProgress();
        _routeRefreshElapsed = 0;
        _refreshMultiFloorLeg();
      });
      _refreshCurrentStep();
      return;
    }

    final campusDestination = _campusRouteDestination;
    if (_routeAcrossBuildingExit && campusDestination != null) {
      setState(() {
        _routeRefreshElapsed = 0;

        if (navigator.parent != null && navigator.currentFloor == 1) {
          _beginCampusExitLeg();
        } else if (navigator.parent == null) {
          final refreshed = navigator.findSameFloorRoute(
            campusDestination[0],
            campusDestination[1],
          );
          routePoints = refreshed;
          routeFloor = 1;
          routeStatus = refreshed.isEmpty
              ? 'No safe route around the simulated hazard'
              : 'Route updated around the simulated hazard';
        }
      });
      _refreshCurrentStep();
      return;
    }

    if (routePoints.length >= 2) {
      final destination = List<double>.from(routePoints.last);
      final refreshed = navigator.findSameFloorRoute(
        destination[0],
        destination[1],
      );

      setState(() {
        _routeRefreshElapsed = 0;
        routePoints = refreshed;
        routeStatus = refreshed.isEmpty
            ? 'No safe route around the simulated hazard'
            : 'Route updated around the simulated hazard';
      });
      _refreshCurrentStep();
    }
  }

  void _onEarthquakeTap(TapUpDetails details) {
    if (!_earthquakePlacementMode || navigator.transition != null) return;

    final world = camera.world(<double>[
      details.localPosition.dx,
      details.localPosition.dy,
    ]);

    final blockage = navigator.addEarthquakeHazard(
      world[0],
      world[1],
      radius: _earthquakeBlockageRadius,
    );

    setState(() {
      _selectedEarthquakeHazardId = blockage.id;
      _earthquakePlacementMode = false;
      routeSelectionMode = false;
      routeStatus =
          'Earthquake blockage marked · recalculating available route';
    });

    _rerouteAfterHazardChange();
  }

  void _onFireTap(TapUpDetails details) {
    if (!_firePlacementMode || navigator.transition != null) return;

    final world = camera.world(<double>[
      details.localPosition.dx,
      details.localPosition.dy,
    ]);

    final fire = navigator.addFireHazard(
      world[0],
      world[1],
      radius: _fireHazardRadius,
    );

    setState(() {
      _selectedFireHazardId = fire.id;
      _firePlacementMode = false;
      routeSelectionMode = false;
      routeStatus =
          'Fire hazard placed · recalculating route around the hazard';
    });

    _rerouteAfterHazardChange();
  }

  void _clearSimulationHazards() {
    final activeRole = _evacuationRouteRole;
    navigator.clearHazards();
    _activeShooterActorId = null;
    _selectedActiveShooterHazardId = null;
    _activeShooterPathMode = false;
    _activeShooterMoving = false;
    _activeShooterPath = const <List<double>>[];
    _activeShooterPathIndex = 1;
    _activeShooterPathDirection = 1;

    setState(() {
      _selectedFireHazardId = null;
      _firePlacementMode = false;
      _selectedEarthquakeHazardId = null;
      _earthquakePlacementMode = false;
      _selectedActiveShooterHazardId = null;
      _activeShooterPlacementMode = false;
      routeStatus = activeRole == null
          ? 'Simulation hazards cleared'
          : 'Hazards cleared · recalculating evacuation route';
    });

    if (activeRole != null) {
      _startRecommendedEvacuationRoute(
        alternative: activeRole == 'alternative',
      );
    }
  }

  bool _activeShooterBlocksCurrentRoute() {
    final id = _activeShooterActorId;
    if (id == null || routePoints.length < 2) return false;

    final shooter = navigator.hazardById(id);
    if (shooter == null) return false;

    // Floor-1 evacuation routes can continue from a building onto campus,
    // so every Floor-1 shooter zone is relevant spatially. On upper floors,
    // require the same building/floor.
    final sameSurface = navigator.currentFloor == 1
        ? shooter.floor == 1
        : shooter.matchesSurface(navigator.parent?.id, navigator.currentFloor);
    if (!sameSurface) return false;

    final limit = shooter.radius + collisionRadius;

    double segmentDistance(
      double px,
      double py,
      List<double> a,
      List<double> b,
    ) {
      final dx = b[0] - a[0];
      final dy = b[1] - a[1];
      final length2 = dx * dx + dy * dy;

      if (length2 <= 1e-9) {
        return hypot(px - a[0], py - a[1]);
      }

      final t = (((px - a[0]) * dx + (py - a[1]) * dy) / length2)
          .clamp(0.0, 1.0)
          .toDouble();
      final cx = a[0] + dx * t;
      final cy = a[1] + dy * t;
      return hypot(px - cx, py - cy);
    }

    for (var i = 1; i < routePoints.length; i++) {
      if (segmentDistance(
            shooter.x,
            shooter.y,
            routePoints[i - 1],
            routePoints[i],
          ) <=
          limit) {
        return true;
      }
    }

    return false;
  }

  bool _updateActiveShooterMovement(double dt) {
    if (!_activeShooterMoving || _activeShooterPath.length < 2 || dt <= 0) {
      return false;
    }

    final id = _activeShooterActorId;
    if (id == null) {
      _activeShooterMoving = false;
      return false;
    }

    final shooter = navigator.hazardById(id);
    if (shooter == null) {
      _activeShooterMoving = false;
      return false;
    }

    var remaining = _activeShooterSpeed * dt;
    var moved = false;

    for (var safety = 0; safety < 8 && remaining > 1e-6; safety++) {
      if (_activeShooterPathIndex < 0 ||
          _activeShooterPathIndex >= _activeShooterPath.length) {
        _activeShooterPathIndex = _activeShooterPath.length > 1 ? 1 : 0;
        _activeShooterPathDirection = 1;
      }

      final target = _activeShooterPath[_activeShooterPathIndex];
      final dx = target[0] - shooter.x;
      final dy = target[1] - shooter.y;
      final distance = hypot(dx, dy);

      if (distance <= 1e-6) {
        _advanceActiveShooterPathIndex();
        continue;
      }

      final step = remaining < distance ? remaining : distance;
      final nx = shooter.x + dx / distance * step;
      final ny = shooter.y + dy / distance * step;

      navigator.moveHazard(id, nx, ny);
      moved = true;
      _shooterDisplacementSinceReroute += step;
      remaining -= step;

      if (step >= distance - 1e-6) {
        _advanceActiveShooterPathIndex();
      } else {
        break;
      }
    }

    return moved;
  }

  void _advanceActiveShooterPathIndex() {
    if (_activeShooterPath.length < 2) return;

    if (_activeShooterPathDirection > 0 &&
        _activeShooterPathIndex >= _activeShooterPath.length - 1) {
      _activeShooterPathDirection = -1;
    } else if (_activeShooterPathDirection < 0 &&
        _activeShooterPathIndex <= 0) {
      _activeShooterPathDirection = 1;
    }

    _activeShooterPathIndex += _activeShooterPathDirection;
    _activeShooterPathIndex = _activeShooterPathIndex.clamp(
      0,
      _activeShooterPath.length - 1,
    );
  }

  void _beginActiveShooterPath() {
    final id = _activeShooterActorId;
    if (id == null) return;

    final shooter = navigator.hazardById(id);
    if (shooter == null) return;

    setState(() {
      _activeShooterMoving = false;
      _activeShooterPathMode = true;
      _activeShooterPath = <List<double>>[
        <double>[shooter.x, shooter.y],
      ];
      _activeShooterPathIndex = 1;
      _activeShooterPathDirection = 1;
      routeStatus =
          'Shooter path: tap points on the map, then press Finish path';
    });
  }

  void _finishActiveShooterPath() {
    setState(() {
      _activeShooterPathMode = false;
      routeStatus = _activeShooterPath.length >= 2
          ? 'Shooter path ready · press Start'
          : 'Shooter path needs at least one destination point';
    });
  }

  void _onActiveShooterPathTap(TapUpDetails details) {
    if (!_activeShooterPathMode || navigator.transition != null) return;

    final id = _activeShooterActorId;
    final shooter = id == null ? null : navigator.hazardById(id);
    if (shooter == null) return;

    final activeBuildingId = navigator.parent?.id;
    final activeFloor = navigator.parent == null ? 1 : navigator.currentFloor;

    if (!shooter.matchesSurface(activeBuildingId, activeFloor)) {
      setState(() {
        routeStatus = 'Return to the shooter floor before editing its path';
      });
      return;
    }

    final world = camera.world(<double>[
      details.localPosition.dx,
      details.localPosition.dy,
    ]);

    setState(() {
      _activeShooterPath = <List<double>>[
        ..._activeShooterPath,
        <double>[world[0], world[1]],
      ];
      routeStatus =
          'Shooter path: ${_activeShooterPath.length - 1} destination point(s)';
    });
  }

  void _toggleActiveShooterMovement() {
    if (_activeShooterPath.length < 2 || _activeShooterActorId == null) {
      setState(() {
        routeStatus = 'Set at least one shooter path destination first';
      });
      return;
    }

    setState(() {
      _activeShooterPathMode = false;
      _activeShooterMoving = !_activeShooterMoving;

      if (_activeShooterMoving &&
          (_activeShooterPathIndex < 0 ||
              _activeShooterPathIndex >= _activeShooterPath.length)) {
        _activeShooterPathIndex = 1;
        _activeShooterPathDirection = 1;
      }

      routeStatus = _activeShooterMoving
          ? 'Shooter simulation moving'
          : 'Shooter paused';
    });

    _movingShooterRerouteElapsed = _movingShooterRerouteInterval;
    _shooterDisplacementSinceReroute = _shooterRerouteMinDisplacement;

    if (_evacuationRouteRole != null) {
      _updateLiveRoute(_movingShooterRerouteInterval);
    }
  }

  void _resetActiveShooterMovement() {
    final id = _activeShooterActorId;
    if (id == null || _activeShooterPath.isEmpty) return;

    final start = _activeShooterPath.first;
    navigator.moveHazard(id, start[0], start[1]);

    setState(() {
      _activeShooterMoving = false;
      _activeShooterPathMode = false;
      _activeShooterPathIndex = _activeShooterPath.length > 1 ? 1 : 0;
      _activeShooterPathDirection = 1;
      routeStatus = 'Shooter reset to path start';
    });

    if (_evacuationRouteRole != null) {
      _updateLiveRoute(1.0);
    }
  }

  void _onActiveShooterTap(TapUpDetails details) {
    if (!_activeShooterPlacementMode || navigator.transition != null) return;

    final world = camera.world(<double>[
      details.localPosition.dx,
      details.localPosition.dy,
    ]);

    final zone = navigator.addActiveShooterHazard(
      world[0],
      world[1],
      radius: _activeThreatRadius,
    );

    setState(() {
      _selectedActiveShooterHazardId = zone.id;
      _activeShooterActorId = zone.id;
      _activeShooterPlacementMode = false;
      _activeShooterMoving = false;
      _activeShooterPathMode = true;
      _activeShooterPath = <List<double>>[
        <double>[zone.x, zone.y],
      ];
      _activeShooterPathIndex = 1;
      _activeShooterPathDirection = 1;
      routeSelectionMode = false;
      routeStatus =
          'Active shooter placed · tap movement points, then Finish path';
    });

    _rerouteAfterHazardChange();
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

  String _evacuationRoleLabel() => 'Route';

  void _startRecommendedEvacuationRoute({required bool alternative}) {
    _firePlacementMode = false;
    _activeShooterPlacementMode = false;
    _resetActiveWaypointProgress();
    if (navigator.transition != null) {
      setState(() {
        routeStatus = 'Finish the stair transition first';
        routeSelectionMode = false;
      });
      return;
    }

    _beginRoutePresentation(
      alternative
          ? 'Calculating alternative path…'
          : 'Calculating evacuation route…',
    );

    final ranked = navigator.rankEvacuationGates();
    final index = alternative ? 1 : 0;

    if (ranked.length <= index) {
      final allBlocked = navigator.allEvacuationGatesBlocked;

      setState(() {
        routePoints = const <List<double>>[];
        routeStatus = allBlocked
            ? 'All modeled evacuation exits are blocked — stay at your current position'
            : alternative
            ? 'No meaningfully different alternative evacuation route is available'
            : 'No valid campus evacuation route is available';
        _evacuationGateKind = null;
        _evacuationRouteRole = null;
        _routeAcrossBuildingExit = false;
        _campusRouteDestination = null;
        routeTargetFloor = null;
        routeBuildingId = null;
        routeFloor = null;
        _routeCalculating = false;
        _routeCalculationHold = 0;
        _routeRevealAnimating = false;
        _routeRevealProgress = 1;
      });
      _refreshCurrentStep();
      return;
    }

    _startEvacuationRoute(
      ranked[index].kind,
      role: alternative ? 'alternative' : 'main',
      precomputedRoute: ranked[index].previewRoute,
    );
  }

  void _startEvacuationRoute(
    String gateKind, {
    required String role,
    List<List<double>> precomputedRoute = const <List<double>>[],
  }) {
    if (navigator.transition != null) {
      setState(() {
        routeStatus = 'Finish the stair transition first';
        routeSelectionMode = false;
      });
      _refreshCurrentStep();
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
      _refreshCurrentStep();
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

        // Preserve the no-safe-route message if every usable stair/path is
        // blocked. Only replace the status when a valid floor leg exists.
        if (routePoints.isNotEmpty) {
          routeStatus =
              '${_evacuationRoleLabel()} evacuation route → ${_gateLabel(gateKind)} · first go to Floor 1';
        }
        return;
      }

      routeTargetFloor = null;
      if (building != null) {
        if (navigator.currentFloor == 1 && precomputedRoute.isNotEmpty) {
          routePoints = precomputedRoute;
          routeFloor = 1;
          routeStatus =
              '${_evacuationRoleLabel()} evacuation route → ${_gateLabel(gateKind)}';
          return;
        }
        _beginCampusExitLeg();
        return;
      }

      final route = precomputedRoute.isNotEmpty
          ? precomputedRoute
          : navigator.findCampusGateRoute(gateKind);
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
    _refreshCurrentStep();
  }

  void _startRouteToFloorOne() {
    final building = navigator.parent;
    if (building == null || navigator.currentFloor <= 1) return;

    setState(() {
      routeSelectionMode = false;
      _resetActiveWaypointProgress();
      routeTargetFloor = 1;
      _stairTurnaroundActive = false;
      routeBuildingId = building.id;
      routeFloor = navigator.currentFloor;
      _routeRefreshElapsed = 0;
      _refreshMultiFloorLeg();
    });
    _refreshCurrentStep();
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

    if (!_routeCalculating) {
      _beginRoutePresentation('Calculating campus exit path…');
    }
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
    _refreshCurrentStep();
  }

  void _resetActiveWaypointProgress() {
    _activeWaypointKey = null;
    _activeWaypointPoints = const <List<double>>[];
    _nextWaypointIndex = 0;
    _previousWaypointPosition = null;
  }

  void _useWaypointGuideForLeg(dynamic leg) {
    final guideKey = navigator.authoredWaypointGuideKeyForSection(leg.section);
    final guidePoints = navigator.authoredWaypointGuideForSection(leg.section);

    if (guideKey == null || guidePoints.length < 2) {
      _resetActiveWaypointProgress();
      return;
    }

    if (_activeWaypointKey != guideKey) {
      _activeWaypointKey = guideKey;
      _activeWaypointPoints = <List<double>>[
        for (final point in guidePoints) <double>[point[0], point[1]],
      ];
      _nextWaypointIndex = 0;
      _previousWaypointPosition = <double>[
        navigator.markerX,
        navigator.markerY,
      ];
    }
  }

  double _waypointPointToSegmentDistance(
    List<double> point,
    List<double> a,
    List<double> b,
  ) {
    final dx = b[0] - a[0];
    final dy = b[1] - a[1];
    final length2 = dx * dx + dy * dy;

    if (length2 <= 1e-9) {
      return hypot(point[0] - a[0], point[1] - a[1]);
    }

    final t = (((point[0] - a[0]) * dx + (point[1] - a[1]) * dy) / length2)
        .clamp(0.0, 1.0)
        .toDouble();

    final px = a[0] + dx * t;
    final py = a[1] + dy * t;
    return hypot(point[0] - px, point[1] - py);
  }

  void _advanceActiveWaypointProgress(List<double> current) {
    if (_activeWaypointPoints.isEmpty ||
        _nextWaypointIndex >= _activeWaypointPoints.length) {
      _previousWaypointPosition = List<double>.from(current);
      return;
    }

    final next = _activeWaypointPoints[_nextWaypointIndex];
    final threshold = (collisionRadius * 2.0).clamp(14.0, 32.0);

    var reached =
        hypot(next[0] - current[0], next[1] - current[1]) <= threshold;

    final previous = _previousWaypointPosition;
    if (!reached && previous != null) {
      reached =
          _waypointPointToSegmentDistance(next, previous, current) <= threshold;
    }

    if (reached) {
      _nextWaypointIndex++;
    }

    _previousWaypointPosition = List<double>.from(current);
  }

  List<List<double>> _buildActiveWaypointRoute() {
    final current = <double>[navigator.markerX, navigator.markerY];

    if (_activeWaypointPoints.isEmpty ||
        _nextWaypointIndex >= _activeWaypointPoints.length) {
      return <List<double>>[current];
    }

    final next = _activeWaypointPoints[_nextWaypointIndex];

    if (navigator.transition != null) {
      return <List<double>>[
        current,
        for (var i = _nextWaypointIndex; i < _activeWaypointPoints.length; i++)
          <double>[_activeWaypointPoints[i][0], _activeWaypointPoints[i][1]],
      ];
    }

    final connector = navigator.findSameFloorRoute(next[0], next[1]);

    if (connector.isEmpty) {
      return <List<double>>[
        current,
        for (var i = _nextWaypointIndex; i < _activeWaypointPoints.length; i++)
          <double>[_activeWaypointPoints[i][0], _activeWaypointPoints[i][1]],
      ];
    }

    return <List<double>>[
      ...connector,
      for (
        var i = _nextWaypointIndex + 1;
        i < _activeWaypointPoints.length;
        i++
      )
        <double>[_activeWaypointPoints[i][0], _activeWaypointPoints[i][1]],
    ];
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

    if (!_routeCalculating) {
      _beginRoutePresentation('Calculating floor route…');
    }
    final leg = navigator.findRouteTowardFloor(targetFloor);
    if (leg == null) {
      routePoints = const [];
      routeFloor = navigator.currentFloor;
      routeStatus =
          'No safe route to Floor $targetFloor — all available stairs or pathways are blocked. Stay at your current position.';
      return;
    }

    _useWaypointGuideForLeg(leg);

    if (_activeWaypointPoints.isNotEmpty) {
      final current = <double>[navigator.markerX, navigator.markerY];
      _advanceActiveWaypointProgress(current);
      routePoints = _buildActiveWaypointRoute();
    } else {
      routePoints = leg.path;
    }

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
        if (_activeWaypointPoints.isNotEmpty) {
          final current = <double>[navigator.markerX, navigator.markerY];
          _advanceActiveWaypointProgress(current);
          routePoints = _buildActiveWaypointRoute();
        } else {
          routePoints = navigator.activeStairRouteGuide();
        }

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
        _resetActiveWaypointProgress();
        _stairTurnaroundActive = false;
        routeFloor = navigator.currentFloor;
        routeStatus = 'Reached Floor $reached';
        return;
      }

      if (routeFloor != navigator.currentFloor) {
        final completedSection = navigator.lastCompletedStair;
        final sameWellNext =
            completedSection != null &&
            navigator.hasSameWellNextStair(completedSection);

        if (sameWellNext) {
          navigator.clearStairLockForSameWell();
          routeFloor = navigator.currentFloor;
          _refreshMultiFloorLeg();
        } else {
          _stairTurnaroundActive = true;
          routeFloor = navigator.currentFloor;
        }
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

      if (_activeWaypointPoints.isNotEmpty) {
        final current = <double>[navigator.markerX, navigator.markerY];
        _advanceActiveWaypointProgress(current);
        routePoints = _buildActiveWaypointRoute();
        routeFloor = navigator.currentFloor;

        if (_nextWaypointIndex >= _activeWaypointPoints.length) {
          routeStatus = 'Continue through the stairs';
        } else {
          routeStatus =
              'Follow stair waypoint ${_nextWaypointIndex + 1}/${_activeWaypointPoints.length}';
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
        _beginRoutePresentation('Recalculating evacuation path…');
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

      // Official evacuation routes normally stay fixed because campus geometry
      // is static. A moving shooter is the exception: its unsafe circle changes
      // the routing barriers every frame.
      if (_evacuationGateKind != null) {
        _routeRefreshElapsed = 0;

        if (_activeShooterMoving) {
          _movingShooterRerouteElapsed += dt;

          final blockedNow = _activeShooterBlocksCurrentRoute();
          final periodicRefresh =
              _movingShooterRerouteElapsed >= _movingShooterRerouteInterval;
          final movedEnough = _shooterDisplacementSinceReroute >=
              _shooterRerouteMinDisplacement;

          // If the shooter enters the current blue route, reroute immediately.
          // Otherwise periodically refresh while it moves so the route can also
          // return to a shorter path after the shooter has moved away.
          // Skip periodic reroutes when the shooter has barely moved to avoid
          // redundant A* calls that produce the same (or nearly same) route.
          if (blockedNow || (periodicRefresh && movedEnough)) {
            _movingShooterRerouteElapsed = 0;
            _shooterDisplacementSinceReroute = 0;

            final refreshed = currentBuildingId == null
                ? navigator.findSameFloorRoute(destination[0], destination[1])
                : navigator.findFloor1CampusRoute(
                    destination[0],
                    destination[1],
                  );

            if (refreshed.isNotEmpty) {
              routePoints = refreshed;
              routeFloor = navigator.currentFloor;
              routeStatus =
                  '${_evacuationRoleLabel()} evacuation route → ${_gateLabel(_evacuationGateKind!)}';
            }
          }
        } else {
          _movingShooterRerouteElapsed = 0;
        }

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
    _resetActiveWaypointProgress();
    _routeRefreshElapsed = 0;
    routeTargetFloor = null;
    _stairTurnaroundActive = false;
    _routeAcrossBuildingExit = false;
    _campusRouteDestination = null;
    _evacuationGateKind = null;
    _evacuationRouteRole = null;
    _routeCalculating = false;
    _routeCalculationHold = 0;
    _routeRevealAnimating = false;
    _routeRevealProgress = 1;
    routeStatus = null;
    routeBuildingId = null;
    routeFloor = null;
    routeSelectionMode = false;
    _currentStep = null;
  }

  void _refreshCurrentStep() {
    _currentStep = RouteStepBuilder.buildCurrentStep(
      routePoints: routePoints,
      playerPosition: <double>[navigator.markerX, navigator.markerY],
      routeStatus: routeStatus,
      isStairTurnaround: _stairTurnaroundActive,
      isMultiFloor: routeTargetFloor != null,
      isCampusExit: _routeAcrossBuildingExit,
      evacuationGateKind: _evacuationGateKind,
      currentFloor: routeFloor,
      targetFloor: routeTargetFloor,
    );
  }

  Widget _buildRouteStepOverlay() {
    final step = _currentStep;
    if (step == null) return const SizedBox.shrink();

    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final bottom = isMobile ? 180.0 : 60.0;

    IconData iconData;
    Color iconColor;
    Color bgColor;
    Color borderColor;

    switch (step.icon) {
      case 'blocked':
        iconData = Icons.block;
        iconColor = const Color(0xFFB42318);
        bgColor = const Color(0xFFFEE4E2);
        borderColor = const Color(0xFFD92D20);
      case 'destination':
        iconData = Icons.flag_rounded;
        iconColor = const Color(0xFF16A34A);
        bgColor = const Color(0xFFDCFCE7);
        borderColor = const Color(0xFF16A34A);
      case 'stairs':
        iconData = Icons.stairs;
        iconColor = const Color(0xFF7C3AED);
        bgColor = const Color(0xFFF3E8FF);
        borderColor = const Color(0xFF7C3AED);
      case 'exit':
        iconData = Icons.logout;
        iconColor = const Color(0xFFEA580C);
        bgColor = const Color(0xFFFFF7ED);
        borderColor = const Color(0xFFEA580C);
      case 'turn_right':
        iconData = Icons.turn_right;
        iconColor = const Color(0xFF2563EB);
        bgColor = const Color(0xFFEFF6FF);
        borderColor = const Color(0xFF2563EB);
      case 'turn_left':
        iconData = Icons.turn_left;
        iconColor = const Color(0xFF2563EB);
        bgColor = const Color(0xFFEFF6FF);
        borderColor = const Color(0xFF2563EB);
      case 'turn_around':
        iconData = Icons.u_turn_left;
        iconColor = const Color(0xFFD97706);
        bgColor = const Color(0xFFFFFBEB);
        borderColor = const Color(0xFFD97706);
      case 'straight':
        iconData = Icons.straight;
        iconColor = const Color(0xFF2563EB);
        bgColor = const Color(0xFFEFF6FF);
        borderColor = const Color(0xFF2563EB);
      case 'recalculating':
        iconData = Icons.refresh;
        iconColor = const Color(0xFF7C3AED);
        bgColor = const Color(0xFFF3E8FF);
        borderColor = const Color(0xFF7C3AED);
      case 'floor_arrived':
        iconData = Icons.check_circle_outline;
        iconColor = const Color(0xFF16A34A);
        bgColor = const Color(0xFFDCFCE7);
        borderColor = const Color(0xFF16A34A);
      default:
        iconData = Icons.info_outline;
        iconColor = const Color(0xFF183B56);
        bgColor = const Color(0xFFF0F4F8);
        borderColor = const Color(0xFFD8E2EC);
    }

    return Positioned(
      left: 18,
      right: 18,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bgColor.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor.withValues(alpha: 0.6), width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x20000000),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(iconData, color: iconColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.instruction,
                        style: TextStyle(
                          color: const Color(0xFF183B56),
                          fontSize: isMobile ? 14 : 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (step.detail != null && step.detail!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          step.detail!,
                          style: TextStyle(
                            color: const Color(0xFF5E7184),
                            fontSize: isMobile ? 11 : 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onMapTap(TapUpDetails details) {
    if (!routeSelectionMode || moveMode) return;

    if (navigator.transition != null) {
      setState(() {
        routeStatus = 'Finish the stair transition first';
        routeSelectionMode = false;
      });
      _refreshCurrentStep();
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
      _refreshCurrentStep();
      return;
    }

    _beginRoutePresentation('Calculating path…');
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
    _refreshCurrentStep();
  }

  List<double>? _gestureAnchor;
  double _gestureScale = 1;

  void _onScaleStart(ScaleStartDetails details) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    if (isMobile && moveMode) {
      _mobileMoveOrigin = details.focalPoint;
      joystickX = 0;
      joystickY = 0;
      followActive = true;
      setState(() {});
      return;
    }

    if (moveMode) return;

    _gestureAnchor = camera.world([
      details.focalPoint.dx,
      details.focalPoint.dy,
    ]);
    _gestureScale = camera.scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    if (isMobile && moveMode) {
      final origin = _mobileMoveOrigin;
      if (origin == null) {
        _mobileMoveOrigin = details.focalPoint;
        return;
      }

      final delta = details.focalPoint - origin;
      final distance = delta.distance;

      if (distance < 6) {
        joystickX = 0;
        joystickY = 0;
      } else {
        final clampedDistance = distance.clamp(0.0, _mobileMoveRadius);
        final strength = clampedDistance / _mobileMoveRadius;
        joystickX = (delta.dx / distance) * strength;
        joystickY = (delta.dy / distance) * strength;
        followActive = true;
      }

      setState(() {});
      return;
    }

    if (moveMode || _gestureAnchor == null) return;

    camera.scale = (_gestureScale * details.scale).clamp(0.3, 3.0);
    final focal = [details.focalPoint.dx, details.focalPoint.dy];
    final current = camera.screen(_gestureAnchor!);
    camera.x += focal[0] - current[0];
    camera.y += focal[1] - current[1];
    setState(() {});
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    if (isMobile && moveMode) {
      _mobileMoveOrigin = null;
      joystickX = 0;
      joystickY = 0;
      setState(() {});
    }
  }
}
