import 'package:flutter/material.dart';
import '../../services/class_service.dart';
import 'widgets/admin_header_actions.dart';

abstract class _AppColors {
  static const tealDark = Color(0xFF007C91);
  static const teal = Color(0xFF0097A7);
  static const textPrimary = Color(0xFF1F2937);
  static const textMuted = Color(0xFF6B7280);
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Admin: Attendance Management drill-down.
///
/// Lists every attendance session of a semester, grouped by class. Each class
/// expands into its sessions (date, time, teacher, present count), and each
/// session expands into the individual attendance records.
class AttendanceByClassScreen extends StatefulWidget {
  final String semesterLabel;
  final String semesterDisplay;

  const AttendanceByClassScreen({
    super.key,
    required this.semesterLabel,
    required this.semesterDisplay,
  });

  @override
  State<AttendanceByClassScreen> createState() =>
      _AttendanceByClassScreenState();
}

class _AttendanceByClassScreenState extends State<AttendanceByClassScreen> {
  final ClassService _classService = ClassService();
  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _classes = [];
  int _totalSessions = 0;
  int _totalRecords = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAttendance() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data =
          await _classService.getAdminAttendanceBySemester(widget.semesterLabel);

      final classes = List<Map<String, dynamic>>.from(data['classes'] ?? []);
      for (final cls in classes) {
        final sessions = List<Map<String, dynamic>>.from(cls['sessions'] ?? []);
        for (final session in sessions) {
          session['records'] =
              List<Map<String, dynamic>>.from(session['records'] ?? []);
        }
        cls['sessions'] = sessions;
      }

