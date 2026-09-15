import 'dart:math' as math;

/// Math helper — Dart doesn't have math.hypot.
double hypot(double x, double y) => math.sqrt(x * x + y * y);
