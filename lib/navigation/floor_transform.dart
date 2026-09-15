import 'dart:math' as math;
import '../models/map_item.dart';

/// FloorTransform — cached transform for building floors.
/// Matches Python FloorTransform from navigation/runtime_cache.py.
class FloorTransform {
  final MapItem parent;
  final double sx;
  final double sy;
  final double cosine;
  final double sine;

  const FloorTransform(
      this.parent, this.sx, this.sy, this.cosine, this.sine);

  factory FloorTransform.build(MapItem parent) {
    final sx = parent.width / (parent.floorWidth ?? 1436);
    final sy = parent.height / (parent.floorHeight ?? 751);
    final angle = parent.rotation * math.pi / 180;
    return FloorTransform(parent, sx, sy, math.cos(angle), math.sin(angle));
  }

  /// Project local floor coordinates to world coordinates.
  List<double> project(double x, double y) {
    final p = parent;
    var px = (x - p.floorOriginX) * sx;
    var py = (y - p.floorOriginY) * sy;
    if (p.mirrored) px = p.width - px;
    return [
      p.x + px * cosine - py * sine,
      p.y + px * sine + py * cosine,
    ];
  }

  /// Unproject world coordinates to local floor coordinates.
  List<double> unproject(double wx, double wy) {
    final p = parent;
    final dx = wx - p.x;
    final dy = wy - p.y;
    var x = dx * cosine + dy * sine;
    final y = -dx * sine + dy * cosine;
    if (p.mirrored) x = p.width - x;
    return [x / sx + p.floorOriginX, y / sy + p.floorOriginY];
  }
}
