import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
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

  BulkValidateResult({
    required this.valid,
    required this.total,
    required this.rows,
  });

  int get validCount => rows.where((r) => !r.hasErrors).length;
  int get errorCount => rows.where((r) => r.hasErrors).length;
}

/// Handles bulk student creation from an Excel-like upload.
///
/// While [bulkMockMode] is `true` the real endpoints are NOT called; instead
/// a canned dataset is returned so the whole UI flow can be exercised before
/// the backend bulk endpoints exist. Flip it to `false` once those endpoints
/// are in place.
class BulkStudentsService {
  final Dio _dio = ApiClient().dio;

  /// Temporary switch: `true` until the backend bulk endpoints are live.
  static const bool bulkMockMode = false;

  BulkStudentsService() {
    _dio.options.baseUrl = ApiConfig.baseUrl;
    _dio.options.connectTimeout = ApiConfig.connectionTimeout;
    _dio.options.receiveTimeout = ApiConfig.receiveTimeout;
  }

  Future<String?> _getToken() async {
    return await StorageService.read(key: 'access_token');
  }

  /// Parse + validate an uploaded Excel file. Never writes to the DB.
  Future<BulkValidateResult> validateUpload({
    required Uint8List fileBytes,
    required String fileName,
    required String defaultPassword,
  }) async {
    if (bulkMockMode) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return _mockValidateRows(defaultPassword: defaultPassword);
    }

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
        rows: [],
      )..rows.add(BulkRow(
          row: 0,
          name: '',
          email: '',
          semester: '',
          errors: {'name': 'Could not read that file. ${_friendlyError(e)}'},
        ));
    }
  }

  /// Re-validate the (possibly edited) rows without touching the DB.
  Future<BulkValidateResult> validateRows({
    required List<BulkRow> rows,
    required String defaultPassword,
  }) async {
    if (bulkMockMode) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return _mockValidateRows(rows: rows, defaultPassword: defaultPassword);
    }

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
      return BulkValidateResult(
        valid: false,
        total: rows.length,
        rows: rows,
      );
    }
  }

  /// Create every row atomically (all-or-nothing). Returns created count.
  Future<Map<String, dynamic>> createBulk({
    required List<BulkRow> rows,
    required String defaultPassword,
  }) async {
    if (bulkMockMode) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final validRows = rows.where((r) => !r.hasErrors).toList();
      return {
        'success': true,
        'created': validRows.length,
        'users': validRows
            .map((r) => {
                  'username': r.name,
                  'email': r.email,
                  'semester': r.semester,
                })
            .toList(),
      };
    }

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
        'error': (e.response?.data is Map &&
                (e.response?.data as Map)['error'] != null)
            ? (e.response?.data as Map)['error'].toString()
            : 'Failed to create students',
      };
    } catch (e) {
      return {'success': false, 'error': _friendlyError(e)};
    }
  }

  BulkValidateResult _parseValidateResponse(dynamic data) {
    if (data is! Map) {
      return BulkValidateResult(valid: false, total: 0, rows: []);
    }
    final rawRows = data['rows'];
    final rows = <BulkRow>[];
    if (rawRows is List) {
      rows.addAll(
        rawRows.whereType<Map>().map((m) => BulkRow.fromJson(Map<String, dynamic>.from(m))),
      );
    }
    return BulkValidateResult(
      valid: data['valid'] == true,
      total: (data['total'] as num?)?.toInt() ?? rows.length,
      rows: rows,
    );
  }

  BulkValidateResult _mockValidateRows({
    List<BulkRow>? rows,
    required String defaultPassword,
  }) {
    List<BulkRow> workingRows;
    if (rows == null) {
      workingRows = [
        BulkRow(row: 2, name: 'Aisha Rahman', email: 'aisha.rahman@example.com', semester: '3'),
        BulkRow(row: 3, name: 'Rajesh Kumar', email: 'rajesh.kumar@example.com', semester: '2'),
        BulkRow(row: 4, name: '', email: 'priya.sharma@example.com', semester: '2'),
        BulkRow(row: 5, name: 'Rahul Verma', email: 'not-an-email', semester: '4'),
        BulkRow(row: 6, name: 'Priya Sharma', email: 'priya.sharma@example.com', semester: '1'),
        BulkRow(row: 7, name: 'Neha Singh', email: 'neha.singh@example.com', semester: ''),
        BulkRow(row: 8, name: 'Karan Mehta', email: 'karan.mehta@example.com', semester: '5'),
      ];
    } else {
      workingRows = List.of(rows);
    }

    final seenEmails = <String>{};
    final duplicateEmails = <String>{};
    for (final r in workingRows) {
      if (r.email.isEmpty) continue;
      if (!seenEmails.add(r.email)) {
        duplicateEmails.add(r.email);
      }
    }

    for (final r in workingRows) {
      r.errors.clear();
      if (r.name.trim().isEmpty) {
        r.errors['name'] = 'Name is required';
      }
      final email = r.email.trim();
      if (email.isEmpty) {
        r.errors['email'] = 'Email is required';
      } else if (!email.contains('@')) {
        r.errors['email'] = 'Enter a valid email';
      } else if (duplicateEmails.contains(email)) {
        r.errors['email'] = 'Email appears more than once in the file';
      }
      if (r.semester.trim().isEmpty) {
        r.errors['semester'] = 'Semester is required';
      }
    }

    return BulkValidateResult(
      total: workingRows.length,
      rows: workingRows,
      valid: workingRows.every((r) => !r.hasErrors),
    );
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'Could not reach the server';
      }
      final data = error.response?.data;
      if (data is Map && data['error'] != null) {
        return data['error'].toString();
      }
      return error.message ?? 'Request failed';
    }
    return error.toString();
  }
}