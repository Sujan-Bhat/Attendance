import 'package:flutter/foundation.dart';

class ApiConfig {
  // Override the base URL at compile time for ANY environment (physical
  // device, your own server, CI) without editing this file:
  //   flutter run --dart-define=API_BASE_URL=https://your-host/api/v1
  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  // For Android Emulator (default for mobile dev)
  static const String _androidEmulatorUrl = 'http://10.0.2.2:8000/api/v1';

  // For Web
  static const String _webUrl = 'http://localhost:8000/api/v1';

  // Example production URL - replace with YOUR own host, or simply use the
  // API_BASE_URL override above. Do not ship the original author's URL.
  static const String _productionUrl =
      'https://your-backend.example.com/api/v1';

  // Set to true for production builds. The actual host still comes from the
  // API_BASE_URL override (falls back to _productionUrl as a placeholder).
  static const bool isProduction = false;

  // Base URL resolution
  static String get baseUrl {
    if (_apiBaseUrl.isNotEmpty) return _apiBaseUrl; // override wins everywhere
    if (isProduction) return _productionUrl;
    if (kIsWeb) {
      return _webUrl;
    }
    return _androidEmulatorUrl; // mobile default (emulator)
  }

  // Connection settings (90s to handle Render free-tier cold starts gracefully)
  static const Duration connectionTimeout = Duration(seconds: 90);
  static const Duration receiveTimeout = Duration(seconds: 90);

  // Auth endpoints
  static String login = '$baseUrl/auth/token/';
  static String register = '$baseUrl/auth/register/';
  static String me = '$baseUrl/auth/me/';
  static String tokenRefresh = '$baseUrl/auth/token/refresh/';

  // Headers
  static Map<String, String> get headers => {
    // 'Bypass-Tunnel-Reminder':'true', // Required to bypass Localtunnel warning page
  };

  static Map<String, String> authHeaders(String? token) => {
    'Authorization': 'Bearer ${token ?? ""}',
    // 'Bypass-Tunnel-Reminder':
    //     'true', // Required to bypass Localtunnel warning page
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
