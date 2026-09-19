import 'dart:math' as math;
import '../models/math_helper.dart';

/// SmoothCamera — frame-independent camera with smooth following.
class SmoothCamera {
  double width;
  double height;
  double x;
  double y;
  double scale;
  double rotation;

  SmoothCamera({
    this.width = 1368,
    this.height = 710,
    this.x = 0,
    this.y = 0,
    this.scale = 1,
    this.rotation = 0,
  });

  List<double> screen(List<double> point) {
    final c = math.cos(rotation);
    final s = math.sin(rotation);
    return [
      x + scale * (c * point[0] - s * point[1]),
      y + scale * (s * point[0] + c * point[1]),
    ];
  }

  List<double> world(List<double> point) {
    final wx = (point[0] - x) / scale;
    final wy = (point[1] - y) / scale;
    final c = math.cos(rotation);
    final s = math.sin(rotation);
    return [c * wx + s * wy, -s * wx + c * wy];
  }

  void center(List<double> point) {
    final sx = screen(point);
    x += width / 2 - sx[0];
    y += height / 2 - sx[1];
  }

  bool visible(List<double> point, {double diameter = 20}) {
    final sx = screen(point);
    final margin = diameter * scale / 2 + 16;
    return sx[0] >= margin &&
        sx[0] <= width - margin &&
        sx[1] >= margin &&
        sx[1] <= height - margin;
  }

  bool follow(
    List<double> point,
    double dt, {
    bool moving = false,
    double diameter = 20,
    bool? guard,
  }) {
    if (dt <= 0) return false;
    final sx = screen(point);
    final ex = width / 2 - sx[0];
    final ey = height / 2 - sx[1];
    final beforeX = x;
    final beforeY = y;
    final margin = diameter * scale / 2 + 24;
    final limitsX = math.max(0.0, width / 2 - margin);
    final limitsY = math.max(0.0, height / 2 - margin);
    final isVisible = visible(point, diameter: diameter);
    final useGuard = guard ?? isVisible;

    var rate = moving ? 5.0 : 7.0;
    if (useGuard) {
      final urgency = math.max(
        ex.abs() / math.max(1, limitsX),
        ey.abs() / math.max(1, limitsY),
      );
      rate += 12 * math.pow(math.max(0.0, urgency - 0.65), 2).toDouble();
    }

    final alpha = -math.exp(-rate * dt) + 1;
    x += ex * alpha;
    y += ey * alpha;

    if (useGuard) {
      final psx = screen(point);
      x +=
          math.max(-limitsX, math.min(limitsX, psx[0] - width / 2)) -
          (psx[0] - width / 2);
      y +=
          math.max(-limitsY, math.min(limitsY, psx[1] - height / 2)) -
          (psx[1] - height / 2);
    }

    if (hypot(ex, ey) < 0.05) {
      x += ex * (1 - alpha);
      y += ey * (1 - alpha);
    }

    return hypot(x - beforeX, y - beforeY) > 1e-6;
  }
}
