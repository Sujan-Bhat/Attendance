import 'package:flutter/material.dart';

import '../../../services/class_service.dart';
import 'bulk_students_tab.dart';
import 'dialog_colors.dart';

/// Tabbed "Add Student" dialog with two divisions:
///   1. Individual (single student form, previously the whole dialog)
///   2. Excel Upload (bulk addition via a .xlsx template)
class AddStudentDialog extends StatefulWidget {
  final ClassService classService;
  final VoidCallback onStudentCreated;

  const AddStudentDialog({
    super.key,
    required this.classService,
    required this.onStudentCreated,
  });

  static Future<void> show({
    required BuildContext context,
    required ClassService classService,
    required VoidCallback onStudentCreated,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => AddStudentDialog(
        classService: classService,
        onStudentCreated: onStudentCreated,
      ),
    );
  }

  @override
  State<AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<AddStudentDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final isBulk = _tabController.index == 1;
        // Keep the dialog within the viewport: subtract the fixed header
        // (title + tab bar + paddings, ~170px) and the dialog's 48px vertical
        // inset from the screen height, and give the rest to the Excel
        // division. This guarantees the footer with 'Cancel' /
        // 'Upload & Validate' always fits on screen. Because the whole dialog
        // is wrapped in a SingleChildScrollView, even on extremely short
        // screens or large text scales the footer stays reachable.
        final screenH = MediaQuery.sizeOf(context).height;
        final bulkHeight = isBulk
            ? (screenH - 218.0).clamp(240.0, 640.0).toDouble()
            : 0.0;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isBulk ? 840 : 660),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Add Student',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: DialogColors.teal.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          color: DialogColors.tealDark,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: DialogColors.textMuted,
                        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        tabs: const [
                          Tab(text: 'Individual'),
                          Tab(text: 'Excel Upload'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // The Individual division is rendered directly so the Dialog
                    // self-sizes to the form exactly like the previous single
                    // student dialog. The Excel division gets a bounded box so
                    // its table can scroll.
                    if (isBulk)
                      SizedBox(
                        height: bulkHeight,
                        child: BulkStudentsTab(
                          classService: widget.classService,
                          onStudentCreated: widget.onStudentCreated,
                        ),
                      )
                    else
                      _IndividualStudentTab(
                        classService: widget.classService,
                        onStudentCreated: widget.onStudentCreated,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Single-student add form. This is the original Add Student dialog content,
/// moved into a tab verbatim (same fields, validation and behaviour).
class _IndividualStudentTab extends StatefulWidget {
  final ClassService classService;
  final VoidCallback onStudentCreated;

  const _IndividualStudentTab({
    required this.classService,
    required this.onStudentCreated,
  });

  @override
  State<_IndividualStudentTab> createState() => _IndividualStudentTabState();
}

class _IndividualStudentTabState extends State<_IndividualStudentTab> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _customSemesterController = TextEditingController();
  static const _presetSemesters = ['1', '2', '3', '4', '5', '6', '7', '8'];
  String? _selectedSemester = '1';
  bool _useCustomSemester = false;
  bool _isSaving = false;
  bool _obscurePassword = true;
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  // Shown only on the field that is currently active: the dropdown when in
  // preset mode, the custom field when "Other…" is chosen.
  String? _dropdownSemesterError;
  String? _customSemesterError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _customSemesterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildNameField(),
                const SizedBox(height: 14),
                _buildEmailField(),
                const SizedBox(height: 14),
                _buildPasswordField(),
                const SizedBox(height: 14),
                _buildSemesterDropdown(),
                if (_useCustomSemester) ...[
                  const SizedBox(height: 14),
                  _buildCustomSemesterField(),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 16),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: DialogColors.tealDark,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 16),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Create'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      textInputAction: TextInputAction.next,
      style: const TextStyle(fontSize: 17),
      onChanged: (_) => setState(() => _nameError = null),
      decoration: InputDecoration(
        labelText: 'Name',
        errorText: _nameError,
        prefixIcon: const Icon(Icons.person_outline, size: 26),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
    );
  }

  Widget _buildEmailField() {
    return TextField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      style: const TextStyle(fontSize: 17),
      onChanged: (_) => setState(() => _emailError = null),
      decoration: InputDecoration(
        labelText: 'Email',
        errorText: _emailError,
        prefixIcon: const Icon(Icons.email_outlined, size: 26),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: const TextStyle(fontSize: 17),
      onChanged: (_) => setState(() => _passwordError = null),
      decoration: InputDecoration(
        labelText: 'Password (min 6 chars)',
        errorText: _passwordError,
        prefixIcon: const Icon(Icons.lock_outline, size: 26),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.grey,
            size: 24,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
    );
  }

  Widget _buildSemesterDropdown() {
    return DropdownButtonFormField<String>(
      value: _useCustomSemester ? 'custom' : _selectedSemester,
      isExpanded: true,
      style: const TextStyle(fontSize: 17),
      decoration: InputDecoration(
        labelText: 'Semester',
        errorText: _useCustomSemester ? null : _dropdownSemesterError,
        prefixIcon: const Icon(Icons.school_outlined, size: 26),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      items: [
        ..._presetSemesters.map(
          (s) => DropdownMenuItem(value: s, child: Text('Semester $s')),
        ),
        const DropdownMenuItem(value: 'custom', child: Text('Other…')),
      ],
      onChanged: (v) {
        setState(() {
          _dropdownSemesterError = null;
          _customSemesterError = null;
          if (v == 'custom') {
            _useCustomSemester = true;
          } else {
            _useCustomSemester = false;
            _selectedSemester = v;
          }
        });
      },
    );
  }

  Widget _buildCustomSemesterField() {
    return TextField(
      controller: _customSemesterController,
      style: const TextStyle(fontSize: 17),
      onChanged: (_) => setState(() => _customSemesterError = null),
      decoration: InputDecoration(
        labelText: 'Custom semester',
        errorText: _customSemesterError,
        prefixIcon: const Icon(Icons.edit_outlined, size: 26),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final semester = _useCustomSemester
        ? _customSemesterController.text.trim()
        : (_selectedSemester ?? '');

    var hasError = false;

    if (name.isEmpty) {
      setState(() => _nameError = 'Name is required');
      hasError = true;
    }
    if (email.isEmpty) {
      setState(() => _emailError = 'Email is required');
      hasError = true;
    } else if (!email.contains('@')) {
      setState(() => _emailError = 'Enter a valid email');
      hasError = true;
    }
    if (password.isEmpty) {
      setState(() => _passwordError = 'Password is required');
      hasError = true;
    } else if (password.length < 6) {
      setState(() => _passwordError = 'At least 6 characters');
      hasError = true;
    }
    if (semester.isEmpty) {
      setState(() {
        if (_useCustomSemester) {
          _customSemesterError = 'Semester is required';
        } else {
          _dropdownSemesterError = 'Semester is required';
        }
      });
      hasError = true;
    }

    if (hasError) return;

    setState(() => _isSaving = true);
    final result = await widget.classService.adminCreateUser(
      username: name,
      email: email,
      password: password,
      role: 'student',
      semester: semester,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: Colors.red),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Student created successfully'),
          backgroundColor: DialogColors.tealDark,
        ),
      );
      widget.onStudentCreated();
    }
  }
}