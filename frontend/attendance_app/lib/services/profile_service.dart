import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'storage_service.dart';
import '../core/api_client.dart';

class ProfileService {
  final Dio _dio = ApiClient().dio;

  ProfileService() {
    _dio.options.baseUrl = ApiConfig.baseUrl;
    _dio.options.connectTimeout = ApiConfig.connectionTimeout;
    _dio.options.receiveTimeout = ApiConfig.receiveTimeout;
  }

  Future<String?> _getToken() async {
    return await StorageService.read(key: 'access_token');
  }

  /// Get current user profile
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('No authentication token found');

      final response = await _dio.get(
        '/auth/me/',
        options: Options(headers: ApiConfig.authHeaders(token)),
      );

      return response.data;
    } on DioException catch (e) {
      print('Error getting user profile: ${e.message}');
      if (e.response != null) {
        print('Response data: ${e.response?.data}');
      }
      rethrow;
    }
  }

  /// Get student's enrolled classes
  Future<List<Map<String, dynamic>>> getStudentClasses() async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('No authentication token found');

      final response = await _dio.get(
        '/students/my-classes/',
        options: Options(headers: ApiConfig.authHeaders(token)),
      );

      return (response.data['classes'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
    } on DioException catch (e) {
      print('Error getting student classes: ${e.message}');
      return [];
    }
  }

  /// Get teacher's classes
  Future<List<Map<String, dynamic>>> getTeacherClasses() async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('No authentication token found');

      final response = await _dio.get(
        '/classes/',
        options: Options(headers: ApiConfig.authHeaders(token)),
      );

      return (response.data['classes'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
    } on DioException catch (e) {
      print('Error getting teacher classes: ${e.message}');
      return [];
    }
  }

  /// Get student's attendance statistics
  Future<Map<String, dynamic>> getStudentStats() async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('No authentication token found');

      final response = await _dio.get(
        '/students/my-attendance/',
        options: Options(headers: ApiConfig.authHeaders(token)),
      );

      final attendance =
          (response.data['attendance'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];

      // Count each backend status explicitly: pending_review records are
      // neither present nor absent and are excluded from the rate's
      // denominator so awaiting review doesn't drag the rate down.
      final total = attendance.length;
      final present = attendance.where((a) => a['status'] == 'present').length;
      final absent = attendance.where((a) => a['status'] == 'absent').length;
      final pending =
          attendance.where((a) => a['status'] == 'pending_review').length;
      final graded = present + absent;
      final rate =
          graded > 0 ? (present / graded * 100).toStringAsFixed(1) : '0.0';

      return {
        'total': total,
        'present': present,
        'absent': absent,
        'pending_review': pending,
        'attendance_rate': rate,
      };
    } on DioException catch (e) {
      print('Error getting student stats: ${e.message}');
      return {'total': 0, 'present': 0, 'absent': 0, 'attendance_rate': '0.0'};
    } catch (e) {
      // Malformed response shape (TypeError from casting) must not escape;
      // fall back to zeroed stats like the DioException path.
      print('Error parsing student stats: $e');
      return {'total': 0, 'present': 0, 'absent': 0, 'attendance_rate': '0.0'};
    }
  }
}
