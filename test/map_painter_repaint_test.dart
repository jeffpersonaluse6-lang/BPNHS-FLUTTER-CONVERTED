import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/map/map_painter.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';

void main() {
  final scene = MapScene(
    name: 'Painter repaint state',
    width: 500,
    height: 400,
    floors: const {'Campus': []},
  );

  test('route reveal progress invalidates the painter', () {
    final navigator = WorldNavigator(
      scene,
      markerX: 100,
      markerY: 100,
      collisionRadius: 4,
    );
    final oldPainter = MapPainter(
      scene: scene,
      navigator: navigator,
      playerCenter: const [100, 100],
      routeRevealProgress: 0,
    );
    final newPainter = MapPainter(
      scene: scene,
      navigator: navigator,
      playerCenter: const [100, 100],
      routeRevealProgress: 0.5,
    );

    expect(newPainter.shouldRepaint(oldPainter), isTrue);
  });

  test(
    'hazard changes invalidate the painter while the player is stationary',
    () {
      final navigator = WorldNavigator(
        scene,
        markerX: 100,
        markerY: 100,
        collisionRadius: 4,
      );
      final oldPainter = MapPainter(
        scene: scene,
        navigator: navigator,
        playerCenter: const [100, 100],
      );

      navigator.addFireHazard(200, 200);

      final newPainter = MapPainter(
        scene: scene,
        navigator: navigator,
        playerCenter: const [100, 100],
      );

      expect(newPainter.shouldRepaint(oldPainter), isTrue);
    },
  );
}