      if (mounted) {
        setState(() {
          _classes = classes;
          _totalSessions =
              int.tryParse(data['total_sessions']?.toString() ?? '') ?? 0;
          _totalRecords =
              int.tryParse(data['total_records']?.toString() ?? '') ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading attendance: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load attendance. Please try again.';
        });
      }
    }
  }

  /// Classes filtered by student name/email or class code/name/teacher. When
  /// searching, only classes/sessions with a match remain, fully expanded.
  List<Map<String, dynamic>> get _filteredClasses {
    if (!_isSearching) return _classes;
    final q = _searchQuery.trim().toLowerCase();
    final result = <Map<String, dynamic>>[];
    for (final cls in _classes) {
      final classHaystack =
          '${cls['class_code'] ?? ''} ${cls['class_name'] ?? ''} ${cls['teacher'] ?? ''}'
              .toLowerCase();
      final sessions =
          List<Map<String, dynamic>>.from(cls['sessions'] ?? []);
      final matchedSessions = classHaystack.contains(q)
          ? sessions
          : sessions.where((session) {
              final sessionHaystack =
                  '${session['teacher'] ?? ''}'.toLowerCase();
              if (sessionHaystack.contains(q)) return true;
              final records =
                  List<Map<String, dynamic>>.from(session['records'] ?? []);
              return records.any((r) =>
                  '${r['username'] ?? ''}'.toLowerCase().contains(q) ||
                  '${r['email'] ?? ''}'.toLowerCase().contains(q));
            }).toList();
      if (matchedSessions.isNotEmpty) {
        result.add({...cls, 'sessions': matchedSessions});
      }
    }
    return result;
  }

  DateTime? _parse(dynamic iso) => DateTime.tryParse(iso?.toString() ?? '');

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '--';
    return '${dt.day.toString().padLeft(2, '0')} ${_months[dt.month - 1]} ${dt.year}';
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _initialOf(dynamic username) {
    final name = username?.toString() ?? '';
    return name.isEmpty ? 'S' : name.substring(0, 1).toUpperCase();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'present':
        return const Color(0xFF22C55E);
      case 'absent':
        return const Color(0xFFEF4444);
      case 'pending_review':
        return const Color(0xFFF59E0B);
      default:
        return _AppColors.textMuted;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'present':
        return Icons.check_circle_rounded;
      case 'absent':
        return Icons.cancel_rounded;
      case 'pending_review':
        return Icons.hourglass_top_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'present':
        return 'Present';
      case 'absent':
        return 'Absent';
      case 'pending_review':
        return 'Review';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_AppColors.tealDark, _AppColors.teal],
                ),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.event_available_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.semesterDisplay,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$_totalSessions sessions \u2022 $_totalRecords records',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          AdminHeaderActions(onRefresh: _loadAttendance, showLogout: false),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_AppColors.teal),
              ),
            )
          : _errorMessage != null
              ? _buildErrorState()
              : Column(
                  children: [
                    _buildSearchBar(),
                    Expanded(
                      child: _filteredClasses.isEmpty
                          ? _buildEmptyState()
                          : _buildClassList(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search by student, class or teacher',
          prefixIcon: const Icon(Icons.search_rounded, color: _AppColors.textMuted),
          suffixIcon: _isSearching
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _AppColors.teal),
          ),
        ),
      ),
    );
  }

  Widget _buildClassList() {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      itemCount: _filteredClasses.length,
      itemBuilder: (context, idx) => _buildClassTile(_filteredClasses[idx]),
    );
  }

  Widget _buildClassTile(Map<String, dynamic> cls) {
    final sessions = List<Map<String, dynamic>>.from(cls['sessions'] ?? []);
    final sessionCount =
        int.tryParse(cls['session_count']?.toString() ?? '') ?? sessions.length;
    final recordCount =
        int.tryParse(cls['record_count']?.toString() ?? '') ?? 0;
    final presentCount =
        int.tryParse(cls['present_count']?.toString() ?? '') ?? 0;
    final hasLive = sessions.any((s) => (s['status'] ?? '') == 'active');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('class-${cls['class_id']}-${_isSearching}'),
          initiallyExpanded: _isSearching,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _AppColors.teal.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.class_rounded,
                color: _AppColors.teal, size: 20),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  '${cls['class_code'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasLive) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Live',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            '${cls['class_name'] ?? ''} \u2022 ${cls['teacher'] ?? ''}',
            style: const TextStyle(fontSize: 12, color: _AppColors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$presentCount/$recordCount',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF16A34A),
              ),
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$sessionCount session${sessionCount == 1 ? '' : 's'} \u2022 $recordCount record${recordCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 11, color: _AppColors.textMuted),
                ),
              ),
            ),
            ...sessions.map(_buildSessionTile),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionTile(Map<String, dynamic> session) {
    final present =
        int.tryParse(session['present_count']?.toString() ?? '') ?? 0;
    final total =
        int.tryParse(session['record_count']?.toString() ?? '') ?? 0;
    final records = List<Map<String, dynamic>>.from(session['records'] ?? []);
    final status = (session['status'] ?? '').toString();
    final start = _parse(session['start_time']);
    final end = _parse(session['end_time']);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('session-${session['session_uuid']}-${_isSearching}'),
          initiallyExpanded: _isSearching,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${_fmtDate(start)} \u2022 ${_fmtTime(start)}\u2013${_fmtTime(end)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (status == 'active') ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Live',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF16A34A),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$present/$total',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${session['teacher'] ?? ''} \u2022 ${session['duration_minutes'] ?? '?'} min \u2022 ${(session['class_type'] ?? 'qr').toString().toUpperCase()}',
              style: const TextStyle(fontSize: 11, color: _AppColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          children: records.isEmpty
              ? const [
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'No attendance records for this session',
                      style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: _AppColors.textMuted),
                    ),
                  ),
                ]
              : records.map(_buildRecordRow).toList(),
        ),
      ),
    );
  }

  Widget _buildRecordRow(Map<String, dynamic> record) {
    final status = (record['status'] ?? 'present').toString();
    final color = _statusColor(status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withOpacity(0.15),
            child: Text(
              _initialOf(record['username']),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record['username'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${record['email'] ?? ''}',
                  style:
                      const TextStyle(fontSize: 12, color: _AppColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_statusIcon(status), size: 12, color: color),
                    const SizedBox(width: 4),
                    Text(
                      _statusLabel(status),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'at ${_fmtTime(_parse(record['marked_at']))}',
                style:
                    const TextStyle(fontSize: 11, color: _AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadAttendance,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy_rounded,
                color: _AppColors.textMuted, size: 48),
            const SizedBox(height: 12),
            Text(
              _isSearching
                  ? 'No matches for your search'
                  : 'No attendance sessions yet',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isSearching
                  ? 'Try a different student, class or teacher.'
                  : 'Sessions appear here once teachers take attendance.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
