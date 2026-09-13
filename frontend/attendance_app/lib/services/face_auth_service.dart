import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';

class FaceAuthService {
  static const String _faceStatusKey = 'has_registered_face';
  final Dio _dio = ApiClient().dio;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    print("FaceAuthService (Backend Mode) Initialized");
  }

  /// Checks if the user has a saved face embedding (locally cached status)
  Future<bool> hasSavedFace() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_faceStatusKey) ?? false;
  }

  /// Helper to convert camera image to base64
  Future<String> _imageToBase64(dynamic cameraImage) async {
    final XFile xFile = cameraImage as XFile;
    final bytes = await xFile.readAsBytes();
    return base64Encode(bytes);
  }

  /// Register a new face with the backend
  Future<bool> registerFace(dynamic cameraImage) async {
    try {
      final base64Image = await _imageToBase64(cameraImage);
      
      final response = await _dio.post(
        '/faces/register/',
        data: {'image': base64Image},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_faceStatusKey, true);
        return true;
      }
      return false;
    } on DioException catch (e) {
      print("Registration DioError: ${e.response?.data}");
      return false;
    } catch (e) {
      print("Registration error: $e");
      return false;
    }
  }

  /// Verify a live face against saved face via backend
  Future<bool> verifyFace(dynamic cameraImage) async {
    try {
      final base64Image = await _imageToBase64(cameraImage);

      final response = await _dio.post(
        '/faces/verify/',
        data: {'image': base64Image},
      );

      if (response.statusCode == 200) {
        // Backend returns whether verification passed
        return response.data['success'] == true;
      }
      return false;
    } catch (e) {
      print("Verification error: $e");
      return false;
    }
  }

  // --- OFFLINE (NATIVE ANDROID) INTEGRATION ---

  static const MethodChannel _offlineChannel = MethodChannel('attendance_app/offline');

  /// Checks if there's a saved face locally (for offline mode)
  Future<bool> hasSavedFaceOffline() async {
    try {
      final result = await _offlineChannel.invokeMethod<bool>('hasSavedFace');
      return result == true;
    } catch (e) {
      print("hasSavedFaceOffline error: $e");
      return false;
    }
  }

  Future<bool> registerFaceOffline(String imagePath) async {
    try {
      final result = await _offlineChannel.invokeMethod<bool>(
        'registerOffline',
        {'imagePath': imagePath},
      );
      if (result == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_faceStatusKey, true);
      }
      return result == true;
    } catch (e) {
      print("registerFaceOffline error: $e");
      return false;
    }
  }

  /// Verify face locally via Native Android (TFLite)
  Future<bool> verifyFaceOffline(String imagePath) async {
    try {
      final result = await _offlineChannel.invokeMapMethod<String, dynamic>(
        'verifyOffline',
        {'imagePath': imagePath},
      );
      return result?['success'] == true;
    } catch (e) {
      print("verifyFaceOffline error: $e");
      return false;
    }
  }
}
