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
}