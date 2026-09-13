import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../services/face_auth_service.dart';

class FaceVerificationScreen extends StatefulWidget {
  final bool isRegistration;

  const FaceVerificationScreen({super.key, this.isRegistration = false});

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  CameraController? _cameraController;
  final FaceAuthService _faceService = FaceAuthService();
  bool _isProcessing = false;
  String _statusMessage = "Position your face in the frame";
  bool _offlineMode = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    await _faceService.initialize();
    
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      setState(() {
        _statusMessage = "Failed to initialize camera.";
      });
    }
  }

  Future<void> _captureAndProcess() async {
    if (_isProcessing || _cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = "Analyzing face...";
    });

    try {
      final image = await _cameraController!.takePicture();

      bool success = false;
      if (widget.isRegistration) {
        if (_offlineMode) {
          success = await _faceService.registerFaceOffline(image.path);
        } else {
          success = await _faceService.registerFace(image);
        }
        if (success) {
          _statusMessage = "Registered";
        } else {
          _statusMessage = "Face registration failed.";
        }
      } else {
        if (_offlineMode) {
          success = await _faceService.verifyFaceOffline(image.path);
        } else {
          success = await _faceService.verifyFace(image);
        }
        if (success) {
          _statusMessage = "Face matched";
        } else {
          _statusMessage = "Face not recognized. Try again.";
        }
      }

      setState(() {});

      if (success) {
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          if (_cameraController != null) {
            await _cameraController!.dispose();
            _cameraController = null;
          }
          Navigator.pop(context, true);
        }
      } else {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          setState(() {
            _statusMessage = "Position your face in the frame";
            _isProcessing = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Error processing face.";
        _isProcessing = false;
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.isRegistration ? 'Set Up Face ID' : 'Verify Face'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera Preview
          CameraPreview(_cameraController!),
          
          // Overlay mask
          ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.7), BlendMode.srcOut),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Center(
                  child: Container(
                    height: 350,
                    width: 250,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(125),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scanning frame box
          Center(
            child: Container(
              height: 350,
              width: 250,
              decoration: BoxDecoration(
                border: Border.all(color: _isProcessing ? Colors.blue : Colors.green, width: 3),
                borderRadius: BorderRadius.circular(125),
              ),
            ),
          ),

          // Status & Capture Button
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Offline Mode', style: TextStyle(color: Colors.white)),
                    Switch(
                      value: _offlineMode,
                      onChanged: (val) {
                        setState(() { _offlineMode = val; });
                      },
                    ),
                  ],
                ),
                Text(
                  _statusMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (!_isProcessing)
                  FloatingActionButton.large(
                    onPressed: _captureAndProcess,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.camera_alt, color: Colors.black, size: 36),
                  )
                else
                  const CircularProgressIndicator(color: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
