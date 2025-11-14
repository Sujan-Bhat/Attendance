import 'package:flutter/material.dart';
import '../../services/class_service.dart';

class AddStudentsScreen extends StatefulWidget {
  final int classId;

  const AddStudentsScreen({super.key, required this.classId});

  @override
  State<AddStudentsScreen> createState() => _AddStudentsScreenState();
}

class _AddStudentsScreenState extends State<AddStudentsScreen> {
  final ClassService _classService = ClassService();

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final rollNoController = TextEditingController();

  List<Map<String, String>> students = [];
  bool _obscurePassword = true;
  bool isLoading = false;
  bool isCheckingEmail = false;
  bool isExistingStudent = false;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    rollNoController.dispose();
    super.dispose();
  }

  Future<void> _checkEmailAndAutoFill(String email) async {
    if (email.isEmpty || !_isValidEmail(email)) {
      setState(() {
        isExistingStudent = false;
      });
      return;
    }

    setState(() {
      isCheckingEmail = true;
    });

    try {
      final studentData = await _classService.checkStudentByEmail(email);

      if (studentData != null && mounted) {
        setState(() {
          isExistingStudent = true;
          nameController.text = studentData['username'] ?? '';
          rollNoController.text = studentData['roll_no']?.toString() ?? '';
          passwordController.clear();
        });

        _showInfoSnackBar('✓ Existing student found! Details auto-filled.');
      } else if (mounted) {
        setState(() {
          isExistingStudent = false;
          nameController.clear();
          rollNoController.clear();
        });
      }
    } catch (e) {
      print('Error checking email: $e');
    } finally {
      if (mounted) {
        setState(() {
          isCheckingEmail = false;
        });
      }
    }
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  void _addStudent() {
    if (emailController.text.isEmpty) {
      _showErrorSnackBar('Email is required');
      return;
    }

    if (!_isValidEmail(emailController.text)) {
      _showErrorSnackBar('Please enter a valid email');
      return;
    }

    if (!isExistingStudent) {
      if (nameController.text.isEmpty) {
        _showErrorSnackBar('Name is required for new students');
        return;
      }
      if (passwordController.text.isEmpty) {
        _showErrorSnackBar('Password is required for new students');
        return;
      }
      if (rollNoController.text.isEmpty) {
        _showErrorSnackBar('Roll number is required for new students');
        return;
      }
      if (passwordController.text.length < 6) {
        _showErrorSnackBar('Password must be at least 6 characters');
        return;
      }
    }

    // Check for duplicate email in list
    if (students.any((s) => s['email'] == emailController.text)) {
      _showErrorSnackBar('Student with this email already in list');
      return;
    }

    // Build student data
    final studentData = <String, String>{'email': emailController.text};

    if (nameController.text.isNotEmpty) {
      studentData['name'] = nameController.text;
    }
    if (passwordController.text.isNotEmpty) {
      studentData['password'] = passwordController.text;
    }
    if (rollNoController.text.isNotEmpty) {
      studentData['rollNo'] = rollNoController.text;
    }

    setState(() {
      students.add(studentData);
      isExistingStudent = false;
    });

    // Clear fields
    nameController.clear();
    emailController.clear();
    passwordController.clear();
    rollNoController.clear();

    _showSuccessSnackBar('✓ Student added to list!');
  }

  void _removeStudent(int index) {
    setState(() {
      students.removeAt(index);
    });
    _showInfoSnackBar('Student removed from list');
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
    List<String> errors = [];

    try {
      for (var student in students) {
        try {
          await _classService.addStudentToClass(widget.classId, student);
          successCount++;
        } catch (e) {
          failCount++;
          errors.add('${student['email']}: ${e.toString()}');
        }
      }

      if (mounted) {
        if (failCount == 0) {
          _showSuccessSnackBar('✓ All $successCount students added successfully!');
          Navigator.pop(context, true);
        } else {
          _showErrorSnackBar(
            '$successCount added, $failCount failed.\n${errors.join('\n')}',
          );
          // Remove successfully added students
          setState(() {
            students = students.where((s) {
              return errors.any((e) => e.contains(s['email']!));
            }).toList();
          });
        }
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
                child: isMobile 
                  ? _buildMobileLayout() 
                  : _buildDesktopLayout(),
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
        _buildAddStudentForm(true),
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
          // LEFT SIDE - Add Student Form
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildAddStudentForm(false),
                  if (students.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSubmitButton(),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(width: 20),
          
          // RIGHT SIDE - Students List
          Expanded(
            flex: 3,
            child: students.isEmpty 
              ? _buildEmptyStudentsList()
              : SingleChildScrollView(
                  child: _buildStudentsList(),
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
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
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
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
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
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddStudentForm(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(20),
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
          const Row(
            children: [
              Icon(Icons.person_add_rounded, color: Color(0xFF007C91)),
              SizedBox(width: 8),
              Text(
                'Student Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF007C91),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Helper text
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Enter email to check if student exists. Details will auto-fill for existing students.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Email field with auto-check
          _buildTextField(
            controller: emailController,
            label: 'Email Address *',
            hint: 'student@example.com',
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
            onChanged: (value) {
              // Debounce: Check email after user stops typing
              Future.delayed(const Duration(milliseconds: 800), () {
                if (emailController.text == value && value.isNotEmpty) {
                  _checkEmailAndAutoFill(value);
                }
              });
            },
            suffixIcon: isCheckingEmail
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: Padding(
                      padding: EdgeInsets.all(12.0),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF007C91),
                        ),
                      ),
                    ),
                  )
                : (isExistingStudent
                    ? Icon(Icons.check_circle, color: Colors.green.shade600, size: 24)
                    : null),
          ),

          const SizedBox(height: 16),

          // Status badge
          if (isExistingStudent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    '✓ Existing student found',
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

          if (!isExistingStudent &&
              emailController.text.isNotEmpty &&
              _isValidEmail(emailController.text) &&
              !isCheckingEmail)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade300, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add_outlined, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'New student - fill all required fields',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 20),

          // Other fields
          _buildTextField(
            controller: nameController,
            label: isExistingStudent ? 'Student Name' : 'Student Name *',
            hint: 'John Doe',
            icon: Icons.person_rounded,
            enabled: !isExistingStudent,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: rollNoController,
            label: isExistingStudent ? 'Roll Number' : 'Roll Number *',
            hint: '2024001',
            icon: Icons.badge_rounded,
            enabled: !isExistingStudent,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: passwordController,
            label: isExistingStudent ? 'Password (Optional)' : 'Password *',
            hint: isExistingStudent ? 'Leave empty for existing' : 'Min. 6 characters',
            icon: Icons.lock_rounded,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: const Color(0xFF007C91),
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
          const SizedBox(height: 24),

          // Add button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _addStudent,
              icon: const Icon(Icons.add_rounded, size: 22),
              label: const Text(
                'Add to List',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007C91),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    Function(String)? onChanged,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      enabled: enabled,
      onChanged: onChanged,
      style: TextStyle(
        color: enabled ? Colors.black87 : Colors.grey.shade600,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400),
        prefixIcon: Icon(icon, color: const Color(0xFF007C91), size: 22),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: enabled ? Colors.grey.shade50 : Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF007C91), width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
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
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
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
                  student.containsKey('password') && student['password']!.isNotEmpty;

              return Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF007C91),
                    radius: 24,
                    child: Text(
                      student['name']?.substring(0, 1).toUpperCase() ??
                          student['email']?.substring(0, 1).toUpperCase() ??
                          'S',
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
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (student.containsKey('rollNo') &&
                              student['rollNo']!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Roll: ${student['rollNo']}',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (student.containsKey('rollNo') &&
                              student['rollNo']!.isNotEmpty &&
                              !hasPassword)
                            const SizedBox(width: 6),
                          if (!hasPassword)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue.shade300),
                              ),
                              child: Text(
                                'Existing Student',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
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
                    icon: const Icon(Icons.close_rounded, color: Colors.red, size: 22),
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