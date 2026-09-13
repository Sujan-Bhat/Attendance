import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:uuid/uuid.dart';

class BleMeshService {
  static final BleMeshService _instance = BleMeshService._internal();
  factory BleMeshService() => _instance;
  BleMeshService._internal();

  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();
  
  bool _isScanning = false;
  bool _isAdvertising = false;
  
  // Custom Service UUID for the Attend App Mesh
  // Using a 16-bit UUID for compactness if possible, but 128-bit is safer for uniqueness.
  // We will use Manufacturer Data instead for the payload, with a specific Manufacturer ID.
  static const int customManufacturerId = 0x02E5; // Apple Inc is 0x004C. We'll use a test/custom one.
  
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  /// Starts broadcasting as the Teacher (Hop 0)
  Future<void> startTeacherBroadcast(String sessionId) async {
    await stopAll();
    
    final payload = _createPayload(sessionId, 0);
    
    final advertiseData = AdvertiseDataCore(
      manufacturerId: customManufacturerId,
      manufacturerData: payload,
    );
    
    await _blePeripheral.start(advertiseData: advertiseData);
    _isAdvertising = true;
    print("Teacher BLE Broadcast started: Session $sessionId | Hop: 0");
  }

  /// Scans for the mesh signal, and upon finding it, stops scanning and relays it (Hop + 1).
  /// Returns a Future that completes with { 'hop_count': int, 'rssi': int }
  Future<Map<String, dynamic>> startStudentScanAndRelay(String sessionId, {Duration timeout = const Duration(seconds: 15)}) async {
    await stopAll();
    
    final completer = Completer<Map<String, dynamic>>();
    
    // Convert target sessionId string to bytes for comparison
    final targetSessionBytes = _uuidToBytes(sessionId);

    _isScanning = true;
    
    // Start scanning
    await FlutterBluePlus.startScan(timeout: timeout);
    
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        final mData = r.advertisementData.manufacturerData;
        if (mData.containsKey(customManufacturerId)) {
          final data = mData[customManufacturerId]!;
          // Payload should be 17 bytes (16 bytes UUID + 1 byte hop count)
          if (data.length >= 17) {
            final rxSessionBytes = data.sublist(0, 16);
            if (_listEquals(rxSessionBytes, targetSessionBytes)) {
              final rxHopCount = data[16];
              final rssi = r.rssi;
              
              print("Match found! Rx Hop: $rxHopCount, RSSI: $rssi");
              
              // We found it! Stop scanning and start relaying
              await FlutterBluePlus.stopScan();
              _scanSubscription?.cancel();
              
              final newHopCount = rxHopCount + 1;
              _startStudentRelay(sessionId, newHopCount);
              
              if (!completer.isCompleted) {
                completer.complete({
                  'hop_count': rxHopCount,
                  'rssi': rssi,
                });
              }
              break;
            }
          }
        }
      }
    });
    
    // Handle timeout
    Future.delayed(timeout, () {
      if (!completer.isCompleted) {
        FlutterBluePlus.stopScan();
        _scanSubscription?.cancel();
        completer.completeError("BLE Verification timeout: Could not find teacher/student signal in range.");
      }
    });

    return completer.future;
  }

  /// Scans for ANY mesh signal, extracts the session ID, and relays it (Hop + 1).
  /// Used for offline Pattern scanning where the student doesn't know the session_id beforehand.
  Future<Map<String, dynamic>> startStudentScanAnySession({Duration timeout = const Duration(seconds: 15)}) async {
    await stopAll();
    
    final completer = Completer<Map<String, dynamic>>();
    _isScanning = true;
    
    await FlutterBluePlus.startScan(timeout: timeout);
    
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        final mData = r.advertisementData.manufacturerData;
        if (mData.containsKey(customManufacturerId)) {
          final data = mData[customManufacturerId]!;
          if (data.length >= 17) {
            final rxSessionBytes = data.sublist(0, 16);
            final rxHopCount = data[16];
            final rssi = r.rssi;
            final sessionId = _bytesToUuid(rxSessionBytes);
            
            print("Match found (ANY)! Rx Hop: $rxHopCount, RSSI: $rssi, Session: $sessionId");
            
            await FlutterBluePlus.stopScan();
            _scanSubscription?.cancel();
            
            final newHopCount = rxHopCount + 1;
            _startStudentRelay(sessionId, newHopCount);
            
            if (!completer.isCompleted) {
              completer.complete({
                'session_id': sessionId,
                'hop_count': rxHopCount,
                'rssi': rssi,
              });
            }
            break;
          }
        }
      }
    });
    
    Future.delayed(timeout, () {
      if (!completer.isCompleted) {
        FlutterBluePlus.stopScan();
        _scanSubscription?.cancel();
        completer.completeError("BLE Verification timeout: Could not find any teacher/student signal in range.");
      }
    });

    return completer.future;
  }

  /// Starts broadcasting as a Student relaying the signal
  Future<void> _startStudentRelay(String sessionId, int myHopCount) async {
    final payload = _createPayload(sessionId, myHopCount);
    
    final advertiseData = AdvertiseDataCore(
      manufacturerId: customManufacturerId,
      manufacturerData: payload,
    );
    
    await _blePeripheral.start(advertiseData: advertiseData);
    _isAdvertising = true;
    print("Student BLE Relay started: Session $sessionId | My Hop: $myHopCount");
  }
  
  /// Stops all BLE activities
  Future<void> stopAll() async {
    if (_isScanning) {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _isScanning = false;
    }
    
    if (_isAdvertising) {
      await _blePeripheral.stop();
      _isAdvertising = false;
    }
  }

  /// Helper: Create 17-byte payload (16 byte UUID + 1 byte Hop Count)
  Uint8List _createPayload(String uuidString, int hopCount) {
    final uuidBytes = _uuidToBytes(uuidString);
    final payload = Uint8List(17);
    for (int i = 0; i < 16; i++) {
      payload[i] = uuidBytes[i];
    }
    payload[16] = hopCount.clamp(0, 255);
    return payload;
  }

  /// Helper: Convert UUID string to 16 bytes
  List<int> _uuidToBytes(String uuidString) {
    // Remove dashes and parse hex
    final clean = uuidString.replaceAll('-', '');
    final bytes = <int>[];
    for (int i = 0; i < clean.length; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  /// Helper: Convert 16 bytes to UUID string
  String _bytesToUuid(List<int> bytes) {
    if (bytes.length != 16) return '';
    final hexString = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
    return '${hexString.substring(0, 8)}-${hexString.substring(8, 12)}-${hexString.substring(12, 16)}-${hexString.substring(16, 20)}-${hexString.substring(20)}';
  }
  
  /// Helper: Compare two lists
  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
