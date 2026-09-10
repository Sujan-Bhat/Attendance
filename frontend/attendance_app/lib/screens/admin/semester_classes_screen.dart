import 'package:flutter/material.dart';
import '../../services/class_service.dart';

class SemesterClassesScreen extends StatefulWidget {
  final String semesterLabel;
  final String semesterDisplay;
  final int totalEnrollments;

  const SemesterClassesScreen({
    super.key,
    required this.semesterLabel,
    required this.semesterDisplay,
    required this.totalEnrollments,
  });

  @override
  State<SemesterClassesScreen> createState() => _SemesterClassesScreenState();
}

class _SemesterClassesScreenState extends State<SemesterClassesScreen> {
  final ClassService _classService = ClassService();
  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _students = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Map<String, dynamic>> get _filteredStudents {
    if (_searchQuery.isEmpty) return _students;
    final q = _searchQuery.toLowerCase();
    return _students.where((s) {
      final name = (s['username'] ?? '').toString().toLowerCase();
      final email = (s['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  /// Returns an uppercase single-letter avatar initial, safely handling a
  /// null or empty username.
  String _initialOf(dynamic username) {
    final name = username?.toString() ?? '';
    return name.isEmpty ? 'S' : name.substring(0, 1).toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _classService.getSemesterStudents(widget.semesterLabel),
        _classService.getAdminUnassignedStudents(),
      ]);
      final data = results[0];
      final unassignedData = results[1];

      final unassigned = List<Map<String, dynamic>>.from(
        unassignedData['students'] ?? [],
      ).where((s) =>
          (s['semester']?.toString() ?? '').trim() ==
          widget.semesterLabel.trim());

      final seen = <int>{};
      final merged = <Map<String, dynamic>>[
        ...List<Map<String, dynamic>>.from(data['students'] ?? []),
      ];
      for (final student in merged) {
        final id = student['id'];
        if (id is int) seen.add(id);
      }
      for (final student in unassigned) {
        final id = student['id'];
        if (id is int && seen.add(id)) {
          merged.add({...student, 'classes': [], 'unassigned': true});
        }
      }

      if (mounted) {
        setState(() {
          _students = merged;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading students: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load students. Please try again.';
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
              child: const Icon(Icons.people_alt_rounded, color: Colors.white, size: 20),
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
                    '${widget.totalEnrollments} students',
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
        actions: [
          if (_students.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red, size: 22),
              onPressed: _showDeleteAllDialog,
              tooltip: 'Delete all students in this semester',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0097A7)),
              ),
            )
          : _errorMessage != null
              ? _buildErrorState()
              : _students.isEmpty
                  ? _buildEmptyState()
                  : Column(
                      children: [
                        _buildSearchBar(),
                        Expanded(child: _buildStudentList()),
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
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadStudents,
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
          Icon(Icons.people_outline, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'No students in this semester',
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SizedBox(
        height: 44,
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: 'Search by name, email or roll no',
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

  Widget _buildStudentList() {
    final filtered = _filteredStudents;
    if (filtered.isEmpty && !_isLoading) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? 'No students in this semester' : 'No students match your search',
          style: const TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
        ),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: filtered.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _buildStudentCard(filtered[index]),
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    final classes = List<Map<String, dynamic>>.from(student['classes'] ?? []);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF007C91),
              radius: 24,
              child: Text(
                _initialOf(student['username']),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student['username'] ?? 'Unknown',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.email_outlined, size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          student['email'] ?? '',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (classes.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Not assigned to any class',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE65100),
                        ),
                      ),
),
          ],
        ),
      ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Color(0xFF007C91), size: 20),
              onPressed: () => _showEditDialog(student),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: () => _showDeleteStudentDialog(student),
              tooltip: 'Delete student',
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> student) {
    final nameController = TextEditingController(text: student['username'] ?? '');
    final emailController = TextEditingController(text: student['email'] ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'Edit Student',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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
                          setDialogState(() => isSaving = true);
                          final result = await _classService.updateStudentDetails(
                            studentId: student['id'],
                            username: nameController.text.trim(),
                            email: emailController.text.trim(),
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
                                content: Text('Student updated successfully'),
                                backgroundColor: Color(0xFF007C91),
                              ),
                            );
                            _loadStudents();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007C91),
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
    );
  }

  void _showDeleteStudentDialog(Map<String, dynamic> student) {
    final studentName = student['username'] ?? 'Unknown';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Student', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Delete $studentName from the database?\n\n'
          'This permanently removes the student, their class enrollments, '
          'and attendance history. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await _classService.adminDeleteStudent(
                student['id'],
              );
              if (!mounted) return;
              if (result['error'] == null) {
                _loadStudents();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$studentName deleted successfully'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAllDialog() {
    final count = _students.length;
    final semesterLabel = widget.semesterLabel;
    final confirmController = TextEditingController();
    bool isDeleting = false;
    bool canDelete = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              'Delete All Students',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delete all $count students in semester $semesterLabel?',
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This permanently removes every student in this semester, '
                    'their class enrollments, and attendance history. '
                    'This action cannot be undone.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmController,
                    onChanged: (v) => setDialogState(
                      () => canDelete = v.trim().toUpperCase() == 'DELETE',
                    ),
                    decoration: InputDecoration(
                      labelText: 'Type DELETE to confirm',
                      hintText: 'DELETE',
                      prefixIcon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  confirmController.dispose();
                  Navigator.pop(ctx);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isDeleting || !canDelete
                    ? null
                    : () async {
                        setDialogState(() => isDeleting = true);
                        final result = await _classService.adminDeleteAllStudents(
                          semesterLabel,
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        confirmController.dispose();
                        if (!mounted) return;
                        if (result['error'] == null) {
                          _loadStudents();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                result['message']?.toString() ??
                                    'All students deleted successfully',
                              ),
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
                    : const Text('Delete All'),
              ),
            ],
          );
        },
      ),
    );
  }
}
