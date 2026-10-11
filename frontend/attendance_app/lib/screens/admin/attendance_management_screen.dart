import 'package:flutter/material.dart';
import '../../services/class_service.dart';
import '../../widgets/admin_web_layout.dart';
import 'attendance_by_class_screen.dart';
import 'widgets/admin_animated_card.dart';
import 'widgets/admin_entrance.dart';
import 'widgets/admin_header_actions.dart';

abstract class _AppColors {
  static const tealDark = Color(0xFF007C91);
  static const teal = Color(0xFF0097A7);
  static const textPrimary = Color(0xFF1F2937);
  static const textMuted = Color(0xFF6B7280);
}

class _SemesterCard {
  final String semesterDisplay;
  final String semesterLabel;
  final int classCount;
  final int sessionCount;
  final int recordCount;
  final Color color;
  final List<Color> gradient;

  const _SemesterCard({
    required this.semesterDisplay,
    required this.semesterLabel,
    required this.classCount,
    required this.sessionCount,
    required this.recordCount,
    required this.color,
    required this.gradient,
  });
}

/// Admin: Attendance Management.
///
/// Hierarchy: semester card -> every attendance session of that semester,
/// grouped by class (see [AttendanceByClassScreen]).
class AttendanceManagementScreen extends StatefulWidget {
  const AttendanceManagementScreen({super.key});

  @override
  State<AttendanceManagementScreen> createState() =>
      _AttendanceManagementScreenState();
}

class _AttendanceManagementScreenState
    extends State<AttendanceManagementScreen> {
  final ClassService _classService = ClassService();
  bool _isLoading = false;
  String? _errorMessage;
  List<_SemesterCard> _semesters = [];

  @override
  void initState() {
    super.initState();
    _loadSemesters();
  }

  Future<void> _loadSemesters() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final summary = await _classService.getAdminAttendanceSemesters();

      if (!mounted) return;

      const colorPalette = [
        Color(0xFF2F80ED),
        Color(0xFF0FA797),
        Color(0xFF6C5CE7),
        Color(0xFFE4B40B),
        Color(0xFF66BB6A),
        Color(0xFFFF7043),
        Color(0xFFA83FD9),
      ];

      const gradientPalette = [
        [Color(0xFF5B9DF9), Colors.white],
        [Color(0xFF14B8A6), Colors.white],
        [Color(0xFF9C8BFF), Colors.white],
        [Color(0xFFE4BD3C), Colors.white],
        [Color(0xFF81C784), Colors.white],
        [Color(0xFFFFA270), Colors.white],
        [Color(0xFFBA6CF5), Colors.white],
      ];

      setState(() {
        _semesters = summary.asMap().entries.map((entry) {
          final index = entry.key;
          final data = entry.value;
          final semesterStr = data['semester']?.toString() ?? '';
          return _SemesterCard(
            semesterDisplay: _semesterDisplay(semesterStr),
            semesterLabel: semesterStr,
            classCount:
                int.tryParse(data['class_count']?.toString() ?? '') ?? 0,
            sessionCount:
                int.tryParse(data['session_count']?.toString() ?? '') ?? 0,
            recordCount:
                int.tryParse(data['record_count']?.toString() ?? '') ?? 0,
            color: colorPalette[index % colorPalette.length],
            gradient: gradientPalette[index % gradientPalette.length],
          );
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading attendance semesters: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Could not load attendance summaries. Please try again.';
        });
      }
    }
  }

  String _semesterDisplay(String raw) {
    final trimmed = raw.trim();
    return int.tryParse(trimmed) != null ? 'Semester $trimmed' : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;

    return AdminWebLayout(
      currentRoute: 'Attendance Management',
      mobileChild: _buildMobileBody(isMobile),
      desktopBody: _buildDesktopBody(),
    );
  }

  Widget _buildMobileBody(bool isMobile) {
    final crossAxisCount = isMobile ? 1 : 2;

    return Stack(
      children: [
        SafeArea(
          child: AdminEntrance(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 16 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderSection(isMobile),
                    const SizedBox(height: 16),
                    _errorMessage != null
                        ? _buildErrorState()
                        : _semesters.isEmpty
                            ? _buildEmptyState()
                            : _buildSemesterGrid(crossAxisCount, isMobile),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_isLoading) _buildLoadingOverlay(),
      ],
    );
  }

  Widget _buildDesktopBody() {
    return Stack(
      children: [
        AdminEntrance(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 20, 40, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDesktopHeader(),
                  const SizedBox(height: 24),
                  _errorMessage != null
                      ? _buildErrorState()
                      : _semesters.isEmpty
                          ? _buildEmptyState()
                          : _buildSemesterGrid(3, false),
                ],
              ),
            ),
          ),
        ),
        if (_isLoading) _buildLoadingOverlay(),
      ],
    );
  }

  Widget _buildLoadingOverlay() => Container(
        color: Colors.black26,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading...'),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildDesktopHeader() {
    return Row(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [_AppColors.tealDark, _AppColors.teal],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: const Icon(Icons.analytics_rounded,
              color: Colors.white, size: 38),
        ),
        const SizedBox(width: 20),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Attendance Management',
                style: TextStyle(
                  color: _AppColors.tealDark,
                  fontSize: 38,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 4),
              Text(
                'Browse every attendance session, grouped by date',
                style: TextStyle(
                  fontSize: 16,
                  color: _AppColors.textMuted,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
        AdminHeaderActions(onRefresh: _loadSemesters, showLogout: false),
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: _AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
      ],
    );
  }

  Widget _buildHeaderSection(bool isMobile) {
    return Row(
      children: [
        if (isMobile)
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: _AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        const Icon(Icons.analytics_rounded, color: _AppColors.tealDark, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Attendance Management',
            style: TextStyle(
              fontSize: isMobile ? 22 : 28,
              fontWeight: FontWeight.w700,
              color: _AppColors.textPrimary,
            ),
          ),
        ),
        AdminHeaderActions(onRefresh: _loadSemesters, showLogout: false),
      ],
    );
  }

  Widget _buildSemesterGrid(int crossAxisCount, bool isMobile) {
    final isCompact = isMobile || crossAxisCount == 2;

    Widget card(_SemesterCard semester) {
      return AdminAnimatedCard(
        title: semester.semesterDisplay,
        subtitle:
            '${semester.sessionCount} session${semester.sessionCount == 1 ? '' : 's'}'
            ' \u2022 ${semester.recordCount} record${semester.recordCount == 1 ? '' : 's'}',
        icon: Icons.event_available_rounded,
        color: semester.color,
        gradient: semester.gradient,
        compact: isCompact,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AttendanceByClassScreen(
                semesterLabel: semester.semesterLabel,
                semesterDisplay: semester.semesterDisplay,
              ),
            ),
          );
        },
        trailing: Icon(
          isCompact
              ? Icons.chevron_right_rounded
              : Icons.arrow_forward_ios_rounded,
          color: semester.color,
          size: isCompact ? 24 : 20,
        ),
      );
    }

    // Phone: column of full-width horizontal cards at natural height.
    if (crossAxisCount == 1) {
      return Column(
        children: [
          for (final semester in _semesters)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: card(semester),
            ),
        ],
      );
    }

    return GridView.builder(
      itemCount: _semesters.length,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: isCompact ? 14 : 42,
        crossAxisSpacing: isCompact ? 18 : 55,
        childAspectRatio: isCompact ? 3.0 : 1.6,
      ),
      itemBuilder: (context, idx) => card(_semesters[idx]),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadSemesters,
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
            const Text(
              'No attendance sessions yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sessions appear here once teachers take attendance.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
