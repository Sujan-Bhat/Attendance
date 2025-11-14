import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';

class AttendanceService {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  AttendanceService() {
    _dio.options.baseUrl = ApiConfig.baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
  }

  Future<String?> _getToken() async {
    return await _storage.read(key: 'access_token');
  }

  /// Mark attendance by scanning QR code
  Future<Map<String, dynamic>> markAttendance(String sessionId) async {
    try {
      final token = await _getToken();
      
      final response = await _dio.post(
        '/sessions/$sessionId/mark/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': response.data['message'] ?? 'Attendance marked successfully',
          'data': response.data,
        };
      }
      
      return {
        'success': false,
        'message': 'Failed to mark attendance',
      };
    } on DioException catch (e) {
      if (e.response != null) {
        final errorMessage = e.response!.data['error'] ?? 
                            e.response!.data['message'] ?? 
                            'Server error';
        return {
          'success': false,
          'message': errorMessage,
        };
      }
      return {
        'success': false,
        'message': 'Network error: ${e.message}',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Unexpected error: $e',
      };
    }
  }

  /// Get student's attendance history
  Future<List<Map<String, dynamic>>> getMyAttendance() async {
    try {
      final token = await _getToken();
      
      final response = await _dio.get(
        '/students/my-attendance/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(
          response.data['attendance'] ?? []
        );
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
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      
      if (response.statusCode == 200) {
        return {
          'success': true,
          'attendance': List<Map<String, dynamic>>.from(
            response.data['attendance'] ?? []
          ),
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
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': response.data['message'] ?? 'Status updated',
          'record': response.data['record'],
        };
      }
      
      return {
        'success': false,
        'message': 'Failed to update status',
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': e.response?.data['error'] ?? 'Failed to update status',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Unexpected error: $e',
      };
    }
  }

  /// Get session attendance details
  Future<Map<String, dynamic>> getSessionAttendanceDetails(String sessionId) async {
    try {
      final token = await _getToken();
      
      final response = await _dio.get(
        '/sessions/$sessionId/attendance/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      
      if (response.statusCode == 200) {
        return {
          'success': true,
          'session': response.data['session'],
          'students': List<Map<String, dynamic>>.from(
            response.data['students'] ?? []
          ),
          'statistics': response.data['statistics'] ?? {},
        };
      }
      
      return {'success': false};
    } catch (e) {
      print('Error fetching session details: $e');
      return {'success': false};
    }
  }
}