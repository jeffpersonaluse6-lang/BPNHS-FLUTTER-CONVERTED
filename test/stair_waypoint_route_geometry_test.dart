import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/navigation/stair_waypoint_guides.dart';

void main() {
  test('authored waypoint guide keeps exact order and reverses cleanly', () {
    const guide = StairWaypointGuide(
      id: 'g',
      buildingId: 'b',
      floorA: 1,
      floorB: 2,
      pointsAtoB: <List<double>>[
        <double>[10, 10],
        <double>[20, 40],
        <double>[55, 40],
        <double>[70, 80],
      ],
    );

    expect(guide.orderedPoints(1, 2), <List<double>>[
      <double>[10, 10],
      <double>[20, 40],
      <double>[55, 40],
      <double>[70, 80],
    ]);

    expect(guide.orderedPoints(2, 1), <List<double>>[
      <double>[70, 80],
      <double>[55, 40],
      <double>[20, 40],
      <double>[10, 10],
    ]);
  });

  test('editor-generated waypoint data exists', () {
    expect(stairWaypointGuides, isNotEmpty);
    for (final guide in stairWaypointGuides) {
      expect(guide.pointsAtoB.length, greaterThanOrEqualTo(2));
      expect(guide.floorA, isNot(guide.floorB));
    }
  });
}
