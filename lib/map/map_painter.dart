import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/map_item.dart';
import '../models/map_scene.dart';
import '../models/math_helper.dart';
import '../navigation/collision.dart';
import '../navigation/floor_transform.dart';
import '../navigation/hazard.dart';
import '../navigation/world_navigator.dart';

const double _defaultFloorWidth = 1436;
const double _defaultFloorHeight = 751;

class MapPainter extends CustomPainter {
  final MapScene scene;
  final WorldNavigator navigator;
  final double cameraX;
  final double cameraY;
  final double cameraScale;
  final double cameraRotation;
  final List<double> playerCenter;
  final double playerSize;
  final double collisionRadius;
  final List<List<double>> routePoints;
  final double routeRevealProgress;

  MapPainter({
    required this.scene,
    required this.navigator,
    this.cameraX = 0,
    this.cameraY = 0,
    this.cameraScale = 1,
    this.cameraRotation = 0,
    required this.playerCenter,
    this.playerSize = 20,
    this.collisionRadius = 10,
    this.routePoints = const [],
    this.routeRevealProgress = 1,
  });

  FloorTransform? _ft;
  double _scale = 1;
  double _layerOpacity = 1;

  List<double> _wx(double lx, double ly, MapItem item) {
    final world = item.localToWorld(lx, ly);
    final ft = _ft;
    if (ft != null) return ft.project(world[0], world[1]);
    return world;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(cameraX, cameraY);
    canvas.scale(cameraScale);
    canvas.rotate(cameraRotation);

    final paint = Paint();
    paint.color = const Color(0xFFEDF8FA);
    canvas.drawRect(Rect.fromLTWH(0, 0, scene.width, scene.height), paint);

    final campusItems = scene.floors['Campus'] ?? [];
    final campusIndex = OpeningIndex(campusItems);

    for (final item in campusItems) {
      if (item.kind == 'building' || item.kind == 'entry_zone') continue;
      _ft = null;
      _scale = 1;
      if (roofKinds.contains(item.kind)) {
        _layerOpacity = _roofObjectOpacity(item, null);
        _renderItem(canvas, item, null);
      } else {
        _layerOpacity = 1;
        _renderItem(canvas, item, campusIndex.forWall(item));
      }
    }

    for (final building in scene.buildings()) {
      _renderBuilding(canvas, building);
    }

    _drawHazards(canvas);
    _drawRoute(canvas);

    canvas.restore();

    _drawPlayer(canvas, size);
  }

  void _renderBuilding(Canvas canvas, MapItem building) {
    final opacities = navigator.floorOpacities(building);
    final ft = navigator.floorTransform(building);
    final (sx, sy) = _floorScale(building);
    final bscale = math.min(sx, sy);

    if (!building.freeBuild &&
        building.imageSrc == null &&
        building.layerStyle == null) {
      final fw = building.floorWidth ?? _defaultFloorWidth;
      final fh = building.floorHeight ?? _defaultFloorHeight;
      final p0 = building.localToWorld(0, 0);
      final p1 = building.localToWorld(fw, 0);
      final p2 = building.localToWorld(fw, fh);
      final p3 = building.localToWorld(0, fh);
      final w0 = ft.project(p0[0], p0[1]);
      final w1 = ft.project(p1[0], p1[1]);
      final w2 = ft.project(p2[0], p2[1]);
      final w3 = ft.project(p3[0], p3[1]);

      final paint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawPath(
        Path()
          ..moveTo(w0[0], w0[1])
          ..lineTo(w1[0], w1[1])
          ..lineTo(w2[0], w2[1])
          ..lineTo(w3[0], w3[1])
          ..close(),
        paint,
      );
    }

    for (var floor = 1; floor <= building.floorCount; floor++) {
      final opacity = opacities[floor] ?? 0;
      if (opacity <= 0) continue;
      final items = scene.floorItems(building.id, floor);
      final floorIndex = OpeningIndex(items);
      for (final item in items) {
        if (item.kind == 'entry_zone') continue;
        _ft = ft;
        _scale = bscale;
        if (roofKinds.contains(item.kind)) {
          _layerOpacity = _roofObjectOpacity(item, building);
          _renderItem(canvas, item, null);
        } else {
          _layerOpacity = opacity;
          _renderItem(canvas, item, floorIndex.forWall(item));
        }
      }
    }

    final roofItems = scene.roofItems(building.id);
    final roofOp = navigator.roofOpacity(
      building,
      navigator.markerX,
      navigator.markerY,
    );
    if (roofOp > 0) {
      final roofIndex = OpeningIndex(roofItems);
      for (final item in roofItems) {
        _ft = ft;
        _scale = bscale;
        if (roofKinds.contains(item.kind)) {
          _layerOpacity = _roofObjectOpacity(item, building);
          _renderItem(canvas, item, null);
        } else {
          _layerOpacity = roofOp;
          _renderItem(canvas, item, roofIndex.forWall(item));
        }
      }
    }
  }

