import 'dart:convert';
import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'storage_service.dart';
import '../core/api_client.dart';

class ClassService {
  final Dio _dio = ApiClient().dio;

  final String baseUrl = ApiConfig.baseUrl;

  ClassService() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = ApiConfig.connectionTimeout;
    _dio.options.receiveTimeout = ApiConfig.receiveTimeout;
  }

  Future<String?> _getToken() async {
    return await StorageService.read(key: 'access_token');
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
        options: Options(headers: {'Authorization': 'Bearer $token'}),
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
    required String name,
    required String semester,
    required List<Map<String, String>> students,
  }) async {
    try {
      final token = await _getToken();

      final response = await _dio.post(
        '/classes/',
        data: {'name': name, 'semester': semester, 'students': students},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
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

      return {'success': false, 'message': errorMessage};
    }
  }

  /// Get all classes for logged-in teacher
  Future<List<Map<String, dynamic>>> getMyClasses() async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/classes/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        final classes = List<Map<String, dynamic>>.from(response.data['classes']);
        StorageService.write(key: 'cached_my_classes', value: jsonEncode(classes));
        return classes;
      }

      return await _getCachedClasses();
    } catch (e) {
      print('Error fetching classes: $e');
      return await _getCachedClasses();
    }
  }

  Future<List<Map<String, dynamic>>> _getCachedClasses() async {
    try {
      final cachedStr = await StorageService.read(key: 'cached_my_classes');
      if (cachedStr != null) {
        final decoded = jsonDecode(cachedStr) as List;
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Admin: Get all classes grouped by semester with student counts
  Future<List<Map<String, dynamic>>> getAdminClassesSummary() async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/admin/classes/summary/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data['semesters']);
      }

      return [];
    } catch (e) {
      print('Error fetching admin classes summary: $e');
      return [];
    }
  }

  /// Admin: Get all classes in a semester with their enrolled students
  Future<Map<String, dynamic>> getSemesterClasses(String semester) async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/admin/classes/by-semester/$semester/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        return response.data;
      }

      return {};
    } catch (e) {
      print('Error fetching semester classes: $e');
      return {};
    }
  }

  /// Admin: Get all unique students in a semester with their enrolled class codes
  Future<Map<String, dynamic>> getSemesterStudents(String semester) async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/admin/students/by-semester/$semester/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        return response.data;
      }

      return {};
    } catch (e) {
      print('Error fetching semester students: $e');
      return {};
    }
  }

  /// Admin: Get pre-registered students (assigned a semester, not yet enrolled)
  Future<Map<String, dynamic>> getAdminUnassignedStudents() async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/admin/students/unassigned/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        return response.data;
      }

      return {'students': [], 'total': 0};
    } catch (e) {
      print('Error fetching unassigned students: $e');
      return {'students': [], 'total': 0};
    }
  }

  /// Admin: Get all teachers with their class details
  Future<Map<String, dynamic>> getTeachers() async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/admin/teachers/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        return response.data;
      }

      return {};
    } catch (e) {
      print('Error fetching teachers: $e');
      return {};
    }
  }

  /// Get detailed information about a specific class
  Future<Map<String, dynamic>?> getClassDetails(int classId) async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/classes/$classId/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
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
        options: Options(headers: {'Authorization': 'Bearer $token'}),
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

  /// Get the full roster for a class: enrolled students plus same-semester
  /// students who are still available to be added.
  /// Returns {class_code, class_name, semester, students, total,
  ///          available_students, total_available} or null on failure.
  Future<Map<String, dynamic>?> getClassRoster(int classId) async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/classes/$classId/students/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }

      return null;
    } catch (e) {
      print('Error fetching class roster: $e');
      return null;
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
        options: Options(headers: {'Authorization': 'Bearer $token'}),
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
        options: Options(headers: {'Authorization': 'Bearer $token'}),
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
        options: Options(headers: {'Authorization': 'Bearer $token'}),
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
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error removing student: $e');
      return false;
    }
  }

  /// Admin: Remove a student from a class (no teacher restriction)
  Future<bool> adminRemoveStudentFromClass(int classId, int studentId) async {
    try {
      final token = await _getToken();

      final response = await _dio.delete(
        '/admin/classes/$classId/remove-student/$studentId/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error removing student: $e');
      return false;
    }
  }

  /// Admin: Create a new user (student or teacher)
  Future<Map<String, dynamic>> adminCreateUser({
    required String username,
    required String email,
    required String password,
    required String role,
    String? semester,
  }) async {
    try {
      final token = await _getToken();

      final response = await _dio.post(
        '/admin/users/create/',
        data: {
          'username': username,
          'email': email,
          'password': password,
          'role': role,
          if (semester != null && semester.isNotEmpty) 'semester': semester,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.data;
    } on DioException catch (e) {
      return {
        'success': false,
        'error': e.response?.data['error'] ?? 'Failed to create user',
      };
    }
  }

  /// Admin: Permanently delete a user
  Future<Map<String, dynamic>> adminDeleteUser(int userId) async {
    try {
      final token = await _getToken();

      final response = await _dio.delete(
        '/admin/users/$userId/delete/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.data;
    } on DioException catch (e) {
      return {
        'success': false,
        'error': e.response?.data['error'] ?? 'Failed to delete user',
      };
    }
  }

  /// Admin: Permanently delete a student from the database
  Future<Map<String, dynamic>> adminDeleteStudent(int studentId) async {
    try {
      final token = await _getToken();

      final response = await _dio.delete(
        '/admin/students/$studentId/delete/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.data;
    } on DioException catch (e) {
      return {
        'success': false,
        'error': e.response?.data['error'] ?? 'Failed to delete student',
      };
    }
  }

  /// Admin: Permanently delete every student of a given semester
  Future<Map<String, dynamic>> adminDeleteAllStudents(String semester) async {
    try {
      final token = await _getToken();

      final response = await _dio.delete(
        '/admin/students/delete-all/$semester/',
        data: {'confirm': true},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.data;
    } on DioException catch (e) {
      return {
        'success': false,
        'error': e.response?.data['error'] ?? 'Failed to delete students',
      };
    }
  }

  /// Get student's enrolled classes
  Future<List<Map<String, dynamic>>> getStudentEnrolledClasses() async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/students/my-classes/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
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
        options: Options(headers: {'Authorization': 'Bearer $token'}),
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

  /// Update student in class
  Future<bool> updateStudentInClass({
    required int classId,
    required int studentId,
  }) async {
    try {
      final token = await _getToken();

      // You'll need to add this endpoint in backend
      final response = await _dio.put(
        '/classes/$classId/update-student/$studentId/',
        data: {},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error updating student: $e');
      return false;
    }
  }

  /// Admin: Update student's name, email
  Future<Map<String, dynamic>> updateStudentDetails({
    required int studentId,
    String? username,
    String? email,
  }) async {
    try {
      final token = await _getToken();

      final response = await _dio.patch(
        '/admin/students/$studentId/update/',
        data: {
          if (username != null) 'username': username,
          if (email != null) 'email': email,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.data;
    } on DioException catch (e) {
      return {
        'success': false,
        'error': e.response?.data['error'] ?? 'Failed to update student',
      };
    }
  }

  /// Admin: Update teacher's name and email
  Future<Map<String, dynamic>> updateTeacherDetails({
    required int teacherId,
    String? username,
    String? email,
  }) async {
    try {
      final token = await _getToken();

      final response = await _dio.patch(
        '/admin/teachers/$teacherId/update/',
        data: {
          if (username != null) 'username': username,
          if (email != null) 'email': email,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.data;
    } on DioException catch (e) {
      return {
        'success': false,
        'error': e.response?.data['error'] ?? 'Failed to update teacher',
      };
    }
  }

  /// Admin: Update class details (code, name, semester)
  Future<Map<String, dynamic>> updateClassDetails({
    required int classId,
    String? classCode,
    String? className,
    String? semester,
    int? teacherId,
  }) async {
    try {
      final token = await _getToken();

      final response = await _dio.put(
        '/admin/classes/$classId/update/',
        data: {
          if (classCode != null) 'class_code': classCode,
          if (className != null) 'class_name': className,
          if (semester != null) 'semester': semester,
          if (teacherId != null) 'teacher_id': teacherId,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.data;
    } on DioException catch (e) {
      return {
        'success': false,
        'error': e.response?.data['error'] ?? 'Failed to update class',
      };
    }
  }

  /// Admin: Get class details with enrolled students
  Future<Map<String, dynamic>> getAdminClassDetail(int classId) async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/admin/classes/$classId/detail/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        return response.data;
      }

      return {};
    } catch (e) {
      print('Error fetching admin class detail: $e');
      return {};
    }
  }

  /// Admin: Get aggregate stats (teacher count, student count)
  Future<Map<String, dynamic>> getAdminStats() async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/admin/stats/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        return response.data;
      }

      return {};
    } catch (e) {
      print('Error fetching admin stats: $e');
      return {};
    }
  }

  /// Admin: Get users by role (teachers or students)
  Future<Map<String, dynamic>> getUsersByRole(String role) async {
    try {
      final token = await _getToken();

      final response = await _dio.get(
        '/admin/users/$role/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        return response.data;
      }

      return {};
    } catch (e) {
      print('Error fetching $role: $e');
      return {};
    }
  }

  /// Admin: Toggle user access (is_active)
  Future<Map<String, dynamic>> toggleUserAccess(int userId) async {
    try {
      final token = await _getToken();

      final response = await _dio.patch(
        '/admin/users/$userId/toggle-access/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        return response.data;
      }

      return {};
    } catch (e) {
      print('Error toggling user access: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> joinClass(String classCode) async {
    try {
      final token = await _getToken();
      final response = await _dio.post(
        '/classes/join/',
        data: {'class_code': classCode},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'message': response.data['message']};
      }
      return {'success': false, 'message': 'Failed to join class'};
    } catch (e) {
      print('Error joining class: $e');
      if (e is DioException && e.response != null) {
        return {
          'success': false,
          'message': e.response?.data['error'] ?? 'Unknown error',
        };
      }
      return {'success': false, 'message': e.toString()};
    }
  }
}
