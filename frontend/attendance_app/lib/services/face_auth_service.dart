import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';

enum FaceVerifyStatus {
  success,
  mismatch,
  noFaceDetected,
  notRegistered,
  error,
}

class FaceVerifyResult {
  final FaceVerifyStatus status;
  final String message;
  final double? similarity;

  FaceVerifyResult({
    required this.status,
    required this.message,
    this.similarity,
  });

  bool get isSuccess => status == FaceVerifyStatus.success;
}

class FaceAuthService {
  static const String _faceStatusKey = 'has_registered_face';
  final Dio _dio = ApiClient().dio;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    print("FaceAuthService (Backend Mode) Initialized");
  }

  /// Checks if the user has a saved face embedding (checks server first when online, falls back to local cache)
  Future<bool> hasSavedFace() async {
    final prefs = await SharedPreferences.getInstance();

    // Check with backend first if online for ground truth
    try {
      final response = await _dio.get('/faces/status/');
      if (response.statusCode == 200) {
        final hasFace = response.data['has_registered_face'] == true;
        await prefs.setBool(_faceStatusKey, hasFace);
        return hasFace;
      }
    } catch (_) {}

    // Fallback to local cache only if server could not be reached
    return prefs.getBool(_faceStatusKey) ?? false;
  }

  /// Helper to convert camera image to base64
  Future<String> _imageToBase64(dynamic cameraImage) async {
    final XFile xFile = cameraImage as XFile;
    final bytes = await xFile.readAsBytes();
    return base64Encode(bytes);
  }

  /// Register a new face with the backend
  Future<Map<String, dynamic>> registerFace(dynamic cameraImage) async {
    try {
      final base64Image = await _imageToBase64(cameraImage);
      
      final response = await _dio.post(
        '/faces/register/',
        data: {'image': base64Image},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_faceStatusKey, true);
        return {'success': true, 'message': 'Face registered successfully!'};
      }
      return {'success': false, 'message': 'Registration failed.'};
    } on DioException catch (e) {
      final msg = e.response?.data?['error']?.toString() ?? 'Registration failed.';
      print("Registration DioError: ${e.response?.data}");
      return {'success': false, 'message': msg};
    } catch (e) {
      print("Registration error: $e");
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  /// Verify a live face against saved face via backend
  Future<FaceVerifyResult> verifyFace(dynamic cameraImage) async {
    try {
      final base64Image = await _imageToBase64(cameraImage);

      final response = await _dio.post(
        '/faces/verify/',
        data: {'image': base64Image},
      );

      if (response.statusCode == 200) {
        final isMatch = response.data['success'] == true;
        final sim = (response.data['similarity'] as num?)?.toDouble();
        if (isMatch) {
          return FaceVerifyResult(
            status: FaceVerifyStatus.success,
            message: "Face matched successfully!",
            similarity: sim,
          );
        } else {
          return FaceVerifyResult(
            status: FaceVerifyStatus.mismatch,
            message: "Face not recognized. Try again.",
            similarity: sim,
          );
        }
      }
      return FaceVerifyResult(
        status: FaceVerifyStatus.error,
        message: "Server error during verification.",
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_faceStatusKey, false);
        return FaceVerifyResult(
          status: FaceVerifyStatus.notRegistered,
          message: "No registered face found on server.",
        );
      }
      final serverMsg = e.response?.data?['error']?.toString();
      if (serverMsg != null && serverMsg.toLowerCase().contains('no face detected')) {
        return FaceVerifyResult(
          status: FaceVerifyStatus.noFaceDetected,
          message: "No face detected in camera.",
        );
      }
      return FaceVerifyResult(
        status: FaceVerifyStatus.error,
        message: serverMsg ?? "Face verification failed.",
      );
    } catch (e) {
      return FaceVerifyResult(
        status: FaceVerifyStatus.error,
        message: "Verification error: $e",
      );
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
