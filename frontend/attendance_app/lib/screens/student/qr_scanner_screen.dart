import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/student_drawer.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../services/attendance_service.dart';
import '../../services/session_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/offline_indicator.dart';
import '../../services/ble_mesh_service.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen>
    with WidgetsBindingObserver {
  final AttendanceService _attendanceService = AttendanceService();
  final SessionService _sessionService = SessionService();

  // Scanner for QR mode (forced flash via returnImage maybe not needed, but we force torch on)
  late final MobileScannerController _scannerController;

  // Camera for Pattern mode capture
  CameraController? _cameraController;

  bool isProcessing = false;
  bool hasScanned = false;
  String? scannedData;
  bool isPatternMode = false;
  bool _cameraPermissionGranted = false;

  bool _isCameraInitializing = false;
  bool _isSwitchingMode = false;

  // Zoom control variables for both modes
  double _baseZoomLevel = 1.0;
  double _currentZoomLevel = 1.0;

  // Camera package zoom bounds
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialize MobileScannerController with torch enabled
    _scannerController = MobileScannerController(torchEnabled: true);
    _checkCameraPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      if (!isPatternMode) {
        _scannerController.start();
      } else {
        _initializePatternCamera();
      }
    } else {
      if (!isPatternMode) {
        _scannerController.stop();
      } else if (_cameraController != null) {
        _cameraController!.dispose();
        _cameraController = null;
      }
    }
  }

  Future<void> _checkCameraPermission() async {
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() {
        _cameraPermissionGranted = status.isGranted;
      });
      if (!status.isGranted) {
        _showPermissionDialog();
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text(
          'This app needs camera access to scan QR codes for attendance. Please grant camera permission in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _initializePatternCamera() async {
    if (_isCameraInitializing) return;

    setState(() {
      _isCameraInitializing = true;
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Using veryHigh (1080p) instead of max. 'max' pushes 4K/50MP raw frames into
      // Flutter's rendering engine, which absolutely destroys the framerate and aspect ratio!
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      // Get zoom limits
      _minAvailableZoom = await _cameraController!.getMinZoomLevel();
      _maxAvailableZoom = await _cameraController!.getMaxZoomLevel();
      _currentZoomLevel = _minAvailableZoom;
    } catch (e) {
      debugPrint('Error initializing camera for pattern capture: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
        });

        // Force flash ON using a robust retry loop
        if (_cameraController != null &&
            _cameraController!.value.isInitialized) {
          _enforceTorch(_cameraController!);
        }
      }
    }
  }

  Future<void> _enforceTorch(CameraController controller) async {
    // Retry up to 5 times (2.5 seconds total) because Android camera
    // hardware takes progressively longer to wake up after rapid toggles
    for (int i = 0; i < 5; i++) {
      if (!mounted || !isPatternMode || _cameraController == null) return;
      try {
        await controller.setFlashMode(FlashMode.torch);
        debugPrint('Flash torch enforced successfully on attempt ${i + 1}');
        return;
      } catch (e) {
        debugPrint('Flash torch enforcement failed on attempt ${i + 1}: $e');
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  void _toggleMode(bool val) async {
    if (val == isPatternMode || _isSwitchingMode) return;

    setState(() {
      _isSwitchingMode = true;
      isPatternMode = val;
    });

    try {
      if (isPatternMode) {
        // Switch to Pattern Mode
        await _scannerController.stop();
        await _initializePatternCamera();
      } else {
        // Switch to QR Mode
        if (_cameraController != null) {
          await _cameraController!.dispose();
          _cameraController = null;
        }
        await _scannerController.start();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingMode = false;
        });
      }
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseZoomLevel = _currentZoomLevel;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) async {
    if (isPatternMode && _cameraController != null) {
      // Handle camera package zoom
      _currentZoomLevel = (_baseZoomLevel * details.scale).clamp(
        _minAvailableZoom,
        _maxAvailableZoom,
      );
      await _cameraController!.setZoomLevel(_currentZoomLevel);
    } else if (!isPatternMode) {
      // Handle mobile_scanner zoom (0.0 to 1.0 ratio typically in newer versions)
      // We estimate standard clamp logic here
      _currentZoomLevel = (_baseZoomLevel * details.scale).clamp(1.0, 5.0);
      // scale for mobile_scanner is usually expected to be between 0.0 and 1.0 in some versions,
      // but if we pass it directly we can convert it to a ratio.
      final zoomRatio = ((_currentZoomLevel - 1.0) / 4.0).clamp(0.0, 1.0);
      _scannerController.setZoomScale(zoomRatio);
    }
  }

  Future<void> _handleQRCode(String qrData) async {
    if (isProcessing || hasScanned || isPatternMode) return;

    setState(() {
      isProcessing = true;
      scannedData = qrData;
    });

    try {
      final dynamic decoded = jsonDecode(qrData);

      if (decoded is! Map<String, dynamic>) {
        _showError('Invalid QR code format. Not an attendance code.');
        setState(() => isProcessing = false);
        return;
      }

      final data = decoded;
      final sessionId = data['session_id'];

      if (sessionId == null) {
        _showError('Invalid QR code');
        setState(() => isProcessing = false);
        return;
      }

      List<ConnectivityResult> connectivityResults = [];
      try {
        connectivityResults = await Connectivity().checkConnectivity();
      } catch (_) {
        // Fallback to empty list (assume online) if connectivity plugin crashes
      }
      final isNetworkOffline =
          connectivityResults.isEmpty ||
          connectivityResults.contains(ConnectivityResult.none);
      
      final isOfflineSession = data['is_offline'] == true;
      final isOffline = isNetworkOffline || isOfflineSession;

      int bleHopCount;
      int bleRssi;
      try {
        // STRICT BLE ENFORCEMENT: Verify presence via BLE Mesh FIRST
        _showBleVerificationDialog();
        final bleResult = await BleMeshService().startStudentScanAndRelay(
            sessionId,
            timeout: const Duration(seconds: 15));
        bleHopCount = bleResult['hop_count'];
        bleRssi = bleResult['rssi'];
        // pop the verifying dialog
        Navigator.of(context, rootNavigator: true).pop();
      } catch (e) {
        print("BLE mesh verification failed: $e");
        // Pop the verifying dialog
        Navigator.of(context, rootNavigator: true).pop();
        _showError('BLE Verification failed. Ensure Bluetooth is on and you are near the teacher.');
        setState(() => isProcessing = false);
        return;
      }

      if (isOffline) {
        final timestamp = DateTime.now().toUtc().toIso8601String();
        await SyncService().enqueueQRScan(sessionId, timestamp, bleHopCount: bleHopCount, bleRssi: bleRssi);

        setState(() {
          hasScanned = true;
          isProcessing = false;
        });

        _showSuccessDialog(
          'Offline Mode: QR scan saved locally. It will sync automatically when internet is restored.',
        );
        return;
      }

      final result = await _attendanceService.markAttendance(
          sessionId,
          bleHopCount: bleHopCount,
          bleRssi: bleRssi
      );

      if (mounted) {
        if (result['success']) {
          setState(() => hasScanned = true);
          _showSuccessDialog(result['message']);
        } else {
          _showError(result['message']);
          setState(() => isProcessing = false);
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Invalid QR code format: $e');
        setState(() => isProcessing = false);
      }
    }
  }

  Future<void> _handlePatternCapture() async {
    if (isProcessing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized)
      return;
    setState(() => isProcessing = true);

    try {
      // Force flash on before taking the picture
      try {
        await _cameraController!.setFlashMode(FlashMode.torch);
      } catch (_) {}

      final XFile picture = await _cameraController!.takePicture();
      final String imagePath = picture.path;

      // Pause preview immediately so the user knows photo was taken
      await _cameraController!.pausePreview();

      List<ConnectivityResult> connectivityResults = [];
      try {
        connectivityResults = await Connectivity().checkConnectivity();
      } catch (_) {
        // Fallback to empty list (assume online) if connectivity plugin crashes
      }
      bool isOffline =
          connectivityResults.isEmpty ||
          connectivityResults.contains(ConnectivityResult.none);

      // Fetch active sessions if online
      String? sessionId;
      if (!isOffline) {
        List<Map<String, dynamic>> sessions = [];
        try {
          sessions = await _sessionService.getStudentActiveSessions();
        } catch (e) {
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('dioexception') || errorStr.contains('socketexception') || errorStr.contains('failed host lookup') || errorStr.contains('connection error')) {
            isOffline = true;
          } else {
            _showError('Network/API Error: $e');
            setState(() => isProcessing = false);
            await _cameraController!.resumePreview();
            return;
          }
        }

        if (!isOffline) {
          final patternSessions = sessions
              .where((s) => s['class_type'] == 'pattern')
              .toList();

          if (patternSessions.isEmpty) {
            _showError(
              'No active pattern session found. Ask your teacher to start an pattern session.',
            );
            setState(() => isProcessing = false);
            await _cameraController!.resumePreview();
            return;
          }

          final session = patternSessions.first;

          // Check if teacher has uploaded the reference image yet
          if (session['has_reference_image'] == false) {
            _showError(
              'Teacher has not uploaded the board photo yet. Please wait and try again.',
            );
            setState(() => isProcessing = false);
            await _cameraController!.resumePreview();
            return;
          }

          sessionId = session['session_id'].toString();
        }
      }

      // BLE MESH VERIFICATION (Enforced for Pattern mode too)
      int bleHopCount;
      int bleRssi;
      
      try {
        _showBleVerificationDialog();
        if (isOffline) {
           final bleResult = await BleMeshService().startStudentScanAnySession(timeout: const Duration(seconds: 15));
           bleHopCount = bleResult['hop_count'];
           bleRssi = bleResult['rssi'];
        } else {
           final bleResult = await BleMeshService().startStudentScanAndRelay(sessionId!, timeout: const Duration(seconds: 15));
           bleHopCount = bleResult['hop_count'];
           bleRssi = bleResult['rssi'];
        }
        Navigator.of(context, rootNavigator: true).pop();
      } catch (e) {
        print("BLE mesh verification failed for pattern: $e");
        Navigator.of(context, rootNavigator: true).pop();
        _showError('BLE Verification failed. Ensure Bluetooth is on and you are near the teacher.');
        setState(() => isProcessing = false);
        await _cameraController!.resumePreview();
        return;
      }

      if (isOffline) {
        final timestamp = DateTime.now().toUtc().toIso8601String();
        await SyncService().enqueuePatternScan(imagePath, timestamp, bleHopCount: bleHopCount, bleRssi: bleRssi);
        if (mounted) {
          setState(() => hasScanned = true);
          _showSuccessDialog(
            'Saved offline. Will sync automatically when internet is restored.',
          );
        }
        return;
      }

      final result = await _attendanceService.verifyImage(
        sessionId: sessionId!,
        imagePath: imagePath,
        focalDistance: 2.0,
        bleHopCount: bleHopCount,
        bleRssi: bleRssi,
      );

      if (mounted) {
        if (result['success']) {
          setState(() => hasScanned = true);
          _showSuccessDialog(
            result['message'] ?? 'Attendance marked successfully',
          );
        } else {
          _showError(result['message'] ?? 'Verification failed');
          setState(() => isProcessing = false);
          await _cameraController!.resumePreview();
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: $e');
        setState(() => isProcessing = false);
        if (_cameraController != null &&
            _cameraController!.value.isInitialized) {
          _cameraController!.resumePreview();
        }
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showBleVerificationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: Color(0xFF007C91)),
            const SizedBox(height: 24),
            const Text(
              'Verifying location via BLE Mesh...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Please stay close to the teacher or other students.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                color: Colors.green.shade600,
                size: 60,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Success!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007C91),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: isMobile ? const StudentDrawer(currentRoute: 'Scan QR') : null,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 10),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            bottom: 8,
            left: isMobile ? 12 : 20,
            right: 16,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF007C91), Color(0xFF0097A7)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              if (isMobile)
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu_rounded, color: Colors.white),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Back',
                  ),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  isPatternMode ? 'Scan Pattern' : 'Scan QR',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const OfflineIndicator(),
                  const SizedBox(width: 8),
                  Text(
                    isPatternMode ? 'Pattern' : 'QR',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Switch(
                    value: isPatternMode,
                    activeThumbColor: Colors.orange,
                    activeTrackColor: Colors.orange.withValues(alpha: 0.5),
                    inactiveThumbColor: Colors.greenAccent,
                    inactiveTrackColor: Colors.greenAccent.withValues(
                      alpha: 0.3,
                    ),
                    onChanged: _toggleMode,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // Camera Background
          if (_cameraPermissionGranted)
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                child: isPatternMode
                    ? (_cameraController != null &&
                              _cameraController!.value.isInitialized
                          ? CameraPreview(_cameraController!)
                          : const Center(child: CircularProgressIndicator()))
                    : MobileScanner(
                        controller: _scannerController,
                        onDetect: (capture) {
                          if (isPatternMode) return;
                          final List<Barcode> barcodes = capture.barcodes;
                          for (final barcode in barcodes) {
                            if (barcode.rawValue != null) {
                              _handleQRCode(barcode.rawValue!);
                              break;
                            }
                          }
                        },
                      ),
              ),
            )
          else
            // No permission
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt, color: Colors.white54, size: 80),
                    SizedBox(height: 16),
                    Text(
                      'Camera permission required',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

          // Scanning Frame Overlay
          Center(
            child: IgnorePointer(
              child: Container(
                width: isMobile ? 250 : 300,
                height: isMobile ? 250 : 300,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: hasScanned
                        ? Colors.green
                        : (isProcessing ? Colors.orange : Colors.white),
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: isProcessing
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: Colors.orange.shade400,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Processing...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
            ),
          ),

          // Corner Markers
          if (!isProcessing && !hasScanned) ...[
            _buildCornerMarker(Alignment.topLeft),
            _buildCornerMarker(Alignment.topRight),
            _buildCornerMarker(Alignment.bottomLeft),
            _buildCornerMarker(Alignment.bottomRight),
          ],

          // Instructions or Capture Button
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: isPatternMode
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Capture Board Pattern',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Point camera at the board. Zoom in so the pattern fills the box clearly, then tap Capture.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: isProcessing
                                ? null
                                : _handlePatternCapture,
                            icon: const Icon(Icons.camera_alt),
                            label: Text(
                              isProcessing
                                  ? 'Processing...'
                                  : 'Capture Pattern',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade400,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hasScanned
                              ? Icons.check_circle
                              : (isProcessing
                                    ? Icons.hourglass_empty
                                    : Icons.qr_code_scanner),
                          color: hasScanned
                              ? Colors.green
                              : (isProcessing ? Colors.orange : Colors.white),
                          size: 40,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          hasScanned
                              ? 'Attendance Marked Successfully!'
                              : (isProcessing
                                    ? 'Verifying...'
                                    : 'Position QR code within the frame'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 14 : 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCornerMarker(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.all(60),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            border: Border(
              top:
                  alignment == Alignment.topLeft ||
                      alignment == Alignment.topRight
                  ? const BorderSide(color: Colors.green, width: 4)
                  : BorderSide.none,
              bottom:
                  alignment == Alignment.bottomLeft ||
                      alignment == Alignment.bottomRight
                  ? const BorderSide(color: Colors.green, width: 4)
                  : BorderSide.none,
              left:
                  alignment == Alignment.topLeft ||
                      alignment == Alignment.bottomLeft
                  ? const BorderSide(color: Colors.green, width: 4)
                  : BorderSide.none,
              right:
                  alignment == Alignment.topRight ||
                      alignment == Alignment.bottomRight
                  ? const BorderSide(color: Colors.green, width: 4)
                  : BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }
}
