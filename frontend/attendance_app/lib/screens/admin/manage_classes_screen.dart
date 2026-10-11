import 'package:flutter/material.dart';
import '../../services/class_service.dart';
import '../../utils/semester_utils.dart';
import '../../widgets/admin_web_layout.dart';
import 'admin_class_detail_screen.dart';
import 'admin_navigation.dart';
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
  final int classCount;
  final int studentCount;
  final Color color;
  final List<Color> gradient;

  const _SemesterCard({
    required this.semesterDisplay,
    required this.semesterLabel,
    required this.classCount,
    required this.studentCount,
    required this.color,
    required this.gradient,
  });
}

/// Admin: Manage Classes.
///
/// Hierarchy: Semester card -> list of classes for that semester (teacher
/// shown beside each class) -> on tapping a class, list its students.
class ManageClassesScreen extends StatefulWidget {
  const ManageClassesScreen({super.key});

  @override
  State<ManageClassesScreen> createState() => _ManageClassesScreenState();
}

class _ManageClassesScreenState extends State<ManageClassesScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  /// Non-blocking warning when the secondary fetch (teachers) fails but the
  /// semester summary rendered fine.
  String? _warningMessage;
  final ClassService _classService = ClassService();
  List<_SemesterCard> _semesters = [];
  List<Map<String, dynamic>> _teachers = [];
  String? _selectedTeacherUsername;
  TextEditingController? _teacherFieldController;
  FocusNode? _teacherFocusNode;
  bool _teacherFieldSeeded = false;

  @override
  void initState() {
    super.initState();
    _loadSemesters();
  }

  @override
  void dispose() {
    _teacherFieldController?.dispose();
    _teacherFocusNode?.dispose();
    super.dispose();
  }

  void _syncTeacherFieldText(String text) {
    final controller = _teacherFieldController;
    if (controller == null) return;
    controller.text = text;
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
  }

  Future<void> _loadSemesters() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _warningMessage = null;
    });

    // Primary fetch: the semester summary. A failure here is fatal.
    final List<Map<String, dynamic>> summary;
    try {
      final raw = await _classService.getAdminClassesSummary();
      summary = List<Map<String, dynamic>>.from(raw);
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

    // Secondary fetch: the teacher list (used by the filter). A failure here
    // degrades to semester cards without the filter instead of wiping the
    // screen.
    List<Map<String, dynamic>> teacherList = [];
    try {
      final teachersData = await _classService.getTeachers();
      teacherList =
          List<Map<String, dynamic>>.from(teachersData['teachers'] ?? []);
    } catch (e) {
      debugPrint('Error loading teachers: $e');
      if (mounted) {
        _warningMessage =
            'Could not load the teacher list. Teacher filtering is unavailable.';
      }
    }

    if (!mounted) return;

    const colorPalette = [
      Color(0xFF6C5CE7),
      Color(0xFFE4B40B),
      Color(0xFFA83FD9),
      Color(0xFF4FBDD6),
      Color(0xFF66BB6A),
      Color(0xFFFF7043),
    ];

    const gradientPalette = [
      [Color(0xFF9C8BFF), Colors.white],
      [Color(0xFFE4BD3C), Colors.white],
      [Color(0xFFBA6CF5), Colors.white],
      [Color(0xFF3AB0E6), Colors.white],
      [Color(0xFF81C784), Colors.white],
      [Color(0xFFFFA270), Colors.white],
    ];

    // Numeric-aware sort so "Semester 2" precedes "Semester 10" (the server
    // returns lexicographic order). Colors are assigned after sorting so each
    // semester keeps a stable color.
    final visible = summary.where((data) {
      final classCount =
          int.tryParse(data['class_count']?.toString() ?? '') ?? 0;
      return classCount > 0;
    }).toList()
      ..sort((a, b) => compareSemesters(
            a['semester']?.toString() ?? '',
            b['semester']?.toString() ?? '',
          ));

    setState(() {
      _semesters = visible.asMap().entries.map((entry) {
        final index = entry.key;
        final data = entry.value;
        final semesterStr = data['semester']?.toString() ?? '';
        return _SemesterCard(
          semesterDisplay: _semesterDisplay(semesterStr),
          semesterLabel: semesterStr,
          classCount:
              int.tryParse(data['class_count']?.toString() ?? '') ?? 0,
          studentCount:
              int.tryParse(data['student_count']?.toString() ?? '') ?? 0,
          color: colorPalette[index % colorPalette.length],
          gradient: gradientPalette[index % gradientPalette.length],
        );
      }).toList();
      _teachers = teacherList;
      _isLoading = false;
    });
  }

  String _semesterDisplay(String raw) {
    final trimmed = raw.trim();
    return int.tryParse(trimmed) != null ? 'Semester $trimmed' : trimmed;
  }

  Map<String, dynamic>? get _selectedTeacher {
    final username = _selectedTeacherUsername;
    if (username == null) return null;
    for (final teacher in _teachers) {
      if (teacher['username'] == username) return teacher;
    }
    return null;
  }

  List<Map<String, dynamic>> get _selectedTeacherClasses {
    final teacher = _selectedTeacher;
    if (teacher == null) return const [];
    return List<Map<String, dynamic>>.from(teacher['classes'] ?? []);
  }

  int _compareSemester(String a, String b) => compareSemesters(a, b);

  Future<void> _openClassDetail(Map<String, dynamic> cls) async {
    final classId = int.tryParse(cls['id']?.toString() ?? '');
    if (classId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminClassDetailScreen(
          classId: classId,
          classCode: cls['class_code'] ?? '',
          className: cls['class_name'] ?? '',
        ),
      ),
    );
    // Class edits/removals happen on the detail screen; refresh counts on
    // return so this list never shows stale student totals.
    if (mounted) _loadSemesters();
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;

    return AdminWebLayout(
      currentRoute: 'Manage Classes',
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
                    if (_warningMessage != null) ...[
                      _buildWarningBanner(),
                      const SizedBox(height: 12),
                    ],
                    if (_teachers.isNotEmpty && !_isLoading) ...[
                      _buildTeacherFilter(isMobile),
                      const SizedBox(height: 20),
                    ],
                    _errorMessage != null
                        ? _buildErrorState()
                        : _selectedTeacher != null
                            ? _buildTeacherClassesView()
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
                  const SizedBox(height: 20),
                  if (_warningMessage != null) ...[
                    _buildWarningBanner(),
                    const SizedBox(height: 12),
                  ],
                  if (_teachers.isNotEmpty && !_isLoading) ...[
                    _buildTeacherFilter(false),
                    const SizedBox(height: 24),
                  ],
                  _errorMessage != null
                      ? _buildErrorState()
                      : _selectedTeacher != null
                          ? _buildTeacherClassesView()
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
          child: const Icon(Icons.class_rounded, color: Colors.white, size: 38),
        ),
        const SizedBox(width: 20),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manage Classes',
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
                'View classes by semester and who teaches them',
                style: TextStyle(
                  fontSize: 16,
                  color: _AppColors.textMuted,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
        const AdminExportButton(dataset: 'classes'),
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
        const Icon(Icons.class_rounded, color: _AppColors.tealDark, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Manage Classes',
            style: TextStyle(
              fontSize: isMobile ? 22 : 28,
              fontWeight: FontWeight.w700,
              color: _AppColors.textPrimary,
            ),
          ),
        ),
        const AdminExportButton(dataset: 'classes'),
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
            '${semester.classCount} class${semester.classCount == 1 ? '' : 'es'} '
            '\u2022 ${semester.studentCount} students',
        icon: Icons.class_rounded,
        color: semester.color,
        gradient: semester.gradient,
        compact: isCompact,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ManageSemesterClassesScreen(
                semesterLabel: semester.semesterLabel,
                semesterDisplay: semester.semesterDisplay,
              ),
            ),
          );
          // Classes may have been edited on the drill-down screen; refresh
          // the semester counts on return.
          if (mounted) _loadSemesters();
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
        // Compact cards get a fixed height (AdminAnimatedCard needs ~103px);
        // a width-derived ratio overflows at 600-675px viewport widths.
        childAspectRatio: 1.6,
        mainAxisExtent: isCompact ? 116 : null,
      ),
      itemBuilder: (context, idx) => card(_semesters[idx]),
    );
  }

  Widget _buildTeacherFilter(bool isMobile) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: isMobile ? double.infinity : 360,
        child: Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase();
            final all = _teachers
                .map((t) => t['username']?.toString() ?? '')
                .where((u) => u.isNotEmpty)
                .toSet()
                .toList();
            if (query.isEmpty) return all;
            return all.where((u) => u.toLowerCase().contains(query)).toList();
          },
          onSelected: (String selection) {
            setState(() {
              _selectedTeacherUsername = selection;
              _teacherFieldSeeded = true;
              _syncTeacherFieldText(selection.isEmpty ? 'All teachers' : selection);
            });
            _teacherFocusNode?.unfocus();
          },
          optionsViewBuilder: (context, onSelected, options) {
            final fieldWidth =
                isMobile ? MediaQuery.of(context).size.width - 32 : 360.0;
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 280,
                    maxWidth: fieldWidth,
                  ),
                  child: options.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No teachers match your search',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (ctx, index) {
                            final name = options.elementAt(index);
                            return _buildTeacherOption(
                              name,
                              isSelected: _selectedTeacherUsername == name,
                              onTap: () => onSelected(name),
                            );
                          },
                        ),
                ),
              ),
            );
          },
          fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
            _teacherFieldController ??= textEditingController;
            _teacherFocusNode ??= focusNode;
            final isAll = _selectedTeacherUsername == null;
            final isEmptyField = textEditingController.text.isEmpty;

            if (!_teacherFieldSeeded && textEditingController.text.isEmpty) {
              _teacherFieldSeeded = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _syncTeacherFieldText(_selectedTeacherUsername ?? 'All teachers');
              });
            }

            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              onChanged: (v) {
                // Free-typing invalidates a previous pick. Without this the
                // list kept filtering by the old teacher while the field
                // displayed something else.
                final selected = _selectedTeacherUsername;
                if (selected != null && v.trim() != selected) {
                  setState(() => _selectedTeacherUsername = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'Filter by teacher',
                hintText: 'Search teacher name',
                prefixIcon: const Icon(
                  Icons.person_search_rounded,
                  color: _AppColors.tealDark,
                  size: 22,
                ),
                suffixIcon: (isAll && isEmptyField)
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          textEditingController.clear();
                          setState(() {
                            _selectedTeacherUsername = null;
                            _teacherFieldSeeded = false;
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            _syncTeacherFieldText('All teachers');
                          });
                          focusNode.unfocus();
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF007C91)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF007C91),
                    width: 1.5,
                  ),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTeacherOption(
    String label, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: _AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: _AppColors.tealDark,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherClassesView() {
    final teacher = _selectedTeacher;
    final classes = _selectedTeacherClasses;

    if (classes.isEmpty) {
      return _buildEmptyTeacherState(
        teacher?['username']?.toString() ?? 'this teacher',
      );
    }

    final bySemester = <String, List<Map<String, dynamic>>>{};
    for (final cls in classes) {
      final sem = cls['semester']?.toString() ?? '';
      bySemester.putIfAbsent(sem, () => []).add(cls);
    }
    final semesterKeys = bySemester.keys.toList()..sort(_compareSemester);
    final totalStudents = classes.fold<int>(0, (sum, c) =>
        sum + (int.tryParse(c['student_count']?.toString() ?? '') ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16, left: 4),
          child: Text(
            '${classes.length} class${classes.length == 1 ? '' : 'es'} across '
            '${semesterKeys.length} semester${semesterKeys.length == 1 ? '' : 's'} '
            '\u2022 $totalStudents students',
            style: const TextStyle(
              fontSize: 14,
              color: _AppColors.textMuted,
              fontFamily: 'Inter',
            ),
          ),
        ),
        for (final sem in semesterKeys) ...[
          _buildSemesterSectionHeader(sem),
          for (final cls in bySemester[sem]!) _buildTeacherClassCard(cls),
        ],
      ],
    );
  }

  Widget _buildSemesterSectionHeader(String semester) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Row(
        children: [
          const Icon(Icons.school_rounded, size: 18, color: _AppColors.tealDark),
          const SizedBox(width: 8),
          Text(
            _semesterDisplay(semester),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _AppColors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherClassCard(Map<String, dynamic> cls) {
    final studentCount =
        int.tryParse(cls['student_count']?.toString() ?? '') ?? 0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openClassDetail(cls),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF7FA),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: Color(0xFF007C91),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cls['class_name'] ?? 'Unnamed class',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: _AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cls['class_code'] ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF007C91),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7FA),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$studentCount student${studentCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF007C91),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 22, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyTeacherState(String teacherName) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No classes for $teacherName',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              color: _AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
          Icon(Icons.class_outlined, size: 80, color: Colors.grey.shade300),
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
}

