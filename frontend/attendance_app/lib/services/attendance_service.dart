import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'storage_service.dart';
import '../core/api_client.dart';

class AttendanceService {
  final Dio _dio = ApiClient().dio;

  AttendanceService() {
    _dio.options.baseUrl = ApiConfig.baseUrl;
    _dio.options.connectTimeout = ApiConfig.connectionTimeout;
    _dio.options.receiveTimeout = ApiConfig.receiveTimeout;
  }

  Future<String?> _getToken() async {
    return await StorageService.read(key: 'access_token');
  }

  /// Mark attendance by scanning QR code
  Future<Map<String, dynamic>> markAttendance(String sessionId, {bool isOfflineSync = false, String? timestamp, int? bleHopCount, int? bleRssi}) async {
    try {
      final token = await _getToken();
      
      final data = <String, dynamic>{};
      if (isOfflineSync) {
        data['is_offline_sync'] = true;
        if (timestamp != null) {
          data['timestamp'] = timestamp;
        }
      }
      
      if (bleHopCount != null) {
        data['ble_hop_count'] = bleHopCount;
      }
      if (bleRssi != null) {
        data['ble_rssi'] = bleRssi;
      }

      final response = await _dio.post(
        '/sessions/$sessionId/mark/',
        data: data,
        options: Options(headers: ApiConfig.authHeaders(token)),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message':
              response.data['message'] ?? 'Attendance marked successfully',
          'data': response.data,
        };
      }

      return {'success': false, 'message': 'Failed to mark attendance'};
    } on DioException catch (e) {
      if (e.response != null) {
        final errorMessage =
            e.response!.data['error'] ??
            e.response!.data['message'] ??
            'Server error';
        return {'success': false, 'message': errorMessage};
      }
      return {'success': false, 'message': 'Network error: ${e.message}'};
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  /// Get student's attendance history
  Future<List<Map<String, dynamic>>> getMyAttendance() async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/students/my-attendance/',
        options: Options(headers: ApiConfig.authHeaders(token)),
      );

      if (response.statusCode == 200) {
        return (response.data['attendance'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
      }

      return [];
    } catch (e) {
      print('Error fetching attendance: $e');
      return [];
    }
  }