  void _drawHazards(Canvas canvas) {
    if (navigator.visibleHazards.isEmpty) return;

    final safeScale = cameraScale.abs() < 1e-9 ? 1.0 : cameraScale.abs();

    for (final hazard in navigator.visibleHazards) {
      final center = Offset(hazard.x, hazard.y);
      final isEarthquake = hazard.kind == HazardKind.earthquake;
      final isFire = hazard.kind == HazardKind.fire;

      if (!isEarthquake) {
        final safetyFill = Paint()
          ..color = const Color(0x12F59E0B)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          center,
          hazard.radius + hazardSafetyClearance,
          safetyFill,
        );

        final safetyBorder = Paint()
          ..color = const Color(0x88F59E0B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / safeScale;
        canvas.drawCircle(
          center,
          hazard.radius + hazardSafetyClearance,
          safetyBorder,
        );
      }

      final Color fillColor;
      final Color borderColor;
      final Color coreColor;
      final Color labelColor;
      final String label;

      if (isEarthquake) {
        fillColor = const Color(0x558B7355);
        borderColor = const Color(0xFF6B5B45);
        coreColor = const Color(0xFF4B4337);
        labelColor = const Color(0xFF4B4337);
        label = 'BLOCKED';
      } else if (isFire) {
        fillColor = const Color(0x44DC2626);
        borderColor = const Color(0xFFE11D48);
        coreColor = const Color(0xFFF97316);
        labelColor = const Color(0xFF991B1B);
        label = 'FIRE';
      } else {
        fillColor = const Color(0x337C3AED);
        borderColor = const Color(0xFFA855F7);
        coreColor = const Color(0xFF581C87);
        labelColor = const Color(0xFF581C87);
        label = 'ACTIVE THREAT';
      }

      final fill = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, hazard.radius, fill);

      final border = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 / safeScale;
      canvas.drawCircle(center, hazard.radius, border);

      if (isEarthquake) {
        final crossPaint = Paint()
          ..color = coreColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 / safeScale
          ..strokeCap = StrokeCap.round;
        final d = 10 / safeScale;
        canvas.drawLine(
          Offset(hazard.x - d, hazard.y - d),
          Offset(hazard.x + d, hazard.y + d),
          crossPaint,
        );
        canvas.drawLine(
          Offset(hazard.x + d, hazard.y - d),
          Offset(hazard.x - d, hazard.y + d),
          crossPaint,
        );
      } else {
        final core = Paint()
          ..color = coreColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 11 / safeScale, core);
      }

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: labelColor,
            fontSize: 11 / safeScale,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          hazard.x - textPainter.width / 2,
          hazard.y + hazard.radius + 6 / safeScale,
        ),
      );
    }
  }

  void _drawRoute(Canvas canvas) {
    if (routePoints.length < 2) return;

    final safeScale = cameraScale.abs() < 1e-9 ? 1.0 : cameraScale.abs();
    final progress = routeRevealProgress.clamp(0.0, 1.0);

    var totalLength = 0.0;
    final segmentLengths = <double>[];
    for (var i = 1; i < routePoints.length; i++) {
      final dx = routePoints[i][0] - routePoints[i - 1][0];
      final dy = routePoints[i][1] - routePoints[i - 1][1];
      final length = math.sqrt(dx * dx + dy * dy);
      segmentLengths.add(length);
      totalLength += length;
    }
    if (totalLength < 1e-9) return;

    final revealLength = totalLength * progress;
    var drawnLength = 0.0;

    final path = Path()..moveTo(routePoints.first[0], routePoints.first[1]);

    for (var i = 1; i < routePoints.length; i++) {
      final segmentLength = segmentLengths[i - 1];
      if (segmentLength < 1e-9) continue;

      final remaining = revealLength - drawnLength;
      if (remaining <= 0) break;

      if (remaining >= segmentLength) {
        path.lineTo(routePoints[i][0], routePoints[i][1]);
        drawnLength += segmentLength;
        continue;
      }

      final t = (remaining / segmentLength).clamp(0.0, 1.0);
      final x =
          routePoints[i - 1][0] +
          (routePoints[i][0] - routePoints[i - 1][0]) * t;
      final y =
          routePoints[i - 1][1] +
          (routePoints[i][1] - routePoints[i - 1][1]) * t;
      path.lineTo(x, y);
      drawnLength = revealLength;
      break;
    }

    final routePaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 / safeScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, routePaint);

    // Destination appears only after the animated route has reached it.
    if (progress < 0.999) return;

    final destination = routePoints.last;
    final markerPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(destination[0], destination[1]),
      8 / safeScale,
      markerPaint,
    );
    markerPaint
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(destination[0], destination[1]),
      3 / safeScale,
      markerPaint,
    );
  }

  void _drawPlayer(Canvas canvas, Size size) {
    final cosR = math.cos(cameraRotation);
    final sinR = math.sin(cameraRotation);
    final sx =
        cameraX +
        cameraScale * (cosR * playerCenter[0] - sinR * playerCenter[1]);
    final sy =
        cameraY +
        cameraScale * (sinR * playerCenter[0] + cosR * playerCenter[1]);
    final center = Offset(sx, sy);

    final paint = Paint();
    paint
      ..color = const Color(0x1606B6D4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, collisionRadius, paint);
    paint
      ..color = const Color(0xFF06B6D4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, collisionRadius, paint);
    paint
      ..color = const Color(0xFF155EEF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, playerSize / 2, paint);
  }

  (double, double) _floorScale(MapItem? parent) {
    if (parent == null) return (1.0, 1.0);
    final fw = parent.floorWidth ?? _defaultFloorWidth;
    final fh = parent.floorHeight ?? _defaultFloorHeight;
    return (parent.width / fw, parent.height / fh);
  }

  double _roofObjectOpacity(MapItem item, MapItem? parent) {
    if (!item.fadeWhenObstructing) return item.opacity;

    final List<List<double>> points;
    if (item.kind == 'gazebo_roof') {
      points = ellipsePoints(item.width, item.height);
    } else {
      points = [
        [0, 0],
        [item.width, 0],
        [item.width, item.height],
        [0, item.height],
      ];
    }

    final worldPoints = <List<double>>[];
    for (final p in points) {
      worldPoints.add(_wx(p[0], p[1], item));
    }

    final area = PolygonBarrier(worldPoints);
    final px = playerCenter[0];
    final py = playerCenter[1];

    final distance = _polygonDistance(area, px, py);
    final factor = item.approachDistance > 0
        ? math.min(1.0, distance / item.approachDistance)
        : (distance > 0 ? 1.0 : 0.0);

    return item.opacity * factor;
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

  void _renderItem(Canvas canvas, MapItem item, List<MapItem>? openings) {
    final paint = Paint();
    paint.color = _parseColor(
      item.color,
    ).withValues(alpha: _layerOpacity * item.opacity);

    switch (item.kind) {
      case 'wall':
        _renderWallFilled(canvas, item, paint, openings);
      case 'room':
      case 'rectangle':
      case 'floor':
      case 'road':
      case 'evacuation_area':
        _renderRoomFilled(canvas, item, paint, openings);
      case 'circle_wall':
        _renderCircleWallFilled(canvas, item, paint, openings);
      case 'railing':
        _renderRailing(canvas, item, paint);
      case 'stairs':
        _renderStairs(canvas, item, paint);
      case 'door':
        _renderDoor(canvas, item, paint);
      case 'double_door':
        _renderDoubleDoor(canvas, item, paint);
      case 'opening':
        _renderOpening(canvas, item, paint);
      case 'window':
        _renderWindow(canvas, item, paint);
      case 'main_gate':
      case 'secondary_gate':
        _renderGate(canvas, item, paint);
      case 'gazebo_roof':
        _renderGazeboRoof(canvas, item, paint);
      case 'court_roof':
        _renderCourtRoof(canvas, item, paint);
      case 'roof':
        _renderRoof(canvas, item, paint, openings);
      case 'ellipse':
        _renderEllipse(canvas, item, paint);
      default:
        break;
    }
  }

  void _renderWallFilled(
    Canvas canvas,
    MapItem item,
    Paint paint,
    List<MapItem>? openings,
  ) {
    if (item.stroke <= 0) return;
    final sections = wallSections(item, openings: openings);
    paint
      ..style = PaintingStyle.fill
      ..color = _parseColor(
        item.color,
      ).withValues(alpha: _layerOpacity * item.opacity);
    for (final section in sections) {
      final polygon = wallPolygon(section);
      if (polygon.isEmpty) continue;
      final path = Path();
      final first = _projectPoint(polygon[0][0], polygon[0][1]);
      path.moveTo(first[0], first[1]);
      for (var i = 1; i < polygon.length; i++) {
        final p = _projectPoint(polygon[i][0], polygon[i][1]);
        path.lineTo(p[0], p[1]);
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  void _renderRoomFilled(
    Canvas canvas,
    MapItem item,
    Paint paint,
    List<MapItem>? openings,
  ) {
    if (item.fill != 'none') {
      final p0 = _wx(0, 0, item);
      final p1 = _wx(item.width, 0, item);
      final p2 = _wx(item.width, item.height, item);
      final p3 = _wx(0, item.height, item);
      paint
        ..style = PaintingStyle.fill
        ..color = _parseColor(
          item.fill,
        ).withValues(alpha: _layerOpacity * item.opacity);
      canvas.drawPath(
        Path()
          ..moveTo(p0[0], p0[1])
          ..lineTo(p1[0], p1[1])
          ..lineTo(p2[0], p2[1])
          ..lineTo(p3[0], p3[1])
          ..close(),
        paint,
      );
    }

    if (item.stroke > 0) {
      final sections = wallSections(item, openings: openings);
      paint
        ..style = PaintingStyle.fill
        ..color = _parseColor(
          item.color,
        ).withValues(alpha: _layerOpacity * item.opacity);
      for (final section in sections) {
        final polygon = wallPolygon(section);
        if (polygon.isEmpty) continue;
        final path = Path();
        final first = _projectPoint(polygon[0][0], polygon[0][1]);
        path.moveTo(first[0], first[1]);
        for (var i = 1; i < polygon.length; i++) {
          final p = _projectPoint(polygon[i][0], polygon[i][1]);
          path.lineTo(p[0], p[1]);
        }
        path.close();
        canvas.drawPath(path, paint);
      }
    }
  }

  void _renderCircleWallFilled(
    Canvas canvas,
    MapItem item,
    Paint paint,
    List<MapItem>? openings,
  ) {
    if (item.stroke <= 0) return;
    final radius = math.max(0.5, item.stroke / 2);
    for (final arcRange in solidArcs(item, openings: openings)) {
      final outer = ellipsePoints(
        item.width + 2 * radius,
        item.height + 2 * radius,
        start: arcRange.$1,
        end: arcRange.$2,
      );
      final iw = math.max(0.001, item.width - 2 * radius);
      final ih = math.max(0.001, item.height - 2 * radius);
      final inner = ellipsePoints(iw, ih, start: arcRange.$1, end: arcRange.$2);
      final polyPoints = <List<double>>[];
      for (final p in outer) {
        polyPoints.add(_wx(p[0] - radius, p[1] - radius, item));
      }
      for (var i = inner.length - 1; i >= 0; i--) {
        polyPoints.add(
          _wx(
            inner[i][0] + (item.width - iw) / 2,
            inner[i][1] + (item.height - ih) / 2,
            item,
          ),
        );
      }
      if (polyPoints.length < 3) continue;
      final path = Path()..moveTo(polyPoints[0][0], polyPoints[0][1]);
      for (var i = 1; i < polyPoints.length; i++) {
        path.lineTo(polyPoints[i][0], polyPoints[i][1]);
      }
      path.close();
      paint
        ..style = PaintingStyle.fill
        ..color = _parseColor(
          item.color,
        ).withValues(alpha: _layerOpacity * item.opacity);
      canvas.drawPath(path, paint);
    }
  }

  void _renderRailing(Canvas canvas, MapItem item, Paint paint) {
    final length = hypot(item.width, item.height);
    if (length < 1) return;
    final nx = -item.height / length;
    final ny = item.width / length;
    final gap = math.max(2.0, math.min(8.0, item.stroke / 2));
    final railWidth = math.max(2.0, item.stroke * 0.4);
    final postWidth = math.max(2.5, item.stroke * 0.5);

    paint
      ..style = PaintingStyle.stroke
      ..color = _parseColor(
        item.color,
      ).withValues(alpha: _layerOpacity * item.opacity);
    for (final sign in [-1.0, 1.0]) {
      paint.strokeWidth = railWidth * _scale;
      final a = _wx(sign * nx * gap, sign * ny * gap, item);
      final b = _wx(
        item.width + sign * nx * gap,
        item.height + sign * ny * gap,
        item,
      );
      canvas.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), paint);
    }

    final count = math.max(1, math.min(300, (length / 24).floor()));
    paint.strokeWidth = postWidth * _scale;
    for (var i = 0; i <= count; i++) {
      final lx = item.width * i / count;
      final ly = item.height * i / count;
      final pa = _wx(lx - nx * (gap + 1), ly - ny * (gap + 1), item);
      final pb = _wx(lx + nx * (gap + 1), ly + ny * (gap + 1), item);
      canvas.drawLine(Offset(pa[0], pa[1]), Offset(pb[0], pb[1]), paint);
    }
  }

  void _renderStairs(Canvas canvas, MapItem item, Paint paint) {
    final p0 = _wx(0, 0, item);
    final p1 = _wx(item.width, 0, item);
    final p2 = _wx(item.width, item.height, item);
    final p3 = _wx(0, item.height, item);
    paint
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: _layerOpacity * item.opacity);
    canvas.drawPath(
      Path()
        ..moveTo(p0[0], p0[1])
        ..lineTo(p1[0], p1[1])
        ..lineTo(p2[0], p2[1])
        ..lineTo(p3[0], p3[1])
        ..close(),
      paint,
    );

    for (var i = 0; i < item.steps; i++) {
      final depth = item.stairDirection == 'up'
          ? (1 - i / math.max(1, item.steps - 1))
          : i / math.max(1, item.steps - 1);
      final shade = (248 - 62 * depth).round().clamp(0, 255);
      paint.color = Color.fromRGBO(
        shade,
        shade,
        shade,
        _layerOpacity * item.opacity,
      );

      final ty = item.height * i / item.steps;
      final ty2 = item.height * (i + 1) / item.steps;
      final sp0 = _wx(0, ty, item);
      final sp1 = _wx(item.width, ty, item);
      final sp2 = _wx(item.width, ty2, item);
      final sp3 = _wx(0, ty2, item);
      canvas.drawPath(
        Path()
          ..moveTo(sp0[0], sp0[1])
          ..lineTo(sp1[0], sp1[1])
          ..lineTo(sp2[0], sp2[1])
          ..lineTo(sp3[0], sp3[1])
          ..close(),
        paint,
      );
    }

    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, item.stroke * 0.5) * _scale
      ..color = _parseColor(
        item.color,
      ).withValues(alpha: _layerOpacity * item.opacity);
    for (var i = 1; i < item.steps; i++) {
      final y = item.height * i / item.steps;
      final la = _wx(0, y, item);
      final lb = _wx(item.width, y, item);
      canvas.drawLine(Offset(la[0], la[1]), Offset(lb[0], lb[1]), paint);
    }
  }

  void _renderDoor(Canvas canvas, MapItem item, Paint paint) {
    final a = _wx(0, item.height, item);
    final b = _wx(item.width, item.height, item);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(8, item.stroke + 6) * _scale
      ..color = Colors.white.withValues(alpha: _layerOpacity * item.opacity);
    canvas.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), paint);

    final c = _wx(0, 0, item);
    paint
      ..strokeWidth = item.stroke * _scale
      ..color = _parseColor(
        item.color,
      ).withValues(alpha: _layerOpacity * item.opacity);
    canvas.drawLine(Offset(a[0], a[1]), Offset(c[0], c[1]), paint);

    final arcPath = Path()..moveTo(a[0], a[1]);
    for (var t = 0; t <= 128; t++) {
      final angle = t * math.pi / 128;
      final p = _wx(
        item.width * math.cos(angle),
        item.height - item.height * math.sin(angle),
        item,
      );
      arcPath.lineTo(p[0], p[1]);
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke * _scale;
    canvas.drawPath(arcPath, paint);
  }

  void _renderDoubleDoor(Canvas canvas, MapItem item, Paint paint) {
    _renderSingleDoor(canvas, item, 0, item.width / 2, false, paint);
    _renderSingleDoor(canvas, item, item.width, item.width / 2, true, paint);
  }

  void _renderSingleDoor(
    Canvas canvas,
    MapItem item,
    double hinge,
    double radius,
    bool mirror,
    Paint paint,
  ) {
    final sign = mirror ? -1.0 : 1.0;
    final h = item.height;

    final a = _wx(hinge, h, item);
    final b = _wx(hinge + sign * radius, h, item);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(8, item.stroke + 6) * _scale
      ..color = Colors.white.withValues(alpha: _layerOpacity * item.opacity);
    canvas.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), paint);

    final c = _wx(hinge, 0, item);
    paint
      ..strokeWidth = item.stroke * _scale
      ..color = _parseColor(
        item.color,
      ).withValues(alpha: _layerOpacity * item.opacity);
    canvas.drawLine(Offset(a[0], a[1]), Offset(c[0], c[1]), paint);

    final arcPath = Path()..moveTo(a[0], a[1]);
    for (var t = 0; t <= 128; t++) {
      final angle = t * math.pi / 128;
      final p = _wx(
        hinge + sign * radius * math.cos(angle),
        h - h * math.sin(angle),
        item,
      );
      arcPath.lineTo(p[0], p[1]);
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke * _scale;
    canvas.drawPath(arcPath, paint);
  }

  void _renderOpening(Canvas canvas, MapItem item, Paint paint) {
    final p0 = _wx(0, 0, item);
    final p1 = _wx(item.width, 0, item);
    final p2 = _wx(item.width, item.height, item);
    final p3 = _wx(0, item.height, item);
    paint
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: _layerOpacity * item.opacity);
    canvas.drawPath(
      Path()
        ..moveTo(p0[0], p0[1])
        ..lineTo(p1[0], p1[1])
        ..lineTo(p2[0], p2[1])
        ..lineTo(p3[0], p3[1])
        ..close(),
      paint,
    );
  }

  void _renderWindow(Canvas canvas, MapItem item, Paint paint) {
    final p0 = _wx(0, 0, item);
    final p1 = _wx(item.width, 0, item);
    final p2 = _wx(item.width, item.height, item);
    final p3 = _wx(0, item.height, item);
    paint
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: _layerOpacity * item.opacity);
    canvas.drawPath(
      Path()
        ..moveTo(p0[0], p0[1])
        ..lineTo(p1[0], p1[1])
        ..lineTo(p2[0], p2[1])
        ..lineTo(p3[0], p3[1])
        ..close(),
      paint,
    );

    final midA = _wx(0, item.height / 2, item);
    final midB = _wx(item.width, item.height / 2, item);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke * _scale
      ..color = _parseColor(
        item.color,
      ).withValues(alpha: _layerOpacity * item.opacity);
    canvas.drawLine(Offset(midA[0], midA[1]), Offset(midB[0], midB[1]), paint);
  }

  void _renderGate(Canvas canvas, MapItem item, Paint paint) {
    final color = _parseColor(
      item.color,
    ).withValues(alpha: _layerOpacity * item.opacity);
    final post = math.max(6.0, math.min(18.0, item.width * 0.07));
    final h = item.height;
    final w = item.width;

    paint
      ..style = PaintingStyle.fill
      ..color = color;
    final lp = _quad(item, 0, 0, post, 0, post, h, 0, h);
    canvas.drawPath(lp, paint);
    final rp = _quad(item, w - post, 0, w, 0, w, h, w - post, h);
    canvas.drawPath(rp, paint);

    final y = h / 2;
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3, item.stroke * 0.65) * _scale;

    if (item.kind == 'main_gate') {
      if (item.gateOpen) {
        _drawLine(
          item,
          post,
          y,
          post + w * 0.28,
          math.max(0, y - h * 0.42),
          canvas,
          paint,
        );
        _drawLine(
          item,
          w - post,
          y,
          w - post - w * 0.28,
          math.max(0, y - h * 0.42),
          canvas,
          paint,
        );
      } else {
        _drawLine(item, post, y, w / 2, y, canvas, paint);
        _drawLine(item, w / 2, y, w - post, y, canvas, paint);
      }
    } else {
      if (item.gateOpen) {
        _drawLine(
          item,
          post,
          y,
          post + w * 0.55,
          math.max(0, y - h * 0.42),
          canvas,
          paint,
        );
      } else {
        _drawLine(item, post, y, w - post, y, canvas, paint);
      }
    }
  }

  Path _quad(
    MapItem item,
    double x0,
    double y0,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    final p0 = _wx(x0, y0, item);
    final p1 = _wx(x1, y1, item);
    final p2 = _wx(x2, y2, item);
    final p3 = _wx(x3, y3, item);
    return Path()
      ..moveTo(p0[0], p0[1])
      ..lineTo(p1[0], p1[1])
      ..lineTo(p2[0], p2[1])
      ..lineTo(p3[0], p3[1])
      ..close();
  }

  void _drawLine(
    MapItem item,
    double x0,
    double y0,
    double x1,
    double y1,
    Canvas canvas,
    Paint paint,
  ) {
    final a = _wx(x0, y0, item);
    final b = _wx(x1, y1, item);
    canvas.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), paint);
  }

  void _renderGazeboRoof(Canvas canvas, MapItem item, Paint paint) {
    final w = item.width;
    final h = item.height;
    final fillColor = _parseColor(
      item.fill,
    ).withValues(alpha: _layerOpacity * item.opacity);

    paint
      ..style = PaintingStyle.fill
      ..color = fillColor;
    for (var n = 0; n < 8; n++) {
      final arcPoints = ellipsePointPairs(
        w,
        h,
        start: n * math.pi / 4,
        end: (n + 1) * math.pi / 4,
      );
      if (arcPoints.isEmpty) continue;
      final center = _wx(w / 2, h / 2, item);
      final path = Path()..moveTo(center[0], center[1]);
      for (final p in arcPoints) {
        final wp = _wx(p.$1, p.$2, item);
        path.lineTo(wp[0], wp[1]);
      }
      path.close();
      canvas.drawPath(path, paint);
    }

    _drawEllipse(
      canvas,
      item,
      w,
      h,
      paint,
      _parseColor(item.color).withValues(alpha: _layerOpacity * item.opacity),
    );

    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke * _scale
      ..color = _parseColor(
        item.color,
      ).withValues(alpha: _layerOpacity * item.opacity);
    for (var n = 0; n < 8; n++) {
      final a = n * math.pi / 4;
      _drawLine(
        item,
        w / 2,
        h / 2,
        w / 2 + w / 2 * math.cos(a),
        h / 2 + h / 2 * math.sin(a),
        canvas,
        paint,
      );
    }

    final innerW = w * 0.92;
    final innerH = h * 0.92;
    final innerPts = ellipsePointPairs(innerW, innerH);
    if (innerPts.isNotEmpty) {
      final innerPath = Path();
      final f = _wx(
        w / 2 + innerPts[0].$1 - w * 0.46,
        h / 2 + innerPts[0].$2 - h * 0.46,
        item,
      );
      innerPath.moveTo(f[0], f[1]);
      for (var i = 1; i < innerPts.length; i++) {
        final p = _wx(
          w / 2 + innerPts[i].$1 - w * 0.46,
          h / 2 + innerPts[i].$2 - h * 0.46,
          item,
        );
        innerPath.lineTo(p[0], p[1]);
      }
      innerPath.close();
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = item.stroke * _scale;
      canvas.drawPath(innerPath, paint);
    }

    final dotPts = ellipsePointPairs(w * 0.08, h * 0.08);
    if (dotPts.isNotEmpty) {
      final dotPath = Path();
      final f = _wx(
        w / 2 + dotPts[0].$1 - w * 0.04,
        h / 2 + dotPts[0].$2 - h * 0.04,
        item,
      );
      dotPath.moveTo(f[0], f[1]);
      for (var i = 1; i < dotPts.length; i++) {
        final p = _wx(
          w / 2 + dotPts[i].$1 - w * 0.04,
          h / 2 + dotPts[i].$2 - h * 0.04,
          item,
        );
        dotPath.lineTo(p[0], p[1]);
      }
      dotPath.close();
      paint
        ..style = PaintingStyle.fill
        ..color = _parseColor(
          item.fill,
        ).withValues(alpha: _layerOpacity * item.opacity);
      canvas.drawPath(dotPath, paint);
    }
  }

  void _renderCourtRoof(Canvas canvas, MapItem item, Paint paint) {
    final w = item.width;
    final h = item.height;
    final fillColor = _parseColor(
      item.fill,
    ).withValues(alpha: _layerOpacity * item.opacity);

    paint
      ..style = PaintingStyle.fill
      ..color = fillColor;
    canvas.drawPath(_quad(item, 0, 0, w, 0, w, h, 0, h), paint);

    final color = _parseColor(
      item.color,
    ).withValues(alpha: _layerOpacity * item.opacity);
    final horizontal = w >= h;
    final count = math.max(
      4,
      math.min(80, (horizontal ? w : h) / 48).ceil().toDouble(),
    );
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, item.stroke * 0.5) * _scale
      ..color = color;
    for (var n = 1; n < count; n++) {
      final p = n / count;
      if (horizontal) {
        _drawLine(item, w * p, 0, w * p, h, canvas, paint);
      } else {
        _drawLine(item, 0, h * p, w, h * p, canvas, paint);
      }
    }

    paint.strokeWidth = math.max(0.5, item.stroke * 0.6) * _scale;
    if (horizontal) {
      _drawLine(item, 0, h / 2, w, h / 2, canvas, paint);
    } else {
      _drawLine(item, w / 2, 0, w / 2, h, canvas, paint);
    }

    for (final p in [0.06, 0.94]) {
      paint.strokeWidth = math.max(0.5, item.stroke * 0.6) * _scale;
      if (horizontal) {
        _drawLine(item, 0, h * p, w, h * p, canvas, paint);
      } else {
        _drawLine(item, w * p, 0, w * p, h, canvas, paint);
      }
    }
  }

  void _renderRoof(
    Canvas canvas,
    MapItem item,
    Paint paint,
    List<MapItem>? openings,
  ) {
    _renderRoomFilled(canvas, item, paint, openings);

    final inset = math.min(item.width, item.height) / 2;
    List<double> first, last;
    if (item.width >= item.height) {
      first = [inset, item.height / 2];
      last = [item.width - inset, item.height / 2];
    } else {
      first = [item.width / 2, inset];
      last = [item.width / 2, item.height - inset];
    }
    final corners = [
      [0.0, 0.0],
      [0.0, item.height],
      [item.width, 0.0],
      [item.width, item.height],
    ];
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke * _scale
      ..color = _parseColor(
        item.color,
      ).withValues(alpha: _layerOpacity * item.opacity);
    for (final corner in corners) {
      final target = corner[0] < item.width / 2 ? first : last;
      _drawLine(
        item,
        corner[0],
        corner[1],
        target[0],
        target[1],
        canvas,
        paint,
      );
    }

    if (first[0] != last[0] || first[1] != last[1]) {
      _drawLine(item, first[0], first[1], last[0], last[1], canvas, paint);
    }
  }

  void _renderEllipse(Canvas canvas, MapItem item, Paint paint) {
    final points = ellipsePointPairs(item.width, item.height);
    if (points.isEmpty) return;
    final path = Path();
    final first = _wx(points[0].$1, points[0].$2, item);
    path.moveTo(first[0], first[1]);
    for (var i = 1; i < points.length; i++) {
      final p = _wx(points[i].$1, points[i].$2, item);
      path.lineTo(p[0], p[1]);
    }
    path.close();

    if (item.fill != 'none') {
      paint
        ..style = PaintingStyle.fill
        ..color = _parseColor(
          item.fill,
        ).withValues(alpha: _layerOpacity * item.opacity);
      canvas.drawPath(path, paint);
    }

    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke * _scale
      ..color = _parseColor(
        item.color,
      ).withValues(alpha: _layerOpacity * item.opacity);
    canvas.drawPath(path, paint);
  }

  void _drawEllipse(
    Canvas canvas,
    MapItem item,
    double w,
    double h,
    Paint paint,
    Color color,
  ) {
    final points = ellipsePointPairs(w, h);
    if (points.isEmpty) return;
    final path = Path();
    final first = _wx(points[0].$1, points[0].$2, item);
    path.moveTo(first[0], first[1]);
    for (var i = 1; i < points.length; i++) {
      final p = _wx(points[i].$1, points[i].$2, item);
      path.lineTo(p[0], p[1]);
    }
    path.close();
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke * _scale
      ..color = color;
    canvas.drawPath(path, paint);
  }

  List<double> _projectPoint(double x, double y) {
    final ft = _ft;
    if (ft != null) return ft.project(x, y);
    return [x, y];
  }

  Color _parseColor(String hex) {
    if (hex == 'none' || hex.isEmpty) return Colors.transparent;
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return Colors.black;
  }

  @override
  bool shouldRepaint(covariant MapPainter oldDelegate) {
    return oldDelegate.cameraX != cameraX ||
        oldDelegate.cameraY != cameraY ||
        oldDelegate.cameraScale != cameraScale ||
        oldDelegate.cameraRotation != cameraRotation ||
        oldDelegate.playerCenter[0] != playerCenter[0] ||
        oldDelegate.playerCenter[1] != playerCenter[1] ||
        oldDelegate.playerSize != playerSize ||
        oldDelegate.collisionRadius != collisionRadius ||
        !identical(oldDelegate.routePoints, routePoints);
  }
}
