import 'package:flutter/material.dart';
import '../../services/class_service.dart';
import '../../widgets/admin_web_layout.dart';
import 'admin_class_detail_screen.dart';

abstract class _AppColors {
  static const tealDark = Color(0xFF007C91);
  static const teal = Color(0xFF0097A7);
  static const textMuted = Color(0xFF6B7280);
}

class ManageTeachersScreen extends StatefulWidget {
  const ManageTeachersScreen({super.key});

  @override
  State<ManageTeachersScreen> createState() => _ManageTeachersScreenState();
}

class _ManageTeachersScreenState extends State<ManageTeachersScreen> {
  final ClassService _classService = ClassService();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = false;
  bool _mobileSearchOpen = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _teachers = [];
  final Set<int> _expandedTeacherIds = {};
  final ScrollController _tableHScroll = ScrollController();

  List<Map<String, dynamic>> get _filteredTeachers {
    if (_searchQuery.isEmpty) return _teachers;
    final q = _searchQuery.toLowerCase();
    return _teachers.where((t) =>
      (t['username']?.toString().toLowerCase() ?? '').contains(q) ||
      (t['email']?.toString().toLowerCase() ?? '').contains(q)
    ).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableHScroll.dispose();
    super.dispose();
  }

  /// Safely parses a teacher id that may arrive as int, String, or null
  /// depending on the backend/JSON serialization path.
  int? _teacherIdOf(Map<String, dynamic> teacher) {
    final raw = teacher['id'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  Future<void> _loadTeachers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _classService.getTeachers();

      if (mounted) {
        setState(() {
          _teachers = List<Map<String, dynamic>>.from(data['teachers'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading teachers: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load teachers. Please check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;

    final Widget mainContent = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_AppColors.tealDark, _AppColors.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildModernAppBar(isMobile),
            if (_mobileSearchOpen) _buildSearchBar(),
            Expanded(
              child: RefreshIndicator(
                color: _AppColors.tealDark,
                onRefresh: _loadTeachers,
                child: _buildContent(isMobile),
              ),
            ),
          ],
        ),
      ),
    );

    return AdminWebLayout(
      currentRoute: 'Manage Teachers',
      showMobileAppBar: false,
      mobileChild: mainContent,
      desktopBody: mainContent,
    );
  }

  Widget _buildModernAppBar(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: isMobile ? 10 : 14,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_AppColors.tealDark, _AppColors.teal],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final searchWidth = isMobile
              ? double.infinity
              : (constraints.maxWidth * 0.4).clamp(240.0, 340.0);
          return Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMobile)
                Builder(
                  builder: (context) => Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.menu_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      tooltip: 'Menu',
                    ),
                  ),
                ),
              if (isMobile) const SizedBox(width: 8),
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
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manage Teachers',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 18 : 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 16),
            _buildSearchField(width: searchWidth),
            const SizedBox(width: 8),
          ] else ...[
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: Icon(
                  _mobileSearchOpen
                      ? Icons.close_rounded
                      : Icons.search_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () =>
                    setState(() => _mobileSearchOpen = !_mobileSearchOpen),
                tooltip: _mobileSearchOpen ? 'Close search' : 'Search',
              ),
            ),
          ],
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.person_add_alt_1_rounded,
                color: Colors.white,
                size: 24,
              ),
              onPressed: _showAddTeacherDialog,
              tooltip: 'Add Teacher',
            ),
          ),
        ],
      );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: _buildSearchField(autofocus: true),
    );
  }

  Widget _buildSearchField({double? width, bool autofocus = false}) {
    return SizedBox(
      width: width ?? double.infinity,
      child: TextField(
        autofocus: autofocus,
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Search by name or email',
          hintStyle: TextStyle(color: Colors.grey.shade400),
          prefixIcon: const Icon(Icons.search, color: _AppColors.teal, size: 22),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _AppColors.teal, width: 2),
          ),
        ),
      ),
    );
  }

  /// Central place that decides between the loading state, error state,
  /// empty state, and the actual teacher list/table.
  Widget _buildContent(bool isMobile) {
    if (_isLoading) {
      return _buildScrollableState(_buildLoadingState());
    }

    if (_errorMessage != null) {
      return _buildScrollableState(_buildErrorState());
    }

    final filtered = _filteredTeachers;

    if (filtered.isEmpty) {
      return _buildScrollableState(_buildEmptyState());
    }

    if (isMobile) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        physics: const BouncingScrollPhysics(),
        itemCount: filtered.length,
        itemBuilder: (context, index) =>
            _buildTeacherCard(filtered[index], index + 1),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(38, 4, 38, 26),
      child: _buildTable(filtered),
    );
  }

  Widget _buildScrollableState(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Loading teachers...',
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

  Widget _buildErrorState() {
    return Center(
      child: Padding(
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
              child: const Icon(
                Icons.error_outline_rounded,
                size: 64,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Oops!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _loadTeachers,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _AppColors.tealDark,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isSearchActive = _searchQuery.isNotEmpty;

    return Center(
      child: Padding(
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
              child: const Icon(
                Icons.person_off_rounded,
                size: 80,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              isSearchActive ? 'No teachers match your search' : 'No Teachers Found',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isSearchActive
                  ? 'Try a different name or email'
                  : 'No teachers have been added yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
                height: 1.5,
              ),
            ),
            if (isSearchActive) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Clear search'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> filtered) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowWidth = constraints.maxWidth >= 1040
            ? constraints.maxWidth
            : 1040.0;

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: Column(
            children: [
              SingleChildScrollView(
                controller: _tableHScroll,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: rowWidth,
                  child: _buildTableHeader(),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _tableHScroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: rowWidth,
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) =>
                          _buildTableRow(filtered[index], index + 1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTableHeader() {
    return Container(
      height: 50,
      decoration: const BoxDecoration(color: _AppColors.teal),
      child: const Row(
        children: [
          SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              'Sl. No',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Teacher Name',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Teacher Email',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Classes',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> teacher, int displayIndex) {
    final classes = List<Map<String, dynamic>>.from(teacher['classes'] ?? []);
    final teacherId = _teacherIdOf(teacher);
    final hasClasses = classes.isNotEmpty;
    final isExpanded = teacherId != null && _expandedTeacherIds.contains(teacherId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 60,
          decoration: BoxDecoration(
            color: displayIndex.isOdd ? const Color(0xFFF5F5F5) : Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: Text(
                  '$displayIndex',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    teacher['username'] ?? '',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    teacher['email'] ?? '',
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    children: [
                      Text(
                        '${teacher['class_count'] ?? 0}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasClasses && teacherId != null) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedTeacherIds.remove(teacherId);
                              } else {
                                _expandedTeacherIds.add(teacherId);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _AppColors.teal.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isExpanded ? 'Hide' : 'View',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _AppColors.teal,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  isExpanded ? Icons.expand_less : Icons.expand_more,
                                  size: 16,
                                  color: _AppColors.teal,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: _AppColors.tealDark, size: 20),
                onPressed: () => _showEditTeacherDialog(teacher),
                tooltip: 'Edit teacher',
              ),
              IconButton(
                icon: const Icon(Icons.swap_horiz, color: _AppColors.tealDark, size: 20),
                onPressed: () => _showReassignTeacherDialog(teacher),
                tooltip: 'Reassign classes',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: () => _showDeleteTeacherDialog(teacher),
                tooltip: 'Delete teacher',
              ),
            ],
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: isExpanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Container(
            padding: const EdgeInsets.fromLTRB(76, 8, 48, 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: _ClassListSection(
              classes: classes,
              dense: true,
              onTapClass: _openClassDetail,
              onReassignClass: (cls) => _showReassignClassDialog(cls, teacher),
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildTeacherCard(Map<String, dynamic> teacher, int displayIndex) {
    final classes = List<Map<String, dynamic>>.from(teacher['classes'] ?? []);
    final teacherId = _teacherIdOf(teacher);
    final isExpanded = teacherId != null && _expandedTeacherIds.contains(teacherId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          InkWell(
            onTap: teacherId == null
                ? null
                : () {
                    setState(() {
                      if (isExpanded) {
                        _expandedTeacherIds.remove(teacherId);
                      } else {
                        _expandedTeacherIds.add(teacherId);
                      }
                    });
                  },
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEAF7FA),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$displayIndex',
                      style: const TextStyle(
                        color: _AppColors.tealDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                teacher['username'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            if (classes.isNotEmpty)
                              Icon(
                                isExpanded ? Icons.expand_less : Icons.expand_more,
                                color: _AppColors.teal,
                                size: 24,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          teacher['email'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: _AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: _AppColors.tealDark, size: 20),
                    onPressed: () => _showEditTeacherDialog(teacher),
                    tooltip: 'Edit teacher',
                  ),
                  IconButton(
                    icon: const Icon(Icons.swap_horiz, color: _AppColors.tealDark, size: 20),
                    onPressed: () => _showReassignTeacherDialog(teacher),
                    tooltip: 'Reassign classes',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    onPressed: () => _showDeleteTeacherDialog(teacher),
                    tooltip: 'Delete teacher',
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: isExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                border: Border(
                  left: BorderSide(color: Colors.grey.shade200),
                  right: BorderSide(color: Colors.grey.shade200),
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: _ClassListSection(
                classes: classes,
                dense: false,
                onTapClass: _openClassDetail,
                onReassignClass: (cls) => _showReassignClassDialog(cls, teacher),
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  void _openClassDetail(Map<String, dynamic> cls) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminClassDetailScreen(
          classId: cls['id'],
          classCode: cls['class_code'] ?? '',
          className: cls['class_name'] ?? '',
        ),
      ),
    );
  }

  void _showAddTeacherDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Add Teacher', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password (min 6 chars)',
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final email = emailController.text.trim();
                          final password = passwordController.text;

                          if (name.isEmpty || email.isEmpty || password.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Name, email, and password are required'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);
                          final result = await _classService.adminCreateUser(
                            username: name,
                            email: email,
                            password: password,
                            role: 'teacher',
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (result['error'] != null) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(result['error']),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text('Teacher created successfully'),
                                backgroundColor: Color(0xFF007C91),
                              ),
                            );
                            _loadTeachers();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _AppColors.tealDark,
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      emailController.dispose();
      passwordController.dispose();
    });
  }

  void _showEditTeacherDialog(Map<String, dynamic> teacher) {
    final nameController = TextEditingController(text: teacher['username'] ?? '');
    final emailController = TextEditingController(text: teacher['email'] ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Edit Teacher', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final email = emailController.text.trim();

                          if (name.isEmpty || email.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Name and email cannot be empty'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);
                          final result = await _classService.updateTeacherDetails(
                            teacherId: teacher['id'],
                            username: name,
                            email: email,
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (result['error'] != null) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(result['error']),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text('Teacher updated successfully'),
                                backgroundColor: Color(0xFF007C91),
                              ),
                            );
                            _loadTeachers();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _AppColors.tealDark,
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      emailController.dispose();
    });
  }

  void _showReassignClassDialog(Map<String, dynamic> cls, Map<String, dynamic> currentTeacher) {
    final classId = cls['id'];
    if (classId == null) return;

    final className = cls['class_name'] ?? '';
    final classCode = cls['class_code'] ?? '';
    final currentName = currentTeacher['username'] ?? 'Unknown';

    final candidateTeachers = _teachers.where((t) =>
      t != currentTeacher &&
      _teacherIdOf(t) != _teacherIdOf(currentTeacher)
    ).toList();

    if (candidateTeachers.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reassign class', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('No other teacher is available to assign this class to.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final candidateIds = candidateTeachers.map((t) => _teacherIdOf(t)!).toList();
    int? selectedId = candidateIds.first;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Reassign class', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '"$className" ($classCode) is currently taught by $currentName.',
                    style: const TextStyle(fontSize: 14, color: _AppColors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: selectedId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'New teacher',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: candidateTeachers.map((t) {
                      final id = _teacherIdOf(t)!;
                      return DropdownMenuItem<int>(
                        value: id,
                        child: Text(
                          t['username'] ?? 'Unknown',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedId = v);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        final id = selectedId ?? candidateIds.first;
                        final newName = candidateTeachers
                            .firstWhere((t) => _teacherIdOf(t) == id)['username'] ?? 'Unknown';
                        final result = await _classService.updateClassDetails(
                          classId: classId,
                          teacherId: id,
                        );
                        if (!dialogCtx.mounted) return;
                        Navigator.pop(dialogCtx);
                        if (!mounted) return;
                        if (result['success'] == true || result['class'] != null) {
                          _loadTeachers();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('"$className" reassigned to $newName'),
                              backgroundColor: _AppColors.tealDark,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result['error']?.toString() ?? 'Failed to reassign class'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _AppColors.tealDark,
                  foregroundColor: Colors.white,
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Reassign'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showReassignTeacherDialog(Map<String, dynamic> teacher) {
    final classes = List<Map<String, dynamic>>.from(teacher['classes'] ?? []);
    if (classes.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reassign classes', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('This teacher has no classes to reassign.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final teacherName = teacher['username'] ?? 'Unknown';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reassign classes', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$teacherName teaches ${classes.length} '
                  'class${classes.length == 1 ? '' : 'es'}. Choose a class to move '
                  'to another teacher.',
                  style: const TextStyle(fontSize: 14, color: _AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                _ReassignableTeacherClasses(
                  classes: classes,
                  onReassign: (cls) {
                    Navigator.pop(ctx);
                    _showReassignClassDialog(cls, teacher);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showDeleteTeacherDialog(Map<String, dynamic> teacher) {
    final teacherId = _teacherIdOf(teacher);
    if (teacherId == null) return;

    final teacherName = teacher['username'] ?? 'Unknown';
    final classCount =
        int.tryParse(teacher['class_count']?.toString() ?? '') ?? 0;

    if (classCount > 0) {
      final classes = List<Map<String, dynamic>>.from(teacher['classes'] ?? []);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Cannot delete teacher',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$teacherName still has $classCount '
                    'class${classCount == 1 ? '' : 'es'} assigned. Reassign or delete '
                    'these classes before deleting the teacher.',
                    style: const TextStyle(fontSize: 14, color: _AppColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  _ReassignableTeacherClasses(
                    classes: classes,
                    onReassign: (cls) {
                      Navigator.pop(ctx);
                      _showReassignClassDialog(cls, teacher);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    bool isDeleting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              'Delete Teacher',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Delete $teacherName from the database?\n\n'
              'This permanently removes the teacher and cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isDeleting
                    ? null
                    : () async {
                        setDialogState(() => isDeleting = true);
                        final result = await _classService.adminDeleteUser(teacherId);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        if (result['error'] == null) {
                          _loadTeachers();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Teacher "$teacherName" deleted'),
                              backgroundColor: const Color(0xFF007C91),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result['error'].toString()),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: isDeleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Delete'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shared "Classes:" expandable section used by both the desktop table row
/// and the mobile card, so styling/behaviour only needs to live in one place.
class _ClassListSection extends StatelessWidget {
  const _ClassListSection({
    required this.classes,
    required this.onTapClass,
    required this.onReassignClass,
    this.dense = false,
  });

  final List<Map<String, dynamic>> classes;
  final void Function(Map<String, dynamic> cls) onTapClass;
  final void Function(Map<String, dynamic> cls) onReassignClass;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: dense ? 4 : 8),
      padding: EdgeInsets.all(dense ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(dense ? 12 : 16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: dense
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF007C91).withOpacity(0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Classes',
                style: TextStyle(
                  fontSize: dense ? 12 : 14,
                  fontWeight: FontWeight.w700,
                  color: _AppColors.tealDark,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _AppColors.tealDark.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${classes.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _AppColors.tealDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (classes.isEmpty)
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 6),
                Text(
                  'No classes assigned',
                  style: TextStyle(
                    fontSize: dense ? 12 : 13,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            )
          else
            ...classes.map((cls) => Padding(
              padding: EdgeInsets.only(bottom: dense ? 6 : 8),
              child: _ClassTile(
                cls: cls,
                dense: dense,
                onTap: () => onTapClass(cls),
                onReassign: () => onReassignClass(cls),
              ),
            )),
        ],
      ),
    );
  }
}

/// One cascading tile for a teacher's class inside [_ClassListSection].
class _ClassTile extends StatelessWidget {
  const _ClassTile({
    required this.cls,
    required this.dense,
    required this.onTap,
    required this.onReassign,
  });

  final Map<String, dynamic> cls;
  final bool dense;
  final VoidCallback onTap;
  final VoidCallback onReassign;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FBFB),
      borderRadius: BorderRadius.circular(dense ? 10 : 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(dense ? 10 : 12),
        child: Container(
          padding: EdgeInsets.all(dense ? 8 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(dense ? 10 : 12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: dense ? 34 : 42,
                height: dense ? 34 : 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_AppColors.tealDark, _AppColors.teal],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(dense ? 9 : 12),
                ),
                child: Icon(
                  Icons.class_rounded,
                  color: Colors.white,
                  size: dense ? 16 : 22,
                ),
              ),
              SizedBox(width: dense ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cls['class_name'] ?? '',
                      style: TextStyle(
                        fontSize: dense ? 13 : 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _ClassMetaChip(
                          label: cls['class_code'] ?? '',
                          dense: dense,
                        ),
                        _ClassMetaChip(
                          label: '${cls['student_count'] ?? 0} students',
                          dense: dense,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: dense ? 8 : 10),
              if (dense)
                IconButton(
                  icon: const Icon(
                    Icons.swap_horiz,
                    size: 18,
                    color: _AppColors.tealDark,
                  ),
                  onPressed: onReassign,
                  tooltip: 'Reassign teacher',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              else
                OutlinedButton.icon(
                  onPressed: onReassign,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _AppColors.tealDark,
                    side: BorderSide(color: _AppColors.tealDark.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text(
                    'Reassign',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              SizedBox(width: dense ? 4 : 6),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small teal pill used for class metadata inside [_ClassTile].
class _ClassMetaChip extends StatelessWidget {
  const _ClassMetaChip({required this.label, required this.dense});

  final String label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: _AppColors.tealDark.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: dense ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: _AppColors.tealDark,
        ),
      ),
    );
  }
}

/// Lists a teacher's classes, each with a reassign action. Used by both the
/// "Cannot delete teacher" dialog and the teacher-level reassign dialog.
class _ReassignableTeacherClasses extends StatelessWidget {
  const _ReassignableTeacherClasses({
    required this.classes,
    required this.onReassign,
  });

  final List<Map<String, dynamic>> classes;
  final void Function(Map<String, dynamic> cls) onReassign;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: classes.map((cls) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${cls['class_name'] ?? ''} (${cls['class_code'] ?? ''})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: () => onReassign(cls),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              icon: const Icon(Icons.swap_horiz, size: 14, color: _AppColors.tealDark),
              label: const Text('Reassign', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      )).toList(),
    );
  }
}