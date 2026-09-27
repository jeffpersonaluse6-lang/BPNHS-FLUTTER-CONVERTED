import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_runtime/emergency/emergency_report.dart';
import 'package:flutter_runtime/emergency/esp32_emergency_client.dart';

void main() {
  test(
    'user status and authorized staff report flow use the ESP32 contract',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var revision = 0;
      final hazards = <String, Map<String, dynamic>>{};

      server.listen((request) async {
        if (request.method == 'POST') {
          expect(request.headers.value('X-SAFEROUTE-KEY'), 'staff-test-key');
          expect(request.contentLength, greaterThan(0));
          expect(request.headers.chunkedTransferEncoding, isFalse);
          final body = await utf8.decoder.bind(request).join();
          if (request.uri.path == '/report') {
            final json = jsonDecode(body) as Map<String, dynamic>;
            final hazardId = json['hazard_id'] as String;
            hazards[hazardId] = <String, dynamic>{
              ...json,
              'has_exact_location': true,
            };
            revision++;
          } else if (request.uri.path == '/clear') {
            final json = jsonDecode(body) as Map<String, dynamic>;
            hazards.remove(json['hazard_id']);
            revision++;
          }
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'revision': revision,
            'hazards': hazards.values.toList(),
          }),
        );
        await request.response.close();
      });

      final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
      final user = Esp32EmergencyStatusClient(baseUri: baseUri);
      final staff = Esp32StaffEmergencyClient(
        baseUri: baseUri,
        staffApiKey: 'staff-test-key',
      );

      final initial = await user.fetchStatus();
      expect(initial.hazards, isEmpty);

      final reported = await staff.report(
        hazardId: 'active_shooter_9',
        type: EmergencyReportType.activeThreat,
        zone: 'BUILDING_A_F2',
        x: 812.5,
        y: 644.25,
        radius: 70,
        buildingId: 'academic-id',
        floor: 2,
        path: const <List<double>>[
          <double>[812.5, 644.25],
          <double>[900, 700],
          <double>[1050, 740],
        ],
      );
      final reportedHazard = reported.byId('active_shooter_9')!;
      expect(reportedHazard.type, EmergencyReportType.activeThreat);
      expect(reportedHazard.zone, 'BUILDING_A_F2');
      expect(reportedHazard.x, 812.5);
      expect(reportedHazard.y, 644.25);
      expect(reportedHazard.radius, 70);
      expect(reportedHazard.buildingId, 'academic-id');
      expect(reportedHazard.floor, 2);
      expect(reportedHazard.path, const <List<double>>[
        <double>[812.5, 644.25],
        <double>[900, 700],
        <double>[1050, 740],
      ]);

      final polled = await user.fetchStatus();
      expect(
        polled.byId('active_shooter_9')!.signature,
        reportedHazard.signature,
      );
      expect(polled.byId('active_shooter_9')!.path, reportedHazard.path);

      final cleared = await staff.clear(hazardId: 'active_shooter_9');
      expect(cleared.hazards, isEmpty);

      user.close();
      staff.close();
      await server.close(force: true);
    },
  );

  test(
    'staff authentication failure is isolated from normal status polling',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = request.method == 'POST'
            ? HttpStatus.unauthorized
            : HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          request.method == 'POST'
              ? '{"ok":false,"error":"invalid staff key"}'
              : '{"ok":true,"revision":0,"hazards":[]}',
        );
        await request.response.close();
      });

      final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
      final user = Esp32EmergencyStatusClient(baseUri: baseUri);
      final staff = Esp32StaffEmergencyClient(
        baseUri: baseUri,
        staffApiKey: 'wrong-password',
      );

      expect((await user.fetchStatus()).hazards, isEmpty);
      await expectLater(
        staff.report(
          hazardId: 'fire_1',
          type: EmergencyReportType.fire,
          zone: 'CAMPUS',
          x: 100,
          y: 200,
          radius: 40,
          buildingId: null,
          floor: 1,
        ),
        throwsA(isA<StaffAuthenticationException>()),
      );

      user.close();
      staff.close();
      await server.close(force: true);
    },
  );
}
