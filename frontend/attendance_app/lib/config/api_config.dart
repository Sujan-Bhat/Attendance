class ApiConfig {
  //  Use your actual local IP
  static const String _localIp = ''; // IP address

  // Choose based on where you're running
  static const String _computerBaseUrl = 'http://localhost:8000/api/v1';
  static const String _androidBaseUrl = 'http://$_localIp:8000/api/v1';
  
  // Auto-detect or manually set
  static String get baseUrl {
    // For now, use local IP for both (works everywhere)
    return _androidBaseUrl;
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
