import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';

class ClassService {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final String baseUrl = ApiConfig.baseUrl;

  ClassService() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = ApiConfig.connectionTimeout;
    _dio.options.receiveTimeout = ApiConfig.receiveTimeout;
  }

  Future<String?> _getToken() async {
    return await _storage.read(key: 'access_token');
  }

  /// Check if student exists by email (for auto-fill feature)
  Future<Map<String, dynamic>?> checkStudentByEmail(String email) async {
    try {
      final token = await _getToken();
      
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await _dio.get(
        '/auth/check-student/',
        queryParameters: {'email': email},
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200 && response.data['exists'] == true) {
        return response.data['student'];
      }
      return null;
    } on DioException catch (e) {
      print('Check student error: ${e.message}');
      return null;
    }
  }

  /// Create a new class with students
  Future<Map<String, dynamic>> createClass({
    required String code,
    required String name,
    required String semester,
    required List<Map<String, String>> students,
  }) async {
    try {
      final token = await _getToken();

      final response = await _dio.post(
        '/classes/',
        data: {
          'code': code,
          'name': name,
          'semester': semester,
          'students': students,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 201) {
        return {
          'success': true,
          'message': response.data['message'],
          'class': response.data['class'],
        };
      }

      return {'success': false, 'message': 'Failed to create class'};
    } on DioException catch (e) {
      String errorMessage = 'Failed to create class';

      if (e.response != null) {
        final data = e.response!.data;
        if (data is Map && data.containsKey('error')) {
          errorMessage = data['error'];
        }
      }

      return {
        'success': false,
        'message': errorMessage,
      };
    }
  }

  /// Get all classes for logged-in teacher
  Future<List<Map<String, dynamic>>> getMyClasses() async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/classes/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data['classes']);
      }

      return [];
    } catch (e) {
      print('Error fetching classes: $e');
      return [];
    }
  }

  /// Get detailed information about a specific class
  Future<Map<String, dynamic>?> getClassDetails(int classId) async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/classes/$classId/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
      }

      return null;
    } catch (e) {
      print('Error fetching class details: $e');
      return null;
    }
  }

  /// Get students enrolled in a class
  Future<List<Map<String, dynamic>>> getClassStudents(int classId) async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/classes/$classId/students/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        // Backend returns {class_code, class_name, semester, students, total}
        if (response.data is Map && response.data.containsKey('students')) {
          return List<Map<String, dynamic>>.from(response.data['students']);
        }
      }

      return [];
    } catch (e) {
      print('Error fetching students: $e');
      return [];
    }
  }

  /// Update class details
  Future<bool> updateClass({
    required int classId,
    String? code,
    String? name,
    String? semester,
  }) async {
    try {
      final token = await _getToken();

      final response = await _dio.put(
        '/classes/$classId/',
        data: {
          if (code != null) 'code': code,
          if (name != null) 'name': name,
          if (semester != null) 'semester': semester,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error updating class: $e');
      return false;
    }
  }

  /// Delete a class
  Future<bool> deleteClass(int classId) async {
    try {
      final token = await _getToken();

      final response = await _dio.delete(
        '/classes/$classId/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      print('Error deleting class: $e');
      return false;
    }
  }

  /// Add a student to an existing class (supports both new and existing students)
  Future<Map<String, dynamic>> addStudentToClass(
    int classId,
    Map<String, String> studentData,
  ) async {
    try {
      final token = await _getToken();

      final response = await _dio.post(
        '/classes/$classId/add-student/',
        data: studentData,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 201) {
        return {
          'success': true,
          'message': response.data['message'],
          'student': response.data['student'],
        };
      }

      return {'success': false, 'message': 'Failed to add student'};
    } on DioException catch (e) {
      return {
        'success': false,
        'message': e.response?.data['error'] ?? 'Failed to add student',
      };
    }
  }

  /// Remove a student from a class
  Future<bool> removeStudentFromClass(int classId, int studentId) async {
    try {
      final token = await _getToken();

      final response = await _dio.delete(
        '/classes/$classId/remove-student/$studentId/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error removing student: $e');
      return false;
    }
  }

  /// Get student's enrolled classes
  Future<List<Map<String, dynamic>>> getStudentEnrolledClasses() async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/students/my-classes/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data['classes']);
      }

      return [];
    } catch (e) {
      print('Error fetching enrolled classes: $e');
      throw Exception('Failed to load enrolled classes');
    }
  }

  /// Get student attendance history
  Future<List<Map<String, dynamic>>> getStudentAttendanceHistory() async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/students/my-attendance/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data['attendance']);
      }

      return [];
    } catch (e) {
      print('Error fetching attendance history: $e');
      throw Exception('Failed to load attendance history');
    }
  }

  /// Update student in class (if you want to edit roll number)
  Future<bool> updateStudentInClass({
    required int classId,
    required int studentId,
    required String rollNo,
  }) async {
    try {
      final token = await _getToken();
      
      // You'll need to add this endpoint in backend
      final response = await _dio.put(
        '/classes/$classId/update-student/$studentId/',
        data: {'roll_no': rollNo},
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      print('Error updating student: $e');
      return false;
    }
  }
}