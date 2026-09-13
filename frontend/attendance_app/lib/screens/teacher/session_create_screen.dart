import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/class_service.dart';
import '../../services/session_service.dart';
import '../../widgets/teacher_drawer.dart';
import 'dart:convert';
import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'session_active_screen.dart';
import '../../services/sync_service.dart';
import '../../widgets/teacher_web_layout.dart';
import '../../widgets/offline_indicator.dart';

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
  String selectedClassType = 'qr'; // Default to qr

  final TextEditingController durationController = TextEditingController();
  final TextEditingController rotationIntervalController = TextEditingController(text: '10');

  Timer? countdownTimer;
  int remainingSeconds = 0;
  bool isSessionActive = false;
  bool isCreatingSession = false;

  Map<String, dynamic>? sessionData; //  Store session data from backend
  String? qrCodeData; // QR code data

  bool isPastSession = false;
  DateTime? selectedStartTime;

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
        _showErrorSnackBar(
          "No classes available. Please create a class first.",
        );
      });
    }
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    durationController.dispose();
    rotationIntervalController.dispose();
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

    setState(() => isCreatingSession = true);

    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final isOffline =
          connectivityResults.isEmpty ||
          connectivityResults.contains(ConnectivityResult.none);

      if (isOffline) {
        final sessionId = const Uuid().v4();
        final startTime = isPastSession && selectedStartTime != null
            ? selectedStartTime!.toUtc()
            : DateTime.now().toUtc();
        final endTime = startTime.add(Duration(minutes: durationMinutes));

        final selectedClass = widget.subjects.firstWhere(
          (c) => c['id'].toString() == selectedSubjectId,
        );

        String? shapeDataStr;
        String? instructionCard;
        String? patternCode;

        if (selectedClassType == 'pattern') {
          final shapes = [
            "circle",
            "square",
            "triangle",
            "diamond",
            "pentagon",
            "hexagon",
          ];
          final rand = Random();
          final outer = shapes[rand.nextInt(shapes.length)];
          final hasInner = rand.nextBool();
          String inner = "none";
          if (hasInner) {
            final otherShapes = shapes.where((s) => s != outer).toList();
            inner = otherShapes[rand.nextInt(otherShapes.length)];
          }
          final freshnessTag = (rand.nextInt(90) + 10).toString();

          if (hasInner) {
            instructionCard =
                "Draw a large \$outer. Inside it, draw a smaller \$inner. Finally, write the number '\$freshnessTag' inside the \$inner.";
          } else {
            instructionCard =
                "Draw a large \$outer. Finally, write the number '\$freshnessTag' inside the \$outer.";
          }

          final shapeCombo = {
            "outer": outer,
            "inner": inner,
            "number": freshnessTag,
          };
          shapeDataStr = jsonEncode(shapeCombo);
          patternCode = freshnessTag;
        }

        await SyncService().enqueueSession(
          id: sessionId,
          classId: int.parse(selectedSubjectId!),
          classType: selectedClassType,
          durationMinutes: durationMinutes,
          startTime: startTime.toIso8601String(),
          endTime: endTime.toIso8601String(),
          shapeData: shapeDataStr,
        );

        final qrDataMap = {
          'session_id': sessionId,
          'class_id': selectedClass['id'],
          'class_code': selectedClass['code'],
          'class_name': selectedClass['name'],
          'semester': selectedClass['semester'],
          'teacher': 'Offline Teacher',
          'start_time': startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
          'duration': durationMinutes,
          'class_type': selectedClassType,
          'pattern_code': patternCode,
          'is_offline': true,
        };

        sessionData = {
          'id': sessionId,
          'session_id': sessionId,
          'class_code': selectedClass['code'],
          'class_name': selectedClass['name'],
          'semester': selectedClass['semester'],
          'teacher_name': 'You (Offline)',
          'start_time': startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
          'is_offline': true,
          'duration_minutes': durationMinutes,
          'status': 'active',
          'is_active': true,
          'qr_data': qrDataMap,
          'class_type': selectedClassType,
          'pattern_code': patternCode,
          'instruction_card': instructionCard,
          'shape_data': shapeDataStr != null ? jsonDecode(shapeDataStr) : null,
        };

        qrCodeData = jsonEncode(qrDataMap);

        setState(() => isCreatingSession = false);
        _showSuccessSnackBar(
          "Session created offline. It will sync automatically when internet is restored.",
        );

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SessionActiveScreen(
              sessionData: sessionData!,
              qrCodeData: qrCodeData!,
            ),
          ),
        );
        return;
      }

      final result = await _sessionService.createSession(
        classId: int.parse(selectedSubjectId!),
        durationMinutes: durationMinutes,
        classType: selectedClassType,
        startTime: isPastSession && selectedStartTime != null
            ? selectedStartTime!.toUtc().toIso8601String()
            : null,
        rotationInterval: int.tryParse(rotationIntervalController.text) ?? 10,
      );

      if (!mounted) return;

      if (result['success']) {
        sessionData = result['session'];
        final qrData = sessionData!['qr_data'];
        qrCodeData = jsonEncode(qrData);

        setState(() => isCreatingSession = false);

        //  NAVIGATE TO FULL-SCREEN SESSION VIEW
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SessionActiveScreen(
              sessionData: sessionData!,
              qrCodeData: qrCodeData!,
            ),
          ),
        );

        _showSuccessSnackBar(
          "Session started for $selectedSubjectCode - $selectedSubjectName",
        );
      } else {
        setState(() => isCreatingSession = false);
        _showErrorSnackBar(result['message'] ?? 'Failed to create session');
      }
    } catch (e) {
      setState(() => isCreatingSession = false);
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
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 15)),
            ),
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
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 15)),
            ),
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

    Widget mainContent = Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF00838f), // Solid Teal background
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
                        icon: const Icon(
                          Icons.menu_rounded,
                          color: Colors.white,
                        ),
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
                  SizedBox(width: isMobile ? 8 : 12),
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
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const OfflineIndicator(),
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
                            padding: EdgeInsets.all(
                              isMobile ? 20 : (isDesktop ? 48 : 32),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Icon Header
                                Center(
                                  child: Container(
                                    padding: EdgeInsets.all(isMobile ? 16 : 24),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF00838f),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.qr_code_2_rounded,
                                      size: isMobile ? 50 : 70,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                SizedBox(height: isMobile ? 24 : 32),

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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: DropdownButtonFormField<String>(
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      prefixIcon: Icon(
                                        Icons.book_rounded,
                                        color: Color(0xFF007C91),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                    ),
                                    dropdownColor: Colors.white,
                                    isExpanded: true,
                                    value: selectedSubjectId,
                                    itemHeight: null,
                                    menuMaxHeight: 300,
                                    items: widget.subjects.map((subject) {
                                      return DropdownMenuItem<String>(
                                        value: subject['id'],
                                        child: Text(
                                          "${subject['name']} (${(subject['semester']?.toString().toLowerCase().contains('semester') == true) ? subject['semester'] : 'Semester ${subject['semester'] ?? ''}'})",
                                          style: TextStyle(
                                            fontSize: isMobile ? 14 : 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: widget.subjects.isEmpty
                                        ? null
                                        : (value) {
                                            setState(() {
                                              selectedSubjectId = value;
                                              final selected = widget.subjects
                                                  .firstWhere(
                                                    (s) => s['id'] == value,
                                                  );
                                              selectedSubjectCode =
                                                  selected['code'];
                                              selectedSubjectName =
                                                  selected['name'];
                                              selectedSemester =
                                                  selected['semester'];
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

                                // Class Type Dropdown
                                Text(
                                  "Class Type",
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: DropdownButtonFormField<String>(
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      prefixIcon: Icon(
                                        Icons.class_rounded,
                                        color: Color(0xFF007C91),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                    ),
                                    dropdownColor: Colors.white,
                                    isExpanded: true,
                                    value: selectedClassType,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'qr',
                                        child: Text('QR'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'pattern',
                                        child: Text('Pattern'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() {
                                          selectedClassType = value;
                                        });
                                      }
                                    },
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
                                    style: TextStyle(
                                      fontSize: isMobile ? 14 : 16,
                                    ),
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(
                                        Icons.timer_outlined,
                                        color: Color(0xFF007C91),
                                      ),
                                      hintText: "e.g. 45",
                                      hintStyle: TextStyle(
                                        color: Colors.grey[400],
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 18,
                                          ),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                  ),
                                ),
                                SizedBox(height: isMobile ? 16 : 24),

                                // QR Rotation Interval (Only show if class type is QR)
                                if (selectedClassType == 'qr') ...[
                                  Text(
                                    "QR Rotation Interval (seconds)",
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
                                      controller: rotationIntervalController,
                                      keyboardType: TextInputType.number,
                                      style: TextStyle(
                                        fontSize: isMobile ? 14 : 16,
                                      ),
                                      decoration: InputDecoration(
                                        prefixIcon: const Icon(
                                          Icons.autorenew_outlined,
                                          color: Color(0xFF007C91),
                                        ),
                                        hintText: "e.g. 10",
                                        hintStyle: TextStyle(
                                          color: Colors.grey[400],
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 18,
                                            ),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: isMobile ? 16 : 24),
                                ],

                                // Past Session Toggle
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
                                  child: SwitchListTile(
                                    title: const Text(
                                      "Past Session",
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: const Text("Create a session for a previous date"),
                                    activeColor: const Color(0xFF007C91),
                                    value: isPastSession,
                                    onChanged: (bool value) {
                                      setState(() {
                                        isPastSession = value;
                                        if (value && selectedStartTime == null) {
                                          selectedStartTime = DateTime.now();
                                        }
                                      });
                                    },
                                  ),
                                ),

                                if (isPastSession) ...[
                                  SizedBox(height: isMobile ? 16 : 24),
                                  Text(
                                    "Start Date & Time",
                                    style: TextStyle(
                                      fontSize: isMobile ? 14 : 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  InkWell(
                                    onTap: () async {
                                      final date = await showDatePicker(
                                        context: context,
                                        initialDate: selectedStartTime ?? DateTime.now(),
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime.now(),
                                        builder: (context, child) {
                                          return Theme(
                                            data: Theme.of(context).copyWith(
                                              colorScheme: const ColorScheme.light(
                                                primary: Color(0xFF007C91),
                                              ),
                                            ),
                                            child: child!,
                                          );
                                        },
                                      );
                                      if (date != null && mounted) {
                                        final time = await showTimePicker(
                                          context: context,
                                          initialTime: TimeOfDay.fromDateTime(selectedStartTime ?? DateTime.now()),
                                          builder: (context, child) {
                                            return Theme(
                                              data: Theme.of(context).copyWith(
                                                colorScheme: const ColorScheme.light(
                                                  primary: Color(0xFF007C91),
                                                ),
                                              ),
                                              child: child!,
                                            );
                                          },
                                        );
                                        if (time != null && mounted) {
                                          setState(() {
                                            selectedStartTime = DateTime(
                                              date.year,
                                              date.month,
                                              date.day,
                                              time.hour,
                                              time.minute,
                                            );
                                          });
                                        }
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
                                      child: Row(
                                        children: [
                                          const Icon(Icons.calendar_today, color: Color(0xFF007C91)),
                                          const SizedBox(width: 12),
                                          Text(
                                            selectedStartTime != null
                                                ? "${selectedStartTime!.toLocal().toString().substring(0, 16)}"
                                                : "Select Date and Time",
                                            style: TextStyle(
                                              fontSize: isMobile ? 14 : 16,
                                              color: selectedStartTime != null ? Colors.black87 : Colors.grey[400],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],

                                SizedBox(height: isMobile ? 20 : 32),

                                // Active Session Display with QR Code
                                if (isSessionActive && qrCodeData != null)
                                  Column(
                                    children: [
                                      // Countdown Timer
                                      Container(
                                        padding: EdgeInsets.all(
                                          isMobile ? 16 : 20,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.orange.shade400,
                                              Colors.deepOrange.shade500,
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.orange.withOpacity(
                                                0.3,
                                              ),
                                              blurRadius: 15,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              "Session Active: $selectedSubjectName",
                                              style: TextStyle(
                                                fontSize: isMobile ? 16 : 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 10),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
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
                                                    fontSize: isMobile
                                                        ? 36
                                                        : 48,
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
                                        padding: EdgeInsets.all(
                                          isMobile ? 16 : 20,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: const Color(
                                              0xFF007C91,
                                            ).withOpacity(0.3),
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.05,
                                              ),
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
                                              foregroundColor: const Color(
                                                0xFF007C91,
                                              ),
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
                                          icon: const Icon(
                                            Icons.stop_circle_rounded,
                                            size: 24,
                                          ),
                                          label: Text(
                                            "End Session",
                                            style: TextStyle(
                                              fontSize: isMobile ? 16 : 18,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.red.shade600,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                // Selected Class Preview
                                if (selectedSubjectId != null)
                                  Container(
                                    margin: EdgeInsets.only(
                                      bottom: isMobile ? 16 : 24,
                                    ),
                                    padding: EdgeInsets.all(isMobile ? 14 : 18),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          const Color(
                                            0xFF007C91,
                                          ).withOpacity(0.1),
                                          const Color(
                                            0xFF0097A7,
                                          ).withOpacity(0.05),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF007C91,
                                        ).withOpacity(0.3),
                                        width: 2,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF007C91),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                Icons.check_circle_rounded,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              "Selected Class",
                                              style: TextStyle(
                                                fontSize: isMobile ? 14 : 16,
                                                fontWeight: FontWeight.bold,
                                                color: const Color(0xFF007C91),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Code row removed
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.book_rounded,
                                                    size: 16,
                                                    color: Colors.grey[600],
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    "Name:",
                                                    style: TextStyle(
                                                      fontSize: isMobile
                                                          ? 12
                                                          : 13,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      selectedSubjectName ??
                                                          'N/A',
                                                      style: TextStyle(
                                                        fontSize: isMobile
                                                            ? 14
                                                            : 15,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Colors.grey[800],
                                                      ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (selectedSemester != null &&
                                                  selectedSemester!.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 8,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.school_rounded,
                                                        size: 16,
                                                        color: Colors.grey[600],
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        "Semester:",
                                                        style: TextStyle(
                                                          fontSize: isMobile
                                                              ? 12
                                                              : 13,
                                                          color:
                                                              Colors.grey[600],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        selectedSemester!,
                                                        style: TextStyle(
                                                          fontSize: isMobile
                                                              ? 14
                                                              : 15,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              Colors.grey[800],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                // Start Session Button
                                if (!isSessionActive)
                                  SizedBox(
                                    width: double.infinity,
                                    height: isMobile ? 48 : 56,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors:
                                              (isCreatingSession ||
                                                  widget.subjects.isEmpty)
                                              ? [
                                                  Colors.grey[400]!,
                                                  Colors.grey[500]!,
                                                ]
                                              : [
                                                  const Color(0xFF007C91),
                                                  const Color(0xFF0097A7),
                                                ],
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow:
                                            (!isCreatingSession &&
                                                widget.subjects.isNotEmpty)
                                            ? [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFF007C91,
                                                  ).withOpacity(0.4),
                                                  blurRadius: 15,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ]
                                            : [],
                                      ),
                                      child: ElevatedButton.icon(
                                        onPressed:
                                            (isCreatingSession ||
                                                widget.subjects.isEmpty)
                                            ? null
                                            : startSession,
                                        icon: isCreatingSession
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
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
                                            borderRadius: BorderRadius.circular(
                                              16,
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
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Widget mobileChild = Scaffold(
      drawer: isMobile
          ? const TeacherDrawer(currentRoute: 'Create Session')
          : null,
      body: mainContent,
    );

    return TeacherWebLayout(
      currentRoute: 'Create Session',
      mobileChild: mobileChild,
      desktopBody: mainContent,
    );
  }
}
