import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/session_service.dart';
import 'dart:convert';

class SessionPage extends StatefulWidget {
  final List<Map<String, String>> subjects;  
  const SessionPage({super.key, required this.subjects});

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage>
    with SingleTickerProviderStateMixin {
  final SessionService _sessionService = SessionService();
  
  String? selectedSubjectId;  
  String? selectedSubjectCode;
  String? selectedSubjectName;
  String? selectedSemester;
  final TextEditingController durationController = TextEditingController();

  Timer? countdownTimer;
  int remainingSeconds = 0;
  bool isSessionActive = false;
  bool isCreatingSession = false;
  
  Map<String, dynamic>? sessionData;  //  Store session data from backend
  String? qrCodeData;  // QR code data

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();

    if (widget.subjects.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showErrorSnackBar("No classes available. Please create a class first.");
      });
    }
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    durationController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ✅ NEW: Start session with backend API call
  Future<void> startSession() async {
    if (selectedSubjectId == null || durationController.text.isEmpty) {
      _showErrorSnackBar("Please select a class and enter duration.");
      return;
    }

    final durationMinutes = int.tryParse(durationController.text);
    if (durationMinutes == null || durationMinutes <= 0) {
      _showErrorSnackBar("Please enter a valid duration in minutes.");
      return;
    }

    setState(() {
      isCreatingSession = true;
    });

    try {
      // Call backend API to create session
      final result = await _sessionService.createSession(
        classId: int.parse(selectedSubjectId!),
        durationMinutes: durationMinutes,
      );

      if (!mounted) return;

      if (result['success']) {
        sessionData = result['session'];
        final qrData = sessionData!['qr_data'];
        
        // Generate QR code string from backend data
        qrCodeData = jsonEncode(qrData);

        setState(() {
          isSessionActive = true;
          remainingSeconds = durationMinutes * 60;
          isCreatingSession = false;
        });

        // Start countdown timer
        countdownTimer?.cancel();
        countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (remainingSeconds > 0) {
            setState(() {
              remainingSeconds--;
            });
          } else {
            timer.cancel();
            _endSession();
          }
        });

        _showSuccessSnackBar(
          "Session started for $selectedSubjectCode - $selectedSubjectName",
        );
      } else {
        setState(() {
          isCreatingSession = false;
        });
        _showErrorSnackBar(result['message'] ?? 'Failed to create session');
      }
    } catch (e) {
      setState(() {
        isCreatingSession = false;
      });
      _showErrorSnackBar('Error creating session: $e');
    }
  }

  // NEW: End session
  Future<void> _endSession() async {
    if (sessionData != null) {
      await _sessionService.endSession(sessionData!['session_id']);
    }
    
    setState(() {
      isSessionActive = false;
      sessionData = null;
      qrCodeData = null;
    });
    
    _showSuccessSnackBar("Session ended successfully!");
  }

  String formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$secs";
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 15))),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 15))),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;
    final isMobile = size.width < 600;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF007C91), Color(0xFF0097A7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top AppBar
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 20,
                  vertical: isMobile ? 10 : 14,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF007C91), Color(0xFF0097A7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: isMobile ? 24 : 28,
                      ),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Back',
                    ),
                    SizedBox(width: isMobile ? 4 : 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Create Session',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isMobile ? 18 : 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                          if (!isMobile)
                            const Text(
                              'Start a new attendance session',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Main Content
              Expanded(
                child: Center(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 16 : (isDesktop ? 0 : 24),
                          vertical: isMobile ? 16 : 24,
                        ),
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: isDesktop ? 550 : double.infinity,
                          ),
                          child: Card(
                            elevation: 20,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4F8FB),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: EdgeInsets.all(isMobile ? 20 : (isDesktop ? 48 : 32)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Icon Header
                                  Center(
                                    child: Container(
                                      padding: EdgeInsets.all(isMobile ? 12 : 16),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF007C91), Color(0xFF0097A7)],
                                        ),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF007C91).withOpacity(0.3),
                                            blurRadius: 20,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.timer_rounded,
                                        size: isMobile ? 40 : 50,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: isMobile ? 16 : 24),

                                  // Title
                                  Text(
                                    "Start a New Session",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: isMobile ? 20 : 24,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF1F2937),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.subjects.isEmpty
                                        ? 'No classes available'
                                        : 'Select class and duration',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: isMobile ? 14 : 15,
                                      color: widget.subjects.isEmpty
                                          ? Colors.red[600]
                                          : Colors.grey[600],
                                    ),
                                  ),
                                  SizedBox(height: isMobile ? 20 : 32),

                                  // Select Class Dropdown
                                  Text(
                                    "Select Class",
                                    style: TextStyle(
                                      fontSize: isMobile ? 14 : 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: DropdownButtonFormField<String>(
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        prefixIcon: Icon(Icons.book_rounded, color: Color(0xFF007C91)),
                                        contentPadding: EdgeInsets.symmetric(vertical: 18),
                                      ),
                                      dropdownColor: Colors.white,
                                      value: selectedSubjectId,
                                      items: widget.subjects.map((subject) {
                                        return DropdownMenuItem<String>(
                                          value: subject['id'],
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                "${subject['code']} - ${subject['name']}",
                                                style: TextStyle(
                                                  fontSize: isMobile ? 14 : 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              Text(
                                                subject['semester'] ?? '',
                                                style: TextStyle(
                                                  fontSize: isMobile ? 11 : 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: widget.subjects.isEmpty
                                          ? null
                                          : (value) {
                                              setState(() {
                                                selectedSubjectId = value;
                                                final selected = widget.subjects.firstWhere(
                                                  (s) => s['id'] == value,
                                                );
                                                selectedSubjectCode = selected['code'];
                                                selectedSubjectName = selected['name'];
                                                selectedSemester = selected['semester'];
                                              });
                                            },
                                      hint: Text(
                                        widget.subjects.isEmpty
                                            ? "No classes available"
                                            : "Select a class",
                                        style: TextStyle(
                                          color: widget.subjects.isEmpty
                                              ? Colors.red[400]
                                              : Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: isMobile ? 16 : 24),

                                  // Duration
                                  Text(
                                    "Duration (minutes)",
                                    style: TextStyle(
                                      fontSize: isMobile ? 14 : 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: TextField(
                                      controller: durationController,
                                      keyboardType: TextInputType.number,
                                      style: TextStyle(fontSize: isMobile ? 14 : 16),
                                      decoration: InputDecoration(
                                        prefixIcon: const Icon(
                                          Icons.timer_outlined,
                                          color: Color(0xFF007C91),
                                        ),
                                        hintText: "e.g. 45",
                                        hintStyle: TextStyle(color: Colors.grey[400]),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 18,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: isMobile ? 20 : 32),

                                  // Active Session Display with QR Code
                                  if (isSessionActive && qrCodeData != null)
                                    Column(
                                      children: [
                                        // Countdown Timer
                                        Container(
                                          padding: EdgeInsets.all(isMobile ? 16 : 20),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.orange.shade400,
                                                Colors.deepOrange.shade500
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.orange.withOpacity(0.3),
                                                blurRadius: 15,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                "Session Active: $selectedSubjectCode",
                                                style: TextStyle(
                                                  fontSize: isMobile ? 16 : 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 10),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.timer_rounded,
                                                    color: Colors.white,
                                                    size: isMobile ? 24 : 30,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    formatTime(remainingSeconds),
                                                    style: TextStyle(
                                                      fontSize: isMobile ? 36 : 48,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: isMobile ? 16 : 24),

                                        //  QR Code from Backend
                                        Container(
                                          padding: EdgeInsets.all(isMobile ? 16 : 20),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: const Color(0xFF007C91).withOpacity(0.3),
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.05),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            children: [
                                              QrImageView(
                                                data: qrCodeData!,
                                                version: QrVersions.auto,
                                                size: isMobile ? 200.0 : 250.0,
                                                backgroundColor: Colors.white,
                                                foregroundColor: const Color(0xFF007C91),
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                "Scan to mark attendance",
                                                style: TextStyle(
                                                  color: Colors.grey[700],
                                                  fontSize: isMobile ? 14 : 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                "Session ID: ${sessionData?['session_id']?.toString().substring(0, 8) ?? ''}...",
                                                style: TextStyle(
                                                  color: Colors.grey[500],
                                                  fontSize: isMobile ? 11 : 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: isMobile ? 16 : 24),

                                        // End Session Button
                                        SizedBox(
                                          width: double.infinity,
                                          height: isMobile ? 48 : 56,
                                          child: ElevatedButton.icon(
                                            onPressed: _endSession,
                                            icon: const Icon(Icons.stop_circle_rounded, size: 24),
                                            label: Text(
                                              "End Session",
                                              style: TextStyle(
                                                fontSize: isMobile ? 16 : 18,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red.shade600,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(16),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                  //  QR Placeholder (when not active)
                                  if (!isSessionActive)
                                    Container(
                                      height: isMobile ? 150 : 180,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(0xFF007C91).withOpacity(0.3),
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.05),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.qr_code_2_rounded,
                                              size: isMobile ? 60 : 80,
                                              color: Colors.grey[300],
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              "QR Code will appear here",
                                              style: TextStyle(
                                                color: Colors.grey[500],
                                                fontSize: isMobile ? 13 : 15,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  
                                  if (!isSessionActive) SizedBox(height: isMobile ? 20 : 32),

                                  // Start Session Button
                                  if (!isSessionActive)
                                    SizedBox(
                                      width: double.infinity,
                                      height: isMobile ? 48 : 56,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: (isCreatingSession || widget.subjects.isEmpty)
                                                ? [Colors.grey[400]!, Colors.grey[500]!]
                                                : [const Color(0xFF007C91), const Color(0xFF0097A7)],
                                          ),
                                          borderRadius: BorderRadius.circular(16),
                                          boxShadow: (!isCreatingSession && widget.subjects.isNotEmpty)
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(0xFF007C91).withOpacity(0.4),
                                                    blurRadius: 15,
                                                    offset: const Offset(0, 8),
                                                  ),
                                                ]
                                              : [],
                                        ),
                                        child: ElevatedButton.icon(
                                          onPressed: (isCreatingSession || widget.subjects.isEmpty)
                                              ? null
                                              : startSession,
                                          icon: isCreatingSession
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(
                                                    color: Colors.white,
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.play_circle_fill_rounded,
                                                  size: 24,
                                                ),
                                          label: Text(
                                            isCreatingSession
                                                ? "Creating..."
                                                : widget.subjects.isEmpty
                                                    ? "No Classes Available"
                                                    : "Start Session",
                                            style: TextStyle(
                                              fontSize: isMobile ? 16 : 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
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