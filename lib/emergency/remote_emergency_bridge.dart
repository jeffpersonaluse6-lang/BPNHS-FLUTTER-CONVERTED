import '../navigation/hazard.dart';
import '../navigation/world_navigator.dart';
import 'emergency_report.dart';
import 'emergency_zone_registry.dart';

class RemoteEmergencyUpdate {
  final bool changed;
  final bool topologyChanged;
  final Set<String> movedHazardIds;
  final List<String> unknownZones;

  const RemoteEmergencyUpdate({
    required this.changed,
    required this.topologyChanged,
    this.movedHazardIds = const <String>{},
    this.unknownZones = const <String>[],
  });
}

/// Reconciles the ESP32 hazard list by stable report ID. Locally authored
/// hazards keep their own IDs; remote copies use a private namespaced ID.
class RemoteEmergencyBridge {
  static const String _remotePrefix = 'esp32_shared:';

  final WorldNavigator navigator;
  final EmergencyZoneRegistry zones;
  final Map<String, String> _lastSignatures = <String, String>{};
  final Set<String> _remoteReportIds = <String>{};

  RemoteEmergencyBridge({required this.navigator, required this.zones});

  static String remoteHazardId(String reportId) => '$_remotePrefix$reportId';
  static bool isRemoteHazardId(String id) => id.startsWith(_remotePrefix);

  Set<String> get remoteHazardIds => <String>{
    for (final reportId in _remoteReportIds) remoteHazardId(reportId),
  };

  RemoteEmergencyUpdate apply(EmergencyStatus status) {
    var changed = false;
    var topologyChanged = false;
    final movedHazardIds = <String>{};
    final unknownZones = <String>[];
    final incomingIds = <String>{};

    for (final report in status.hazards) {
      final reportId = report.hazardId!;
      incomingIds.add(reportId);
      if (_lastSignatures[reportId] == report.signature) continue;
      _lastSignatures[reportId] = report.signature;

      final location = report.hasExactLocation
          ? EmergencyZoneLocation(
              x: report.x!,
              y: report.y!,
              buildingId: report.buildingId,
              floor: report.floor!,
            )
          : zones.resolve(report.zone!);
      if (location == null) {
        changed = true;
        unknownZones.add(report.zone ?? 'unknown');
        final remoteId = remoteHazardId(reportId);
        if (navigator.removeHazard(remoteId)) {
          changed = true;
          topologyChanged = true;
        }
        _remoteReportIds.remove(reportId);
        continue;
      }

      final (kind, defaultRadius) = switch (report.type!) {
        EmergencyReportType.fire => (HazardKind.fire, 40.0),
        EmergencyReportType.blockedPath => (HazardKind.earthquake, 55.0),
        EmergencyReportType.activeThreat => (HazardKind.activeShooter, 70.0),
      };
      final radius = report.radius ?? defaultRadius;

      // The reporting device already owns this exact local hazard. Never add
      // a remote copy on that same device, even after the shooter has moved.
      final local = navigator.hazardById(reportId);
      if (local != null && !isRemoteHazardId(local.id)) {
        final oldRemoteId = remoteHazardId(reportId);
        if (navigator.removeHazard(oldRemoteId)) {
          changed = true;
          topologyChanged = true;
        }
        _remoteReportIds.remove(reportId);
        continue;
      }

      // Metadata such as a newly configured shooter path must repaint even
      // when the remote hazard's position and collision shape are unchanged.
      changed = true;
      final remoteId = remoteHazardId(reportId);
      final existing = navigator.hazardById(remoteId);
      final sameShape =
          existing != null &&
          existing.kind == kind &&
          existing.buildingId == location.buildingId &&
          existing.floor == location.floor &&
          (existing.radius - radius).abs() <= 0.001;
      if (sameShape) {
        final didMove =
            (existing.x - location.x).abs() > 0.001 ||
            (existing.y - location.y).abs() > 0.001;
        if (didMove) {
          navigator.moveHazard(remoteId, location.x, location.y);
          movedHazardIds.add(remoteId);
          changed = true;
        }
      } else {
        navigator.setReportedHazard(
          id: remoteId,
          kind: kind,
          x: location.x,
          y: location.y,
          radius: radius,
          buildingId: location.buildingId,
          floor: location.floor,
        );
        changed = true;
        topologyChanged = true;
      }
      _remoteReportIds.add(reportId);
    }

    final removedIds = _lastSignatures.keys
        .where((reportId) => !incomingIds.contains(reportId))
        .toList(growable: false);
    for (final reportId in removedIds) {
      _lastSignatures.remove(reportId);
      if (navigator.removeHazard(remoteHazardId(reportId))) {
        changed = true;
        topologyChanged = true;
      }
      _remoteReportIds.remove(reportId);
    }

    return RemoteEmergencyUpdate(
      changed: changed,
      topologyChanged: topologyChanged,
      movedHazardIds: movedHazardIds,
      unknownZones: unknownZones,
    );
  }
}
