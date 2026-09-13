import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/session_service.dart';
import '../common/custom_camera_screen.dart';
import '../../widgets/pattern_painter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../services/sync_service.dart';
import '../../widgets/offline_indicator.dart';
import '../../services/ble_mesh_service.dart';

class SessionActiveScreen extends StatefulWidget {
  final Map<String, dynamic> sessionData;
  final String qrCodeData;

  const SessionActiveScreen({
    super.key,
    required this.sessionData,
    required this.qrCodeData,
  });

  @override
  State<SessionActiveScreen> createState() => _SessionActiveScreenState();
}

class _SessionActiveScreenState extends State<SessionActiveScreen> {
  final SessionService _sessionService = SessionService();

  Timer? _countdownTimer;
  Timer? _refreshTimer;
  int remainingSeconds = 0;

  List<Map<String, dynamic>> students = [];
  Map<String, dynamic> statistics = {};
  bool isLoading = true;
  bool isUploadingReference = false;
  String? referenceImagePath;

  static const _channel = MethodChannel('attendance_app/camera');
  StreamSubscription? _syncSubscription;
  StreamSubscription? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _initializeSession();
    _startAutoRefresh();
    
    // Start BLE Broadcasting for this session
    BleMeshService().startTeacherBroadcast(widget.sessionData['session_id'].toString());

