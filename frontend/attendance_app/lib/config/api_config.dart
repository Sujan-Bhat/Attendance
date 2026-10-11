import 'package:flutter/foundation.dart';

class ApiConfig {
  // Override the base URL at compile time for ANY environment:
  //   flutter run --dart-define=API_BASE_URL=https://your-forwarded-port.devtunnels.ms/api/v1
  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  // Local testing / VS Code Port Forwarding URL (change this to your VS Code forwarded port URL if testing on mobile)
  static const String _localPortForwardUrl = 'https://qdg6mx71-8000.inc1.devtunnels.ms/api/v1';

  // For Android Emulator (default for mobile dev)
  static const String _androidEmulatorUrl = 'https://qdg6mx71-8000.inc1.devtunnels.ms/api/v1';

  // Production URL
  static const String _productionUrl = 'https://presence-cne6ezafcncnduf3.indiasouthcentral-01.azurewebsites.net/api/v1';

  // Toggle between local testing (false) and production (true)
  static const bool isProduction = true;

  // Base URL resolution
  static String get baseUrl {
    if (_apiBaseUrl.isNotEmpty) return _apiBaseUrl; // CLI --dart-define wins
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && !origin.contains('localhost') && !origin.contains('127.0.0.1')) {
        return '$origin/api/v1';
      }
    }
    if (isProduction) return _productionUrl;
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return _localPortForwardUrl;
    }
    return _androidEmulatorUrl;
  }

  // Connection settings
  static const Duration connectionTimeout = Duration(seconds: 90);
  static const Duration receiveTimeout = Duration(seconds: 90);

  // Auth endpoints
  static String login = '$baseUrl/auth/token/';
  static String register = '$baseUrl/auth/register/';
  static String me = '$baseUrl/auth/me/';
  static String tokenRefresh = '$baseUrl/auth/token/refresh/';

  // Headers
  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Bypass-Tunnel-Reminder': 'true', // Bypasses tunnel landing page warnings
  };

  static Map<String, String> authHeaders(String? token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${token ?? ""}',
    'Bypass-Tunnel-Reminder': 'true',
  };
}
// import 'package:flutter/foundation.dart';

// class ApiConfig {
//   static const String _apiBaseUrl =
//       String.fromEnvironment('API_BASE_URL');

//   // Android Emulator
//   static const String _androidEmulatorUrl =
//       'http://10.0.2.2:8000/api/v1';

//   // Flutter Web / Chrome
//   static const String _webUrl =
//       'http://localhost:8000/api/v1';

//   static const String _productionUrl =
//       'https://your-backend.example.com/api/v1';

//   static const bool isProduction = false;

//   // static String get baseUrl {
//   //   if (_apiBaseUrl.isNotEmpty) {
//   //     return _apiBaseUrl;
//   //   }

//   //   if (isProduction) {
//   //     return _productionUrl;
//   //   }

//   //   if (kIsWeb) {
//   //     return _webUrl;
//   //   }

//   //   return _androidEmulatorUrl;
//   // }
//     static String get baseUrl {
//     if (_apiBaseUrl.isNotEmpty) {
//       return _apiBaseUrl;
//     }

//     if (isProduction) {
//       return _productionUrl;
//     }

//     if (defaultTargetPlatform == TargetPlatform.windows) {
//       return _webUrl;
//     }

//     if (kIsWeb) {
//       return _webUrl;
//     }

//     return _androidEmulatorUrl;
//   }

//   static const Duration connectionTimeout =
//       Duration(seconds: 90);

//   static const Duration receiveTimeout =
//       Duration(seconds: 90);

//   static String login = '$baseUrl/auth/token/';
//   static String register = '$baseUrl/auth/register/';
//   static String me = '$baseUrl/auth/me/';
//   static String tokenRefresh =
//       '$baseUrl/auth/token/refresh/';

//   static Map<String, String> get headers => {
//         'Content-Type': 'application/json',
//       };

//   static Map<String, String> authHeaders(String? token) => {
//         'Content-Type': 'application/json',
//         'Authorization': 'Bearer ${token ?? ""}',
//       };
// }
