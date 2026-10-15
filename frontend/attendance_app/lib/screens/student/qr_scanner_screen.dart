import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../services/attendance_service.dart';
import '../../services/session_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/offline_indicator.dart';
import '../../widgets/student_drawer.dart';
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

  // Unified camera controller for both QR and Pattern modes
  CameraController? _cameraController;
  CameraDescription? _cameraDescription;
  bool _isCameraInitializing = false;
  bool _cameraPermissionGranted = false;
  bool _isTorchOn = false;

  // ML Kit barcode scanner
  late final BarcodeScanner _barcodeScanner;
  bool _isDetecting = false;

  // Mode and flow state
  bool isPatternMode = false;
  bool _isSwitchingMode = false;
  bool isProcessing = false;
  bool hasScanned = false;
  String? scannedData;

  // Decoder diagnostics. Without these, every ML Kit failure is swallowed by
  // debugPrint and the scanner looks identical to "nothing is happening".
  int _framesProcessed = 0;
  int _inputImageErrors = 0;
  int _decodeErrors = 0;
  int _consecutiveDecodeErrors = 0;
  bool _streamStartFailed = false;
  String? _decoderError;
  bool _decoderErrorAnnounced = false;
  String? _cameraInitError;

  // Zoom control variables for unified controller
  double _baseZoomLevel = 1.0;
  double _currentZoomLevel = 1.0;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopImageStreamSafely();
    _barcodeScanner.close();
    _cameraController?.dispose();
    _cameraController = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // AppLifecycleState.inactive is a strict NO-OP:
    // Pulling down Android notification shade or status bar must not freeze or tear down camera hardware.
    if (state == AppLifecycleState.inactive) {
      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        _initializeCamera();
      } else {
        // Only restore the torch if the user explicitly turned it on.
        if (_isTorchOn) {
          _enforceTorch(_cameraController!);
        }
        if (!isPatternMode && !isProcessing && !hasScanned) {
          _startImageStreamSafely();
        }
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // App is backgrounded: stop image stream and release camera hardware session cleanly
      _stopImageStreamSafely();
      _cameraController?.dispose();
      _cameraController = null;
    }
  }

  Future<void> _initializeCamera() async {
    if (_isCameraInitializing) return;

    setState(() {
      _isCameraInitializing = true;
    });

    try {
      final status = await Permission.camera.request();
      if (!mounted) return;

      if (!status.isGranted) {
        setState(() {
          _cameraPermissionGranted = false;
          _isCameraInitializing = false;
        });
        _showPermissionDialog();
        return;
      }

      setState(() {
        _cameraPermissionGranted = true;
      });

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('No cameras found on device');
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraDescription = backCamera;

      final controller = CameraController(
        backCamera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      _cameraController = controller;
      await controller.initialize();
      if (!mounted || _cameraController != controller) {
        controller.dispose();
        return;
      }

      // Query zoom limits
      try {
        _minAvailableZoom = await controller.getMinZoomLevel();
        _maxAvailableZoom = await controller.getMaxZoomLevel();
        _currentZoomLevel = _minAvailableZoom;
      } catch (e) {
        debugPrint('Error querying zoom levels: $e');
      }

      // Torch is OFF by default in QR mode. The scanner is normally aimed at a
      // lit phone screen, and an on-camera flash reflects straight off it and
      // washes the QR pattern out. Pattern mode photographs a physical board,
      // so it keeps the flash.
      if (isPatternMode) {
        await _enforceTorch(controller);
      }

      // In QR mode, start streaming frames to ML Kit immediately
      if (!isPatternMode && !isProcessing && !hasScanned && mounted) {
        await _startImageStreamSafely();
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _cameraInitError = 'Camera failed to start: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
        });
      }
    }
  }

  Future<void> _enforceTorch(CameraController controller) async {
    // Retry up to 5 times (300ms backoff) to accommodate Android HAL settling delays
    for (int i = 0; i < 5; i++) {
      if (!mounted || _cameraController != controller) return;
      try {
        await controller.setFlashMode(FlashMode.torch);
        if (mounted) {
          setState(() {
            _isTorchOn = true;
          });
        }
        debugPrint('Flash torch enforced successfully on attempt ${i + 1}');
        return;
      } catch (e) {
        debugPrint('Flash torch enforcement failed on attempt ${i + 1}: $e');
        if (i < 4) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }
  }

  Future<void> _startImageStreamSafely() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_cameraController!.value.isStreamingImages) return;

    // The image stream is what feeds ML Kit. If it never starts, the scanner
    // shows a live preview but can never detect anything, so retry and then
    // surface the failure instead of swallowing it.
    Object? lastError;
    for (int attempt = 0; attempt < 3; attempt++) {
      if (_cameraController == null || !_cameraController!.value.isInitialized) return;
      if (_cameraController!.value.isStreamingImages) return;
      try {
        await _cameraController!.startImageStream(_processCameraImage);
        if (_streamStartFailed && mounted) {
          setState(() {
            _streamStartFailed = false;
            _decoderError = null;
          });
        }
        return;
      } catch (e) {
        lastError = e;
        debugPrint('Failed to start image stream (attempt ${attempt + 1}): $e');
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    if (mounted) {
      setState(() {
        _streamStartFailed = true;
        _decoderError = 'Camera frame stream failed to start: $lastError';
      });
    }
  }

  Future<void> _stopImageStreamSafely() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (!_cameraController!.value.isStreamingImages) return;

    try {
      await _cameraController!.stopImageStream();
    } catch (e) {
      debugPrint('Failed to stop image stream: $e');
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
        // Switching to Pattern Mode:
        // Do NOT dispose camera. Simply stop the image stream while keeping the preview live.
        // Board-photo capture benefits from the flash, so force it on here.
        await _stopImageStreamSafely();
        if (_cameraController != null && _cameraController!.value.isInitialized) {
          if (_cameraController!.value.isPreviewPaused) {
            await _cameraController!.resumePreview();
          }
          await _enforceTorch(_cameraController!);
        }
      } else {
        // Switching to QR Mode:
        // Keep camera live, resume preview if paused, and start the image stream.
        // Torch stays off: scanning a lit screen with a flash washes out the QR.
        if (_cameraController != null && _cameraController!.value.isInitialized) {
          if (_cameraController!.value.isPreviewPaused) {
            await _cameraController!.resumePreview();
          }
          try {
            await _cameraController!.setFlashMode(FlashMode.off);
          } catch (e) {
            debugPrint('Failed to turn torch off entering QR mode: $e');
          }
          if (mounted) {
            setState(() => _isTorchOn = false);
          }
          if (!isProcessing && !hasScanned) {
            await _startImageStreamSafely();
          }
        }
      }
    } catch (e) {
      debugPrint('Error toggling mode: $e');
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
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      _currentZoomLevel = (_baseZoomLevel * details.scale).clamp(
        _minAvailableZoom,
        _maxAvailableZoom,
      );
      try {
        await _cameraController!.setZoomLevel(_currentZoomLevel);
      } catch (e) {
        debugPrint('Error setting zoom level: $e');
      }
    }
  }

  InputImageRotation? _getImageRotation() {
    if (_cameraDescription == null) return null;
    final sensorOrientation = _cameraDescription!.sensorOrientation;

    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      final deviceOrientation = _cameraController?.value.deviceOrientation;
      final rotationCompensation = _orientations[deviceOrientation];
      if (rotationCompensation == null) {
        return InputImageRotationValue.fromRawValue(sensorOrientation) ??
            InputImageRotation.rotation90deg;
      }

      int rotationDegrees;
      if (_cameraDescription!.lensDirection == CameraLensDirection.front) {
        rotationDegrees = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationDegrees = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      return InputImageRotationValue.fromRawValue(rotationDegrees) ??
          InputImageRotation.rotation90deg;
    }
    return null;
  }

  void _recordInputImageError(String message) {
    _inputImageErrors++;
    _decoderError = message;
    _consecutiveDecodeErrors++;
    debugPrint('InputImage rejected: $message');
    _announceDecoderProblem();
  }

  /// Surface a persistent decoder problem in the UI exactly once, so a broken
  /// pipeline is distinguishable from "the camera preview is simply idle".
  void _announceDecoderProblem() {
    if (_decoderErrorAnnounced || !mounted) return;
    if (_consecutiveDecodeErrors < 5) return;
    _decoderErrorAnnounced = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Refresh the diagnostics panel in the bottom card.
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('QR decoder problem: $_decoderError'),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
        ),
      );
    });
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (image.planes.isEmpty) {
      _recordInputImageError('Camera delivered a frame with no planes');
      return null;
    }
    final rotation = _getImageRotation();
    if (rotation == null) {
      _recordInputImageError('Could not determine frame rotation');
      return null;
    }

    // camera_android_camerax packs the requested NV21 stream into exactly one
    // plane. A multi-plane (YUV_420_888) frame cannot be handed to ML Kit by
    // concatenating the planes: the chroma planes are subsampled and carry
    // their own row strides, so the resulting buffer is corrupt and decoding
    // fails on every frame with no visible symptom. Reject it loudly instead.
    if (image.planes.length != 1) {
      _recordInputImageError(
        'Expected a single-plane frame but received ${image.planes.length} planes',
      );
      return null;
    }

    final InputImageFormat? format =
        InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) {
      _recordInputImageError(
        'Unrecognised camera image format (raw=${image.format.raw})',
      );
      return null;
    }
    if (Platform.isAndroid && format != InputImageFormat.nv21) {
      _recordInputImageError(
        'Expected NV21 frames on Android but got ${image.format.raw}',
      );
      return null;
    }

    final Plane plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _processCameraImage(CameraImage image) async {
    // Drop frame immediately if:
    // 1. Concurrency mutex locked (_isDetecting)
    // 2. Attendance network/BLE validation is running (isProcessing)
    // 3. A code has already been recognized and handled (hasScanned)
    // 4. User switched to Pattern Scan mode (isPatternMode)
    if (_isDetecting || isProcessing || hasScanned || isPatternMode) {
      return;
    }

    _isDetecting = true;
    _framesProcessed++;
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        // _inputImageFromCameraImage already recorded and surfaced the reason.
        return;
      }

      final List<Barcode> barcodes =
          await _barcodeScanner.processImage(inputImage);

      // The decoder produced a result without throwing, so the pipeline is
      // healthy — this frame simply had no QR code in it.
      _consecutiveDecodeErrors = 0;
      _decoderError = null;

      if (barcodes.isNotEmpty &&
          !hasScanned &&
          !isProcessing &&
          !isPatternMode &&
          mounted) {
        for (final barcode in barcodes) {
          final rawValue = barcode.rawValue;
          if (rawValue != null && rawValue.isNotEmpty) {
            _handleQRCode(rawValue);
            break;
          }
        }
      }
    } catch (e) {
      _decodeErrors++;
      _consecutiveDecodeErrors++;
      _decoderError = 'ML Kit failed to decode frame: $e';
      debugPrint('ML Kit barcode detection error: $e');
      _announceDecoderProblem();
    } finally {
      _isDetecting = false;
    }
  }

  void _resumeQRScanningAfterDelay({int seconds = 3}) {
    Future.delayed(Duration(seconds: seconds), () async {
      if (mounted && !hasScanned && !isPatternMode) {
        setState(() => isProcessing = false);
        await _startImageStreamSafely();
      }
    });
  }

  Future<void> _handleQRCode(String qrData) async {
    if (isProcessing || hasScanned || isPatternMode) return;

    setState(() {
      isProcessing = true;
      scannedData = qrData;
    });

    // Suspend image stream while handling verification
    await _stopImageStreamSafely();

    try {
      final dynamic decoded = jsonDecode(qrData);

      if (decoded is! Map<String, dynamic>) {
        _showError('Invalid QR code format. Not an attendance code.');
        _resumeQRScanningAfterDelay();
        return;
      }

      final data = decoded;
      final sessionId = data['session_id'];

      if (sessionId == null) {
        _showError('Invalid QR code');
        _resumeQRScanningAfterDelay();
        return;
      }

      final token = data['token'];
      if (token == null) {
        // Until the first rotation tick, the teacher's screen falls back to
        // metadata QR data that carries no token. It can never validate
        // server-side, so reject it immediately instead of spending 15s in a
        // BLE scan first.
        _showError(
          'QR code not ready yet. Wait for the "Rotating QR code" countdown, then scan again.',
        );
        _resumeQRScanningAfterDelay();
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
          timeout: const Duration(seconds: 15),
        );
        bleHopCount = bleResult['hop_count'];
        bleRssi = bleResult['rssi'];
        // pop the verifying dialog
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      } catch (e) {
        debugPrint("BLE mesh verification failed: $e");
        // Pop the verifying dialog
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          _showError(
            'BLE Verification failed. Ensure Bluetooth is on and you are near the teacher.',
          );
        }
        _resumeQRScanningAfterDelay();
        return;
      }

      if (token != null) {
        if (mounted) {
          if (isOffline) {
            final timestamp = DateTime.now().toUtc().toIso8601String();
            await SyncService().enqueueQRScan(
              sessionId,
              timestamp,
              qrToken: token,
              bleHopCount: bleHopCount,
              bleRssi: bleRssi,
            );
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
            qrToken: token,
            bleHopCount: bleHopCount,
            bleRssi: bleRssi,
          );

          if (mounted) {
            if (result['success']) {
              setState(() => hasScanned = true);
              _showSuccessDialog(result['message']);
            } else {
              _showError(result['message']);
              _resumeQRScanningAfterDelay();
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Invalid QR code format: $e');
        _resumeQRScanningAfterDelay();
      }
    }
  }

  Future<void> _handlePatternCapture() async {
    if (isProcessing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }
    setState(() => isProcessing = true);

    try {
      // 1. Ensure any stream is stopped before capture
      await _stopImageStreamSafely();

      // 2. Force flash on before taking the picture
      try {
        await _cameraController!.setFlashMode(FlashMode.torch);
      } catch (_) {}

      // 3. Take photo
      final XFile picture = await _cameraController!.takePicture();
      final String imagePath = picture.path;

      // 4. Pause preview immediately so the user knows photo was taken
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
          if (errorStr.contains('dioexception') ||
              errorStr.contains('socketexception') ||
              errorStr.contains('failed host lookup') ||
              errorStr.contains('connection error')) {
            isOffline = true;
          } else {
            if (mounted) {
              _showError('Network/API Error: $e');
              setState(() => isProcessing = false);
            }
            if (_cameraController != null &&
                _cameraController!.value.isInitialized) {
              await _cameraController!.resumePreview();
              await _enforceTorch(_cameraController!);
            }
            return;
          }
        }

        if (!isOffline) {
          final patternSessions = sessions
              .where((s) => s['class_type'] == 'pattern')
              .toList();

          if (patternSessions.isEmpty) {
            isOffline = true;
          } else {
            final session = patternSessions.first;

            // Check if teacher has uploaded the reference image yet
            if (session['has_reference_image'] == false) {
              if (mounted) {
                _showError(
                  'Teacher has not uploaded the board photo yet. Please wait and try again.',
                );
              }
              Future.delayed(const Duration(seconds: 3), () async {
                if (mounted) {
                  setState(() => isProcessing = false);
                  if (_cameraController != null &&
                      _cameraController!.value.isInitialized) {
                    await _cameraController!.resumePreview();
                    await _enforceTorch(_cameraController!);
                  }
                }
              });
              return;
            }

            sessionId = session['session_id'].toString();
          }
        }
      }

      // BLE MESH VERIFICATION (Enforced for Pattern mode too)
      int bleHopCount;
      int bleRssi;

      try {
        _showBleVerificationDialog();
        if (isOffline) {
          final bleResult = await BleMeshService().startStudentScanAnySession(
            timeout: const Duration(seconds: 15),
          );
          bleHopCount = bleResult['hop_count'];
          bleRssi = bleResult['rssi'];
        } else {
          final bleResult = await BleMeshService().startStudentScanAndRelay(
            sessionId!,
            timeout: const Duration(seconds: 15),
          );
          bleHopCount = bleResult['hop_count'];
          bleRssi = bleResult['rssi'];
        }
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      } catch (e) {
        debugPrint("BLE mesh verification failed for pattern: $e");
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          _showError(
            'BLE Verification failed. Ensure Bluetooth is on and you are near the teacher.',
          );
          setState(() => isProcessing = false);
        }
        if (_cameraController != null &&
            _cameraController!.value.isInitialized) {
          await _cameraController!.resumePreview();
          await _enforceTorch(_cameraController!);
        }
        return;
      }

      if (isOffline) {
        final timestamp = DateTime.now().toUtc().toIso8601String();
        await SyncService().enqueuePatternScan(
          imagePath,
          timestamp,
          bleHopCount: bleHopCount,
          bleRssi: bleRssi,
        );
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
          if (_cameraController != null &&
              _cameraController!.value.isInitialized) {
            await _cameraController!.resumePreview();
            await _enforceTorch(_cameraController!);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: $e');
        setState(() => isProcessing = false);
        if (_cameraController != null &&
            _cameraController!.value.isInitialized) {
          await _cameraController!.resumePreview();
          await _enforceTorch(_cameraController!);
        }
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
                    color: Colors.white.withValues(alpha: 0.2),
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
                  IconButton(
                    icon: Icon(
                      _isTorchOn ? Icons.flash_on : Icons.flash_off,
                      color: _isTorchOn ? Colors.yellowAccent : Colors.white70,
                      size: 22,
                    ),
                    tooltip: 'Toggle Flash',
                    onPressed: () async {
                      if (_cameraController != null &&
                          _cameraController!.value.isInitialized) {
                        final newMode =
                            _isTorchOn ? FlashMode.off : FlashMode.torch;
                        try {
                          await _cameraController!.setFlashMode(newMode);
                          if (mounted) {
                            setState(
                              () => _isTorchOn = newMode == FlashMode.torch,
                            );
                          }
                        } catch (e) {
                          debugPrint('Toggle torch failed: $e');
                        }
                      }
                    },
                  ),
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
          // 1. Camera Viewport
          if (_cameraPermissionGranted)
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                child: (_cameraController != null &&
                        _cameraController!.value.isInitialized)
                    ? CameraPreview(_cameraController!)
                    : Center(
                        child: CircularProgressIndicator(
                          color: isPatternMode
                              ? Colors.orangeAccent
                              : const Color(0xFF007C91),
                        ),
                      ),
              ),
            )
          else
            // No permission view
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

          // 2. Scanning Frame Overlay
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

          // 3. Corner Markers (when not processing and not completed)
          if (!isProcessing && !hasScanned) ...[
            _buildCornerMarker(Alignment.topLeft),
            _buildCornerMarker(Alignment.topRight),
            _buildCornerMarker(Alignment.bottomLeft),
            _buildCornerMarker(Alignment.bottomRight),
          ],

          // 4. Mode-specific Instruction / Action Bottom Card
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
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
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
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
                        if (_cameraInitError != null ||
                            _streamStartFailed ||
                            _decoderError != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade700.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _cameraInitError ??
                                      (_streamStartFailed
                                          ? 'Camera frame stream is not running — QR detection is disabled.'
                                          : 'QR decoder problem: $_decoderError'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'frames $_framesProcessed · input errors $_inputImageErrors · decode errors $_decodeErrors',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
              top: alignment == Alignment.topLeft ||
                      alignment == Alignment.topRight
                  ? const BorderSide(color: Colors.green, width: 4)
                  : BorderSide.none,
              bottom: alignment == Alignment.bottomLeft ||
                      alignment == Alignment.bottomRight
                  ? const BorderSide(color: Colors.green, width: 4)
                  : BorderSide.none,
              left: alignment == Alignment.topLeft ||
                      alignment == Alignment.bottomLeft
                  ? const BorderSide(color: Colors.green, width: 4)
                  : BorderSide.none,
              right: alignment == Alignment.topRight ||
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
