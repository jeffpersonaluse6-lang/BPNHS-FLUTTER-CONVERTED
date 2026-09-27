import 'dart:async';

import '../navigation/hazard.dart';
import 'emergency_report.dart';
import 'esp32_emergency_client.dart';

/// Isolated staff-authenticated write path. Credentials for a reported moving
/// threat are retained only in memory so its existing hazard can be updated.
class StaffHazardReporter {
  final Uri? baseUri;
  final Map<String, String> _movementCredentials = <String, String>{};
  final Map<String, Future<void>> _hazardQueues = <String, Future<void>>{};

  StaffHazardReporter({this.baseUri});

  Future<EmergencyStatus> report({
    required HazardZone hazard,
    required String staffPassword,
    bool keepCredentialForMovement = false,
    bool moving = false,
    List<List<double>>? path,
  }) {
    return _enqueue(hazard.id, () {
      return _sendReport(
        hazard: hazard,
        staffPassword: staffPassword,
        keepCredentialForMovement: keepCredentialForMovement,
        moving: moving,
        path: path,
      );
    });
  }

  Future<EmergencyStatus> _sendReport({
    required HazardZone hazard,
    required String staffPassword,
    required bool keepCredentialForMovement,
    required bool moving,
    List<List<double>>? path,
  }) async {
    final client = Esp32StaffEmergencyClient(
      staffApiKey: staffPassword,
      baseUri: baseUri,
    );
    try {
      final status = await client.report(
        hazardId: hazard.id,
        type: _reportType(hazard.kind),
        zone: hazard.buildingId == null
            ? 'CAMPUS'
            : '${hazard.buildingId}_F${hazard.floor}',
        x: hazard.x,
        y: hazard.y,
        radius: hazard.radius,
        buildingId: hazard.buildingId,
        floor: hazard.floor,
        moving: moving,
        path: path,
      );
      if (keepCredentialForMovement) {
        _movementCredentials[hazard.id] = staffPassword;
      }
      return status;
    } finally {
      client.close();
    }
  }

  Future<EmergencyStatus?> updateMovement({
    required HazardZone hazard,
    required bool moving,
    List<List<double>>? path,
  }) {
    return _enqueue(hazard.id, () async {
      final password = _movementCredentials[hazard.id];
      if (password == null) return null;
      return _sendReport(
        hazard: hazard,
        staffPassword: password,
        keepCredentialForMovement: true,
        moving: moving,
        path: path,
      );
    });
  }

  Future<EmergencyStatus> clear({
    required String hazardId,
    required String staffPassword,
  }) {
    return _enqueue(hazardId, () async {
      final client = Esp32StaffEmergencyClient(
        staffApiKey: staffPassword,
        baseUri: baseUri,
      );
      try {
        final status = await client.clear(hazardId: hazardId);
        _movementCredentials.remove(hazardId);
        return status;
      } finally {
        client.close();
      }
    });
  }

  Future<T> _enqueue<T>(String hazardId, Future<T> Function() operation) {
    final previous = _hazardQueues[hazardId] ?? Future<void>.value();
    final result = previous.then<T>((_) => operation());
    final tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    _hazardQueues[hazardId] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_hazardQueues[hazardId], tail)) {
          _hazardQueues.remove(hazardId);
        }
      }),
    );
    return result;
  }

  void forget(String hazardId) => _movementCredentials.remove(hazardId);

  void dispose() => _movementCredentials.clear();

  EmergencyReportType _reportType(HazardKind kind) {
    return switch (kind) {
      HazardKind.fire => EmergencyReportType.fire,
      HazardKind.earthquake => EmergencyReportType.blockedPath,
      HazardKind.activeShooter => EmergencyReportType.activeThreat,
    };
  }
}