/// Lists every class in a semester, with the teacher who takes each class.
/// Tapping a class opens its student list.
class ManageSemesterClassesScreen extends StatefulWidget {
  final String semesterLabel;
  final String semesterDisplay;

  const ManageSemesterClassesScreen({
    super.key,
    required this.semesterLabel,
    required this.semesterDisplay,
  });

  @override
  State<ManageSemesterClassesScreen> createState() =>
      _ManageSemesterClassesScreenState();
}

class _ManageSemesterClassesScreenState
    extends State<ManageSemesterClassesScreen> {
  final ClassService _classService = ClassService();
  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _classes = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredClasses {
    if (_searchQuery.isEmpty) return _classes;
    final q = _searchQuery.toLowerCase();
    return _classes.where((c) {
      final name = (c['class_name'] ?? '').toString().toLowerCase();
      final code = (c['class_code'] ?? '').toString().toLowerCase();
      final teacher = (c['teacher_name'] ?? '').toString().toLowerCase();
      return name.contains(q) || code.contains(q) || teacher.contains(q);
    }).toList();
  }

  int? _classIdOf(Map<String, dynamic> cls) {
    final raw = cls['id'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  Future<void> _loadClasses() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _classService.getSemesterClasses(widget.semesterLabel);

      if (mounted) {
        setState(() {
          _classes = List<Map<String, dynamic>>.from(data['classes'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading classes: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load classes. Please try again.';
        });
      }
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
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1F2937)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF007C91), Color(0xFF0097A7)],
                ),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.class_rounded, color: Colors.white, size: 20),
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
                      color: Color(0xFF1F2937),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_classes.length} classes',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0097A7)),
              ),
            )
          : _errorMessage != null
              ? _buildErrorState()
              : _classes.isEmpty
                  ? _buildEmptyState()
                  : Column(
                      children: [
                        _buildClassSearchBar(),
                        Expanded(child: _buildClassList()),
                      ],
                    ),
    );
  }

  Widget _buildClassSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SizedBox(
        height: 44,
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: 'Search by class name, code or teacher',
            hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.3), fontSize: 14),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF007C91)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF007C91)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
      ),
    );
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
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadClasses,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007C91),
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
          Icon(Icons.class_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'No classes in this semester',
            style: TextStyle(
              fontSize: 18,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassList() {
    final filtered = _filteredClasses;
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty
              ? 'No classes in this semester'
              : 'No classes match your search',
          style: const TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
        ),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: filtered.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildClassCard(filtered[index]),
      ),
    );
  }

  Widget _buildClassCard(Map<String, dynamic> cls) {
    final classId = _classIdOf(cls);
    final studentCount = int.tryParse(cls['student_count']?.toString() ?? '') ?? 0;
    final teacherName = cls['teacher_name']?.toString().trim() ?? '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: classId == null
            ? null
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminClassDetailScreen(
                      classId: classId,
                      classCode: cls['class_code'] ?? '',
                      className: cls['class_name'] ?? '',
                    ),
                  ),
                );
                // Detail edits (rename, reassign, remove student) change the
                // counts shown here; refresh on return.
                if (mounted) _loadClasses();
              },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEAF7FA),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.menu_book_rounded,
                        color: Color(0xFF007C91), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cls['class_name'] ?? 'Unnamed class',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cls['class_code'] ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF007C91),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF7FA),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$studentCount student${studentCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF007C91),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 16, color: Color(0xFF6B7280)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      teacherName.isEmpty ? 'Teacher not assigned' : teacherName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: teacherName.isEmpty
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 22, color: Color(0xFF9CA3AF)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}