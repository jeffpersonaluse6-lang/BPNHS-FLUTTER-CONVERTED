import 'dart:convert';
import 'dart:io';

import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'startup player surface is detected before evacuation routing',
    () async {
      final raw =
          jsonDecode(await File('assets/map_workspace.json').readAsString())
              as Map<String, dynamic>;
      final scene = MapScene.fromJson(raw);
      final navigator = WorldNavigator(scene, collisionRadius: 4);

      expect(navigator.parent, isNull);
      expect(
        navigator.rankEvacuationGates(),
        isEmpty,
        reason: 'this reproduces the pre-fix false no-route startup state',
      );

      navigator.update(navigator.markerX, navigator.markerY);

      expect(navigator.parent, isNotNull);
      expect(navigator.parent!.text, 'CR');
      expect(navigator.currentFloor, 1);
      expect(
        navigator.rankEvacuationGates(),
        isNotEmpty,
        reason: 'the initial player position must have an evacuation route',
      );
    },
  );
}
