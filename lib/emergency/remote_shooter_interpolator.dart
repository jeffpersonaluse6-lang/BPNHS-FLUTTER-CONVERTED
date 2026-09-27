import 'dart:ui';

/// Interpolates remote shooter render positions between authoritative snapshots.
/// Collision and routing continue to use the latest server-reported position.
class RemoteShooterInterpolator {
  final Duration duration;
  final Map<String, _ShooterTween> _tweens = <String, _ShooterTween>{};
  final Map<String, Offset> _positions = <String, Offset>{};

  RemoteShooterInterpolator({
    this.duration = const Duration(milliseconds: 160),
  });

  Map<String, Offset> get positions =>
      Map<String, Offset>.unmodifiable(_positions);

  bool get isAnimating => _tweens.isNotEmpty;

  void retarget(String id, Offset from, Offset to) {
    final start = _positions[id] ?? from;
    if ((to - start).distance < 0.1 || duration.inMicroseconds <= 0) {
      _tweens.remove(id);
      _positions.remove(id);
      return;
    }
    _positions[id] = start;
    _tweens[id] = _ShooterTween(from: start, to: to);
  }

  /// Advances all active tweens, returning true while another repaint is
  /// needed. Finished entries are removed so the map falls back to the exact
  /// authoritative coordinates stored on the hazard.
  bool advance(double seconds) {
    if (_tweens.isEmpty || seconds <= 0) return _tweens.isNotEmpty;

    var changed = false;
    final finished = <String>[];
    for (final entry in _tweens.entries) {
      final tween = entry.value;
      tween.elapsed += seconds;
      changed = true;
      final progress = (tween.elapsed / duration.inMicroseconds * 1e6).clamp(
        0.0,
        1.0,
      );
      if (progress >= 1) {
        finished.add(entry.key);
      } else {
        _positions[entry.key] = Offset.lerp(tween.from, tween.to, progress)!;
      }
    }
    for (final id in finished) {
      _tweens.remove(id);
      _positions.remove(id);
    }
    return changed || _tweens.isNotEmpty;
  }

  void retainOnly(Set<String> ids) {
    _tweens.removeWhere((id, _) => !ids.contains(id));
    _positions.removeWhere((id, _) => !ids.contains(id));
  }

  void clear() {
    _tweens.clear();
    _positions.clear();
  }
}

class _ShooterTween {
  final Offset from;
  final Offset to;
  double elapsed = 0;

  _ShooterTween({required this.from, required this.to});
}
