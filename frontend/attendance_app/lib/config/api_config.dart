class ApiConfig {
  // Local IP for physical phone testing on same Wi-Fi.
  static const String _localIp = '';

  // Compile-time overrides:
  // flutter run --dart-define=API_BASE_URL=https://your-backend.onrender.com/api/v1
  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  // Local defaults
  static const String _computerBaseUrl = 'http://localhost:8000/api/v1';

  static String get baseUrl {
    if (_apiBaseUrl.isNotEmpty) {
      return _apiBaseUrl;
    }

    if (_localIp.isNotEmpty) {
      return 'http://$_localIp:8000/api/v1';
    }

    return _computerBaseUrl;
  }
  
  // Connection settings
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  
  // Auth endpoints
  static String login = '$baseUrl/auth/token/';
  static String register = '$baseUrl/auth/register/';
  static String me = '$baseUrl/auth/me/';
  static String tokenRefresh = '$baseUrl/auth/token/refresh/';
  
  // Headers
  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
  };
  
  static Map<String, String> authHeaders(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };
}
