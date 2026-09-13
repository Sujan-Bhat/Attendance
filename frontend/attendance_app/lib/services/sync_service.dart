import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_service.dart';
import 'package:flutter/foundation.dart';

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

  SyncService._internal() {
    _startPeriodicSync();
  }

  void _startPeriodicSync() {
    // Try to sync every 30 seconds automatically for edge cases where the user remains online
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncQueueToServer();
    });
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'offline_sync.db');

    return await openDatabase(
      path,
      version: 6,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
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
              status TEXT DEFAULT 'pending'
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS offline_qr_queue (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id TEXT NOT NULL,
              timestamp TEXT NOT NULL,
              status TEXT DEFAULT 'pending'
            )
          ''');
        }
        if (oldVersion < 4) {
          try {
            await db.execute(
                'ALTER TABLE offline_sessions ADD COLUMN class_type TEXT NOT NULL DEFAULT "qr"');
          } catch (e) {
            // Ignore if column already exists
          }
        }
        if (oldVersion < 5) {
          try {
            await db.execute('ALTER TABLE offline_qr_queue ADD COLUMN ble_hop_count INTEGER');
            await db.execute('ALTER TABLE offline_qr_queue ADD COLUMN ble_rssi INTEGER');
          } catch (e) {
            // Ignore if columns already exist
          }
        }
        if (oldVersion < 6) {
          try {
            await db.execute('ALTER TABLE offline_queue ADD COLUMN ble_hop_count INTEGER');
            await db.execute('ALTER TABLE offline_queue ADD COLUMN ble_rssi INTEGER');
          } catch (e) {
            // Ignore if columns already exist
          }
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            image_path TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            ble_hop_count INTEGER,
            ble_rssi INTEGER,
            status TEXT DEFAULT 'pending'
          )
        ''');
        await db.execute('''
          CREATE TABLE offline_sessions (
            id TEXT PRIMARY KEY,
            class_id INTEGER NOT NULL,
            class_type TEXT NOT NULL,
            duration_minutes INTEGER NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            shape_data TEXT,
            reference_image_path TEXT,
            status TEXT DEFAULT 'pending'
          )
        ''');
        await db.execute('''
          CREATE TABLE offline_qr_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            ble_hop_count INTEGER,
            ble_rssi INTEGER,
            status TEXT DEFAULT 'pending'
          )
        ''');
      },
    );
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
    await db.insert('offline_sessions', sessionItem);
    debugPrint('Queued offline session ${sessionData['id']}');
  }

  Future<void> enqueuePatternScan(String imagePath, String timestamp, {int? bleHopCount, int? bleRssi}) async {
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
    await db.insert('offline_queue', item..remove('id'));
    debugPrint('Queued offline pattern scan at $timestamp');
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
  }) async {
    final item = {
      'id': id,
      'class_id': classId,
      'class_type': classType,
      'duration_minutes': durationMinutes,
      'start_time': startTime,
      'end_time': endTime,
      'shape_data': shapeData,
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
    await db.insert('offline_sessions', item);
    debugPrint('Queued offline session $id');
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
          if (DateTime.now().toUtc().difference(scanTime.toUtc()).inHours >= 24) {
            debugPrint('Discarding expired pattern scan $id (older than 24 hours)');
            if (kIsWeb) {
              final list = await _getWebList('offline_queue');
              list.removeWhere((e) => e['id'] == id);
              await _saveWebList('offline_queue', list);
            } else {
              final db = await database;
              await db.delete('offline_queue', where: 'id = ?', whereArgs: [id]);
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
              debugPrint('Successfully synced record $id');
              anythingSynced = true;
            } else {
              debugPrint('Failed to sync record $id: ${result['message']}');
            }
          } catch (e) {
            debugPrint('Error syncing record $id: $e');
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

          // Check 24-hour expiration
          final scanTime = DateTime.parse(timestamp);
          if (DateTime.now().toUtc().difference(scanTime.toUtc()).inHours >= 24) {
            debugPrint('Discarding expired QR scan $id (older than 24 hours)');
            if (kIsWeb) {
              final list = await _getWebList('offline_qr_queue');
              list.removeWhere((e) => e['id'] == id);
              await _saveWebList('offline_qr_queue', list);
            } else {
              final db = await database;
              await db.delete('offline_qr_queue', where: 'id = ?', whereArgs: [id]);
            }
            continue;
          }

          final bleHopCount = record['ble_hop_count'] as int?;
          final bleRssi = record['ble_rssi'] as int?;

          try {
            final result = await _attendanceService.markAttendance(
              sessionId,
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
              debugPrint('Successfully synced QR record $id');
              anythingSynced = true;
            } else {
              debugPrint('Failed to sync QR record $id: ${result['message']}');
            }
          } catch (e) {
            debugPrint('Error syncing QR record $id: $e');
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

  Future<void> enqueueQRScan(String sessionId, String timestamp, {int? bleHopCount, int? bleRssi}) async {
    final item = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'session_id': sessionId,
      'timestamp': timestamp,
      'ble_hop_count': bleHopCount,
      'ble_rssi': bleRssi,
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
    await db.insert('offline_qr_queue', item..remove('id'));
    debugPrint('Queued offline QR scan for session $sessionId');
  }
}
