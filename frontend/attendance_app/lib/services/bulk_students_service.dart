import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api_client.dart';
import 'storage_service.dart';

/// A parsed, still-editable row from an Excel upload.
///
/// `row` is the 1-based Excel sheet row number (header is row 1). `errors`
/// maps a field name (`name`, `email`, `semester`) to the reason the value
/// failed validation.
class BulkRow {
  final int row;
  String name;
  String email;
  String semester;
  final Map<String, String> errors;

  BulkRow({
    required this.row,
    required this.name,
    required this.email,
    required this.semester,
    Map<String, String>? errors,
  }) : errors = errors ?? {};

  bool get hasErrors => errors.isNotEmpty;

  factory BulkRow.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'];
    final errors = <String, String>{};
    if (rawErrors is Map) {
      rawErrors.forEach((k, v) => errors['$k'] = '$v');
    }
    return BulkRow(
      row: (json['row'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?)?.trim() ?? '',
      email: (json['email'] as String?)?.trim().toLowerCase() ?? '',
      semester: (json['semester'] as String?)?.trim() ?? '',
      errors: errors,
    );
  }

  Map<String, String> toRowMap() => {
        'name': name,
        'email': email,
        'semester': semester,
      };
}

/// Result of validating an uploaded file or an edited row set.
class BulkValidateResult {
  final bool valid;
  final int total;
  final List<BulkRow> rows;

  /// Batch-level failure (weak default password, unreadable file, network
  /// error). Without this the backend's `error` payload was silently dropped
  /// and a failed validation looked identical to a passing one.
  final String? error;

  BulkValidateResult({
    required this.valid,
    required this.total,
    required this.rows,
    this.error,
  });

  int get validCount => rows.where((r) => !r.hasErrors).length;
  int get errorCount => rows.where((r) => r.hasErrors).length;
}

/// Handles bulk student creation from an Excel-like upload.
class BulkStudentsService {
  final Dio _dio = ApiClient().dio;

  /// Dio is a shared singleton already configured by ApiClient; never mutate
  /// its options here (see ClassService).
  BulkStudentsService();

  Future<String?> _getToken() async {
    return await StorageService.read(key: 'access_token');
  }

  /// Parse + validate an uploaded Excel file. Never writes to the DB.
  Future<BulkValidateResult> validateUpload({
    required Uint8List fileBytes,
    required String fileName,
    required String defaultPassword,
  }) async {
    try {
      final token = await _getToken();
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
        'default_password': defaultPassword,
      });
      final response = await _dio.post(
        '/admin/students/bulk/validate/',
        data: formData,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return _parseValidateResponse(response.data);
    } catch (e) {
      return BulkValidateResult(
        valid: false,
        total: 0,
        rows: const [],
        error: apiErrorMessage(e, 'Could not read that file.'),
      );
    }
  }

  /// Re-validate the (possibly edited) rows without touching the DB.
  Future<BulkValidateResult> validateRows({
    required List<BulkRow> rows,
    required String defaultPassword,
  }) async {
    try {
      final token = await _getToken();
      final response = await _dio.post(
        '/admin/students/bulk/validate-rows/',
        data: {
          'rows': rows.map((r) => r.toRowMap()).toList(),
          'default_password': defaultPassword,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return _parseValidateResponse(response.data);
    } catch (e) {
      // Surface the failure instead of returning error-free rows: otherwise
      // the review step would show "N students ready to add" after a call
      // that never actually ran.
      return BulkValidateResult(
        valid: false,
        total: rows.length,
        rows: rows,
        error: apiErrorMessage(e, 'Could not re-validate the rows'),
      );
    }
  }

  /// Create every row atomically (all-or-nothing). Returns created count.
  Future<Map<String, dynamic>> createBulk({
    required List<BulkRow> rows,
    required String defaultPassword,
  }) async {
    try {
      final token = await _getToken();
      final response = await _dio.post(
        '/admin/students/bulk/create/',
        data: {
          'rows': rows.map((r) => r.toRowMap()).toList(),
          'default_password': defaultPassword,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } on DioException catch (e) {
      return {
        'success': false,
        'error': apiErrorMessage(e, 'Failed to create students'),
      };
    } catch (e) {
      return {'success': false, 'error': apiErrorMessage(e, e.toString())};
    }
  }

  BulkValidateResult _parseValidateResponse(dynamic data) {
    if (data is! Map) {
      return BulkValidateResult(
        valid: false,
        total: 0,
        rows: const [],
        error: 'Unexpected response from the server',
      );
    }
    final rawRows = data['rows'];
    final rows = <BulkRow>[];
    if (rawRows is List) {
      rows.addAll(
        rawRows.whereType<Map>().map((m) => BulkRow.fromJson(Map<String, dynamic>.from(m))),
      );
    }
    // The backend reports batch-level problems (e.g. "Default password must
    // be at least 6 characters") in `error`, alongside otherwise valid rows.
    final batchError = data['error'];
    return BulkValidateResult(
      valid: data['valid'] == true,
      total: (data['total'] as num?)?.toInt() ?? rows.length,
      rows: rows,
      error: batchError is String && batchError.isNotEmpty ? batchError : null,
    );
  }
}