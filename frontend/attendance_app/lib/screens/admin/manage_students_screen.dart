import 'package:flutter/material.dart';
import '../../services/class_service.dart';
import '../../utils/semester_utils.dart';
import '../../widgets/admin_web_layout.dart';
import 'admin_navigation.dart';
import 'semester_classes_screen.dart';
import 'widgets/add_student_dialog.dart';
import 'widgets/admin_animated_card.dart';
import 'widgets/admin_entrance.dart';
import 'widgets/admin_export_button.dart';
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
  final int studentCount;
  final Color color;
  final List<Color> gradient;

  const _SemesterCard({
    required this.semesterDisplay,
    required this.semesterLabel,
    required this.studentCount,
    required this.color,
    required this.gradient,
  });
}

class ManageStudentsScreen extends StatefulWidget {
  const ManageStudentsScreen({super.key});

  @override
  State<ManageStudentsScreen> createState() => _ManageStudentsScreenState();
}

class _ManageStudentsScreenState extends State<ManageStudentsScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  /// Non-blocking warning when the secondary fetch (unassigned students)
  /// fails but the semester summary rendered fine.
  String? _warningMessage;
  final ClassService _classService = ClassService();
  List<_SemesterCard> _semesters = [];

  /// Every student who is not in any class: those with a semester but no
  /// class, plus those no flow can reach (blank/missing profile semester).
  int _unassignedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSemesters();
  }

  Future<void> _loadSemesters() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _warningMessage = null;
    });

    // Primary fetch: the semester summary. A failure here is fatal.
    final List<Map<String, dynamic>> summary;
    try {
      summary =
          List<Map<String, dynamic>>.from(await _classService.getAdminClassesSummary());
    } catch (e) {
      debugPrint('Error loading class summaries: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load class summaries. Please try again.';
        });
      }
      return;
    }

    // Secondary fetch: unassigned-student counts (the amber banner). A
    // failure here degrades to semester cards without the banner.
    int unassignedTotal = 0;
    try {
      final unassignedData =
          await _classService.getAdminUnassignedStudents();
      final unreachable =
          (unassignedData['unreachable'] as List?)?.length ?? 0;
      final unenrolled = (unassignedData['students'] as List?)?.length ?? 0;
      unassignedTotal = unreachable + unenrolled;
    } catch (e) {
      debugPrint('Error loading unassigned students: $e');
      if (mounted) {
        _warningMessage =
            'Could not load the unassigned-students count. Students not yet '
            'in a class may not be shown here.';
      }
    }

    if (!mounted) return;

    const colorPalette = [
      Color(0xFFD34C53),
      Color(0xFFE4B40B),
      Color(0xFFA83FD9),
      Color(0xFF4FBDD6),
      Color(0xFF66BB6A),
      Color(0xFF46CDD5),
    ];

    const gradientPalette = [
      [Color(0xFFF2658B), Colors.white],
      [Color(0xFFE4BD3C), Colors.white],
      [Color(0xFFBA6CF5), Colors.white],
      [Color(0xFF3AB0E6), Colors.white],
      [Color(0xFF81C784), Colors.white],
      [Color(0xFF5FD4D4), Colors.white],
    ];

    // Numeric-aware sort so "Semester 2" precedes "Semester 10"; colors are
    // assigned after sorting so each semester keeps a stable color.
    final sorted = List<Map<String, dynamic>>.from(summary)
      ..sort((a, b) => compareSemesters(
            a['semester']?.toString() ?? '',
            b['semester']?.toString() ?? '',
          ));

    setState(() {
      _semesters = sorted.asMap().entries.map((entry) {
        final index = entry.key;
        final data = entry.value;
        final semesterStr = data['semester']?.toString() ?? '';
        return _SemesterCard(
          semesterDisplay: _semesterDisplay(semesterStr),
          semesterLabel: semesterStr,
          studentCount:
              int.tryParse(data['total_students']?.toString() ?? '') ??
                  int.tryParse(data['student_count']?.toString() ?? '') ??
                  0,
          color: colorPalette[index % colorPalette.length],
          gradient: gradientPalette[index % gradientPalette.length],
        );
      }).toList();
      _unassignedCount = unassignedTotal;
      _isLoading = false;
    });
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
      currentRoute: 'Manage Students',
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
                    const SizedBox(height: 24),
                    _errorMessage != null
                        ? _buildErrorState()
                        : _buildStudentsContent(crossAxisCount, isMobile),
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
                      : _buildStudentsContent(3, false),
                ],
              ),
            ),
          ),
        ),
        if (_isLoading) _buildLoadingOverlay(),
      ],
    );
  }

  Widget _buildStudentsContent(int crossAxisCount, bool isMobile) {
    final unassigned = _unassignedCount;
    return Column(
      children: [
        if (_warningMessage != null) ...[
          _buildWarningBanner(),
          const SizedBox(height: 16),
        ],
        if (unassigned > 0) ...[
          _buildUnassignedCard(unassigned),
          const SizedBox(height: 24),
        ],
        if (_semesters.isEmpty)
          _buildEmptyState()
        else
          _buildSemesterGrid(crossAxisCount, isMobile),
      ],
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _warningMessage!,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Color(0xFF92400E)),
            onPressed: () => setState(() => _warningMessage = null),
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildUnassignedCard(int count) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Card(
          color: const Color(0xFFFFFBEB),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFFCD34D)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _openUnassigned,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_search_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Unassigned',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: _AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count student${count == 1 ? '' : 's'} not in any class \u2014 tap to review',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Color(0xFFF59E0B),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUnassigned() async {
    final count = _unassignedCount;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SemesterClassesScreen(
          semesterLabel: 'unassigned',
          semesterDisplay: 'Unassigned',
          totalEnrollments: count,
          showUnassignedOnly: true,
        ),
      ),
    );
    _loadSemesters();
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
            // BUG FIX: was BorderRadius.circular(63.5) on a 76x76 box, which
            // doesn't correspond to any meaningful dimension. Using
            // BoxShape.circle is correct regardless of the box size.
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [_AppColors.tealDark, _AppColors.teal],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: const Icon(Icons.people_alt_rounded, color: Colors.white, size: 38),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Manage Students',
                style: TextStyle(
                  color: _AppColors.tealDark,
                  fontSize: 38,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              const Text(
                'View and manage students by semester',
                style: TextStyle(
                  fontSize: 16,
                  color: _AppColors.textMuted,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: _showAddStudentDialog,
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
          label: const Text('Add Student'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _AppColors.tealDark,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(width: 16),
        const AdminExportButton(dataset: 'students'),
        AdminHeaderActions(onRefresh: _loadSemesters, showLogout: false),
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _AppColors.textPrimary),
          onPressed: () => backToAdminDashboard(context),
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
            icon: const Icon(Icons.arrow_back_rounded, color: _AppColors.textPrimary),
            onPressed: () => backToAdminDashboard(context),
          ),
        const Icon(Icons.people_alt_rounded, color: _AppColors.tealDark, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Manage Students',
            style: TextStyle(
              fontSize: isMobile ? 22 : 28,
              fontWeight: FontWeight.w700,
              color: _AppColors.textPrimary,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.person_add_alt_1_rounded, color: _AppColors.tealDark, size: 26),
          onPressed: _showAddStudentDialog,
          tooltip: 'Add Student',
        ),
        const AdminExportButton(dataset: 'students'),
        AdminHeaderActions(onRefresh: _loadSemesters, showLogout: false),
      ],
    );
  }

  Widget _buildSemesterGrid(int crossAxisCount, bool isMobile) {
    final isCompact = isMobile || crossAxisCount == 2;

    Widget card(_SemesterCard semester) {
      return AdminAnimatedCard(
        title: semester.semesterDisplay,
        subtitle: '${semester.studentCount} Students',
        icon: Icons.school_rounded,
        color: semester.color,
        gradient: semester.gradient,
        compact: isCompact,
        onTap: () => _openSemester(semester),
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
        // Compact cards get a fixed height (AdminAnimatedCard needs ~103px);
        // a width-derived ratio overflows at 600-675px viewport widths.
        childAspectRatio: 1.6,
        mainAxisExtent: isCompact ? 116 : null,
      ),
      itemBuilder: (context, idx) => card(_semesters[idx]),
    );
  }

  Future<void> _openSemester(_SemesterCard semester) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SemesterClassesScreen(
          semesterLabel: semester.semesterLabel,
          semesterDisplay: semester.semesterDisplay,
          totalEnrollments: semester.studentCount,
        ),
      ),
    );
    _loadSemesters();
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 72, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: _AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadSemesters,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _AppColors.tealDark,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.school_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          const Text(
            'No classes found',
            style: TextStyle(
              fontSize: 18,
              color: _AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create classes to see semester summaries',
            style: TextStyle(
              fontSize: 14,
              color: _AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddStudentDialog() {
    AddStudentDialog.show(
      context: context,
      classService: _classService,
      onStudentCreated: _loadSemesters,
    );
  }
}