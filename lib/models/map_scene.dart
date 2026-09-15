import 'dart:convert';
import 'package:flutter/services.dart';
import 'map_item.dart';

/// MapScene — holds all floor layers loaded from map_workspace.json.
/// Matches Python MapScene from map/scene.py.
class MapScene {
  final String name;
  final double width;
  final double height;

  /// All floor layers keyed by scope string.
  /// "Campus" = the top-level campus layer.
  /// "{buildingId}:Floor {n}" = building floor layers.
  /// "{buildingId}:Roof" = building roof layers.
  final Map<String, List<MapItem>> floors;

  MapScene({
    required this.name,
    required this.width,
    required this.height,
    required this.floors,
  });

  /// Build from raw JSON data.
  factory MapScene.fromJson(Map<String, dynamic> raw) {
    if (raw['format'] != 'bpnhs-map') {
      throw Exception('Not a BPNHS map workspace');
    }
    final floorsRaw = raw['floors'] as Map<String, dynamic>;
    final floors = <String, List<MapItem>>{};
    for (final entry in floorsRaw.entries) {
      floors[entry.key] = (entry.value as List<dynamic>)
          .map((e) => MapItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return MapScene(
      name: raw['name'] as String? ?? 'BPNHS campus',
      width: (raw['width'] as num).toDouble(),
      height: (raw['height'] as num).toDouble(),
      floors: floors,
    );
  }

  /// Load from an asset bundle.
  static Future<MapScene> loadFromAssets(AssetBundle bundle, String path) async {
    final json = await bundle.loadString(path);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return MapScene.fromJson(data);
  }

  /// All building items on the campus layer.
  List<MapItem> buildings() {
    return (floors['Campus'] ?? [])
        .where((item) => item.kind == 'building')
        .toList();
  }

  /// Get items for a building floor.
  List<MapItem> floorItems(String buildingId, int floor) {
    return floors['$buildingId:Floor $floor'] ?? [];
  }

  /// Get roof items for a building.
  List<MapItem> roofItems(String buildingId) {
    return floors['$buildingId:Roof'] ?? [];
  }

  /// Find building whose opens key matches.
  MapItem? parentForKey(String key) {
    final campus = floors['Campus'] ?? [];
    for (final item in campus) {
      if (item.kind == 'building' && item.opens == key) {
        return item;
      }
    }
    return null;
  }
}
