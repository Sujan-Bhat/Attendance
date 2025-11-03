import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';

class SessionService {
  final String baseUrl = ApiConfig.baseUrl; 
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  SessionService() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = ApiConfig.connectionTimeout;
    _dio.options.receiveTimeout = ApiConfig.receiveTimeout;
  }

  Future<String?> _getToken() async {
    return await _storage.read(key: 'access_token');
  }

  /// Create a new attendance session
  Future<Map<String, dynamic>> createSession({
    required int classId,
    required int durationMinutes,
  }) async {
    try {
      final token = await _getToken();
      
      final response = await _dio.post(
        '/sessions/create/',
        data: {
          'class_id': classId,
          'duration_minutes': durationMinutes,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      
      if (response.statusCode == 201) {
        return {
          'success': true,
          'session': response.data['session'],
        };
      }
      
      return {'success': false, 'message': 'Failed to create session'};
    } on DioException catch (e) {
      return {
        'success': false,
        'message': e.response?.data['error'] ?? 'Failed to create session',
      };
    }
  }

  /// Get active sessions
  Future<List<Map<String, dynamic>>> getActiveSessions() async {
    try {
      final token = await _getToken();
      
      final response = await _dio.get(
        '/sessions/active/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data['sessions']);
      }
      
      return [];
    } catch (e) {
      print('Error fetching active sessions: $e');
      return [];
    }
  }

  /// Get session details
  Future<Map<String, dynamic>?> getSessionDetails(String sessionId) async {
    try {
      final token = await _getToken();
      
      final response = await _dio.get(
        '/sessions/$sessionId/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      
      if (response.statusCode == 200) {
        return response.data;
      }
      
      return null;
    } catch (e) {
      print('Error fetching session details: $e');
      return null;
    }
  }

  /// End session
  Future<bool> endSession(String sessionId) async {
    try {
      final token = await _getToken();
      
      final response = await _dio.post(
        '/sessions/$sessionId/end/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      print('Error ending session: $e');
      return false;
    }
  }

  /// Mark attendance (for students)
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
          'message': response.data['message'],
        };
      }
      
      return {'success': false, 'message': 'Failed to mark attendance'};
    } on DioException catch (e) {
      return {
        'success': false,
        'message': e.response?.data['error'] ?? 'Failed to mark attendance',
      };
    }
  }
}