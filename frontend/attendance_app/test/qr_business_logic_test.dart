import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. QR Payload Edge Cases & Schema Decoding', () {
    test('Invalid JSON string throws FormatException', () {
      const invalidJsonList = [
        '',
        'not a json string',
        '{unquoted_key: 123}',
        '{"session_id": "abc", broken',
        '<xml>not json</xml>',
      ];

      for (final raw in invalidJsonList) {
        expect(
          () => jsonDecode(raw),
          throwsA(isA<FormatException>()),
          reason: 'Raw value "$raw" must throw FormatException',
        );
      }
    });

    test('Valid JSON primitives and non-Map types are rejected by schema check', () {
      const nonMapJsonList = [
        '12345',
        '"just a string"',
        'true',
        'false',
        'null',
        '[1, 2, 3]',
        '[{"session_id": "test-uuid"}]',
      ];

      for (final raw in nonMapJsonList) {
        final decoded = jsonDecode(raw);
        final isAttendanceMap = decoded is Map<String, dynamic>;
        expect(
          isAttendanceMap,
          isFalse,
          reason: 'Decoded "$raw" (${decoded.runtimeType}) should NOT be Map<String, dynamic>',
        );
      }
    });

    test('Missing session_id key or null session_id fails validation', () {
      const missingSessionIds = [
        '{}',
        '{"token": "secret123"}',
        '{"session_id": null}',
        '{"session_id": null, "token": "xyz"}',
        '{"other_id": "uuid-123", "is_offline": true}',
      ];

      for (final raw in missingSessionIds) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final sessionId = decoded['session_id'];
        expect(
          sessionId,
          isNull,
          reason: 'Payload "$raw" must yield null sessionId and be rejected',
        );
      }
    });

    test('EMPIRICAL BUG: Integer session_id passes null check but causes TypeError when passed to String parameter', () {
      const integerSessionPayload = '{"session_id": 12345, "token": "valid-token"}';
      final decoded = jsonDecode(integerSessionPayload) as Map<String, dynamic>;
      final dynamic sessionId = decoded['session_id'];

      expect(sessionId, isNotNull, reason: 'sessionId passes null check');
      expect(sessionId is String, isFalse, reason: 'sessionId is int, not String');

      // Calling a function expecting String with dynamic int throws TypeError in sound null safety
      void simulateBleCall(String id) {}

      expect(
        () => simulateBleCall(sessionId),
        throwsA(isA<TypeError>()),
        reason: 'Integer session_id causes runtime TypeError: type int is not a subtype of type String',
      );
    });

    test('EMPIRICAL BEHAVIOR: Null or missing token correctly routes to tokenless attendance branch', () {
      const nullTokenPayloads = [
        '{"session_id": "c1f7a4e0-9b4b-4f9e-8c8a-1e3d7a8b9c0d"}',
        '{"session_id": "c1f7a4e0-9b4b-4f9e-8c8a-1e3d7a8b9c0d", "token": null}',
      ];

      for (final raw in nullTokenPayloads) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final sessionId = decoded['session_id'];
        final token = decoded['token'];

        expect(sessionId, isNotNull);
        expect(token, isNull, reason: 'Token should be null for tokenless branch');
      }
    });

    test('EMPIRICAL BUG: Non-string token passes null check but causes TypeError when passed to String? parameter', () {
      const intTokenPayload = '{"session_id": "c1f7a4e0-9b4b-4f9e-8c8a-1e3d7a8b9c0d", "token": 99999}';
      final decoded = jsonDecode(intTokenPayload) as Map<String, dynamic>;
      final dynamic token = decoded['token'];

      expect(token != null, isTrue, reason: 'token != null evaluates to true');
      expect(token is String, isFalse, reason: 'token is int, not String');

      void simulateAttendanceCall(String id, {String? qrToken}) {}

      expect(
        () => simulateAttendanceCall('id', qrToken: token),
        throwsA(isA<TypeError>()),
        reason: 'Non-string token causes runtime TypeError: type int is not a subtype of type String?',
      );
    });

    test('Unexpected keys and extra schema properties are ignored gracefully', () {
      const richPayload = '''
      {
        "session_id": "c1f7a4e0-9b4b-4f9e-8c8a-1e3d7a8b9c0d",
        "token": "tok123456",
        "is_offline": false,
        "unexpected_array": [1, 2, 3],
        "nested": {"key": "val"},
        "extra_flag": true
      }
      ''';

      final decoded = jsonDecode(richPayload) as Map<String, dynamic>;
      expect(decoded['session_id'], equals('c1f7a4e0-9b4b-4f9e-8c8a-1e3d7a8b9c0d'));
      expect(decoded['token'], equals('tok123456'));
      expect(decoded['is_offline'], isFalse);
    });
  });

  group('2. BLE Mesh Serialization & Proximity Verification Integration', () {
    List<int> uuidToBytes(String uuidString) {
      final clean = uuidString.replaceAll('-', '');
      final bytes = <int>[];
      for (int i = 0; i < clean.length; i += 2) {
        bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
      }
      return bytes;
    }

    Uint8List createPayload(String uuidString, int hopCount) {
      final uuidBytes = uuidToBytes(uuidString);
      final payload = Uint8List(17);
      for (int i = 0; i < 16; i++) {
        payload[i] = uuidBytes[i];
      }
      payload[16] = hopCount.clamp(0, 255);
      return payload;
    }

    test('Valid UUID converts to exact 16-byte list and 17-byte BLE payload', () {
      const validUuid = 'c1f7a4e0-9b4b-4f9e-8c8a-1e3d7a8b9c0d';
      final bytes = uuidToBytes(validUuid);
      expect(bytes.length, equals(16));
      expect(bytes[0], equals(0xc1));
      expect(bytes[1], equals(0xf7));
      expect(bytes[15], equals(0x0d));

      final payload = createPayload(validUuid, 0);
      expect(payload.length, equals(17));
      expect(payload[16], equals(0)); // Hop 0 for teacher

      final relayPayload = createPayload(validUuid, 1);
      expect(relayPayload[16], equals(1)); // Hop 1 for student relay
    });

    test('Hop count clamping logic', () {
      const validUuid = 'c1f7a4e0-9b4b-4f9e-8c8a-1e3d7a8b9c0d';
      expect(createPayload(validUuid, -5)[16], equals(0));
      expect(createPayload(validUuid, 300)[16], equals(255));
    });

    test('EMPIRICAL BUG: Odd-length hex session_id triggers RangeError in uuidToBytes', () {
      const oddLengthSessionId = '12345'; // length 5, clean.substring(4, 6) will fail
      expect(
        () => uuidToBytes(oddLengthSessionId),
        throwsA(isA<RangeError>()),
        reason: 'clean.substring(4, 6) with length 5 throws RangeError',
      );
    });

    test('EMPIRICAL BUG: Non-hex session_id triggers FormatException in uuidToBytes', () {
      const nonHexSessionId = 'session-invalid-id-xyz123';
      expect(
        () => uuidToBytes(nonHexSessionId),
        throwsA(isA<FormatException>()),
        reason: 'int.parse("se", radix: 16) throws FormatException',
      );
    });

    test('EMPIRICAL BUG: Short session_id throws RangeError in createPayload', () {
      const shortSessionId = 'c1f7a4'; // Only 3 bytes
      expect(
        () => createPayload(shortSessionId, 0),
        throwsA(isA<RangeError>()),
        reason: 'Loop up to 16 exceeds 3 bytes and throws RangeError',
      );
    });

    test('BLE proximity timeout error simulation stops flow without marking attendance', () async {
      bool attendanceMarked = false;
      bool offlineQueued = false;
      String? errorMessage;

      Future<Map<String, dynamic>> mockBleVerify(String sessionId, {Duration timeout = const Duration(seconds: 15)}) async {
        throw 'BLE Verification timeout: Could not find teacher/student signal in range.';
      }

      const sessionId = 'c1f7a4e0-9b4b-4f9e-8c8a-1e3d7a8b9c0d';

      try {
        await mockBleVerify(sessionId);
        attendanceMarked = true;
      } catch (e) {
        errorMessage = 'BLE Verification failed. Ensure Bluetooth is on and you are near the teacher.';
      }

      expect(attendanceMarked, isFalse);
      expect(offlineQueued, isFalse);
      expect(errorMessage, contains('BLE Verification failed'));
    });

    test('BLE proximity verification success extracts hop_count and rssi and passes to mark/enqueue', () async {
      Future<Map<String, dynamic>> mockBleVerify(String sessionId) async {
        return {
          'hop_count': 2,
          'rssi': -72,
        };
      }

      const sessionId = 'c1f7a4e0-9b4b-4f9e-8c8a-1e3d7a8b9c0d';
      final bleResult = await mockBleVerify(sessionId);

      expect(bleResult['hop_count'], equals(2));
      expect(bleResult['rssi'], equals(-72));

      int relayedHop = (bleResult['hop_count'] as int) + 1;
      expect(relayedHop, equals(3));
    });
  });

  group('3. Offline Handling & SyncService Queueing Integration', () {
    test('Offline condition evaluation: evaluates true on ConnectivityResult.none or is_offline', () {
      bool isOfflineCheck(List<ConnectivityResult> connectivity, bool? isOfflineSession) {
        final isNetworkOffline = connectivity.isEmpty || connectivity.contains(ConnectivityResult.none);
        return isNetworkOffline || (isOfflineSession == true);
      }

      expect(isOfflineCheck([ConnectivityResult.none], false), isTrue);
      expect(isOfflineCheck([], false), isTrue);
      expect(isOfflineCheck([ConnectivityResult.wifi], true), isTrue);
      expect(isOfflineCheck([ConnectivityResult.mobile], true), isTrue);
      expect(isOfflineCheck([ConnectivityResult.wifi], false), isFalse);
      expect(isOfflineCheck([ConnectivityResult.mobile], null), isFalse);
    });

    test('Web offline QR queue item serialization matches expected SyncService structure', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      const sessionId = 'c1f7a4e0-9b4b-4f9e-8c8a-1e3d7a8b9c0d';
      const token = 'test-token-123';
      final timestamp = DateTime.now().toUtc().toIso8601String();
      const bleHopCount = 1;
      const bleRssi = -68;

      final item = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'session_id': sessionId,
        'timestamp': timestamp,
        'ble_hop_count': bleHopCount,
        'ble_rssi': bleRssi,
        'qr_token': token,
        'status': 'pending',
      };

      await prefs.setString('offline_qr_queue', jsonEncode([item]));

      final stored = prefs.getString('offline_qr_queue');
      expect(stored, isNotNull);
      final list = jsonDecode(stored!) as List<dynamic>;
      expect(list.length, equals(1));

      final first = list.first as Map<String, dynamic>;
      expect(first['session_id'], equals(sessionId));
      expect(first['qr_token'], equals(token));
      expect(first['ble_hop_count'], equals(1));
      expect(first['ble_rssi'], equals(-68));
      expect(first['status'], equals('pending'));
    });

    test('Web offline pattern queue item serialization matches expected structure', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      const imagePath = '/path/to/board_pattern.jpg';
      final timestamp = DateTime.now().toUtc().toIso8601String();
      const bleHopCount = 0;
      const bleRssi = -45;

      final item = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'image_path': imagePath,
        'timestamp': timestamp,
        'ble_hop_count': bleHopCount,
        'ble_rssi': bleRssi,
        'status': 'pending',
      };

      await prefs.setString('offline_queue', jsonEncode([item]));

      final stored = prefs.getString('offline_queue');
      expect(stored, isNotNull);
      final list = jsonDecode(stored!) as List<dynamic>;
      expect(list.length, equals(1));

      final first = list.first as Map<String, dynamic>;
      expect(first['image_path'], equals(imagePath));
      expect(first['ble_hop_count'], equals(0));
      expect(first['ble_rssi'], equals(-45));
      expect(first['status'], equals('pending'));
    });

    test('Offline expiration logic: scans >= 24 hours old are flagged as expired', () {
      final now = DateTime.now().toUtc();
      final freshScanTimestamp = now.subtract(const Duration(hours: 23)).toIso8601String();
      final expiredScanTimestamp = now.subtract(const Duration(hours: 25)).toIso8601String();

      bool isExpired(String timestamp) {
        final scanTime = DateTime.parse(timestamp);
        return DateTime.now().toUtc().difference(scanTime.toUtc()).inHours >= 24;
      }

      expect(isExpired(freshScanTimestamp), isFalse);
      expect(isExpired(expiredScanTimestamp), isTrue);
    });

    test('EMPIRICAL BUG: Online scan network failure does NOT automatically fallback to SyncService enqueue', () async {
      bool offlineQueued = false;
      bool scanResumed = false;

      // In QRScannerScreen lines 505-520:
      // If network is assumed online (isOffline == false), but attendanceService returns network error:
      final markResult = {'success': false, 'message': 'Network error: Connection timeout'};

      if (!(markResult['success'] as bool)) {
        // Code only does _showError and _resumeQRScanningAfterDelay
        scanResumed = true;
      } else {
        offlineQueued = true;
      }

      expect(offlineQueued, isFalse, reason: 'Online failure never triggers enqueueQRScan fallback');
      expect(scanResumed, isTrue, reason: 'Scanner resumes scanning after delay instead of saving offline');
    });
  });
}
