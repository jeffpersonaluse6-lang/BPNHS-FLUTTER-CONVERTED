import 'dart:math' as math;

/// Simple grid index for bounding-box lookups.
/// Matches Python spatial.py BoundsIndex exactly.
class BoundsIndex {
  final List<(double, double, double, double)> boxes;
  final int cellSize;
  final Map<(int, int), List<int>> cells = {};
  final List<int> large = [];

  BoundsIndex(this.boxes, {this.cellSize = 128}) {
    for (var i = 0; i < boxes.length; i++) {
      final range = cellRange(boxes[i]);
      final cellCount = (range[2] - range[0] + 1) * (range[3] - range[1] + 1);
      if (cellCount > 64) {
        large.add(i);
        continue;
      }
      for (var x = range[0]; x <= range[2]; x++) {
        for (var y = range[1]; y <= range[3]; y++) {
          cells.putIfAbsent((x, y), () => []).add(i);
        }
      }
    }
  }

  /// Returns [x0, y0, x1, y1] as cell coordinates.
  List<int> cellRange((double, double, double, double) box) {
    return [
      (box.$1 / cellSize).floor(),
      (box.$2 / cellSize).floor(),
      (box.$3 / cellSize).floor(),
      (box.$4 / cellSize).floor(),
    ];
  }

  List<int> query((double, double, double, double) box,
      {List<double> padding = const [0, 0]}) {
    final expanded = (
      box.$1 - padding[0],
      box.$2 - padding[1],
      box.$3 + padding[0],
      box.$4 + padding[1],
    );
    final range = cellRange(expanded);
    final x0 = range[0];
    final y0 = range[1];
    final x1 = range[2];
    final y1 = range[3];
    final candidates = Set<int>.from(large);

    if ((x1 - x0 + 1) * (y1 - y0 + 1) > math.max(64, cells.length * 2)) {
      for (final entry in cells.entries) {
        final key = entry.key;
        final values = entry.value;
        if (key.$1 >= x0 && key.$1 <= x1 && key.$2 >= y0 && key.$2 <= y1) {
          candidates.addAll(values);
        }
      }
    } else {
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          candidates.addAll(cells[(x, y)] ?? []);
        }
      }
    }

    return candidates.where((n) {
      final b = boxes[n];
      return b.$3 >= expanded.$1 &&
          b.$1 <= expanded.$3 &&
          b.$4 >= expanded.$2 &&
          b.$2 <= expanded.$4;
    }).toList();
  }
}
