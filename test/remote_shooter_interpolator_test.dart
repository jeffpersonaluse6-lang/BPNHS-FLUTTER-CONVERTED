import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/emergency/remote_shooter_interpolator.dart';

void main() {
  test(
    'smoothly interpolates a remote shooter and repaints its final frame',
    () {
      final interpolator = RemoteShooterInterpolator(
        duration: const Duration(milliseconds: 200),
      );
      interpolator.retarget(
        'remote:shooter',
        const Offset(0, 0),
        const Offset(100, 40),
      );

      expect(interpolator.advance(0.1), isTrue);
      expect(interpolator.positions['remote:shooter'], const Offset(50, 20));
      // Completion must still request one final repaint so the display snaps
      // exactly to the authoritative hazard location.
      expect(interpolator.advance(0.1), isTrue);
      expect(interpolator.positions, isEmpty);
      expect(interpolator.advance(0.1), isFalse);
    },
  );

  test(
    'retarget starts from the current visual position, not the last packet',
    () {
      final interpolator = RemoteShooterInterpolator(
        duration: const Duration(milliseconds: 200),
      );
      interpolator.retarget(
        'remote:shooter',
        const Offset(0, 0),
        const Offset(100, 0),
      );
      interpolator.advance(0.1);
      interpolator.retarget(
        'remote:shooter',
        const Offset(0, 0),
        const Offset(200, 0),
      );
      interpolator.advance(0.1);

      expect(interpolator.positions['remote:shooter'], const Offset(125, 0));
    },
  );
}
