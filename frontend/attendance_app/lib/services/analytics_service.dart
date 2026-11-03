import 'package:dio/dio.dart';
import '../config/api_config.dart';
import 'storage_service.dart';
import '../core/api_client.dart';

class AnalyticsService {
  final Dio _dio = ApiClient().dio;

  AnalyticsService() {
    _dio.options.baseUrl = ApiConfig.baseUrl;
    _dio.options.connectTimeout = ApiConfig.connectionTimeout;
    _dio.options.receiveTimeout = ApiConfig.receiveTimeout;
  }

  Future<String?> _getToken() async {
    return await StorageService.read(key: 'access_token');
  }

  Future<Map<String, dynamic>?> getTeacherAnalytics() async {
    try {
      final token = await _getToken();
      if (token == null) return null;

      final response = await _dio.get(
        '/analytics/teacher/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return null;
    } on DioException catch (e) {
      print('Teacher analytics error: ${e.message}');
      return null;
    } catch (e) {
      print('Unexpected error in getTeacherAnalytics: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getStudentAnalytics() async {
    try {
      final token = await _getToken();
      if (token == null) return null;

      final response = await _dio.get(
        '/analytics/student/',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return null;
    } on DioException catch (e) {
      print('Student analytics error: ${e.message}');
      return null;
    } catch (e) {
      print('Unexpected error in getStudentAnalytics: $e');
      return null;
    }
  }
}
