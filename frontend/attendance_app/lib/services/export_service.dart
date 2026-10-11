import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';

import '../config/api_config.dart';
import '../utils/web_utils_stub.dart'
    if (dart.library.js_interop) '../utils/web_utils.dart';
import 'storage_service.dart';

/// Admin exports: download (web) or share (mobile) PDF/Excel exports of
/// students, teachers, classes and attendance details. The backend renders
/// the documents; this service only transports the bytes.
class ExportService {
  /// Deliberately NOT the shared ApiClient Dio: exports legitimately need a
  /// long receive timeout, and mutating the singleton's `options` would
  /// silently change that timeout for every other request in the app.
  late final Dio _dio;

  /// Set by [fetchExport]: the server's timestamped filename (if any) so the
  /// downloaded file matches what the backend rendered.
  String? _lastFilename;

  ExportService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectionTimeout,
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
  }

  /// Fetch an export from `/admin/export/<dataset>/<format>/` as bytes.
  Future<Uint8List> fetchExport({
    required String dataset,
    required String format,
    String? semester,
  }) async {
    final token = await StorageService.read(key: 'access_token');
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await _dio.get<List<int>>(
      '/admin/export/$dataset/$format/',
      queryParameters: {
        if (semester != null && semester.trim().isNotEmpty)
          'semester': semester.trim(),
      },
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.bytes,
      ),
    );

    final data = response.data;
    if (data == null || data.isEmpty) {
      throw Exception('Export returned no data');
    }
    _lastFilename = _filenameFrom(response.headers);
    return Uint8List.fromList(data);
  }

  String? _filenameFrom(Headers headers) {
    final disposition = headers.value('content-disposition');
    if (disposition == null) return null;
    final match = RegExp(r'filename="?([^";]+)"?').firstMatch(disposition);
    return match?.group(1)?.trim();
  }

  /// Full export flow: fetch the bytes, then download them on web or open
  /// the platform share sheet on mobile.
  Future<void> exportDataset({
    required String dataset,
    required String format,
    String? semester,
  }) async {
    final bytes = await fetchExport(
      dataset: dataset,
      format: format,
      semester: semester,
    );

    final mime = format == 'pdf'
        ? 'application/pdf'
        : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    final extension = format == 'pdf' ? 'pdf' : 'xlsx';
    final scope = (semester == null || semester.trim().isEmpty)
        ? ''
        : '_sem${semester.trim()}';
    // Prefer the name the backend attached (it carries a timestamp, so two
    // exports in the same minute don't overwrite each other in the browser).
    final filename = _lastFilename ??
        '${dataset}_details$scope.$extension';
    _lastFilename = null;

    if (kIsWeb) {
      downloadWeb(bytes, filename, mimeType: mime);
      return;
    }

    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: mime, name: filename)],
      subject: filename,
    );
  }
}