  /// Get teacher's attendance history with optional filters
  Future<Map<String, dynamic>> getTeacherAttendanceHistory({
    int? classId,
    String? sessionId,
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final token = await _getToken();

      // Build query parameters
      final queryParams = <String, dynamic>{};
      if (classId != null) queryParams['class_id'] = classId.toString();
      if (sessionId != null) queryParams['session_id'] = sessionId;
      if (dateFrom != null) queryParams['date_from'] = dateFrom;
      if (dateTo != null) queryParams['date_to'] = dateTo;

      final response = await _dio.get(
        '/teachers/attendance-history/',
        queryParameters: queryParams,
        options: Options(headers: ApiConfig.authHeaders(token)),
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'attendance':
              (response.data['attendance'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [],
          'statistics': response.data['statistics'] ?? {},
        };
      }

      return {'success': false, 'attendance': [], 'statistics': {}};
    } catch (e) {
      print('Error fetching teacher attendance: $e');
      return {'success': false, 'attendance': [], 'statistics': {}};
    }
  }

  /// Update attendance status (teacher only)
  Future<Map<String, dynamic>> updateAttendanceStatus({
    required int recordId,
    required String status,
  }) async {
    try {
      final token = await _getToken();

      final response = await _dio.put(
        '/attendance/$recordId/update/',
        data: {'status': status},
        options: Options(headers: ApiConfig.authHeaders(token)),
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': response.data['message'] ?? 'Status updated',
          'record': response.data['record'],
        };
      }

      return {'success': false, 'message': 'Failed to update status'};
    } on DioException catch (e) {
      return {
        'success': false,
        'message': e.response?.data['error'] ?? 'Failed to update status',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  /// Get session attendance details
  Future<Map<String, dynamic>> getSessionAttendanceDetails(
    String sessionId,
  ) async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/sessions/$sessionId/attendance/',
        options: Options(headers: ApiConfig.authHeaders(token)),
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'session': response.data['session'],
          'students':
              (response.data['students'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [],
          'statistics': response.data['statistics'] ?? {},
        };
      }

      return {'success': false};
    } catch (e) {
      print('Error fetching session details: $e');
      return {'success': false};
    }
  }

  /// Verify student image for pattern attendance
  Future<Map<String, dynamic>> verifyImage({
    required String sessionId,
    required String imagePath,
    required double focalDistance,
    bool flashFired = false,
    int? bleHopCount,
    int? bleRssi,
  }) async {
    try {
      final token = await _getToken();

      final formData = FormData.fromMap({
        'session_id': sessionId,
        'focal_distance': focalDistance,
        'flash_fired': flashFired,
        'student_image': await MultipartFile.fromFile(imagePath),
        if (bleHopCount != null) 'ble_hop_count': bleHopCount,
        if (bleRssi != null) 'ble_rssi': bleRssi,
      });

      final response = await _dio.post(
        '/sessions/verify-image/',
        data: formData,
        options: Options(headers: ApiConfig.authHeaders(token)),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message':
              response.data['message'] ?? 'Attendance marked successfully',
          'score': response.data['score'],
          'status': response.data['status'],
        };
      }

      return {'success': false, 'message': 'Verification failed'};
    } on DioException catch (e) {
      String errorMessage = 'Verification failed';
      if (e.response?.data is Map<String, dynamic>) {
        errorMessage = e.response?.data['error'] ?? errorMessage;
      }
      return {'success': false, 'message': errorMessage};
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  /// Sync an offline pattern image that was queued locally
  Future<Map<String, dynamic>> syncOfflinePattern({
    required String imagePath,
    required String timestamp,
    int? bleHopCount,
    int? bleRssi,
  }) async {
    try {
      final token = await _getToken();

      final formData = FormData.fromMap({
        'timestamp': timestamp,
        'student_image': await MultipartFile.fromFile(imagePath),
        if (bleHopCount != null) 'ble_hop_count': bleHopCount,
        if (bleRssi != null) 'ble_rssi': bleRssi,
      });

      final response = await _dio.post(
        '/sessions/sync-offline-pattern/',
        data: formData,
        options: Options(headers: ApiConfig.authHeaders(token)),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': response.data['message'] ?? 'Successfully synced',
        };
      }

      return {'success': false, 'message': 'Sync failed'};
    } on DioException catch (e) {
      String errorMessage = 'Sync failed';
      if (e.response?.data is Map<String, dynamic>) {
        errorMessage = e.response?.data['error'] ?? errorMessage;
      }
      return {'success': false, 'message': errorMessage};
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  /// Sync an offline session (Teacher)
  Future<Map<String, dynamic>> syncOfflineSession({
    required String sessionId,
    required int classId,
    required String classType,
    required int durationMinutes,
    required String startTime,
    required String endTime,
    String? shapeData,
    String? referenceImagePath,
  }) async {
    try {
      final token = await _getToken();

      final mapData = <String, dynamic>{
        'session_id': sessionId,
        'class_id': classId.toString(),
        'class_type': classType,
        'duration_minutes': durationMinutes.toString(),
        'start_time': startTime,
        'end_time': endTime,
      };

      if (shapeData != null) {
        mapData['shape_data'] = shapeData;
      }

      if (referenceImagePath != null) {
        mapData['reference_image'] = await MultipartFile.fromFile(
          referenceImagePath,
        );
      }

      final formData = FormData.fromMap(mapData);

      final response = await _dio.post(
        '/sessions/sync-offline-session/',
        data: formData,
        options: Options(headers: ApiConfig.authHeaders(token)),
      );

      if (response.statusCode == 201) {
        return {'success': true, 'message': response.data['message']};
      }
      return {'success': false, 'message': 'Failed to sync session'};
    } on DioException catch (e) {
      String errorMessage = 'Sync failed';
      if (e.response?.data is Map<String, dynamic>) {
        errorMessage = e.response?.data['error'] ?? errorMessage;
      }
      return {'success': false, 'message': errorMessage};
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }
}
