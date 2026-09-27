enum EmergencyReportType { fire, blockedPath, activeThreat }

EmergencyReportType? emergencyReportTypeFromWire(String? value) {
  switch (value) {
    case 'fire':
      return EmergencyReportType.fire;
    case 'blocked_path':
      return EmergencyReportType.blockedPath;
    case 'active_threat':
      return EmergencyReportType.activeThreat;
  }
  return null;
}

String emergencyReportTypeToWire(EmergencyReportType value) {
  switch (value) {
    case EmergencyReportType.fire:
      return 'fire';
    case EmergencyReportType.blockedPath:
      return 'blocked_path';
    case EmergencyReportType.activeThreat:
      return 'active_threat';
  }
}

/// The small, versioned status document exposed by the ESP32.
class EmergencyReport {
  final bool active;
  final String? hazardId;
  final EmergencyReportType? type;
  final String? zone;
  final double? x;
  final double? y;
  final double? radius;
  final String? buildingId;
  final int? floor;
  final int revision;
  final bool moving;
  final List<List<double>> path;

  const EmergencyReport({
    required this.active,
    this.hazardId,
    required this.type,
    required this.zone,
    this.x,
    this.y,
    this.radius,
    this.buildingId,
    this.floor,
    required this.revision,
    this.moving = false,
    this.path = const <List<double>>[],
  });

  factory EmergencyReport.fromJson(
    Map<String, dynamic> json, {
    int? statusRevision,
  }) {
    final active = json['active'] ?? true;
    final revision = statusRevision ?? json['revision'];
    if (active is! bool || revision is! num) {
      throw const FormatException('Invalid SAFEROUTE status response');
    }

    final rawType = json['type'];
    final rawZone = json['zone'];
    final rawHazardId = json['hazard_id'];
    final type = emergencyReportTypeFromWire(
      rawType is String && rawType.isNotEmpty ? rawType : null,
    );
    final zone = rawZone is String && rawZone.trim().isNotEmpty
        ? rawZone.trim()
        : null;
    final hazardId = rawHazardId is String && rawHazardId.trim().isNotEmpty
        ? rawHazardId.trim()
        : null;
    final hasExactLocation = json['has_exact_location'] == true;
    final x = hasExactLocation && json['x'] is num
        ? (json['x'] as num).toDouble()
        : null;
    final y = hasExactLocation && json['y'] is num
        ? (json['y'] as num).toDouble()
        : null;
    final radius = hasExactLocation && json['radius'] is num
        ? (json['radius'] as num).toDouble()
        : null;
    final floor = hasExactLocation && json['floor'] is num
        ? (json['floor'] as num).toInt()
        : null;
    final rawBuildingId = json['building_id'];
    final buildingId =
        hasExactLocation && rawBuildingId is String && rawBuildingId.isNotEmpty
        ? rawBuildingId
        : null;

    final validExactLocation =
        x != null && y != null && radius != null && radius > 0 && floor != null;
    final rawPath = json['path'];
    final path = <List<double>>[];
    if (rawPath != null) {
      if (rawPath is! List || rawPath.length > 16) {
        throw const FormatException('Invalid active-threat path');
      }
      for (final rawPoint in rawPath) {
        if (rawPoint is! List ||
            rawPoint.length != 2 ||
            rawPoint[0] is! num ||
            rawPoint[1] is! num) {
          throw const FormatException('Invalid active-threat path point');
        }
        path.add(<double>[
          (rawPoint[0] as num).toDouble(),
          (rawPoint[1] as num).toDouble(),
        ]);
      }
    }
    if (active &&
        (hazardId == null ||
            type == null ||
            (!validExactLocation && zone == null))) {
      throw const FormatException(
        'Active report is missing its ID, type, or location',
      );
    }

    return EmergencyReport(
      active: active,
      hazardId: hazardId,
      type: type,
      zone: zone,
      x: x,
      y: y,
      radius: radius,
      buildingId: buildingId,
      floor: floor,
      revision: revision.toInt(),
      moving: json['moving'] == true,
      path: List<List<double>>.unmodifiable(path),
    );
  }

  bool get hasExactLocation =>
      x != null && y != null && radius != null && floor != null;

  String get signature =>
      '$active:${hazardId ?? ''}:${type?.name ?? ''}:${zone ?? ''}:'
      '${x ?? ''}:${y ?? ''}:${radius ?? ''}:${buildingId ?? ''}:${floor ?? ''}:'
      '$moving:${path.map((point) => '${point[0]},${point[1]}').join(';')}';
}

/// One authoritative ESP32 snapshot containing every active shared hazard.
class EmergencyStatus {
  final int revision;
  final String? serverId;
  final List<EmergencyReport> hazards;

  const EmergencyStatus({
    required this.revision,
    this.serverId,
    required this.hazards,
  });

  factory EmergencyStatus.fromJson(Map<String, dynamic> json) {
    final revision = json['revision'];
    final rawServerId = json['server_id'];
    final rawHazards = json['hazards'];
    if (revision is! num ||
        rawHazards is! List ||
        (rawServerId != null && rawServerId is! String)) {
      throw const FormatException('Invalid SAFEROUTE status response');
    }

    final hazards = <EmergencyReport>[];
    final seenIds = <String>{};
    for (final raw in rawHazards) {
      if (raw is! Map) {
        throw const FormatException('Invalid shared hazard entry');
      }
      final report = EmergencyReport.fromJson(
        Map<String, dynamic>.from(raw),
        statusRevision: revision.toInt(),
      );
      final id = report.hazardId!;
      if (!seenIds.add(id)) {
        throw FormatException('Duplicate shared hazard ID: $id');
      }
      hazards.add(report);
    }
    return EmergencyStatus(
      revision: revision.toInt(),
      serverId: rawServerId as String?,
      hazards: hazards,
    );
  }

  EmergencyReport? byId(String hazardId) {
    for (final hazard in hazards) {
      if (hazard.hazardId == hazardId) return hazard;
    }
    return null;
  }
}
