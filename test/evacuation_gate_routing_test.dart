import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/models/map_item.dart';
import 'package:flutter_runtime/models/map_scene.dart';
import 'package:flutter_runtime/navigation/world_navigator.dart';

MapItem gate(String kind, double x) => MapItem(
  kind: kind,
  x: x,
  y: 540,
  width: 120,
  height: 24,
  stroke: kind == 'main_gate' ? 10 : 8,
  color: '#1F2937',
  fill: 'none',
  text: kind == 'main_gate' ? 'Main Gate' : 'Secondary Gate',
  blocking: true,
  gateOpen: false,
  id: '$kind-id',
);

void main() {
  MapScene scene() => MapScene(
    name: 'Gate routing test',
    width: 1000,
    height: 600,
    floors: {
      'Campus': [gate('main_gate', 700), gate('secondary_gate', 150)],
    },
  );

  test('finds both configured campus evacuation gates', () {
    final nav = WorldNavigator(
      scene(),
      markerX: 500,
      markerY: 250,
      collisionRadius: 10,
    );
    expect(nav.campusGate('main_gate')?.text, 'Main Gate');
    expect(nav.campusGate('secondary_gate')?.text, 'Secondary Gate');
    expect(nav.campusGate('not_a_gate'), isNull);
  });

  test('gate approach points stay on the inside-campus side', () {
    final nav = WorldNavigator(
      scene(),
      markerX: 500,
      markerY: 250,
      collisionRadius: 10,
    );
    final main = nav.campusGateApproach('main_gate');
    final secondary = nav.campusGateApproach('secondary_gate');

    expect(main, isNotNull);
    expect(secondary, isNotNull);
    expect(main![1], lessThan(540));
    expect(secondary![1], lessThan(540));
  });

  test('main and alternative gate routes are independently reachable', () {
    final nav = WorldNavigator(
      scene(),
      markerX: 500,
      markerY: 250,
      collisionRadius: 10,
    );

    final main = nav.findCampusGateRoute('main_gate');
    final alt = nav.findCampusGateRoute('secondary_gate');

    expect(main.length, greaterThanOrEqualTo(2));
    expect(alt.length, greaterThanOrEqualTo(2));
    expect(main.last, isNot(equals(alt.last)));

    final mainTarget = nav.campusGateApproach('main_gate')!;
    final altTarget = nav.campusGateApproach('secondary_gate')!;
    expect(main.last[0], closeTo(mainTarget[0], 1e-6));
    expect(main.last[1], closeTo(mainTarget[1], 1e-6));
    expect(alt.last[0], closeTo(altTarget[0], 1e-6));
    expect(alt.last[1], closeTo(altTarget[1], 1e-6));
  });

  test('missing gate produces no route', () {
    final empty = MapScene(
      name: 'No gates',
      width: 1000,
      height: 600,
      floors: const {'Campus': <MapItem>[]},
    );
    final nav = WorldNavigator(
      empty,
      markerX: 500,
      markerY: 250,
      collisionRadius: 10,
    );
    expect(nav.findCampusGateRoute('main_gate'), isEmpty);
  });
}
