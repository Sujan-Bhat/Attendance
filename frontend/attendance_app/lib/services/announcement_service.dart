import 'package:dio/dio.dart';
import '../config/api_config.dart';
import 'storage_service.dart';

class AnnouncementService {
  final Dio _dio = Dio();
  final String baseUrl = ApiConfig.baseUrl;

  AnnouncementService() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = ApiConfig.connectionTimeout;
    _dio.options.receiveTimeout = ApiConfig.receiveTimeout;
  }

  Future<String?> _getToken() async {
    return await StorageService.read(key: 'access_token');
  }

  /// Get all announcements created by the teacher
  Future<List<Map<String, dynamic>>> getAnnouncements() async {
    try {
      final token = await _getToken();
      final response = await _dio.get(
        '/announcements/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data['announcements'] ?? []);
      }
      return [];
    } catch (e) {
      print('Error fetching announcements: $e');
      return [];
    }
  }

  /// Create a new announcement
  Future<Map<String, dynamic>> createAnnouncement({
    required String targetType,
    int? targetClassId,
    int? targetStudentId,
    required String message,
    bool isUrgent = false,
    double attendanceThreshold = 75.0,
  }) async {
    try {
      final token = await _getToken();
      final response = await _dio.post(
        '/announcements/',
        data: {
          'target_type': targetType,
          if (targetClassId != null) 'target_class_id': targetClassId,
          if (targetStudentId != null) 'target_student_id': targetStudentId,
          'message': message,
          'is_urgent': isUrgent,
          'attendance_threshold': attendanceThreshold,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'announcement': response.data};
      }
      return {'success': false, 'message': 'Failed to create announcement'};
    } on DioException catch (e) {
      return {
        'success': false,
        'message': e.response?.data['error'] ?? 'Failed to create announcement',
      };
    }
  }

  /// Update an announcement
  Future<Map<String, dynamic>> updateAnnouncement({
    required int id,
    required String message,
    bool? isUrgent,
  }) async {
    try {
      final token = await _getToken();
      final response = await _dio.put(
        '/announcements/$id/',
        data: {
          'message': message,
          if (isUrgent != null) 'is_urgent': isUrgent,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'announcement': response.data};
      }
      return {'success': false, 'message': 'Failed to update announcement'};
    } on DioException catch (e) {
      return {
        'success': false,
        'message': e.response?.data['error'] ?? 'Failed to update announcement',
      };
    }
  }

  /// Delete an announcement
  Future<bool> deleteAnnouncement(int id) async {
    try {
      final token = await _getToken();
      final response = await _dio.delete(
        '/announcements/$id/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      print('Error deleting announcement: $e');
      return false;
    }
  }

  /// Get announcements for the student
  Future<List<Map<String, dynamic>>> getStudentAnnouncements() async {
    try {
      final token = await _getToken();
      final response = await _dio.get(
        '/students/announcements/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data['announcements'] ?? []);
      }
      return [];
    } catch (e) {
      print('Error fetching student announcements: $e');
      return [];
    }
  }

  /// Get students with low attendance in a class
  Future<Map<String, dynamic>> getLowAttendanceStudents(int classId, {double threshold = 75.0}) async {
    try {
      final token = await _getToken();
      final response = await _dio.get(
        '/classes/$classId/low-attendance/',
        queryParameters: {'threshold': threshold},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        return response.data;
      }
      return {'total': 0, 'count': 0, 'students': []};
    } catch (e) {
      print('Error fetching low attendance students: $e');
      return {'total': 0, 'count': 0, 'students': []};
    }
  }
}
