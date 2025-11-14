import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/attendance_service.dart';
import '../../services/class_service.dart';

class TeacherAttendanceHistoryScreen extends StatefulWidget {
  const TeacherAttendanceHistoryScreen({super.key});

  @override
  State<TeacherAttendanceHistoryScreen> createState() =>
      _TeacherAttendanceHistoryScreenState();
}

class _TeacherAttendanceHistoryScreenState
    extends State<TeacherAttendanceHistoryScreen>
    with SingleTickerProviderStateMixin {
  final AttendanceService _attendanceService = AttendanceService();
  final ClassService _classService = ClassService();

  List<Map<String, dynamic>> attendanceRecords = [];
  List<Map<String, dynamic>> classes = [];
  Map<String, dynamic> statistics = {};
  Map<String, Map<String, List<Map<String, dynamic>>>> groupedData = {};

  bool isLoading = true;
  String? errorMessage;

  int? selectedClassId;
  DateTime? selectedDateFrom;
  DateTime? selectedDateTo;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _loadClasses();
    await _loadAttendanceHistory();
  }

  Future<void> _loadClasses() async {
    try {
      final loadedClasses = await _classService.getMyClasses();
      if (mounted) {
        setState(() {
          classes = loadedClasses;
        });
      }
    } catch (e) {
      print('Error loading classes: $e');
    }
  }

  Future<void> _loadAttendanceHistory() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      String? dateFrom;
      String? dateTo;

      if (selectedDateFrom != null) {
        dateFrom = DateFormat('yyyy-MM-dd').format(selectedDateFrom!);
      }
      if (selectedDateTo != null) {
        dateTo = DateFormat('yyyy-MM-dd').format(selectedDateTo!);
      }

      final result = await _attendanceService.getTeacherAttendanceHistory(
        classId: selectedClassId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      if (mounted) {
        setState(() {
          attendanceRecords = result['attendance'] ?? [];
          statistics = result['statistics'] ?? {};
          _groupRecordsByClassAndSession();
          isLoading = false;
        });

        _animationController.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'Failed to load attendance: $e';
          isLoading = false;
        });
      }
    }
  }

  void _groupRecordsByClassAndSession() {
    groupedData.clear();
    
    for (var record in attendanceRecords) {
      final classKey = '${record['class_code']} - ${record['class_name']}';
      
      // ✅ CHANGED: Convert to local time before parsing
      final markedAt = DateTime.parse(record['marked_at']).toLocal();
      
      // Create a unique session key using session_id + datetime
      final sessionId = record['session_id']?.toString() ?? 'unknown';
      
      // Use session_id as primary key, fallback to datetime if no session_id
      String sessionKey;
      if (sessionId != 'unknown' && sessionId.isNotEmpty) {
        sessionKey = sessionId;
      } else {
        // Group by hour if no session_id (rounded to nearest hour)
        sessionKey = 'datetime_${markedAt.year}-${markedAt.month.toString().padLeft(2, '0')}-${markedAt.day.toString().padLeft(2, '0')}_${markedAt.hour.toString().padLeft(2, '0')}';
      }
      
      if (!groupedData.containsKey(classKey)) {
        groupedData[classKey] = {};
      }
      
      if (!groupedData[classKey]!.containsKey(sessionKey)) {
        groupedData[classKey]![sessionKey] = [];
      }
      
      groupedData[classKey]![sessionKey]!.add(record);
    }
    
    // Sort sessions by datetime (newest first) within each class
    for (var classKey in groupedData.keys) {
      final sortedSessions = Map.fromEntries(
        groupedData[classKey]!.entries.toList()
          ..sort((a, b) {
            // ✅ CHANGED: Convert to local time
            final dateA = DateTime.parse(a.value.first['marked_at']).toLocal();
            final dateB = DateTime.parse(b.value.first['marked_at']).toLocal();
            return dateB.compareTo(dateA); // Descending order
          }),
      );
      groupedData[classKey] = sortedSessions;
    }
  }

  Future<void> _updateAttendanceStatus(
    Map<String, dynamic> record,
    String newStatus,
  ) async {
    final recordId = record['id'];

    final result = await _attendanceService.updateAttendanceStatus(
      recordId: recordId,
      status: newStatus,
    );

    if (result['success']) {
      _showSuccessSnackBar('Attendance updated successfully');
      await _loadAttendanceHistory();
    } else {
      _showErrorSnackBar(result['message'] ?? 'Failed to update');
    }
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => _FilterDialog(
        classes: classes,
        selectedClassId: selectedClassId,
        selectedDateFrom: selectedDateFrom,
        selectedDateTo: selectedDateTo,
        onApply: (classId, dateFrom, dateTo) {
          setState(() {
            selectedClassId = classId;
            selectedDateFrom = dateFrom;
            selectedDateTo = dateTo;
          });
          _loadAttendanceHistory();
        },
        onClear: () {
          setState(() {
            selectedClassId = null;
            selectedDateFrom = null;
            selectedDateTo = null;
          });
          _loadAttendanceHistory();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;

    return Scaffold(
      body: Container(
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
              _buildModernAppBar(isMobile),
              if (statistics.isNotEmpty) _buildStatisticsCard(isMobile),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadAttendanceHistory,
                  color: const Color(0xFF007C91),
                  child: _buildBody(isMobile),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernAppBar(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 20,
        vertical: isMobile ? 12 : 16,
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
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attendance History',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 22 : 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${attendanceRecords.length} total records',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: isMobile ? 13 : 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.filter_list_rounded,
                color: Colors.white,
                size: 22,
              ),
              onPressed: _showFilterDialog,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.refresh_rounded,
                color: Colors.white,
                size: 22,
              ),
              onPressed: _loadAttendanceHistory,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard(bool isMobile) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.white.withOpacity(0.95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007C91).withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatCard(
                'Total',
                '${statistics['total']}',
                Icons.people_rounded,
                const Color(0xFF007C91),
              ),
              _buildStatCard(
                'Present',
                '${statistics['present']}',
                Icons.check_circle_rounded,
                Colors.green,
              ),
              _buildStatCard(
                'Absent',
                '${statistics['absent']}',
                Icons.cancel_rounded,
                Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF007C91).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF007C91).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.trending_up_rounded,
                  color: const Color(0xFF007C91),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Attendance Rate: ${statistics['attendance_rate'] ?? 0}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF007C91),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildBody(bool isMobile) {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading attendance data...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Center(child: _buildErrorState(isMobile));
    }

    if (attendanceRecords.isEmpty) {
      return Center(child: _buildEmptyState(isMobile));
    }

    return ListView.builder(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      physics: const BouncingScrollPhysics(),
      itemCount: groupedData.length,
      itemBuilder: (context, index) {
        return FadeTransition(
          opacity: Tween<double>(begin: 0, end: 1).animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Interval(
                (index / groupedData.length) * 0.5,
                1.0,
                curve: Curves.easeOut,
              ),
            ),
          ),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.2),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: _animationController,
                curve: Interval(
                  (index / groupedData.length) * 0.5,
                  1.0,
                  curve: Curves.easeOut,
                ),
              ),
            ),
            child: _buildModernClassCard(
              groupedData.keys.elementAt(index),
              groupedData.values.elementAt(index),
              isMobile,
            ),
          ),
        );
      },
    );
  }

  Widget _buildModernClassCard(
    String className,
    Map<String, List<Map<String, dynamic>>> sessions,
    bool isMobile,
  ) {
    final allRecords = sessions.values.expand((x) => x).toList();
    final presentCount = allRecords.where((r) => r['status'] == 'present').length;
    final attendanceRate = allRecords.isNotEmpty
        ? (presentCount / allRecords.length * 100)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [Colors.white, Colors.white.withOpacity(0.95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007C91).withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.all(isMobile ? 16 : 20),
          childrenPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 16,
            vertical: 8,
          ),
          leading: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF007C91), Color(0xFF0097A7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF007C91).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.auto_stories_rounded,
              color: Colors.white,
              size: isMobile ? 24 : 26,
            ),
          ),
          title: Text(
            className,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 16 : 17,
              color: Colors.grey.shade800,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildInfoChip(
                  Icons.event_note_rounded,
                  '${sessions.length} sessions',
                ),
                _buildInfoChip(
                  Icons.people_rounded,
                  '${allRecords.length} records',
                ),
                _buildInfoChip(
                  Icons.trending_up_rounded,
                  '${attendanceRate.toStringAsFixed(1)}%',
                  color: attendanceRate >= 75 ? Colors.green : Colors.orange,
                ),
              ],
            ),
          ),
          children: sessions.entries.map((sessionEntry) {
            return _buildSessionGroup(
              sessionEntry.key,
              sessionEntry.value,
              isMobile,
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSessionGroup(
    String sessionKey,
    List<Map<String, dynamic>> records,
    bool isMobile,
  ) {
    // ✅ CHANGED: Convert to local time
    final sessionDateTime = records.isNotEmpty
        ? DateTime.parse(records.first['marked_at']).toLocal()
        : DateTime.now();
    
    final presentCount = records.where((r) => r['status'] == 'present').length;
    final attendanceRate = (presentCount / records.length * 100);

    // Determine if this is a session ID or datetime-based key
    final bool hasSessionId = !sessionKey.startsWith('datetime_');
    
    // Format display text based on key type
    String sessionTitle;
    String sessionSubtitle;
    
    if (hasSessionId) {
      // Display session ID (truncated)
      final displayId = sessionKey.length > 12 
          ? '${sessionKey.substring(0, 12)}...' 
          : sessionKey;
      sessionTitle = 'Session: $displayId';
      sessionSubtitle = DateFormat('EEEE, MMM dd, yyyy').format(sessionDateTime);
    } else {
      // Display date and time for datetime-based grouping
      sessionTitle = DateFormat('EEEE, MMM dd, yyyy').format(sessionDateTime);
      sessionSubtitle = 'Session Time: ${DateFormat('hh:mm a').format(sessionDateTime)}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF007C91).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF007C91).withOpacity(0.3),
              ),
            ),
            child: Icon(
              Icons.qr_code_2_rounded,
              color: const Color(0xFF007C91),
              size: 20,
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sessionTitle,
                style: TextStyle(
                  fontSize: isMobile ? 14 : 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    hasSessionId ? Icons.calendar_today_rounded : Icons.access_time_rounded,
                    size: 12,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      sessionSubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('hh:mm a').format(sessionDateTime),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline_rounded, size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      '${records.length} students',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.trending_up_rounded,
                      size: 12,
                      color: attendanceRate >= 75 ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${attendanceRate.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: attendanceRate >= 75 ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          children: records.map((record) {
            return _buildModernAttendanceRow(record, isMobile);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildModernAttendanceRow(Map<String, dynamic> record, bool isMobile) {
    final isPresent = record['status'] == 'present';
    
    // ✅ ADD THIS: Convert UTC to local time
    final markedAt = DateTime.parse(record['marked_at']).toLocal();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPresent
              ? Colors.green.withOpacity(0.3)
              : Colors.red.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isPresent
                    ? [Colors.green, Colors.green.shade700]
                    : [Colors.red, Colors.red.shade700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: (isPresent ? Colors.green : Colors.red).withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              isPresent ? Icons.check_circle : Icons.cancel,
              color: Colors.white,
              size: isMobile ? 20 : 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record['student_name'] ?? 'Unknown',
                  style: TextStyle(
                    fontSize: isMobile ? 14 : 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.badge_rounded, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          'Roll: ${record['roll_no'] ?? 'N/A'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('hh:mm a').format(markedAt), // ✅ CHANGED to 12-hour format
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: isPresent
                      ? Colors.green.withOpacity(0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.check_circle,
                    color: isPresent ? Colors.green : Colors.grey.shade400,
                    size: isMobile ? 22 : 24,
                  ),
                  onPressed: isPresent
                      ? null
                      : () => _updateAttendanceStatus(record, 'present'),
                  tooltip: 'Mark present',
                ),
              ),
              const SizedBox(width: 4),
              Container(
                decoration: BoxDecoration(
                  color: !isPresent
                      ? Colors.red.withOpacity(0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.cancel,
                    color: !isPresent ? Colors.red : Colors.grey.shade400,
                    size: isMobile ? 22 : 24,
                  ),
                  onPressed: !isPresent
                      ? null
                      : () => _updateAttendanceStatus(record, 'absent'),
                  tooltip: 'Mark absent',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? const Color(0xFF007C91)).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (color ?? const Color(0xFF007C91)).withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color ?? const Color(0xFF007C91),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isMobile) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.history_rounded,
              size: 80,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'No Records Found',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            selectedClassId != null || selectedDateFrom != null
                ? 'Try adjusting your filters'
                : 'No attendance records yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isMobile) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Oops!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _loadAttendanceHistory,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF007C91),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 8,
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF007C91),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

/// -------------------- FILTER DIALOG --------------------
class _FilterDialog extends StatefulWidget {
  final List<Map<String, dynamic>> classes;
  final int? selectedClassId;
  final DateTime? selectedDateFrom;
  final DateTime? selectedDateTo;
  final Function(int?, DateTime?, DateTime?) onApply;
  final VoidCallback onClear;

  const _FilterDialog({
    required this.classes,
    required this.selectedClassId,
    required this.selectedDateFrom,
    required this.selectedDateTo,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late int? tempClassId;
  late DateTime? tempDateFrom;
  late DateTime? tempDateTo;

  @override
  void initState() {
    super.initState();
    tempClassId = widget.selectedClassId;
    tempDateFrom = widget.selectedDateFrom;
    tempDateTo = widget.selectedDateTo;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF007C91), Color(0xFF0097A7)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.filter_list_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Filter Attendance',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter by Class',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF007C91).withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonFormField<int>(
                value: tempClassId,
                decoration: InputDecoration(
                  hintText: 'All Classes',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('All Classes')),
                  ...widget.classes.map((c) => DropdownMenuItem<int>(
                        value: c['id'],
                        child: Text('${c['class_code']} - ${c['class_name']}'),
                      )),
                ],
                onChanged: (value) => setState(() => tempClassId = value),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Date Range',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _buildDateTile(
              icon: Icons.calendar_today_rounded,
              label: tempDateFrom == null
                  ? 'From Date (Optional)'
                  : DateFormat('MMM dd, yyyy').format(tempDateFrom!),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: tempDateFrom ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) setState(() => tempDateFrom = date);
              },
              onClear: tempDateFrom != null
                  ? () => setState(() => tempDateFrom = null)
                  : null,
            ),
            const SizedBox(height: 8),
            _buildDateTile(
              icon: Icons.calendar_today_rounded,
              label: tempDateTo == null
                  ? 'To Date (Optional)'
                  : DateFormat('MMM dd, yyyy').format(tempDateTo!),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: tempDateTo ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) setState(() => tempDateTo = date);
              },
              onClear: tempDateTo != null
                  ? () => setState(() => tempDateTo = null)
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onClear();
            Navigator.pop(context);
          },
          child: const Text('Clear All'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onApply(tempClassId, tempDateFrom, tempDateTo);
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF007C91),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: const Text('Apply Filters'),
        ),
      ],
    );
  }

  Widget _buildDateTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF007C91).withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF007C91).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF007C91), size: 20),
        ),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        trailing: onClear != null
            ? IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: onClear,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}