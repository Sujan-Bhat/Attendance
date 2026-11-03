import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../main.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  // Stream to notify listeners when a sync completes
  final _syncCompleteController = StreamController<void>.broadcast();
  Stream<void> get onSyncComplete => _syncCompleteController.stream;

  Database? _database;
  final AttendanceService _attendanceService = AttendanceService();
  Timer? _syncTimer;
  bool _isSyncing = false;
  int _syncCycleCount = 0;
  final Map<dynamic, int> _retryCountMap = {};

  SyncService._internal() {
    _startPeriodicSync();
    _listenForConnectivityChanges();
  }

  void _startPeriodicSync() {
    // Try to sync every 30 seconds automatically for edge cases where the user remains online
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncQueueToServer();
    });
  }

  /// Instantly trigger sync when the device regains connectivity.
  void _listenForConnectivityChanges() {
    Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.isNotEmpty && !results.contains(ConnectivityResult.none);
      if (isOnline && !_isSyncing) {
        debugPrint('[SyncService] Connectivity restored! Resetting backoff and triggering immediate sync...');
        _retryCountMap.clear();
        syncQueueToServer();
      }
    });
  }

  /// Exponential backoff: items that keep failing are retried less frequently.
  /// - Attempts 0-2: every cycle (30s)
  /// - Attempts 3-5: every 2nd cycle (60s)
  /// - Attempts 6-10: every 4th cycle (2min)
  /// - Attempts 11-20: every 10th cycle (5min)
  /// - Attempts >20: every 30th cycle (15min)
  /// Note: Items are never permanently failed by count; they naturally expire after 24 hours.
  bool _shouldRetryItem(dynamic itemId) {
    final count = _retryCountMap[itemId] ?? 0;
    if (count < 3) return true;
    if (count < 6) return _syncCycleCount % 2 == 0;
    if (count < 11) return _syncCycleCount % 4 == 0;
    if (count < 21) return _syncCycleCount % 10 == 0;
    return _syncCycleCount % 30 == 0;
  }

  void _recordRetryFailure(dynamic itemId) {
    _retryCountMap[itemId] = (_retryCountMap[itemId] ?? 0) + 1;
  }

  void _clearRetryCount(dynamic itemId) {
    _retryCountMap.remove(itemId);
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  static const int _dbVersion = 8;

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'offline_sync.db');

    return await openDatabase(
      path,
      version: _dbVersion,
      onUpgrade: (db, oldVersion, newVersion) async {
        debugPrint('[SyncService] onUpgrade from $oldVersion to $newVersion');
        await _ensureSchema(db);
      },
      onCreate: (db, version) async {
        debugPrint('[SyncService] onCreate version $version');
        await _ensureSchema(db);
      },
      onOpen: (db) async {
        debugPrint('[SyncService] onOpen database - checking schema self-repair');
        await _ensureSchema(db);
      },
    );
  }

  /// Ensures all tables and all required columns exist across any DB version.
  /// Self-heals in-place without deleting existing user data.
  Future<void> _ensureSchema(Database db) async {
    // 1. Ensure all required tables exist
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        image_path TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        ble_hop_count INTEGER,
        ble_rssi INTEGER,
        status TEXT DEFAULT 'pending'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_sessions (
        id TEXT PRIMARY KEY,
        class_id INTEGER NOT NULL,
        class_type TEXT NOT NULL,
        duration_minutes INTEGER NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        shape_data TEXT,
        reference_image_path TEXT,
        totp_secret TEXT,
        rotation_interval INTEGER,
        status TEXT DEFAULT 'pending'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_qr_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        ble_hop_count INTEGER,
        ble_rssi INTEGER,
        qr_token TEXT,
        captcha TEXT,
        status TEXT DEFAULT 'pending'
      )
    ''');

    // 2. Safely ensure all columns exist across table variations
    await _ensureColumns(db, 'offline_queue', {
      'image_path': 'TEXT NOT NULL DEFAULT ""',
      'timestamp': 'TEXT NOT NULL DEFAULT ""',
      'ble_hop_count': 'INTEGER',
      'ble_rssi': 'INTEGER',
      'status': "TEXT DEFAULT 'pending'",
    });

    await _ensureColumns(db, 'offline_sessions', {
      'class_id': 'INTEGER NOT NULL DEFAULT 0',
      'class_type': 'TEXT NOT NULL DEFAULT "qr"',
      'duration_minutes': 'INTEGER NOT NULL DEFAULT 45',
      'start_time': 'TEXT NOT NULL DEFAULT ""',
      'end_time': 'TEXT NOT NULL DEFAULT ""',
      'shape_data': 'TEXT',
      'reference_image_path': 'TEXT',
      'totp_secret': 'TEXT',
      'rotation_interval': 'INTEGER',
      'status': "TEXT DEFAULT 'pending'",
    });

    await _ensureColumns(db, 'offline_qr_queue', {
      'session_id': 'TEXT NOT NULL DEFAULT ""',
      'timestamp': 'TEXT NOT NULL DEFAULT ""',
      'ble_hop_count': 'INTEGER',
      'ble_rssi': 'INTEGER',
      'qr_token': 'TEXT',
      'captcha': 'TEXT',
      'status': "TEXT DEFAULT 'pending'",
    });
  }

  Future<void> _ensureColumns(
    Database db,
    String tableName,
    Map<String, String> requiredColumns,
  ) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info($tableName)');
      final existingColumns = info
          .map((row) => (row['name'] as String?)?.toLowerCase())
          .whereType<String>()
          .toSet();

      for (final entry in requiredColumns.entries) {
        if (!existingColumns.contains(entry.key.toLowerCase())) {
          try {
            await db.execute('ALTER TABLE $tableName ADD COLUMN ${entry.key} ${entry.value}');
            debugPrint('[SyncService] Added missing column "${entry.key}" to $tableName');
          } catch (e) {
            debugPrint('[SyncService] Error adding column "${entry.key}" to $tableName: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[SyncService] Failed inspecting columns for $tableName: $e');
    }
  }

  // --- WEB HELPERS ---
  Future<List<Map<String, dynamic>>> _getWebList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(key);
    if (str == null) return [];
    final List<dynamic> decoded = jsonDecode(str);
    return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _saveWebList(String key, List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(list));
  }
  // -------------------

  Future<void> enqueueOfflineSession(Map<String, dynamic> sessionData) async {
    final sessionItem = {
      'id': sessionData['id'],
      'class_id': sessionData['class_id'],
      'class_type': sessionData['class_type'],
      'duration_minutes': sessionData['duration_minutes'],
      'start_time': sessionData['start_time'],
      'end_time': sessionData['end_time'],
      'shape_data': sessionData['shape_data'],
      'status': 'pending',
    };

    if (kIsWeb) {
      final list = await _getWebList('offline_sessions');
      list.add(sessionItem);
      await _saveWebList('offline_sessions', list);
      debugPrint('Queued Web offline session ${sessionData['id']}');
      return;
    }

    final db = await database;
    try {
      await db.insert('offline_sessions', sessionItem);
      debugPrint('Queued offline session ${sessionData['id']}');
    } catch (e) {
      debugPrint('[SyncService] Insert offline_sessions failed: $e. Repairing schema...');
      await _ensureSchema(db);
      await db.insert('offline_sessions', sessionItem);
      debugPrint('Queued offline session ${sessionData['id']} after repair');
    }
  }

  Future<void> enqueuePatternScan(
    String imagePath,
    String timestamp, {
    int? bleHopCount,
    int? bleRssi,
  }) async {
    final item = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'image_path': imagePath,
      'timestamp': timestamp,
      'ble_hop_count': bleHopCount,
      'ble_rssi': bleRssi,
      'status': 'pending',
    };

    if (kIsWeb) {
      final list = await _getWebList('offline_queue');
      list.add(item);
      await _saveWebList('offline_queue', list);
      debugPrint('Queued Web offline pattern scan at $timestamp');
      return;
    }

    final db = await database;
    try {
      await db.insert('offline_queue', item..remove('id'));
      debugPrint('Queued offline pattern scan at $timestamp');
    } catch (e) {
      debugPrint('[SyncService] Insert offline_queue failed: $e. Repairing schema...');
      await _ensureSchema(db);
      await db.insert('offline_queue', item..remove('id'));
      debugPrint('Queued offline pattern scan at $timestamp after repair');
    }
  }

  Future<int> getPendingCount() async {
    if (kIsWeb) {
      final list = await _getWebList('offline_queue');
      return list.where((e) => e['status'] == 'pending').length;
    }

    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM offline_queue WHERE status = ?',
      ['pending'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> enqueueSession({
    required String id,
    required int classId,
    required String classType,
    required int durationMinutes,
    required String startTime,
    required String endTime,
    String? shapeData,
    String? totpSecret,
    int? rotationInterval,
  }) async {
    final item = {
      'id': id,
      'class_id': classId,
      'class_type': classType,
      'duration_minutes': durationMinutes,
      'start_time': startTime,
      'end_time': endTime,
      'shape_data': shapeData,
      'totp_secret': totpSecret,
      'rotation_interval': rotationInterval,
      'status': 'pending',
    };

    if (kIsWeb) {
      final list = await _getWebList('offline_sessions');
      list.add(item);
      await _saveWebList('offline_sessions', list);
      debugPrint('Queued Web offline session $id');
      return;
    }

    final db = await database;
    try {
      await db.insert('offline_sessions', item);
      debugPrint('Queued offline session $id');
    } catch (e) {
      debugPrint('[SyncService] Insert offline_sessions failed: $e. Repairing schema...');
      await _ensureSchema(db);
      await db.insert('offline_sessions', item);
      debugPrint('Queued offline session $id after repair');
    }
  }

  Future<void> updateSessionReferenceImage(String id, String imagePath) async {
    if (kIsWeb) {
      final list = await _getWebList('offline_sessions');
      for (var item in list) {
        if (item['id'] == id) {
          item['reference_image_path'] = imagePath;
        }
      }
      await _saveWebList('offline_sessions', list);
      debugPrint('Updated Web offline session $id with reference image');
      return;
    }

    final db = await database;
    await db.update(
      'offline_sessions',
      {'reference_image_path': imagePath},
      where: 'id = ?',
      whereArgs: [id],
    );
    debugPrint('Updated offline session $id with reference image');
  }

  Future<void> syncQueueToServer() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _syncCycleCount++;
    bool anythingSynced = false;

    try {
      // 1. Sync Sessions First
      List<Map<String, dynamic>> pendingSessions = [];
      if (kIsWeb) {
        final list = await _getWebList('offline_sessions');
        pendingSessions = list.where((e) => e['status'] == 'pending').toList();
      } else {
        final db = await database;
        pendingSessions = await db.query(
          'offline_sessions',
          where: 'status = ?',
          whereArgs: ['pending'],
        );
      }

      if (pendingSessions.isNotEmpty) {
        debugPrint(
          'Found ${pendingSessions.length} pending offline sessions. Attempting sync...',
        );
        for (var session in pendingSessions) {
          final id = session['id'] as String;
          final classId = session['class_id'] as int;
          final classType = session['class_type'] as String;
          final durationMinutes = session['duration_minutes'] as int;
          final startTime = session['start_time'] as String;
          final endTime = session['end_time'] as String;
          final shapeData = session['shape_data'] as String?;
          final referenceImagePath = session['reference_image_path'] as String?;
          final totpSecret = session['totp_secret'] as String?;
          final rotationInterval = session['rotation_interval'] as int?;

          // Check 24-hour expiration
          final sessionStartTime = DateTime.parse(startTime);
          if (DateTime.now().toUtc().difference(sessionStartTime.toUtc()).inHours >= 24) {
            debugPrint('Discarding expired offline session $id (older than 24 hours)');
            if (kIsWeb) {
              final list = await _getWebList('offline_sessions');
              list.removeWhere((e) => e['id'] == id);
              await _saveWebList('offline_sessions', list);
            } else {
              final db = await database;
              await db.delete(
                'offline_sessions',
                where: 'id = ?',
                whereArgs: [id],
              );
            }
            continue;
          }

          try {
            final result = await _attendanceService.syncOfflineSession(
              sessionId: id,
              classId: classId,
              classType: classType,
              durationMinutes: durationMinutes,
              startTime: startTime,
              endTime: endTime,
              shapeData: shapeData,
              referenceImagePath: referenceImagePath,
              totpSecret: totpSecret,
              rotationInterval: rotationInterval,
            );

            if (result['success']) {
              if (kIsWeb) {
                final list = await _getWebList('offline_sessions');
                list.removeWhere((e) => e['id'] == id);
                await _saveWebList('offline_sessions', list);
              } else {
                final db = await database;
                await db.update(
                  'offline_sessions',
                  {'status': 'synced'},
                  where: 'id = ?',
                  whereArgs: [id],
                );
              }
              debugPrint('Successfully synced offline session $id');
              anythingSynced = true;
            } else {
              debugPrint(
                'Failed to sync offline session $id: ${result['message']}',
              );
            }
          } catch (e) {
            debugPrint('Error syncing offline session $id: $e');
          }
        }
      }

      // 2. Sync Pattern Scans
      List<Map<String, dynamic>> pendingRecords = [];
      if (kIsWeb) {
        final list = await _getWebList('offline_queue');
        pendingRecords = list.where((e) => e['status'] == 'pending').toList();
      } else {
        final db = await database;
        pendingRecords = await db.query(
          'offline_queue',
          where: 'status = ?',
          whereArgs: ['pending'],
        );
      }

      if (pendingRecords.isNotEmpty) {
        debugPrint(
          'Found ${pendingRecords.length} pending offline pattern scans. Attempting sync...',
        );
        for (var record in pendingRecords) {
          final id = record['id'];
          final imagePath = record['image_path'] as String;
          final timestamp = record['timestamp'] as String;

          // Check 24-hour expiration
          final scanTime = DateTime.parse(timestamp);
          if (DateTime.now().toUtc().difference(scanTime.toUtc()).inHours >=
              24) {
            debugPrint(
              'Discarding expired pattern scan $id (older than 24 hours)',
            );
            if (kIsWeb) {
              final list = await _getWebList('offline_queue');
              list.removeWhere((e) => e['id'] == id);
              await _saveWebList('offline_queue', list);
            } else {
              final db = await database;
              await db.delete(
                'offline_queue',
                where: 'id = ?',
                whereArgs: [id],
              );
            }
            continue;
          }

          // Check if image exists (Skip on web, as path might be data URL or local object URL)
          if (!kIsWeb) {
            final file = File(imagePath);
            if (!await file.exists()) {
              debugPrint(
                'Image file not found for queued record $id, marking as failed.',
              );
              final db = await database;
              await db.update(
                'offline_queue',
                {'status': 'failed_file_missing'},
                where: 'id = ?',
                whereArgs: [id],
              );
              continue;
            }
          }

          final bleHopCount = record['ble_hop_count'] as int?;
          final bleRssi = record['ble_rssi'] as int?;

          // Exponential backoff: skip items that are backing off
          if (!_shouldRetryItem('pattern_$id')) {
            continue;
          }

          try {
            final result = await _attendanceService.syncOfflinePattern(
              imagePath: imagePath,
              timestamp: timestamp,
              bleHopCount: bleHopCount,
              bleRssi: bleRssi,
            );

            if (result['success']) {
              if (kIsWeb) {
                final list = await _getWebList('offline_queue');
                list.removeWhere((e) => e['id'] == id);
                await _saveWebList('offline_queue', list);
              } else {
                final db = await database;
                await db.update(
                  'offline_queue',
                  {'status': 'synced'},
                  where: 'id = ?',
                  whereArgs: [id],
                );
              }
              _clearRetryCount('pattern_$id');
              debugPrint('Successfully processed record $id');
              
              if (result['status'] == 'failed_retry') {
                final context = navigatorKey.currentContext;
                if (context != null) {
                  showDialog(
                    context: context,
                    builder: (BuildContext ctx) {
                      return AlertDialog(
                        title: const Text('Scan Failed'),
                        content: Text(result['message'] ?? 'Verification failed. The session is still active, please scan again.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      );
                    }
                  );
                }
              } else {
                scaffoldMessengerKey.currentState?.showSnackBar(
                  SnackBar(
                    content: Text(result['message'] ?? 'Offline attendance synced successfully'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              anythingSynced = true;
            } else {
              _recordRetryFailure('pattern_$id');
              debugPrint('[SyncService] Failed pattern $id (attempt ${_retryCountMap['pattern_$id'] ?? 0}): ${result['message']}');
            }
          } catch (e) {
            _recordRetryFailure('pattern_$id');
            debugPrint('[SyncService] Error syncing pattern $id: $e');
          }
        }
      }

      // 3. Sync QR Scans
      List<Map<String, dynamic>> pendingQrScans = [];
      if (kIsWeb) {
        final list = await _getWebList('offline_qr_queue');
        pendingQrScans = list.where((e) => e['status'] == 'pending').toList();
      } else {
        final db = await database;
        pendingQrScans = await db.query(
          'offline_qr_queue',
          where: 'status = ?',
          whereArgs: ['pending'],
        );
      }

      if (pendingQrScans.isNotEmpty) {
        debugPrint(
          'Found ${pendingQrScans.length} pending offline QR scans. Attempting sync...',
        );
        for (var record in pendingQrScans) {
          final id = record['id'];
          final sessionId = record['session_id'] as String;
          final timestamp = record['timestamp'] as String;
          final qrToken = record['qr_token'] as String?;

          // Check 24-hour expiration
          final scanTime = DateTime.parse(timestamp);
          if (DateTime.now().toUtc().difference(scanTime.toUtc()).inHours >=
              24) {
            debugPrint('Discarding expired QR scan $id (older than 24 hours)');
            if (kIsWeb) {
              final list = await _getWebList('offline_qr_queue');
              list.removeWhere((e) => e['id'] == id);
              await _saveWebList('offline_qr_queue', list);
            } else {
              final db = await database;
              await db.delete(
                'offline_qr_queue',
                where: 'id = ?',
                whereArgs: [id],
              );
            }
            continue;
          }

          final bleHopCount = record['ble_hop_count'] as int?;
          final bleRssi = record['ble_rssi'] as int?;

          // Exponential backoff: skip items that are backing off
          if (!_shouldRetryItem('qr_$id')) {
            continue;
          }

          try {
            final result = await _attendanceService.markAttendance(
              sessionId,
              qrToken: qrToken,
              isOfflineSync: true,
              timestamp: timestamp,
              bleHopCount: bleHopCount,
              bleRssi: bleRssi,
            );
            if (result['success']) {
              if (kIsWeb) {
                final list = await _getWebList('offline_qr_queue');
                list.removeWhere((e) => e['id'] == id);
                await _saveWebList('offline_qr_queue', list);
              } else {
                final db = await database;
                await db.update(
                  'offline_qr_queue',
                  {'status': 'synced'},
                  where: 'id = ?',
                  whereArgs: [id],
                );
              }
              _clearRetryCount('qr_$id');
              debugPrint('Successfully processed QR record $id');
              
              if (result['status'] == 'failed_retry') {
                final context = navigatorKey.currentContext;
                if (context != null) {
                  showDialog(
                    context: context,
                    builder: (BuildContext ctx) {
                      return AlertDialog(
                        title: const Text('Scan Failed'),
                        content: Text(result['message'] ?? 'Verification failed. The session is still active, please scan again.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      );
                    }
                  );
                }
              } else {
                scaffoldMessengerKey.currentState?.showSnackBar(
                  SnackBar(
                    content: Text(result['message'] ?? 'Offline attendance synced successfully'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              anythingSynced = true;
            } else {
              _recordRetryFailure('qr_$id');
              debugPrint('[SyncService] Failed QR $id (attempt ${_retryCountMap['qr_$id'] ?? 0}): ${result['message']}');
            }
          } catch (e) {
            _recordRetryFailure('qr_$id');
            debugPrint('[SyncService] Error syncing QR $id: $e');
          }
        }
      }
    } finally {
      _isSyncing = false;
      // Notify listeners only if something was actually synced
      if (anythingSynced) {
        _syncCompleteController.add(null);
      }
    }
  }

  Future<void> enqueueQRScan(
    String sessionId,
    String timestamp, {
    int? bleHopCount,
    int? bleRssi,
    String? qrToken,
  }) async {
    final item = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'session_id': sessionId,
      'timestamp': timestamp,
      'ble_hop_count': bleHopCount,
      'ble_rssi': bleRssi,
      'qr_token': qrToken,
      'status': 'pending',
    };

    if (kIsWeb) {
      final list = await _getWebList('offline_qr_queue');
      list.add(item);
      await _saveWebList('offline_qr_queue', list);
      debugPrint('Queued Web offline QR scan for session $sessionId');
      return;
    }

    final db = await database;
    try {
      await db.insert('offline_qr_queue', item..remove('id'));
      debugPrint('Queued offline QR scan for session $sessionId');
    } catch (e) {
      debugPrint('[SyncService] Insert offline_qr_queue failed: $e. Repairing schema...');
      await _ensureSchema(db);
      await db.insert('offline_qr_queue', item..remove('id'));
      debugPrint('Queued offline QR scan for session $sessionId after repair');
    }
  }
}
