import 'dart:convert';
import 'package:dio/dio.dart';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../core/api_client.dart';
import 'storage_service.dart';

class LoginResult {
  final bool success;
  final String? errorMessage;

  const LoginResult({required this.success, this.errorMessage});

  factory LoginResult.ok() => const LoginResult(success: true);
  factory LoginResult.failed([String? message]) =>
      LoginResult(success: false, errorMessage: message);
}

class AuthService {
  final Dio _dio = ApiClient().dio;

  /// Attempts login and returns a [LoginResult] so callers can surface
  /// server-specific reasons (e.g. "account blocked by administrator")
  /// instead of a generic failure.
  Future<LoginResult> login(String email, String password) async {
    try {
      // Step 1: Make POST request to /auth/token/ endpoint(Django backend)
      final response = await _dio.post(
        '/auth/token/',
        data: {'email': email, 'password': password},
        options: Options(headers: ApiConfig.headers),
      );

      if (response.statusCode == 200) {
        // Step 2: Store tokens securely
        await StorageService.write(
          key: 'access_token',
          value: response.data['access'],
        );
        await StorageService.write(
          key: 'refresh_token',
          value: response.data['refresh'],
        );

        // Step 3: Fetch and store user profile data
        try {
          final me = await _dio.get('/auth/me/');
          await StorageService.write(key: 'user', value: json.encode(me.data));
        } catch (e) {
          print('Error fetching user data: $e');
        }
        return LoginResult.ok();
      }
      return LoginResult.failed();
    } on DioException catch (e) {
      print(
        'Login error [${e.response?.statusCode}]: ${e.response?.data ?? e.message}',
      );
      print('Exact error: ${e.error}');
      print('Type: ${e.type}');

      // Django typically returns 401 for both bad credentials and blocked
      // accounts; the server sends a human-readable `detail` we can show.
      final data = e.response?.data;
      String? detail;
      if (data is Map && data['detail'] is String) {
        detail = data['detail'] as String;
      } else if (data is Map && data['error'] is String) {
        detail = data['error'] as String;
      }

      if (e.response?.statusCode == 401) {
        final msg = detail ?? 'Invalid email or password';
        return LoginResult.failed(msg);
      }
      if (e.response?.statusCode == 404) {
        return LoginResult.failed('Server not found');
      }
      if (e.response?.statusCode == 500) {
        return LoginResult.failed('Server error. Please try again later');
      }
      if (e.type == DioExceptionType.connectionTimeout) {
        return LoginResult.failed('Connection timeout');
      }
      if (e.type == DioExceptionType.connectionError) {
        return LoginResult.failed('Cannot connect to server');
      }
      return LoginResult.failed(detail ?? 'Login failed. Please try again.');
    } catch (e) {
      print('Unexpected login error: $e');
      rethrow;
    }
  }

  Future<LoginResult> signUp({
    required String username,
    required String email,
    required String password,
    required String password2,
    required String role,
  }) async {
    try {
      // Make POST request to /auth/register/ endpoint(Django backend)
      final response = await _dio.post(
        '/auth/register/',
        data: {
          'username': username,
          'email': email,
          'password': password,
          'password2': password2,
          'role': role.toLowerCase(),
        },
      );
      // Success if status code is 201 Created
      return response.statusCode == 201
          ? LoginResult.ok()
          : LoginResult.failed();
    } on DioException catch (e) {
      print('Signup error: ${e.response?.data ?? e.message}');
      return LoginResult.failed();
    } catch (e) {
      print('Signup error: $e');
      return LoginResult.failed();
    }
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final response = await _dio.get('/auth/me/');
      await StorageService.write(key: 'user', value: json.encode(response.data));
      return response.data;
    } catch (e) {
      print('Get user error: $e');
      try {
        final userJson = await StorageService.read(key: 'user');
        if (userJson != null && userJson.isNotEmpty) {
          return json.decode(userJson) as Map<String, dynamic>;
        }
      } catch (_) {}
      return null;
    }
  }

  Future<String> getUserRole() async {
    try {
      final userJson = await StorageService.read(key: 'user');
      if (userJson != null && userJson.isNotEmpty) {
        final map = json.decode(userJson) as Map<String, dynamic>;
        final role = (map['role'] ?? map['data']?['role'] ?? '')
            .toString()
            .toLowerCase();
        if (role.isNotEmpty) return role;
      }
      // Fallback: fetch from API and cache
      final me = await _dio.get('/auth/me/');
      await StorageService.write(key: 'user', value: json.encode(me.data));
      final role = (me.data['role'] ?? '').toString().toLowerCase();
      return role.isNotEmpty ? role : 'student';
    } catch (_) {
      return 'student';
    }
  }

  Future<void> logout() async {
    await StorageService.delete(key: 'access_token');
    await StorageService.delete(key: 'refresh_token');
    await StorageService.delete(key: 'user');
  }

  Future<bool> isLoggedIn() async {
    final token = await StorageService.read(key: 'access_token');
    return token != null;
  }
}
