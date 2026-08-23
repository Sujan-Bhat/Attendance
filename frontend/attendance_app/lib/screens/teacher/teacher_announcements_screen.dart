import 'package:flutter/material.dart';
import '../../services/class_service.dart';
import '../../services/announcement_service.dart';

class TeacherAnnouncementsScreen extends StatefulWidget {
  const TeacherAnnouncementsScreen({super.key});

  @override
  State<TeacherAnnouncementsScreen> createState() => _TeacherAnnouncementsScreenState();
}

class _TeacherAnnouncementsScreenState extends State<TeacherAnnouncementsScreen> {
  final AnnouncementService _announcementService = AnnouncementService();
  final ClassService _classService = ClassService();

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _filteredAnnouncements = [];
  
  bool _isLoading = true;
  bool _isLoadingStudents = false;
  
  // Form State
  String _targetType = 'class'; // 'class', 'individual', 'low_attendance'
  final List<String> _targetTypes = ['class', 'individual', 'low_attendance'];
  int _selectedTabIndex = 0;
  
  int? _selectedClassId;
  int? _selectedStudentId;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  bool _isUrgent = false;
  double _attendanceThreshold = 75.0;
  int _lowAttendanceCount = 0;
  bool _isCheckingLowAttendance = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    
    try {
      final classes = await _classService.getMyClasses();
      final announcements = await _announcementService.getAnnouncements();
      
      setState(() {
        _classes = classes;
        _announcements = announcements;
        _filteredAnnouncements = announcements;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadStudents(int classId) async {
    setState(() => _isLoadingStudents = true);
    try {
      final students = await _classService.getClassStudents(classId);
      setState(() {
        _students = students;
        _selectedStudentId = null;
      });
      if (_targetType == 'low_attendance') {
        _checkLowAttendance(classId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading students: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingStudents = false);
      }
    }
  }

  Future<void> _checkLowAttendance(int classId) async {
    if (!mounted) return;
    setState(() => _isCheckingLowAttendance = true);
    try {
      final result = await _announcementService.getLowAttendanceStudents(classId, threshold: _attendanceThreshold);
      if (!mounted) return;
      setState(() {
        _lowAttendanceCount = (result['count'] ?? result['total'] ?? 0) as int;
      });
    } catch (e) {
      print('Error checking low attendance: $e');
    } finally {
      if (mounted) setState(() => _isCheckingLowAttendance = false);
    }
  }

  void _filterAnnouncements(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredAnnouncements = _announcements;
      } else {
        _filteredAnnouncements = _announcements.where((a) {
          final message = (a['message'] ?? '').toLowerCase();
          final className = (a['target_class_name'] ?? '').toLowerCase();
          return message.contains(query.toLowerCase()) || className.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Future<void> _sendAnnouncement() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a class')),
      );
      return;
    }
    
    if (_targetType == 'individual' && _selectedStudentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a student')),
      );
      return;
    }
    
    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message')),
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final result = await _announcementService.createAnnouncement(
      targetType: _targetType,
      targetClassId: _selectedClassId,
      targetStudentId: _selectedStudentId,
      message: _messageController.text.trim(),
      isUrgent: _isUrgent,
      attendanceThreshold: _attendanceThreshold,
    );

    // Hide loading
    if (mounted) Navigator.pop(context);

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement sent successfully!')),
      );
      _messageController.clear();
      setState(() {
        _isUrgent = false;
      });
      _loadInitialData(); // Refresh list
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Failed to send announcement')),
      );
    }
  }

  Future<void> _deleteAnnouncement(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Announcement'),
        content: const Text('Are you sure you want to delete this announcement?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await _announcementService.deleteAnnouncement(id);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement deleted')),
      );
      _loadInitialData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete announcement')),
      );
    }
  }

  Future<void> _editAnnouncement(Map<String, dynamic> announcement) async {
    final TextEditingController editController = TextEditingController(text: announcement['message']);
    bool editIsUrgent = announcement['is_urgent'] ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Edit Announcement'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: editController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Edit message...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Mark as urgent'),
                      activeColor: const Color(0xFF0097A7),
                      value: editIsUrgent,
                      onChanged: (val) {
                        setStateDialog(() => editIsUrgent = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0097A7),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          }
        );
      },
    );

    if (result == true) {
      final success = await _announcementService.updateAnnouncement(
        id: announcement['id'],
        message: editController.text.trim(),
        isUrgent: editIsUrgent,
      );
      if (success['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Announcement updated')),
        );
        _loadInitialData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success['message'] ?? 'Failed to update announcement')),
        );
      }
    }
  }

  String _getTimeAgo(String? timestamp) {
    if (timestamp == null) return 'Unknown time';
    final DateTime time = DateTime.parse(timestamp);
    final Duration diff = DateTime.now().difference(time);
    if (diff.inDays > 0) {
      return '${diff.inDays} days ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} hours ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }

  String _getInitials(String? name) {
    if (name == null || name.isEmpty) return 'T';
    final parts = name.split(' ');
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  Widget _buildLeftPanel() {
    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New Announcement',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 24),
            // Toggle Buttons
            Center(
              child: ToggleButtons(
                isSelected: [
                  _selectedTabIndex == 0,
                  _selectedTabIndex == 1,
                  _selectedTabIndex == 2,
                ],
                onPressed: (index) {
                  setState(() {
                    _selectedTabIndex = index;
                    _targetType = _targetTypes[index];
                  });
                  // Trigger low-attendance check AFTER setState so _targetType is updated
                  if (_targetTypes[index] == 'low_attendance' && _selectedClassId != null) {
                    _checkLowAttendance(_selectedClassId!);
                  }
                },
                color: Colors.grey[600],
                selectedColor: Colors.white,
                fillColor: const Color(0xFF0097A7),
                borderRadius: BorderRadius.circular(8),
                constraints: const BoxConstraints(minHeight: 40, minWidth: 100),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Class')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Individual')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Low Attendance')),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Class Dropdown
            DropdownButtonFormField<int>(
              decoration: InputDecoration(
                labelText: 'Select Class',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              value: _selectedClassId,
              items: _classes.map((c) {
                final className = c['class_name'] ?? c['name'] ?? '';
                final classCode = c['class_code'] ?? '';
                final semester = c['semester'] != null ? ' - ${c['semester']}' : '';
                final display = classCode.isNotEmpty ? '[$classCode] $className$semester' : '$className$semester';
                return DropdownMenuItem<int>(
                  value: c['id'],
                  child: Text(display),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedClassId = val;
                  _lowAttendanceCount = 0; // reset while loading
                });
                if (val != null) {
                  _loadStudents(val);
                  // If already on low_attendance tab, immediately fetch the count
                  if (_targetType == 'low_attendance') {
                    _checkLowAttendance(val);
                  }
                }
              },
            ),
            const SizedBox(height: 16),
            // Student Dropdown (if individual)
            if (_targetType == 'individual')
              _isLoadingStudents
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: 'Select Student',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      value: _selectedStudentId,
                      items: _students.map((s) {
                        final firstName = s['first_name'] ?? '';
                        final lastName = s['last_name'] ?? '';
                        final rollNo = s['roll_no'] ?? 'N/A';
                        final username = s['username'] ?? 'Student';
                        final displayName = (firstName.isNotEmpty || lastName.isNotEmpty)
                            ? '$firstName $lastName'.trim()
                            : username;
                        return DropdownMenuItem<int>(
                          value: s['id'],
                          child: Text('$displayName ($rollNo)'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedStudentId = val;
                        });
                      },
                    ),
            // Low attendance preview
            if (_targetType == 'low_attendance' && _selectedClassId != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Threshold: ${_attendanceThreshold.toInt()}%'),
                    Slider(
                      value: _attendanceThreshold,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      activeColor: Colors.orange,
                      label: '${_attendanceThreshold.toInt()}%',
                      onChanged: (val) {
                        setState(() {
                          _attendanceThreshold = val;
                        });
                      },
                      onChangeEnd: (val) {
                        if (_selectedClassId != null) {
                          _checkLowAttendance(_selectedClassId!);
                        }
                      },
                    ),
                    _isCheckingLowAttendance
                        ? const Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('Calculating...'),
                            ],
                          )
                        : Text(
                            '$_lowAttendanceCount student${_lowAttendanceCount == 1 ? '' : 's'} found below ${_attendanceThreshold.toInt()}% attendance.',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _lowAttendanceCount > 0 ? Colors.orange.shade800 : Colors.grey[600],
                            ),
                          ),
                  ],
                ),
              ),
            if (_targetType != 'low_attendance') const SizedBox(height: 16),
            // Message Field
            TextField(
              controller: _messageController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Write what students or class needs to know...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            // Urgent Toggle
            SwitchListTile(
              title: const Text('Mark as urgent'),
              activeColor: const Color(0xFF0097A7),
              contentPadding: EdgeInsets.zero,
              value: _isUrgent,
              onChanged: (val) {
                setState(() {
                  _isUrgent = val;
                });
              },
            ),
            const SizedBox(height: 24),
            // Send Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _sendAnnouncement,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0097A7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Send Announcement', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Announcements',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_horiz),
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Search Bar
        TextField(
          controller: _searchController,
          onChanged: _filterAnnouncements,
          decoration: InputDecoration(
            hintText: 'Search announcements...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // List View
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredAnnouncements.isEmpty
                  ? Center(
                      child: Text(
                        'No announcements found',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredAnnouncements.length,
                      itemBuilder: (context, index) {
                        final announcement = _filteredAnnouncements[index];
                        final isUrgent = announcement['is_urgent'] == true;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 1,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: isUrgent
                                ? const BorderSide(color: Colors.red, width: 1)
                                : BorderSide.none,
                          ),
                          child: InkWell(
                            onLongPress: () {
                              _deleteAnnouncement(announcement['id']);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.red.shade700,
                                    child: Text(
                                      _getInitials(announcement['teacher_name'] ?? 'Me'),
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              announcement['teacher_name'] ?? 'Me',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            Text(
                                              _getTimeAgo(announcement['created_at']),
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          announcement['target_class_name'] ?? 'Target: ${announcement['target_type']}',
                                          style: TextStyle(
                                            color: const Color(0xFF0097A7),
                                            fontWeight: FontWeight.w500,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          announcement['message'] ?? '',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Color(0xFF1F2937)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (val) {
                                      if (val == 'edit') {
                                        _editAnnouncement(announcement);
                                      } else if (val == 'delete') {
                                        _deleteAnnouncement(announcement['id']);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Announcements'),
            Text(
              "Send updates to a full class or a single student, and track what's already gone out.",
              style: TextStyle(fontSize: 12, color: Colors.grey[200]),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0097A7),
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 800) {
            // Desktop/Tablet layout
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: SingleChildScrollView(child: _buildLeftPanel()),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 1,
                    child: _buildRightPanel(),
                  ),
                ],
              ),
            );
          } else {
            // Mobile layout
            return DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    labelColor: Color(0xFF0097A7),
                    indicatorColor: Color(0xFF0097A7),
                    tabs: [
                      Tab(text: 'New'),
                      Tab(text: 'Recent'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16.0),
                          child: _buildLeftPanel(),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: _buildRightPanel(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}
