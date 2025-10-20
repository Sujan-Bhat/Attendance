import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final String baseUrl = 'http://localhost:8000/api/v1'; 
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late SharedPreferences _prefs;

  AuthService() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 5);
    _dio.options.receiveTimeout = const Duration(seconds: 3);

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  Future<bool> login(String username, String password) async {
    try {
      final response = await _dio.post('/auth/token/', data: {
        'username': username,
        'password': password,
      });

      if (response.statusCode == 200) {
        await _storage.write(key: 'access_token', value: response.data['access']);
        await _storage.write(key: 'refresh_token', value: response.data['refresh']);

        try {
          final me = await _dio.get('/auth/me/');
          await _storage.write(key: 'user', value: json.encode(me.data));
        } catch (e) {
          print('Error fetching user data: $e');
        }
        return true;
      }
      return false;
    } on DioException catch (e) {
      print('❌ Login error [${e.response?.statusCode}]: ${e.response?.data ?? e.message}');
      // Let the UI handle the DioException
      rethrow;
    } catch (e) {
      print('❌ Unexpected login error: $e');
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
      final response = await _dio.post('/auth/register/', data: {
        'username': username,
        'email': email,
        'password': password,
        'password2': password2,
        'role': role.toLowerCase(),
      });
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
      return response.data;
    } catch (e) {
      print('Get user error: $e');
      return null;
    }
  }

  Future<String> getUserRole() async {
    try {
      final userJson = await _storage.read(key: 'user');
      if (userJson != null && userJson.isNotEmpty) {
        final map = json.decode(userJson) as Map<String, dynamic>;
        final role = (map['role'] ?? map['data']?['role'] ?? '').toString().toLowerCase();
        if (role.isNotEmpty) return role;
      }
      // Fallback: fetch from API and cache
      final me = await _dio.get('/auth/me/');
      await _storage.write(key: 'user', value: json.encode(me.data));
      final role = (me.data['role'] ?? '').toString().toLowerCase();
      return role.isNotEmpty ? role : 'student';
    } catch (_) {
      return 'student';
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'user');
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: 'access_token');
    return token != null;
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }
}