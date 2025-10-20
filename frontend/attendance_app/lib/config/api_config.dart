class ApiConfig {
  static const String baseUrl = 'http://localhost:8000/api/v1';
  
  // Auth endpoints
  static const String login = '$baseUrl/auth/token/';
  static const String register = '$baseUrl/auth/register/';
  static const String me = '$baseUrl/auth/me/';
  static const String tokenRefresh = '$baseUrl/auth/token/refresh/';
  
  // Headers
  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
  };
  
  static Map<String, String> authHeaders(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };
}