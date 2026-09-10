import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/class_service.dart';

class AddStudentsScreen extends StatefulWidget {
  final int classId;

  const AddStudentsScreen({super.key, required this.classId});

  @override
  State<AddStudentsScreen> createState() => _AddStudentsScreenState();
}

class _AddStudentsScreenState extends State<AddStudentsScreen> {
  final ClassService _classService = ClassService();

  List<Map<String, String>> students = [];
  bool isLoading = false;
  String? classCode;

  List<Map<String, dynamic>> _enrolledStudents = [];
  List<Map<String, dynamic>> _availableStudents = [];
  final Set<String> _enrolledEmails = {};
  final searchController = TextEditingController();
  bool _rosterLoading = true;
  String? _semester;

  @override
  void initState() {
    super.initState();
    _fetchClassDetails();
    _fetchRoster();
  }

  Future<void> _fetchRoster() async {
    try {
      final roster = await _classService.getClassRoster(widget.classId);
      if (roster != null && mounted) {
        setState(() {
          _semester = roster['semester'] as String?;
          _enrolledStudents = List<Map<String, dynamic>>.from(
            roster['students'] ?? const [],
          );
          _availableStudents = List<Map<String, dynamic>>.from(
            roster['available_students'] ?? const [],
          );
          _enrolledEmails
            ..clear()
            ..addAll(
              _enrolledStudents
                  .map((s) => (s['email'] as String? ?? '').toLowerCase())
                  .where((e) => e.isNotEmpty),
            );
          _rosterLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching roster: $e');
      if (mounted) {
        setState(() {
          _rosterLoading = false;
        });
      }
    }
  }

  Future<void> _fetchClassDetails() async {
    try {
      final details = await _classService.getClassDetails(widget.classId);
      if (details != null && mounted) {
        setState(() {
          classCode = details['class_code'];
        });
      }
    } catch (e) {
      debugPrint('Error fetching class details: $e');
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _removeStudent(int index) {
    setState(() {
      students.removeAt(index);
    });
    _showInfoSnackBar('Student removed from list');
  }

  void _addAvailableStudent(Map<String, dynamic> student) {
    final email = (student['email'] as String? ?? '').trim().toLowerCase();
    if (email.isEmpty) return;
    if (_enrolledEmails.contains(email)) {
      _showErrorSnackBar('This student is already enrolled in this class.');
      return;
    }
    if (students.any((s) => s['email'] == email)) {
      _showErrorSnackBar('Student with this email already in list');
      return;
    }
    final name = student['username'] as String? ?? email;
    setState(() {
      students.add({'email': email, 'name': name});
    });
    _showSuccessSnackBar('✓ $name added to list!');
  }

  Future<void> _submitStudents() async {
    if (students.isEmpty) {
      _showErrorSnackBar('Please add at least one student');
      return;
    }

    setState(() {
      isLoading = true;
    });

    int successCount = 0;
    int failCount = 0;
    final failedEmails = <String>{};
    final errors = <String>[];

    try {
      for (var student in students) {
        final result =
            await _classService.addStudentToClass(widget.classId, student);
        if (result['success'] == true) {
          successCount++;
        } else {
          failCount++;
          final email = student['email'] ?? '';
          failedEmails.add(email);
          errors.add(
            '$email: ${result['message'] ?? 'Failed to add student'}',
          );
        }
      }

      if (!mounted) return;

      if (failCount == 0) {
        _showSuccessSnackBar(
          '✓ All $successCount students added successfully!',
        );
        // Keep the screen open so the next batch can be added immediately.
        setState(() {
          students.clear();
        });
        // Refresh roster so enrolled grows and available shrinks.
        _fetchRoster();
      } else {
        // Keep only the students that failed so they can be retried.
        setState(() {
          students =
              students.where((s) => failedEmails.contains(s['email'])).toList();
        });
        _showEnrollErrors(successCount, failCount, errors);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to add students: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _showEnrollErrors(
    int successCount,
    int failCount,
    List<String> errors,
  ) {
    _showErrorSnackBar('$successCount added, $failCount failed.');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$failCount student${failCount == 1 ? '' : 's'} failed'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (successCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '$successCount added successfully.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              for (final error in errors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
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
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF007C91),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 900; // Increased breakpoint for better layout

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
              _buildAppBar(isMobile),
              Expanded(
                child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  //  MOBILE LAYOUT (Stacked)
  Widget _buildMobileLayout() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SizedBox(
          height: 650, // Fixed height for tabs
          child: _buildLeftPanel(true),
        ),
        const SizedBox(height: 24),
        _buildAvailableSection(),
        if (students.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildStudentsList(),
          const SizedBox(height: 24),
          _buildSubmitButton(),
        ],
      ],
    );
  }

  //  DESKTOP LAYOUT (Side by Side)
  Widget _buildDesktopLayout() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT SIDE - Add Student Form / Share Link
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 600, // Fixed height for tab view to work properly in row
              child: _buildLeftPanel(false),
            ),
          ),

          const SizedBox(width: 20),

          // RIGHT SIDE - Students List + Roster
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAvailableSection(),
                        const SizedBox(height: 16),
                        if (students.isEmpty)
                          _buildEmptyStudentsList()
                        else
                          _buildStudentsList(),
                      ],
                    ),
                  ),
                ),
                if (students.isNotEmpty) _buildSubmitButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  //  EMPTY STATE for Students List
  Widget _buildEmptyStudentsList() {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
              Icons.people_outline_rounded,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 20),
            Text(
              'No Students Added Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add students using the form on the left',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add Students',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Enroll students to your class',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          if (classCode != null)
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.share_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                tooltip: 'Share Invite Link',
                onPressed: () {
                  final link =
                      'https://presence-cne6ezafcncnduf3.indiasouthcentral-01.azurewebsites.net/join/$classCode';
                  Share.share(
                    'Join my class on Presence!\nTap here to join: $link',
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel(bool isMobile) {
    return DefaultTabController(
      length: 2,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: const TabBar(
                labelColor: Color(0xFF007C91),
                unselectedLabelColor: Colors.grey,
                indicatorColor: Color(0xFF007C91),
                indicatorWeight: 3,
                tabs: [
                  Tab(icon: Icon(Icons.link_rounded), text: 'Invite Link'),
                  Tab(
                    icon: Icon(Icons.group_rounded),
                    text: 'Enrolled Students',
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [_buildShareLinkTab(), _buildEnrolledTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareLinkTab() {
    final link = classCode != null
        ? 'https://presence-cne6ezafcncnduf3.indiasouthcentral-01.azurewebsites.net/join/$classCode'
        : 'Loading...';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Link',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF007C91),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    link,
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () {
                    if (classCode != null) {
                      Clipboard.setData(ClipboardData(text: link));
                      _showSuccessSnackBar('✓ Link copied to clipboard!');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.copy_rounded,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: SizedBox(
              width: 200,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (classCode != null) {
                    Share.share(
                      'Join my class on Presence!\nTap here to join: $link',
                    );
                  }
                },
                icon: const Icon(
                  Icons.reply_rounded,
                  size: 24,
                ), // Share arrow icon
                label: const Text(
                  'Share link',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0097A7),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnrolledTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.group_rounded, color: Color(0xFF007C91)),
              SizedBox(width: 8),
              Text(
                'Enrolled Students',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF007C91),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_rosterLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF007C91)),
                ),
              ),
            )
          else if (_enrolledStudents.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'No students enrolled yet.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007C91).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        color: Color(0xFF007C91),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_enrolledStudents.length} student'
                        '${_enrolledStudents.length == 1 ? '' : 's'} enrolled',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF007C91),
                        ),
                      ),
                    ],
                  ),
                ),
                ..._enrolledStudents.map(_buildEnrolledStudentRow).toList(),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAvailableSection() {
    if (_rosterLoading) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF007C91)),
          ),
        ),
      );
    }

    final query = searchController.text.trim().toLowerCase();
    final available = query.isEmpty
        ? _availableStudents
        : _availableStudents
              .where((s) =>
                  (s['username'] as String? ?? '')
                      .toLowerCase()
                      .contains(query) ||
                  (s['email'] as String? ?? '')
                      .toLowerCase()
                      .contains(query))
              .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: Color(0xFF007C91),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Available this Semester (${available.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF007C91),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: TextField(
              controller: searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search by name or email...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),
          if (available.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No available students for this semester'
                '${_semester != null ? ' ($_semester)' : ''}.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            )
          else
            ...available.map(_buildAvailableStudentTile).toList(),
        ],
      ),
    );
  }

  Widget _buildAvailableStudentTile(Map<String, dynamic> student) {
    final name = student['username'] as String? ?? 'Student';
    final email = student['email'] as String? ?? '';
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF007C91),
        radius: 16,
        child: Text(
          _initialOf(name) ?? 'S',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        email,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: IconButton(
        icon: const Icon(
          Icons.add_circle_rounded,
          color: Color(0xFF007C91),
        ),
        tooltip: 'Add to list',
        onPressed: () => _addAvailableStudent(student),
      ),
    );
  }

  Widget _buildEnrolledStudentRow(Map<String, dynamic> student) {
    final name = student['username'] as String? ?? 'Student';
    final email = student['email'] as String? ?? '';
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: CircleAvatar(
        backgroundColor: Colors.green.shade600,
        radius: 16,
        child: Text(
          _initialOf(name) ?? 'S',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        email,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
    );
  }

  String? _initialOf(String? value) {
    if (value == null || value.isEmpty) return null;
    return value.substring(0, 1).toUpperCase();
  }

  Widget _buildStudentsList() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF007C91).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.list_alt_rounded,
                  color: Color(0xFF007C91),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Students to Add (${students.length})',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF007C91),
                  ),
                ),
              ),
              if (students.length > 1)
                TextButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Clear All Students?'),
                        content: Text(
                          'Remove all ${students.length} students from the list?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              setState(() => students.clear());
                              Navigator.pop(context);
                              _showInfoSnackBar('All students removed');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('Clear All'),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear All'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: students.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final student = students[index];
              final hasPassword =
                  student.containsKey('password') &&
                  student['password']!.isNotEmpty;
              final initial =
                  _initialOf(student['name']) ??
                  _initialOf(student['email']) ??
                  'S';

              return Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF007C91),
                    radius: 24,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  title: Text(
                    student['name'] ?? student['email']!.split('@')[0],
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        student['email']!,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (!hasPassword)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Existing',
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.red,
                      size: 22,
                    ),
                    onPressed: () => _removeStudent(index),
                    tooltip: 'Remove student',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF007C91), Color(0xFF0097A7)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007C91).withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : _submitStudents,
        icon: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.check_rounded, color: Colors.white, size: 24),
        label: Text(
          isLoading
              ? 'Adding Students...'
              : 'Enroll ${students.length} ${students.length == 1 ? "Student" : "Students"}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
