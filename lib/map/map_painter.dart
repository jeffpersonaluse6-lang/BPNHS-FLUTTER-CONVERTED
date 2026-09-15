import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/map_item.dart';
import '../models/map_scene.dart';
import '../models/math_helper.dart';
import '../navigation/collision.dart';
import '../navigation/world_navigator.dart';

/// MapPainter — CustomPainter that renders the entire campus scene.
class MapPainter extends CustomPainter {
  final MapScene scene;
  final WorldNavigator navigator;
  final List<double> playerCenter;
  final double playerSize;
  final double collisionRadius;
  final Set<String> fadedRoofs;
  final Map<int, double> floorOpacities;

  MapPainter({
    required this.scene,
    required this.navigator,
    required this.playerCenter,
    this.playerSize = 20,
    this.collisionRadius = 26,
    this.fadedRoofs = const {},
    this.floorOpacities = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    paint.color = const Color(0xFFEDF8FA);
    canvas.drawRect(Rect.fromLTWH(0, 0, scene.width, scene.height), paint);

    final campusItems = scene.floors['Campus'] ?? [];

    for (final item in campusItems) {
      if (item.kind == 'building') continue;
      if (item.kind == 'entry_zone') continue;
      _renderItem(canvas, item, null, 1.0);
    }

    final buildings = scene.buildings();
    for (final building in buildings) {
      final opacities = navigator.floorOpacities(building);

      for (var floor = 1; floor <= building.floorCount; floor++) {
        final opacity = opacities[floor] ?? 0;
        if (opacity <= 0) continue;
        final items = scene.floorItems(building.id, floor);
        for (final item in items) {
          if (item.kind == 'entry_zone') continue;
          _renderItem(canvas, item, building, opacity);
        }
      }

      final roofItems = scene.roofItems(building.id);
      final roofOpacity = opacities[building.floorCount] ?? 1.0;
      for (final item in roofItems) {
        _renderItem(canvas, item, building, roofOpacity);
      }

      paint.color = Colors.white;
      paint.style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(building.x, building.y, building.width, building.height),
        paint,
      );
    }

    for (final item in campusItems) {
      if (item.kind != 'entry_zone') continue;
      _renderEntryZone(canvas, item, paint);
    }

    // Collision preview
    paint
      ..color = const Color(0x1606B6D4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(playerCenter[0], playerCenter[1]), collisionRadius, paint);
    paint
      ..color = const Color(0xFF06B6D4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(
        Offset(playerCenter[0], playerCenter[1]), collisionRadius, paint);

    // Player
    paint
      ..color = const Color(0xFF155EEF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(playerCenter[0], playerCenter[1]), playerSize / 2, paint);
  }

  void _renderItem(
      Canvas canvas, MapItem item, MapItem? parent, double opacity) {
    final paint = Paint();
    paint.color = _parseColor(item.color).withOpacity(opacity * item.opacity);

    switch (item.kind) {
      case 'wall':
        _renderWall(canvas, item, paint, opacity);
      case 'room':
      case 'rectangle':
      case 'floor':
        _renderRoom(canvas, item, paint, opacity);
      case 'circle_wall':
        _renderCircleWall(canvas, item, paint, opacity);
      case 'railing':
        _renderRailing(canvas, item, paint, opacity);
      case 'stairs':
        _renderStairs(canvas, item, paint, opacity);
      case 'door':
        _renderDoor(canvas, item, paint, opacity);
      case 'double_door':
        _renderDoubleDoor(canvas, item, paint, opacity);
      case 'opening':
        _renderOpening(canvas, item, paint, opacity);
      case 'window':
        _renderWindow(canvas, item, paint, opacity);
      case 'main_gate':
      case 'secondary_gate':
        _renderGate(canvas, item, paint, opacity);
      case 'gazebo_roof':
        _renderGazeboRoof(canvas, item, paint, opacity);
      case 'court_roof':
        _renderCourtRoof(canvas, item, paint, opacity);
      case 'roof':
        _renderRoof(canvas, item, paint, opacity);
      case 'building':
        _renderBuilding(canvas, item, paint, opacity);
      default:
        break;
    }
  }

  void _renderWall(Canvas canvas, MapItem item, Paint paint, double opacity) {
    final a = item.localToWorld(0, 0);
    final b = item.localToWorld(item.width, item.height);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke
      ..color = _parseColor(item.color).withOpacity(opacity * item.opacity);
    canvas.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), paint);
  }

  void _renderRoom(Canvas canvas, MapItem item, Paint paint, double opacity) {
    final p0 = item.localToWorld(0, 0);
    final p1 = item.localToWorld(item.width, 0);
    final p2 = item.localToWorld(item.width, item.height);
    final p3 = item.localToWorld(0, item.height);

    final path = Path()
      ..moveTo(p0[0], p0[1])
      ..lineTo(p1[0], p1[1])
      ..lineTo(p2[0], p2[1])
      ..lineTo(p3[0], p3[1])
      ..close();

    if (item.fill != 'none') {
      paint
        ..style = PaintingStyle.fill
        ..color = _parseColor(item.fill).withOpacity(opacity * item.opacity);
      canvas.drawPath(path, paint);
    }

    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke
      ..color = _parseColor(item.color).withOpacity(opacity * item.opacity);
    canvas.drawPath(path, paint);
  }

  void _renderCircleWall(
      Canvas canvas, MapItem item, Paint paint, double opacity) {
    final arcs = solidArcs(item);
    for (final arcRange in arcs) {
      final points = ellipsePoints(item.width, item.height,
          start: arcRange.$1, end: arcRange.$2);
      if (points.length < 2) continue;

      final path = Path();
      final first = item.localToWorld(points[0][0], points[0][1]);
      path.moveTo(first[0], first[1]);
      for (var i = 1; i < points.length; i++) {
        final p = item.localToWorld(points[i][0], points[i][1]);
        path.lineTo(p[0], p[1]);
      }
      if (arcRange.$2 - arcRange.$1 >= 2 * math.pi - 1e-9) path.close();

      if (item.fill != 'none') {
        paint
          ..style = PaintingStyle.fill
          ..color = _parseColor(item.fill).withOpacity(opacity * item.opacity);
        canvas.drawPath(path, paint);
      }

      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = item.stroke
        ..color = _parseColor(item.color).withOpacity(opacity * item.opacity);
      canvas.drawPath(path, paint);
    }
  }

  void _renderRailing(
      Canvas canvas, MapItem item, Paint paint, double opacity) {
    final a = item.localToWorld(0, 0);
    final b = item.localToWorld(item.width, item.height);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke
      ..color = _parseColor(item.color).withOpacity(opacity * item.opacity);
    canvas.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), paint);

    final length = hypot(item.width, item.height);
    if (length < 1) return;
    final count = math.max(1, math.min(300, (length / 24).floor()));
    final nx = -item.height / length;
    final ny = item.width / length;
    paint.strokeWidth = math.max(2, item.stroke * 0.5);
    for (var i = 0; i <= count; i++) {
      final lx = item.width * i / count;
      final ly = item.height * i / count;
      final pa = item.localToWorld(lx - nx * 3, ly - ny * 3);
      final pb = item.localToWorld(lx + nx * 3, ly + ny * 3);
      canvas.drawLine(Offset(pa[0], pa[1]), Offset(pb[0], pb[1]), paint);
    }
  }

  void _renderStairs(
      Canvas canvas, MapItem item, Paint paint, double opacity) {
    final p0 = item.localToWorld(0, 0);
    final p1 = item.localToWorld(item.width, 0);
    final p2 = item.localToWorld(item.width, item.height);
    final p3 = item.localToWorld(0, item.height);
    paint
      ..style = PaintingStyle.fill
      ..color = Colors.white.withOpacity(opacity * item.opacity);
    canvas.drawPath(
        Path()
          ..moveTo(p0[0], p0[1])
          ..lineTo(p1[0], p1[1])
          ..lineTo(p2[0], p2[1])
          ..lineTo(p3[0], p3[1])
          ..close(),
        paint);

    for (var i = 0; i < item.steps; i++) {
      final depth = item.stairDirection == 'up'
          ? (1 - i / math.max(1, item.steps - 1))
          : i / math.max(1, item.steps - 1);
      final shade = (248 - 62 * depth).round().clamp(0, 255);
      paint.color = Color.fromRGBO(shade, shade, shade, opacity * item.opacity);

      final ty = item.height * i / item.steps;
      final ty2 = item.height * (i + 1) / item.steps;
      final sp0 = item.localToWorld(0, ty);
      final sp1 = item.localToWorld(item.width, ty);
      final sp2 = item.localToWorld(item.width, ty2);
      final sp3 = item.localToWorld(0, ty2);
      canvas.drawPath(
          Path()
            ..moveTo(sp0[0], sp0[1])
            ..lineTo(sp1[0], sp1[1])
            ..lineTo(sp2[0], sp2[1])
            ..lineTo(sp3[0], sp3[1])
            ..close(),
          paint);
    }

    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _parseColor(item.color).withOpacity(opacity * item.opacity);
    for (var i = 1; i < item.steps; i++) {
      final y = item.height * i / item.steps;
      final la = item.localToWorld(0, y);
      final lb = item.localToWorld(item.width, y);
      canvas.drawLine(Offset(la[0], la[1]), Offset(lb[0], lb[1]), paint);
    }
  }

  void _renderDoor(
      Canvas canvas, MapItem item, Paint paint, double opacity) {
    final a = item.localToWorld(0, item.height);
    final b = item.localToWorld(item.width, item.height);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(8, item.stroke + 6)
      ..color = Colors.white.withOpacity(opacity);
    canvas.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), paint);

    final c = item.localToWorld(0, 0);
    paint
      ..strokeWidth = item.stroke
      ..color = _parseColor(item.color).withOpacity(opacity * item.opacity);
    canvas.drawLine(Offset(a[0], a[1]), Offset(c[0], c[1]), paint);

    final arcPath = Path()..moveTo(a[0], a[1]);
    for (var t = 0; t <= 32; t++) {
      final angle = t * math.pi / 32;
      final p = item.localToWorld(
          item.width * math.cos(angle),
          item.height - item.height * math.sin(angle));
      arcPath.lineTo(p[0], p[1]);
    }
    paint..style = PaintingStyle.stroke..strokeWidth = item.stroke;
    canvas.drawPath(arcPath, paint);
  }

  void _renderDoubleDoor(
      Canvas canvas, MapItem item, Paint paint, double opacity) {
    _renderSingleDoor(canvas, item, 0, item.width / 2, false, paint, opacity);
    _renderSingleDoor(canvas, item, item.width, item.width / 2, true, paint, opacity);
  }

  void _renderSingleDoor(Canvas canvas, MapItem item, double hinge,
      double radius, bool mirror, Paint paint, double opacity) {
    final sign = mirror ? -1.0 : 1.0;
    final h = item.height;

    final a = item.localToWorld(hinge, h);
    final b = item.localToWorld(hinge + sign * radius, h);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(8, item.stroke + 6)
      ..color = Colors.white.withOpacity(opacity);
    canvas.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), paint);

    final c = item.localToWorld(hinge, 0);
    paint
      ..strokeWidth = item.stroke
      ..color = _parseColor(item.color).withOpacity(opacity * item.opacity);
    canvas.drawLine(Offset(a[0], a[1]), Offset(c[0], c[1]), paint);

    final arcPath = Path()..moveTo(a[0], a[1]);
    for (var t = 0; t <= 32; t++) {
      final angle = t * math.pi / 32;
      final p = item.localToWorld(
          hinge + sign * radius * math.cos(angle), h - h * math.sin(angle));
      arcPath.lineTo(p[0], p[1]);
    }
    paint..style = PaintingStyle.stroke..strokeWidth = item.stroke;
    canvas.drawPath(arcPath, paint);
  }

  void _renderOpening(
      Canvas canvas, MapItem item, Paint paint, double opacity) {
    final p0 = item.localToWorld(0, 0);
    final p1 = item.localToWorld(item.width, 0);
    final p2 = item.localToWorld(item.width, item.height);
    final p3 = item.localToWorld(0, item.height);
    paint
      ..style = PaintingStyle.fill
      ..color = Colors.white.withOpacity(opacity * item.opacity);
    canvas.drawPath(
        Path()
          ..moveTo(p0[0], p0[1])
          ..lineTo(p1[0], p1[1])
          ..lineTo(p2[0], p2[1])
          ..lineTo(p3[0], p3[1])
          ..close(),
        paint);
  }

  void _renderWindow(
      Canvas canvas, MapItem item, Paint paint, double opacity) {
    final p0 = item.localToWorld(0, 0);
    final p1 = item.localToWorld(item.width, 0);
    final p2 = item.localToWorld(item.width, item.height);
    final p3 = item.localToWorld(0, item.height);
    paint
      ..style = PaintingStyle.fill
      ..color = Colors.white.withOpacity(opacity * item.opacity);
    canvas.drawPath(
        Path()
          ..moveTo(p0[0], p0[1])
          ..lineTo(p1[0], p1[1])
          ..lineTo(p2[0], p2[1])
          ..lineTo(p3[0], p3[1])
          ..close(),
        paint);

    final midA = item.localToWorld(0, item.height / 2);
    final midB = item.localToWorld(item.width, item.height / 2);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke
      ..color = _parseColor(item.color).withOpacity(opacity * item.opacity);
    canvas.drawLine(Offset(midA[0], midA[1]), Offset(midB[0], midB[1]), paint);
  }

  void _renderGate(
      Canvas canvas, MapItem item, Paint paint, double opacity) {
    final color = _parseColor(item.color).withOpacity(opacity * item.opacity);
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
      ..strokeWidth = math.max(3, item.stroke * 0.65);

    if (item.kind == 'main_gate') {
      if (item.gateOpen) {
        _drawLine(item, post, y, post + w * 0.28, math.max(0, y - h * 0.42), canvas, paint);
        _drawLine(item, w - post, y, w - post - w * 0.28, math.max(0, y - h * 0.42), canvas, paint);
      } else {
        _drawLine(item, post, y, w / 2, y, canvas, paint);
        _drawLine(item, w / 2, y, w - post, y, canvas, paint);
      }
    } else {
      if (item.gateOpen) {
        _drawLine(item, post, y, post + w * 0.55, math.max(0, y - h * 0.42), canvas, paint);
      } else {
        _drawLine(item, post, y, w - post, y, canvas, paint);
      }
    }
  }

  Path _quad(MapItem item, double x0, double y0, double x1, double y1,
      double x2, double y2, double x3, double y3) {
    final p0 = item.localToWorld(x0, y0);
    final p1 = item.localToWorld(x1, y1);
    final p2 = item.localToWorld(x2, y2);
    final p3 = item.localToWorld(x3, y3);
    return Path()
      ..moveTo(p0[0], p0[1])
      ..lineTo(p1[0], p1[1])
      ..lineTo(p2[0], p2[1])
      ..lineTo(p3[0], p3[1])
      ..close();
  }

  void _drawLine(MapItem item, double x0, double y0, double x1, double y1,
      Canvas canvas, Paint paint) {
    final a = item.localToWorld(x0, y0);
    final b = item.localToWorld(x1, y1);
    canvas.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), paint);
  }

  void _renderGazeboRoof(
      Canvas canvas, MapItem item, Paint paint, double opacity) {
    final w = item.width;
    final h = item.height;
    final fillColor = _parseColor(item.fill).withOpacity(opacity * item.opacity);

    paint
      ..style = PaintingStyle.fill
      ..color = fillColor;
    for (var n = 0; n < 8; n++) {
      final arcPoints = ellipsePointPairs(w, h,
          start: n * math.pi / 4, end: (n + 1) * math.pi / 4);
      if (arcPoints.isEmpty) continue;
      final center = item.localToWorld(w / 2, h / 2);
      final path = Path()..moveTo(center[0], center[1]);
      for (final p in arcPoints) {
        final wp = item.localToWorld(p.$1, p.$2);
        path.lineTo(wp[0], wp[1]);
      }
      path.close();
      canvas.drawPath(path, paint);
    }

    final color = _parseColor(item.color).withOpacity(opacity * item.opacity);
    _drawEllipse(canvas, item, w, h, paint, color);

    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke
      ..color = color;
    for (var n = 0; n < 8; n++) {
      final a = n * math.pi / 4;
      _drawLine(item, w / 2, h / 2, w / 2 + w / 2 * math.cos(a),
          h / 2 + h / 2 * math.sin(a), canvas, paint);
    }
  }

  void _renderCourtRoof(
      Canvas canvas, MapItem item, Paint paint, double opacity) {
    final w = item.width;
    final h = item.height;
    final fillColor = _parseColor(item.fill).withOpacity(opacity * item.opacity);

    paint
      ..style = PaintingStyle.fill
      ..color = fillColor;
    canvas.drawPath(_quad(item, 0, 0, w, 0, w, h, 0, h), paint);

    final color = _parseColor(item.color).withOpacity(opacity * item.opacity);
    final horizontal = w >= h;
    final count = math.max(4, math.min(80, (horizontal ? w : h) / 48).ceil().toDouble());
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, item.stroke * 0.5)
      ..color = color;
    for (var n = 1; n < count; n++) {
      final p = n / count;
      if (horizontal) {
        _drawLine(item, w * p, 0, w * p, h, canvas, paint);
      } else {
        _drawLine(item, 0, h * p, w, h * p, canvas, paint);
      }
    }

    paint.strokeWidth = math.max(0.5, item.stroke * 0.6);
    if (horizontal) {
      _drawLine(item, 0, h / 2, w, h / 2, canvas, paint);
    } else {
      _drawLine(item, w / 2, 0, w / 2, h, canvas, paint);
    }
  }

  void _renderRoof(
      Canvas canvas, MapItem item, Paint paint, double opacity) {
    _renderRoom(canvas, item, paint, opacity);
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
      ..strokeWidth = item.stroke;
    for (final corner in corners) {
      final target = corner[0] < item.width / 2 ? first : last;
      _drawLine(item, corner[0], corner[1], target[0], target[1], canvas, paint);
    }
  }

  void _renderBuilding(
      Canvas canvas, MapItem item, Paint paint, double opacity) {
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke
      ..color = _parseColor(item.color).withOpacity(opacity * item.opacity);
    canvas.drawPath(_quad(item, 0, 0, item.width, 0, item.width, item.height, 0, item.height), paint);
  }

  void _renderEntryZone(Canvas canvas, MapItem item, Paint paint) {
    paint
      ..style = PaintingStyle.fill
      ..color = const Color(0x30155EEF);
    canvas.drawPath(_quad(item, 0, 0, item.width, 0, item.width, item.height, 0, item.height), paint);
  }

  void _drawEllipse(Canvas canvas, MapItem item, double w, double h,
      Paint paint, Color color) {
    final points = ellipsePointPairs(w, h);
    if (points.isEmpty) return;
    final path = Path();
    final first = item.localToWorld(points[0].$1, points[0].$2);
    path.moveTo(first[0], first[1]);
    for (var i = 1; i < points.length; i++) {
      final p = item.localToWorld(points[i].$1, points[i].$2);
      path.lineTo(p[0], p[1]);
    }
    path.close();
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = item.stroke
      ..color = color;
    canvas.drawPath(path, paint);
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
    return oldDelegate.playerCenter[0] != playerCenter[0] ||
        oldDelegate.playerCenter[1] != playerCenter[1] ||
        oldDelegate.playerSize != playerSize ||
        oldDelegate.fadedRoofs != fadedRoofs ||
        oldDelegate.floorOpacities != floorOpacities;
  }
}