    _syncSubscription = SyncService().onSyncComplete.listen((_) {
      if (mounted) {
        setState(() {
          widget.sessionData['is_offline'] = false;
        });
        _fetchAttendanceData(showLoading: false);
      }
    });
    
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      if (mounted) {
        final isOffline = result.isEmpty || result.contains(ConnectivityResult.none);
        if (isOffline && widget.sessionData['is_offline'] == false) {
          setState(() {
            widget.sessionData['is_offline'] = true;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    BleMeshService().stopAll();
    _syncSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _countdownTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _initializeSession() {
    // CHANGE THIS: Use IST fields if available, fallback to original
    final startTimeStr =
        widget.sessionData['start_time_ist'] ??
        widget.sessionData['start_time'];
    final endTimeStr =
        widget.sessionData['end_time_ist'] ?? widget.sessionData['end_time'];

    // Parse as UTC then convert to local
    DateTime startTime;
    DateTime endTime;

    try {
      // Parse the ISO string (includes timezone offset)
      startTime = DateTime.parse(startTimeStr);
      endTime = DateTime.parse(endTimeStr);

      // If no timezone info, assume it's UTC and convert to local
      if (!startTimeStr.contains('+') && !startTimeStr.contains('Z')) {
        startTime = DateTime.parse(startTimeStr).toUtc().toLocal();
        endTime = DateTime.parse(endTimeStr).toUtc().toLocal();
      }
    } catch (e) {
      print('Error parsing time: $e');
      startTime = DateTime.now();
      endTime = DateTime.now().add(const Duration(hours: 1));
    }

    print('Start Time: $startTime'); // Debug
    print('End Time: $endTime'); // Debug
    print('Current Time: ${DateTime.now()}'); // Debug

    final duration = endTime.difference(DateTime.now());

    setState(() {
      remainingSeconds = duration.inSeconds > 0 ? duration.inSeconds : 0;
    });

    // Start countdown only if there is time remaining
    if (remainingSeconds > 0) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (remainingSeconds > 0) {
          setState(() => remainingSeconds--);
        } else {
          timer.cancel();
          if (widget.sessionData['is_offline'] != true) {
            _endSession();
          }
        }
      });
    }

    // Load initial data
    _fetchAttendanceData();
  }

  void _startAutoRefresh() {
    // Refresh student list every 3 seconds for real-time updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchAttendanceData(showLoading: false);
    });
  }

  Future<void> _fetchAttendanceData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => isLoading = true);
    }

    try {
      final result = await _sessionService.getSessionAttendance(
        widget.sessionData['session_id'].toString(),
      );

      if (!mounted) return;
      
      if (result != null && result['success'] == true) {
        setState(() {
          students = List<Map<String, dynamic>>.from(result['students'] ?? []);
          statistics = result['statistics'] ?? {};
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
      }
      print('Error fetching attendance: $e');
    }
  }

  Future<void> _manualMarkAttendance(int studentId, String status) async {
    final result = await _sessionService.manualMarkAttendance(
      sessionId: widget.sessionData['session_id'].toString(),
      studentId: studentId,
      status: status,
    );

    if (result['success']) {
      _showSuccessSnackBar(result['message'] ?? 'Attendance updated');
      _fetchAttendanceData(showLoading: false); // Refresh immediately
    } else {
      _showErrorSnackBar(result['message'] ?? 'Failed to update');
    }
  }

  Future<void> _endSession() async {
    BleMeshService().stopAll(); // Stop BLE broadcasting
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.warning_rounded, color: Colors.red.shade700),
            ),
            const SizedBox(width: 12),
            const Text('End Session?'),
          ],
        ),
        content: const Text(
          'All students who haven\'t marked attendance will be automatically marked as ABSENT.\n\nThis action cannot be undone.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('End Session'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOffline =
          connectivityResult.isEmpty ||
          connectivityResult.contains(ConnectivityResult.none);

      if (isOffline) {
        if (mounted) {
          Navigator.pop(context);
          _showSuccessSnackBar(
            'Session ended offline. It will sync automatically when internet is restored.',
          );
        }
        return;
      }

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final result = await _sessionService.endSession(
        widget.sessionData['session_id'].toString(),
      );

      if (mounted) {
        Navigator.pop(context); // Close loading

        if (result['success'] == true) {
          final stats = result['statistics'] ?? {};

          // Show statistics dialog
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF007C91), Color(0xFF0097A7)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.check_circle, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Text('Session Ended'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatRow(
                    'Total Students',
                    '${stats['total_students'] ?? 0}',
                    Icons.people,
                    const Color(0xFF007C91),
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow(
                    'Present',
                    '${stats['present'] ?? 0}',
                    Icons.check_circle,
                    Colors.green,
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow(
                    'Absent',
                    '${stats['absent'] ?? 0}',
                    Icons.cancel,
                    Colors.red,
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow(
                    'Attendance Rate',
                    '${stats['attendance_rate'] ?? 0}%',
                    Icons.trending_up,
                    Colors.orange,
                  ),

                  if ((stats['auto_marked_absent'] ?? 0) > 0) ...[
                    const Divider(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${stats['auto_marked_absent']} student(s) automatically marked absent',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pop(context); // Go back to previous screen
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007C91),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        } else {
          _showErrorSnackBar(result['message'] ?? 'Failed to end session');
        }
      }
    }
  }

  Future<void> _cancelSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Cancel Session?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to cancel and delete this session? All attendance records will be permanently removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Session'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Session'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final result = await _sessionService.deleteSession(widget.sessionData['session_id'].toString());
      if (mounted) {
        Navigator.pop(context); // close loader
        if (result['success'] == true) {
          Navigator.pop(context); // close active screen
        } else {
          _showErrorSnackBar(result['message'] ?? 'Failed to delete session');
        }
      }
    }
  }

  Future<void> _markAllPresent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark All Present'),
        content: const Text('Are you sure you want to mark all enrolled students in this class as present?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007C91),
              foregroundColor: Colors.white,
            ),
            child: const Text('Mark All Present'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final result = await _sessionService.markAllPresent(widget.sessionData['session_id'].toString());
      if (mounted) {
        Navigator.pop(context); // close loader
        if (result['success'] == true) {
          _showSuccessSnackBar(result['message'] ?? 'Marked all present');
          _fetchAttendanceData(showLoading: false);
        } else {
          _showErrorSnackBar(result['message'] ?? 'Failed to mark all present');
        }
      }
    }
  }

  Widget _buildStatRow(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 1000;
    final isTablet = size.width > 600 && size.width <= 1000;
    final isMobile = size.width <= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active Session: ${widget.sessionData['class_code']}${widget.sessionData['class_type'] == 'pattern' ? ' (Pattern Mode)' : ''}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.sessionData['class_name'] ?? '',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        backgroundColor: const Color(0xFF00838f),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          const OfflineIndicator(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchAttendanceData(),
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle),
            onPressed: _endSession,
            tooltip: 'End Session',
          ),
          if (widget.sessionData['is_offline'] != true)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'cancel') {
                  _cancelSession();
                } else if (value == 'mark_all') {
                  _markAllPresent();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'mark_all',
                  child: Row(
                    children: [
                      Icon(Icons.done_all, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Mark All Present'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'cancel',
                  child: Row(
                    children: [
                      Icon(Icons.delete_forever, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Cancel Session', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please end the session to exit.'),
              backgroundColor: Colors.orange,
            ),
          );
        },
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : isMobile
            ? _buildMobileLayout()
            : _buildDesktopLayout(isDesktop),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTimerCard(),
            const SizedBox(height: 16),
            _buildQRSection(size: 200),
            const SizedBox(height: 16),
            const SizedBox(height: 16),
              if (widget.sessionData['is_offline'] == true && students.isEmpty)
                _buildOfflinePlaceholder()
              else ...[
                _buildStatisticsCard(),
              const SizedBox(height: 16),
              _buildStudentsList(isMobile: true),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(bool isDesktop) {
    return Row(
      children: [
        // LEFT SIDE - QR Code
        Expanded(
          flex: isDesktop ? 2 : 3,
          child: Container(
            color: Colors.white,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTimerCard(),
                    const SizedBox(height: 32),
                    _buildQRSection(size: isDesktop ? 400 : 300),
                    const SizedBox(height: 24),
                    if (widget.sessionData['is_offline'] == true && students.isEmpty)
                      _buildOfflinePlaceholder()
                    else
                      _buildStatisticsCard(),
                  ],
                ),
              ),
            ),
          ),
        ),

        // DIVIDER
        Container(width: 1, color: Colors.grey[300]),

        // RIGHT SIDE - Students List
        if (widget.sessionData['is_offline'] == true && students.isEmpty)
          const Expanded(flex: 3, child: SizedBox.shrink())
        else
          Expanded(
            flex: isDesktop ? 3 : 4,
            child: _buildStudentsList(isMobile: false),
          ),
      ],
    );
  }

  Widget _buildTimerCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: remainingSeconds > 60
            ? const Color(0xFF00838f)
            : Colors.orange.shade700,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color:
                (remainingSeconds > 60
                        ? const Color(0xFF00838f)
                        : Colors.orange)
                    .withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Text(
            _formatTime(remainingSeconds),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadReferenceImage() async {
    String? imagePath;
    try {
      imagePath = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => const CustomCameraScreen(
            title: 'Capture Pattern',
            helperText:
                'Capture the entire whiteboard with the drawn pattern clearly visible.',
          ),
        ),
      );
    } catch (e) {
      _showErrorSnackBar('Camera error: $e');
      return;
    }

    if (imagePath == null) return;

    setState(() => isUploadingReference = true);

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOffline =
          connectivityResult.isEmpty ||
          connectivityResult.contains(ConnectivityResult.none);

      if (isOffline) {
        await SyncService().updateSessionReferenceImage(
          widget.sessionData['session_id'].toString(),
          imagePath,
        );
        setState(() => referenceImagePath = imagePath);
        _showSuccessSnackBar(
          'Reference image saved offline. It will sync automatically when internet is restored.',
        );
      } else {
        final result = await _sessionService.uploadReferenceImage(
          widget.sessionData['session_id'].toString(),
          imagePath,
        );

        if (result['success'] == true) {
          setState(() => referenceImagePath = imagePath);
          _showSuccessSnackBar('Reference image uploaded successfully');
        } else {
          _showErrorSnackBar(result['message'] ?? 'Upload failed');
        }
      }
    } catch (e) {
      _showErrorSnackBar('Upload error: $e');
    } finally {
      setState(() => isUploadingReference = false);
    }
  }

  Widget _buildQRSection({required double size}) {
    final isPattern = widget.sessionData['class_type'] == 'pattern';
    final patternCode = widget.sessionData['pattern_code'] ?? '??';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF007C91), width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          if (isPattern) ...[
            if (widget.sessionData['shape_data'] != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF22C55E), width: 2),
                ),
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: CustomPaint(
                    painter: PatternPainter(
                      shapeData:
                          widget.sessionData['shape_data']
                              as Map<String, dynamic>,
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF22C55E), width: 2),
                ),
                child: Text(
                  patternCode,
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: Color(0xFF166534),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              "Draw this exactly on the board",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 24),
            InkWell(
              onTap: isUploadingReference ? null : _uploadReferenceImage,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF007C91),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF007C91).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: isUploadingReference
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        referenceImagePath != null ? Icons.check : Icons.upload,
                        color: Colors.white,
                        size: 28,
                      ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Take a photo of the board",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1F2937),
              ),
            ),
          ] else ...[
            QrImageView(
              data: widget.qrCodeData,
              version: QrVersions.auto,
              size: size,
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF00838f),
            ),
            const SizedBox(height: 16),
            const Text(
              "Scan to Mark Attendance",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            "Session ID: ${widget.sessionData['session_id'].toString().substring(0, 8)}......",
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          if (isPattern) ...[
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh, size: 32),
                  color: const Color(0xFF007C91),
                  onPressed: () => _fetchAttendanceData(),
                ),
                const SizedBox(width: 48),
                IconButton(
                  icon: const Icon(Icons.stop_circle, size: 32),
                  color: const Color(0xFF007C91),
                  onPressed: _endSession,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
  Widget _buildOfflinePlaceholder() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 48, color: Colors.orange.shade400),
          const SizedBox(height: 16),
          const Text(
            'Offline Session',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Student list and statistics are unavailable while offline. They will be calculated automatically once the session is synced to the server.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.orange.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard() {
    final total = statistics['total'] ?? 0;
    final present = statistics['present'] ?? 0;
    final absent = statistics['absent'] ?? 0;
    final rate = statistics['attendance_rate'] ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.blue.shade50, Colors.white]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          const Text(
            'Attendance Statistics',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Total', total.toString(), Colors.blue),
              _buildStatItem('Present', present.toString(), Colors.green),
              _buildStatItem('Absent', absent.toString(), Colors.red),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: total > 0 ? present / total : 0,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              rate >= 75
                  ? Colors.green
                  : (rate >= 50 ? Colors.orange : Colors.red),
            ),
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
          const SizedBox(height: 8),
          Text(
            '${rate.toStringAsFixed(1)}% Attendance Rate',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: rate >= 75
                  ? Colors.green[700]
                  : (rate >= 50 ? Colors.orange[700] : Colors.red[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildStudentsList({bool isMobile = false}) {
    if (students.isEmpty) {
      return const Center(child: Text('No students enrolled in this class'));
    }

    return ListView.builder(
      shrinkWrap: isMobile,
      physics: isMobile ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(16),
      itemCount: students.length,
      itemBuilder: (context, index) {
        final student = students[index];
        final isPresent = student['status'] == 'present';
        final hasRecord = student['has_record'] == true;

        return Card(
          color: isPresent ? Colors.white : const Color(0xFFFFF0F0),
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isPresent ? Colors.grey.shade200 : const Color(0xFFFFCDCD),
              width: 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: isPresent
                  ? Colors.green.shade100
                  : Colors.red.shade100,
              child: Icon(
                isPresent ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: isPresent ? Colors.green : Colors.red,
                size: 28,
              ),
            ),
            title: Text(
              student['username'] ?? 'Unknown',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                if (hasRecord && isPresent && student['marked_at'] != null)
                  Text(
                    'Marked at: ${DateTime.parse(student['marked_at']).toLocal().toString().substring(11, 16)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Present Button
                IconButton(
                  onPressed: isPresent
                      ? null
                      : () => _manualMarkAttendance(student['id'], 'present'),
                  icon: const Icon(Icons.check_circle_rounded),
                  color: Colors.green,
                  tooltip: 'Mark Present',
                  style: IconButton.styleFrom(
                    backgroundColor: isPresent
                        ? Colors.green.withOpacity(0.2)
                        : Colors.green.withOpacity(0.1),
                  ),
                ),
                const SizedBox(width: 8),
                // Absent Button
                IconButton(
                  onPressed: !isPresent
                      ? null
                      : () => _manualMarkAttendance(student['id'], 'absent'),
                  icon: const Icon(Icons.cancel_rounded),
                  color: Colors.red,
                  tooltip: 'Mark Absent',
                  style: IconButton.styleFrom(
                    backgroundColor: !isPresent
                        ? Colors.red.withOpacity(0.2)
                        : Colors.red.withOpacity(0.1),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
