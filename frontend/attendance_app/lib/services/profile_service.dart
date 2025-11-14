import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';

class ProfileService {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ProfileService() {
    _dio.options.baseUrl = ApiConfig.baseUrl;
    _dio.options.connectTimeout = ApiConfig.connectionTimeout;
    _dio.options.receiveTimeout = ApiConfig.receiveTimeout;
  }

  Future<String?> _getToken() async {
    return await _storage.read(key: 'access_token');
  }

  /// Get current user profile
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('No authentication token found');

      final response = await _dio.get(
        '/auth/me/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
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
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      return List<Map<String, dynamic>>.from(response.data['classes'] ?? []);
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
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      return List<Map<String, dynamic>>.from(response.data['classes'] ?? []);
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
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      final attendance = List<Map<String, dynamic>>.from(
        response.data['attendance'] ?? []
      );

      final total = attendance.length;
      final present = attendance.where((a) => a['status'] == 'present').length;
      final absent = total - present;
      final rate = total > 0 ? (present / total * 100).toStringAsFixed(1) : '0.0';

      return {
        'total': total,
        'present': present,
        'absent': absent,
        'attendance_rate': rate,
      };
    } on DioException catch (e) {
      print('Error getting student stats: ${e.message}');
      return {
        'total': 0,
        'present': 0,
        'absent': 0,
        'attendance_rate': '0.0',
      };
    }
  }
}