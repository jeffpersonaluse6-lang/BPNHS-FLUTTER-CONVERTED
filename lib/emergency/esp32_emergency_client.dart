import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'emergency_report.dart';

const String defaultSafeRouteServerUrl = String.fromEnvironment(
  'SAFEROUTE_SERVER_URL',
  defaultValue: 'http://192.168.4.1',
);

class StaffAuthenticationException implements Exception {
  const StaffAuthenticationException();

  @override
  String toString() => 'Incorrect staff password';
}

class SharedHazardConflictException implements Exception {
  const SharedHazardConflictException();

  @override
  String toString() => 'A different shared hazard is currently active';
}

class Esp32RequestException implements Exception {
  final int statusCode;
  final String message;

  const Esp32RequestException(this.statusCode, this.message);

  @override
  String toString() => 'ESP32 HTTP $statusCode: $message';
}

String _esp32ErrorMessage(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic> && decoded['error'] is String) {
      return decoded['error'] as String;
    }
  } on FormatException {
    // Fall back to the raw response below.
  }
  final trimmed = body.trim();
  return trimmed.isEmpty ? 'Request rejected' : trimmed;
}

/// Read-only client used by normal SAFEROUTE user mode.
class Esp32EmergencyStatusClient {
  final Uri baseUri;
  final Duration timeout;
  final HttpClient _httpClient;

  Esp32EmergencyStatusClient({
    Uri? baseUri,
    this.timeout = const Duration(seconds: 2),
    HttpClient? httpClient,
  }) : baseUri = baseUri ?? Uri.parse(defaultSafeRouteServerUrl),
       _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = timeout;
    _httpClient.idleTimeout = timeout;
  }

  Uri _endpoint(String path) => baseUri.resolve(path);

  Future<EmergencyStatus> fetchStatus() async {
    final request = await _httpClient
        .getUrl(_endpoint('/status'))
        .timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'ESP32 returned HTTP ${response.statusCode}',
        uri: _endpoint('/status'),
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ESP32 status must be a JSON object');
    }
    return EmergencyStatus.fromJson(decoded);
  }

  void close() => _httpClient.close(force: true);
}

/// Write client for a separate authorized staff/admin mode.
/// The normal evacuation screen never creates this class or stores its key.
class Esp32StaffEmergencyClient {
  final Uri baseUri;
  final String staffApiKey;
  final Duration timeout;
  final HttpClient _httpClient;

  Esp32StaffEmergencyClient({
    required this.staffApiKey,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 2),
    HttpClient? httpClient,
  }) : baseUri = baseUri ?? Uri.parse(defaultSafeRouteServerUrl),
       _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = timeout;
    _httpClient.idleTimeout = timeout;
  }

  Uri _endpoint(String path) => baseUri.resolve(path);

  Future<EmergencyStatus> report({
    required String hazardId,
    required EmergencyReportType type,
    required String zone,
    required double x,
    required double y,
    required double radius,
    required String? buildingId,
    required int floor,
    bool moving = false,
    List<List<double>>? path,
  }) {
    final payload = <String, dynamic>{
      'hazard_id': hazardId,
      'type': emergencyReportTypeToWire(type),
      'zone': zone,
      'x': x,
      'y': y,
      'radius': radius,
      'building_id': buildingId ?? '',
      'floor': floor,
      'active': true,
      'moving': moving,
    };
    if (path != null) payload['path'] = path;
    return _post('/report', payload);
  }

  Future<EmergencyStatus> clear({required String hazardId}) =>
      _post('/clear', <String, dynamic>{'hazard_id': hazardId});

  Future<EmergencyStatus> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final endpoint = _endpoint(path);
    final request = await _httpClient.postUrl(endpoint).timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set('X-SAFEROUTE-KEY', staffApiKey);
    // ESP32 WebServer does not reliably expose a chunked request body through
    // server.arg("plain"). Send one fixed-length UTF-8 payload instead.
    final encodedBody = utf8.encode(jsonEncode(payload));
    request.contentLength = encodedBody.length;
    request.add(encodedBody);

    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode == HttpStatus.unauthorized) {
      throw const StaffAuthenticationException();
    }
    if (response.statusCode == HttpStatus.conflict) {
      throw const SharedHazardConflictException();
    }
    if (response.statusCode != HttpStatus.ok) {
      throw Esp32RequestException(
        response.statusCode,
        _esp32ErrorMessage(body),
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ESP32 response must be a JSON object');
    }
    return EmergencyStatus.fromJson(decoded);
  }

  void close() => _httpClient.close(force: true);
}
