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
  id: '$kind-$x',
);

MapScene twoGateScene() => MapScene(
  name: 'Automatic gate ranking',
  width: 1200,
  height: 600,
  floors: {
    'Campus': [gate('secondary_gate', 100), gate('main_gate', 950)],
  },
);

void main() {
  test('closest valid complete gate route becomes Main route', () {
    final nav = WorldNavigator(
      twoGateScene(),
      markerX: 180,
      markerY: 250,
      collisionRadius: 10,
    );

    final ranked = nav.rankEvacuationGates();

    expect(ranked, hasLength(2));
    expect(ranked.first.kind, 'secondary_gate');
    expect(ranked[1].kind, 'main_gate');
    expect(nav.recommendedEvacuationGateKind(), 'secondary_gate');
    expect(nav.recommendedEvacuationGateKind(alternative: true), 'main_gate');
  });

  test('ranking flips when Main Gate is the better complete route', () {
    final nav = WorldNavigator(
      twoGateScene(),
      markerX: 930,
      markerY: 250,
      collisionRadius: 10,
    );

    final ranked = nav.rankEvacuationGates();

    expect(ranked, hasLength(2));
    expect(ranked.first.kind, 'main_gate');
    expect(ranked[1].kind, 'secondary_gate');
  });

  test('alternative is unavailable when only one official gate exists', () {
    final scene = MapScene(
      name: 'Single gate',
      width: 1200,
      height: 600,
      floors: {
        'Campus': [gate('main_gate', 950)],
      },
    );
    final nav = WorldNavigator(
      scene,
      markerX: 500,
      markerY: 250,
      collisionRadius: 10,
    );

    expect(nav.rankEvacuationGates(), hasLength(1));
    expect(nav.recommendedEvacuationGateKind(), 'main_gate');
    expect(nav.recommendedEvacuationGateKind(alternative: true), isNull);
  });

  test('Main and Alternative always point at different official gates', () {
    final nav = WorldNavigator(
      twoGateScene(),
      markerX: 500,
      markerY: 250,
      collisionRadius: 10,
    );

    final main = nav.recommendedEvacuationGateKind();
    final alternative = nav.recommendedEvacuationGateKind(alternative: true);

    expect(main, isNotNull);
    expect(alternative, isNotNull);
    expect(main, isNot(equals(alternative)));
  });

  test('all hazard-blocked official gates produce no evacuation option', () {
    final nav = WorldNavigator(
      twoGateScene(),
      markerX: 500,
      markerY: 250,
      collisionRadius: 10,
    );

    final main = nav.campusGateApproach('main_gate')!;
    final secondary = nav.campusGateApproach('secondary_gate')!;
    nav.addFireHazard(main[0], main[1]);
    nav.addEarthquakeHazard(secondary[0], secondary[1]);

    expect(nav.allEvacuationGatesBlocked, isTrue);
    expect(nav.rankEvacuationGates(), isEmpty);
    expect(nav.recommendedEvacuationGateKind(), isNull);
  });
}
