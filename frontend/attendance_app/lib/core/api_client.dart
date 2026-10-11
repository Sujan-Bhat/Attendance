import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../services/storage_service.dart';

/// Best-effort human-readable message for a failed request.
///
/// The response body is NOT guaranteed to be a JSON map — Django serves HTML
/// error pages, proxies return HTML502s, and unknown paths fall through to the
/// Flutter web catch-all — so indexing `response.data['error']` blindly
/// throws `NoSuchMethodError` inside the error handler and the real reason is
/// lost. Always read the body defensively and fall back to the status code.
String apiErrorMessage(Object error, [String fallback = 'Request failed']) {
  if (error is! DioException) return fallback;

  final data = error.response?.data;
  if (data is Map) {
    for (final key in ['error', 'detail', 'message']) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
  } else if (data is String) {
    final text = data.trim();
    // Only surface short strings; a500-page of HTML is not a message.
    if (text.isNotEmpty && text.length < 200 && !text.startsWith('<')) {
      return text;
    }
  }

  switch (error.response?.statusCode) {
    case 400:
      return 'Please check the details you entered';
    case 401:
      return 'Session expired. Please log in again.';
    case 403:
      return 'You do not have permission to do that';
    case 404:
      return 'Not found';
    case 409:
      return 'That record changed or was taken just now. Refresh and retry.';
  }

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return 'Could not reach the server';
    default:
      return error.message ?? fallback;
  }
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  late final Dio dio;
  bool _isRefreshing = false;
  final List<Map<String, dynamic>> _failedRequestsQueue = [];

  factory ApiClient() {
    return _instance;
  }

  ApiClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectionTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await StorageService.read(key: 'access_token');
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          // options.headers['Bypass-Tunnel-Reminder'] = 'true'; change this
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          // If 401 Unauthorized, try to refresh the token
          if (error.response?.statusCode == 401) {
            final RequestOptions options = error.requestOptions;
            
            // Skip refresh for auth endpoints to prevent loops
            if (options.path.contains('/auth/token/')) {
              return handler.next(error);
            }

            if (_isRefreshing) {
              // Wait for the token to be refreshed
              _failedRequestsQueue.add({
                'options': options,
                'handler': handler,
              });
              return;
            }

            _isRefreshing = true;

            try {
              final refreshToken = await StorageService.read(key: 'refresh_token');
              if (refreshToken == null || refreshToken.isEmpty) {
                _clearTokensAndLogout();
                return handler.next(error);
              }

              // Create a separate Dio instance for refreshing to avoid interceptor loops
              final refreshDio = Dio(
                BaseOptions(
                  baseUrl: ApiConfig.baseUrl,
                  connectTimeout: ApiConfig.connectionTimeout,
                  receiveTimeout: ApiConfig.receiveTimeout,
                ),
              );

              final response = await refreshDio.post(
                '/auth/token/refresh/',
                data: {'refresh': refreshToken},
              );

              if (response.statusCode == 200) {
                final newAccessToken = response.data['access'];
                await StorageService.write(key: 'access_token', value: newAccessToken);
                
                // If the backend also rotates refresh tokens, save it
                if (response.data.containsKey('refresh')) {
                  await StorageService.write(key: 'refresh_token', value: response.data['refresh']);
                }

                // Update the current failed request with the new token
                options.headers['Authorization'] = 'Bearer $newAccessToken';
                
                // Retry all queued requests
                for (var req in _failedRequestsQueue) {
                  final reqOptions = req['options'] as RequestOptions;
                  reqOptions.headers['Authorization'] = 'Bearer $newAccessToken';
                  // Retry the request
                  final retryResponse = await dio.fetch(reqOptions);
                  (req['handler'] as ErrorInterceptorHandler).resolve(retryResponse);
                }
                _failedRequestsQueue.clear();

                // Retry the original request that triggered the 401
                final retryResponse = await dio.fetch(options);
                _isRefreshing = false;
                return handler.resolve(retryResponse);
              }
            } catch (e) {
              _failedRequestsQueue.clear();
              _isRefreshing = false;
              _clearTokensAndLogout();
              return handler.next(error);
            }
            
            _isRefreshing = false;
          }
          return handler.next(error);
        },
      ),
    );
  }

  Future<void> _clearTokensAndLogout() async {
    await StorageService.delete(key: 'access_token');
    await StorageService.delete(key: 'refresh_token');
    await StorageService.delete(key: 'user');
    // Note: Since this is an API client, it doesn't have UI context to navigate.
    // However, failing API calls will return empty/error states and many screens
    // handle empty state by showing a message. The auth stream or global state
    // could be notified here if implemented.
  }
}
