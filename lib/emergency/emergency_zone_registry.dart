import '../models/map_item.dart';
import '../models/map_scene.dart';

class EmergencyZoneLocation {
  final double x;
  final double y;
  final String? buildingId;
  final int floor;

  const EmergencyZoneLocation({
    required this.x,
    required this.y,
    required this.buildingId,
    required this.floor,
  });
}

/// Converts stable staff-facing zone IDs into the map's existing coordinate
/// system. Building floor zones use the center of that building's authored
/// floor canvas, not its smaller campus footprint.
class EmergencyZoneRegistry {
  final MapScene scene;

  const EmergencyZoneRegistry(this.scene);

  static const Map<String, String> _aliases = <String, String>{
    'BUILDING_A': 'SHS_ACADEMIC',
    'ACADEMIC': 'SHS_ACADEMIC',
    'ACADEMIC_BUILDING': 'SHS_ACADEMIC',
    'SHS_ACADEMIC_BUILDING': 'SHS_ACADEMIC',
    'JHS_BUILDING_A': 'JHS_A',
    'JHS_BUILDING_B': 'JHS_B',
    'JHS_BUILDING_C': 'JHS_C',
    'JHS_BUILDING_D': 'JHS_D',
    'TVL_A': 'SHS_TVL_A',
    'TVL_B': 'SHS_TVL_B',
    'TVL_C': 'SHS_TVL_C',
    'MAIN_COVERED_COURT': 'MAIN_COURT',
    'JHS_COVERED_COURT': 'MAIN_COURT',
  };

  EmergencyZoneLocation? resolve(String rawZone) {
    var zone = _normalize(rawZone);
    if (zone.isEmpty) return null;

    var floor = 1;
    final floorMatch = RegExp(r'^(.*)_F([1-9][0-9]*)$').firstMatch(zone);
    if (floorMatch != null) {
      zone = floorMatch.group(1)!;
      floor = int.parse(floorMatch.group(2)!);
    }
    zone = _aliases[zone] ?? zone;

    final building = _findBuilding(zone);
    if (building == null) {
      if (floorMatch != null) return null;
      final campusItem = _findCampusItem(zone);
      if (campusItem == null) return null;
      final center = campusItem.localToWorld(
        campusItem.width / 2,
        campusItem.height / 2,
      );
      return EmergencyZoneLocation(
        x: center[0],
        y: center[1],
        buildingId: null,
        floor: 1,
      );
    }
    if (floor > building.floorCount) return null;

    if (floorMatch == null) {
      final center = building.localToWorld(
        building.width / 2,
        building.height / 2,
      );
      return EmergencyZoneLocation(
        x: center[0],
        y: center[1],
        buildingId: null,
        floor: 1,
      );
    }

    final floorWidth = building.floorWidth ?? building.width;
    final floorHeight = building.floorHeight ?? building.height;
    return EmergencyZoneLocation(
      x: building.floorOriginX + floorWidth / 2,
      y: building.floorOriginY + floorHeight / 2,
      buildingId: building.id,
      floor: floor,
    );
  }

  MapItem? _findBuilding(String zone) {
    for (final building in scene.buildings()) {
      if (_normalize(building.id) == zone ||
          _normalize(building.text) == zone ||
          _normalize(building.opens ?? '') == zone) {
        return building;
      }
    }
    return null;
  }

  MapItem? _findCampusItem(String zone) {
    for (final item in scene.floors['Campus'] ?? const <MapItem>[]) {
      if (_normalize(item.id) == zone ||
          _normalize(item.text) == zone ||
          _normalize(item.kind) == zone) {
        return item;
      }
    }
    return null;
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll('Ñ', 'N')
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}
