import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  double collisionRadius = 26;

  double joystickX = 0;
  double joystickY = 0;
  bool moveMode = false;
  bool followActive = false;
  final Set<String> fadedRoofs = {};

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
    return LayoutBuilder(
      builder: (context, constraints) {
        camera.width = constraints.maxWidth;
        camera.height = constraints.maxHeight;
        _updateRoofFading();

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
                          child: GestureDetector(
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            child: CustomPaint(
                              painter: MapPainter(
                                scene: widget.scene,
                                navigator: navigator,
                                playerCenter: [
                                  navigator.markerX,
                                  navigator.markerY,
                                ],
                                playerSize: playerSize,
                                collisionRadius: collisionRadius,
                                fadedRoofs: fadedRoofs,
                                floorOpacities: navigator.parent != null
                                    ? navigator.floorOpacities(navigator.parent!)
                                    : {},
                              ),
                              size: Size.infinite,
                            ),
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
      },
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
                  moveMode
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
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: () {
              moveMode = !moveMode;
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

  void _updateRoofFading() {
    fadedRoofs.clear();
    if (navigator.parent == null) {
      for (final building in widget.scene.buildings()) {
        final opacity = navigator.roofOpacity(
            building, navigator.markerX, navigator.markerY);
        if (opacity < 1) fadedRoofs.add(building.id);
      }
    }
  }
}
