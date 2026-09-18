import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('waypoint routing is bound to a physical StairSection', () {
    final source = File(
      'lib/navigation/world_navigator.dart',
    ).readAsStringSync();

    expect(source, contains('_routeWaypointGuideForSection('));
    expect(
      source,
      contains('nearestSection?.id != section.id'),
      reason:
          'Each authored guide must be assigned to its nearest physical stair.',
    );
    expect(
      source,
      isNot(contains('_routeWaypointGuideForConnection(')),
      reason:
          'The old floor-pair-only lookup caused every stair to reuse guide #1.',
    );
  });

  test('blocked authored path can fall through to another stair candidate', () {
    final source = File(
      'lib/navigation/world_navigator.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('_pathClearOfSurfaceHazards('),
      reason: 'A fire/unsafe zone must reject the blocked authored guide.',
    );
    expect(
      source,
      contains('for (final section in eligible)'),
      reason:
          'After one blocked guide is rejected, the other eligible stair must still be evaluated.',
    );
  });
}
