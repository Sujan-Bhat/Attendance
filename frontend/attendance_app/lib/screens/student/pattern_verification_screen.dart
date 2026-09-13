import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/attendance_service.dart';

class PatternVerificationScreen extends StatefulWidget {
  final String sessionId;
  final String classCode;

  const PatternVerificationScreen({
    super.key,
    required this.sessionId,
    required this.classCode,
  });

  @override
  State<PatternVerificationScreen> createState() =>
      _PatternVerificationScreenState();
}

class _PatternVerificationScreenState extends State<PatternVerificationScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  bool _isProcessing = false;
  String? _capturedImagePath;
  bool _offlineMode = false;

  static const _channel = MethodChannel('attendance_app/camera');
  static const _offlineChannel = MethodChannel('attendance_app/offline');

  Future<void> _captureImage() async {
    String? imagePath;
    try {
      imagePath = await _channel.invokeMethod<String>('captureImage');
    } on MissingPluginException {
      imagePath = null;
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Camera error: $e');
      }
      return;
    }

    if (imagePath != null) {
      setState(() => _capturedImagePath = imagePath);
      _verifyAttendance(imagePath);
    }
  }

  Future<void> _verifyAttendance(String imagePath) async {
    setState(() => _isProcessing = true);

    try {
      final result = await _attendanceService.verifyImage(
        sessionId: widget.sessionId,
        imagePath: imagePath,
        focalDistance: 2.0,
      );

      if (mounted) {
        if (result['success']) {
          _showSuccessDialog(
            result['message'] ?? 'Attendance marked successfully',
          );
        } else {
          _showErrorSnackBar(result['message'] ?? 'Verification failed');
          setState(() {
            _capturedImagePath = null;
            _isProcessing = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error: $e');
        setState(() {
          _capturedImagePath = null;
          _isProcessing = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
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
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close verification screen
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
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 10),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            bottom: 8,
            left: 20,
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
                  'Verify: ${widget.classCode}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Center(
        child: _isProcessing
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Verifying pattern...'),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        size: 80,
                        color: Colors.orange.shade400,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Take a Picture of the Board',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Match the pattern drawn by your teacher to mark your attendance.',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _captureImage,
                        icon: const Icon(Icons.camera),
                        label: const Text('Open Camera'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF007C91),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
