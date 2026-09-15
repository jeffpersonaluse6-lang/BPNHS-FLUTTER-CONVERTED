import 'dart:math' as math;
import '../models/spatial_index.dart';

/// RuntimeIndex — items + spatial index.
class RuntimeIndex<T> {
  final List<T> items;
  final BoundsIndex index;

  RuntimeIndex(this.items, List<(double, double, double, double)> boxes,
      {int cellSize = 256})
      : index = BoundsIndex(boxes, cellSize: cellSize);

  List<T> query(double px, double py,
      {double padding = 0, double? px2, double? py2}) {
    final minX = math.min(px, px2 ?? px);
    final minY = math.min(py, py2 ?? py);
    final maxX = math.max(px, px2 ?? px);
    final maxY = math.max(py, py2 ?? py);
    final results = index.query(
      (minX, minY, maxX, maxY),
      padding: [padding, padding],
    );
    return results.map((i) => items[i]).toList();
  }
}
