import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ClassService {
  final String baseUrl = 'http://localhost:8000/api/v1';
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ClassService() {
    _dio.options.baseUrl = baseUrl;
  }

  Future<String?> _getToken() async {
    return await _storage.read(key: 'access_token');
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
        } else if (data is Map) {
          // Handle validation errors
          final errors = <String>[];
          data.forEach((key, value) {
            if (value is List) {
              errors.addAll(value.map((e) => e.toString()));
            } else {
              errors.add(value.toString());
            }
          });
          errorMessage = errors.join('\n');
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
  Future<Map<String, dynamic>?> getClassStudents(int classId) async {
    try {
      final token = await _getToken();
      
      final response = await _dio.get(
        '/classes/$classId/students/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      
      if (response.statusCode == 200) {
        return response.data;
      }
      
      return null;
    } catch (e) {
      print('Error fetching students: $e');
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
      
      return response.statusCode == 204;
    } catch (e) {
      print('Error deleting class: $e');
      return false;
    }
  }

  /// Add a student to an existing class
  Future<Map<String, dynamic>> addStudentToClass({
    required int classId,
    required String name,
    required String email,
    required String password,
    required String rollNo,
  }) async {
    try {
      final token = await _getToken();
      
      final response = await _dio.post(
        '/classes/$classId/add-student/',
        data: {
          'name': name,
          'email': email,
          'password': password,
          'rollNo': rollNo,
        },
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
}