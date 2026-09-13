import 'dart:convert';
import 'package:dio/dio.dart';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../core/api_client.dart';
import 'storage_service.dart';

class AuthService {
  final Dio _dio = ApiClient().dio;

  Future<bool> login(String email, String password) async {
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
        return true;
      }
      return false;
    } on DioException catch (e) {
      print(
        'Login error [${e.response?.statusCode}]: ${e.response?.data ?? e.message}',
      );
      print('Exact error: ${e.error}');
      print('Type: ${e.type}');
      return false;
    } catch (e) {
      print('Unexpected login error: $e');
      rethrow;
    }
  }

  Future<bool> signUp({
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
      return response.statusCode == 201;
    } on DioException catch (e) {
      print('Signup error: ${e.response?.data ?? e.message}');
      return false;
    } catch (e) {
      print('Signup error: $e');
      return false;
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
