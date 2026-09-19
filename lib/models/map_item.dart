import 'dart:math' as math;
import 'circle_opening.dart';
import 'math_helper.dart';

/// MapItem — matches Python DraftItem from drafting/models.py exactly.
class MapItem {
  final String kind;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final double stroke;
  final String color;
  final String fill;
  final String text;
  final double fontSize;
  final int steps;
  final bool mirrored;
  final bool blocking;
  final String? imageSrc;
  final String? layerStyle;
  final String? opens;
  final String subtitle;
  final int floorCount;
  final String? groupId;
  final String? parentId;
  final String stairDirection;
  final int? stairTo;
  final List<int> completedFloors;
  final double approachDistance;
  final bool fadeWhenObstructing;
  final double? floorWidth;
  final double? floorHeight;
  final double floorOriginX;
  final double floorOriginY;
  final bool freeBuild;
  final int? stairFrom;
  final bool stairEnabled;
  final double? stairSpeedMultiplier;
  final double? collisionThickness;
  final double opacity;
  final List<CircleOpening> circleOpenings;
  final bool gateOpen;
  final String id;

  const MapItem({
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.stroke = 2,
    this.color = '#111111',
    this.fill = 'none',
    this.text = 'Room',
    this.fontSize = 18,
    this.steps = 12,
    this.mirrored = false,
    this.blocking = true,
    this.imageSrc,
    this.layerStyle,
    this.opens,
    this.subtitle = '',
    this.floorCount = 1,
    this.groupId,
    this.parentId,
    this.stairDirection = 'up',
    this.stairTo,
    this.completedFloors = const [],
    this.approachDistance = 80,
    this.fadeWhenObstructing = true,
    this.floorWidth,
    this.floorHeight,
    this.floorOriginX = 0,
    this.floorOriginY = 0,
    this.freeBuild = false,
    this.stairFrom,
    this.stairEnabled = true,
    this.stairSpeedMultiplier,
    this.collisionThickness,
    this.opacity = 1,
    this.circleOpenings = const [],
    this.gateOpen = false,
    required this.id,
  });

  factory MapItem.fromJson(Map<String, dynamic> json) {
    return MapItem(
      kind: json['kind'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      stroke: (json['stroke'] as num?)?.toDouble() ?? 2,
      color: json['color'] as String? ?? '#111111',
      fill: json['fill'] as String? ?? 'none',
      text: json['text'] as String? ?? 'Room',
      fontSize: (json['font_size'] as num?)?.toDouble() ?? 18,
      steps: (json['steps'] as num?)?.toInt() ?? 12,
      mirrored: json['mirrored'] as bool? ?? false,
      blocking: json['blocking'] as bool? ?? true,
      imageSrc: json['image_src'] as String?,
      layerStyle: json['layer_style'] as String?,
      opens: json['opens'] as String?,
      subtitle: json['subtitle'] as String? ?? '',
      floorCount: (json['floor_count'] as num?)?.toInt() ?? 1,
      groupId: json['group_id'] as String?,
      parentId: json['parent_id'] as String?,
      stairDirection: json['stair_direction'] as String? ?? 'up',
      stairTo: (json['stair_to'] as num?)?.toInt(),
      completedFloors:
          (json['completed_floors'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      approachDistance: (json['approach_distance'] as num?)?.toDouble() ?? 80,
      fadeWhenObstructing: json['fade_when_obstructing'] as bool? ?? true,
      floorWidth: (json['floor_width'] as num?)?.toDouble(),
      floorHeight: (json['floor_height'] as num?)?.toDouble(),
      floorOriginX: (json['floor_origin_x'] as num?)?.toDouble() ?? 0,
      floorOriginY: (json['floor_origin_y'] as num?)?.toDouble() ?? 0,
      freeBuild: json['free_build'] as bool? ?? false,
      stairFrom: (json['stair_from'] as num?)?.toInt(),
      stairEnabled: json['stair_enabled'] as bool? ?? true,
      stairSpeedMultiplier: (json['stair_speed_multiplier'] as num?)
          ?.toDouble(),
      collisionThickness: (json['collision_thickness'] as num?)?.toDouble(),
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
      circleOpenings:
          (json['circle_openings'] as List<dynamic>?)
              ?.map((e) => CircleOpening.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      gateOpen: json['gate_open'] as bool? ?? false,
      id: json['id'] as String,
    );
  }

  List<double> localToWorld(double lx, double ly) {
    double mx = mirrored ? width - lx : lx;
    final angle = rotation * math.pi / 180;
    return [
      x + mx * math.cos(angle) - ly * math.sin(angle),
      y + mx * math.sin(angle) + ly * math.cos(angle),
    ];
  }

  List<double> worldToLocal(double wx, double wy) {
    final angle = -rotation * math.pi / 180;
    final dx = wx - x;
    final dy = wy - y;
    final lx = dx * math.cos(angle) - dy * math.sin(angle);
    final ly = dx * math.sin(angle) + dy * math.cos(angle);
    return [mirrored ? width - lx : lx, ly];
  }

  bool contains(double px, double py, {double tolerance = 8}) {
    final local = worldToLocal(px, py);
    final lx = local[0];
    final ly = local[1];

    if (kind == 'circle_wall' || kind == 'gazebo_roof') {
      final rx = width / 2;
      final ry = height / 2;
      final normalized = hypot((lx - rx) / rx, (ly - ry) / ry);
      final reach = math.max(tolerance, stroke / 2) / math.min(rx, ry);
      return kind == 'circle_wall'
          ? (normalized - 1).abs() <= reach
          : normalized <= 1 + reach;
    }
    if (kind == 'wall' || kind == 'line' || kind == 'railing') {
      final length2 = width * width + height * height;
      final t = length2 > 0 ? (lx * width + ly * height) / length2 : 0.0;
      final clampedT = t.clamp(0.0, 1.0);
      final radius = kind == 'railing' ? stroke / 2 + 2 : stroke / 2;
      return hypot(lx - clampedT * width, ly - clampedT * height) <=
          math.max(tolerance, radius);
    }
    return -tolerance <= lx &&
        lx <= width + tolerance &&
        -tolerance <= ly &&
        ly <= height + tolerance;
  }
}
