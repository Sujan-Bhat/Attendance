import 'package:flutter/material.dart';
import '../../services/announcement_service.dart';
import '../../services/class_service.dart';

class TeacherAnnouncementsScreen extends StatefulWidget {
  const TeacherAnnouncementsScreen({super.key});

  @override
  State<TeacherAnnouncementsScreen> createState() => _TeacherAnnouncementsScreenState();
}

class _TeacherAnnouncementsScreenState extends State<TeacherAnnouncementsScreen> {
  final AnnouncementService _announcementService = AnnouncementService();
  final ClassService _classService = ClassService();

  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _filteredAnnouncements = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _students = [];

  bool _isLoadingAnnouncements = true;
  bool _isLoadingClasses = true;
  bool _isLoadingStudents = false;
  bool _isSending = false;

  // Form Fields
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  
  String _targetType = 'class'; // 'class', 'individual', 'low_attendance'
  int? _selectedClassId;
  int? _selectedStudentId;
  int _minAttendanceThreshold = 75;
  bool _isUrgent = false;

  String _filterType = 'All'; // 'All', 'class', 'individual', 'low_attendance', 'Urgent'

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterList);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoadingAnnouncements = true;
      _isLoadingClasses = true;
    });

    try {
      final announcements = await _announcementService.getAnnouncements();
      final classes = await _classService.getMyClasses();

      setState(() {
        _announcements = announcements;
        _filteredAnnouncements = announcements;
        _classes = classes;
        _isLoadingAnnouncements = false;
        _isLoadingClasses = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingAnnouncements = false;
        _isLoadingClasses = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadStudents(int classId) async {
    setState(() {
      _isLoadingStudents = true;
      _students = [];
      _selectedStudentId = null;
    });

    try {
      final students = await _classService.getClassStudents(classId);
      setState(() {
        _students = students;
        _isLoadingStudents = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingStudents = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading students: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _filterList() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredAnnouncements = _announcements.where((ann) {
        final matchesSearch = ann['title'].toString().toLowerCase().contains(query) ||
            ann['content'].toString().toLowerCase().contains(query);
        
        bool matchesFilter = true;
        if (_filterType == 'class') {
          matchesFilter = ann['target_type'] == 'class';
        } else if (_filterType == 'individual') {
          matchesFilter = ann['target_type'] == 'individual';
        } else if (_filterType == 'low_attendance') {
          matchesFilter = ann['target_type'] == 'low_attendance';
        } else if (_filterType == 'Urgent') {
          matchesFilter = ann['is_urgent'] == true;
        }

        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  Future<void> _sendAnnouncement() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a class'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (_targetType == 'individual' && _selectedStudentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a student'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final result = await _announcementService.createAnnouncement(
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        targetType: _targetType,
        targetClassId: _selectedClassId,
        targetStudentId: _selectedStudentId,
        minAttendanceThreshold: _targetType == 'low_attendance' ? _minAttendanceThreshold : null,
        isUrgent: _isUrgent,
      );

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Announcement sent successfully!'), backgroundColor: Colors.green),
        );
        _titleController.clear();
        _contentController.clear();
        setState(() {
          _isUrgent = false;
          _selectedStudentId = null;
        });
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Failed to send announcement'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _deleteAnnouncement(int id) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Announcement'),
        content: const Text('Are you sure you want to delete this announcement?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoadingAnnouncements = true);
    final success = await _announcementService.deleteAnnouncement(id);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted successfully'), backgroundColor: Colors.green));
      _loadData();
    } else {
      setState(() => _isLoadingAnnouncements = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete'), backgroundColor: Colors.red));
    }
  }

  void _editAnnouncement(Map<String, dynamic> ann) {
    final titleController = TextEditingController(text: ann['title'] ?? '');
    final contentController = TextEditingController(text: ann['content'] ?? '');
    bool isUrgent = ann['is_urgent'] ?? false;

    showDialog(
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
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: contentController,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Urgent'),
                      value: isUrgent,
                      onChanged: (val) => setStateDialog(() => isUrgent = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    setState(() => _isLoadingAnnouncements = true);
                    final result = await _announcementService.updateAnnouncement(
                      id: ann['id'],
                      title: titleController.text.trim(),
                      content: contentController.text.trim(),
                      isUrgent: isUrgent,
                    );
                    if (result['success'] == true) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated successfully'), backgroundColor: Colors.green));
                      _loadData();
                    } else {
                      setState(() => _isLoadingAnnouncements = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Failed to update'), backgroundColor: Colors.red));
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E5B53), foregroundColor: Colors.white),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isWideScreen = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Announcements'),
            const Text(
              "Send updates to a full class or a single student, and track what's already gone out.",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E5B53),
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: const Color(0xFFF4EDDC),
        child: isWideScreen
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(child: _buildComposerCard()),
                  ),
                  Expanded(flex: 3, child: _buildRecentList()),
                ],
              )
            : _buildMobileLayout(),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF4EDDC),
            child: const TabBar(
              labelColor: Color(0xFF1E5B53),
              indicatorColor: Color(0xFF1E5B53),
              tabs: [
                Tab(icon: Icon(Icons.send_rounded), text: 'New Announcement'),
                Tab(icon: Icon(Icons.history_rounded), text: 'Recent'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                SingleChildScrollView(child: _buildComposerCard()),
                _buildRecentList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposerCard() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'New Announcement',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 20),
            
            // Target buttons (Segmented Control)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: Row(
                children: [
                  _buildTargetButton('Class', 'class', true, false),
                  _buildTargetButton('Individual', 'individual', false, false),
                  _buildTargetButton('Low Attendance', 'low_attendance', false, true),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Class Dropdown
            _isLoadingClasses
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<int>(
                    decoration: InputDecoration(
                      labelText: 'Select Class',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF1E5B53)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black54),
                      ),
                    ),
                    value: _selectedClassId,
                    items: _classes.map((c) {
                      return DropdownMenuItem<int>(
                        value: c['id'],
                        child: Text('${c['class_code'] != null ? '[${c['class_code']}] ' : ''}${c['class_name']}'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedClassId = val;
                      });
                      if (val != null && _targetType == 'individual') {
                        _loadStudents(val);
                      }
                    },
                    validator: (val) => val == null ? 'Please select a class' : null,
                  ),
            const SizedBox(height: 16),

            // Student Dropdown (Only visible if individual)
            if (_targetType == 'individual') ...[
              if (_isLoadingStudents)
                const Center(child: CircularProgressIndicator())
              else if (_selectedClassId == null)
                const Text('Select a class first to list students', style: TextStyle(color: Colors.grey))
              else if (_students.isEmpty)
                const Text('No students enrolled in this class', style: TextStyle(color: Colors.grey))
              else
                DropdownButtonFormField<int>(
                  decoration: InputDecoration(
                    labelText: 'Select Student',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1E5B53)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black54),
                    ),
                  ),
                  value: _selectedStudentId,
                  items: _students.map((s) {
                    return DropdownMenuItem<int>(
                      value: s['id'],
                      child: Text(s['username'] ?? s['email'] ?? ''),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedStudentId = val;
                    });
                  },
                  validator: (val) => val == null ? 'Please select a student' : null,
                ),
              const SizedBox(height: 16),
            ],

            // Low Attendance Threshold Slider (Only visible if low_attendance)
            if (_targetType == 'low_attendance') ...[
              Text(
                'Minimum Attendance: $_minAttendanceThreshold%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Slider(
                value: _minAttendanceThreshold.toDouble(),
                min: 10,
                max: 100,
                divisions: 18,
                activeColor: const Color(0xFF1E5B53),
                label: '$_minAttendanceThreshold%',
                onChanged: (double val) {
                  setState(() {
                    _minAttendanceThreshold = val.round();
                  });
                },
              ),
              const SizedBox(height: 16),
            ],

            // Title Field (Optional, hide if you want to match exactly, but let's keep it styled)
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black54),
                ),
              ),
              validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a title' : null,
            ),
            const SizedBox(height: 16),

            // Message Field
            TextFormField(
              controller: _contentController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Write what students or class needs to know...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black54),
                ),
              ),
              validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a message' : null,
            ),
            const SizedBox(height: 16),

            // Mark as urgent
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mark as urgent'),
              value: _isUrgent,
              activeColor: const Color(0xFF1E5B53),
              onChanged: (val) {
                setState(() => _isUrgent = val);
              },
            ),
            const SizedBox(height: 16),

            // Send button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSending ? null : _sendAnnouncement,
                icon: _isSending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                label: const Text('Send Announcement', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E5B53),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetButton(String label, String type, bool isFirst, bool isLast) {
    final bool isSelected = _targetType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _targetType = type;
            if (type != 'individual') {
              _students = [];
              _selectedStudentId = null;
            } else if (_selectedClassId != null) {
              _loadStudents(_selectedClassId!);
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E5B53) : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: isFirst ? const Radius.circular(25) : Radius.zero,
              right: isLast ? const Radius.circular(25) : Radius.zero,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentList() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Announcements', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          // Filter & Search bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search announcements...',
                    prefixIcon: const Icon(Icons.search),
                    fillColor: const Color(0xFFF4EDDC),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black54),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black54),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4EDDC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black54),
                ),
                child: DropdownButton<String>(
                  value: _filterType,
                  underline: const SizedBox(),
                  items: ['All', 'class', 'individual', 'low_attendance', 'Urgent'].map((String val) {
                    return DropdownMenuItem<String>(
                      value: val,
                      child: Text(
                        val == 'class' ? 'Class' : val == 'individual' ? 'Private' : val == 'low_attendance' ? 'Low Attend.' : val,
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _filterType = val;
                      });
                      _filterList();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          Expanded(
            child: _isLoadingAnnouncements
                ? const Center(child: CircularProgressIndicator())
                : _filteredAnnouncements.isEmpty
                    ? const Center(child: Text('No announcements found.'))
                    : ListView.builder(
                        itemCount: _filteredAnnouncements.length,
                        itemBuilder: (context, index) {
                          final ann = _filteredAnnouncements[index];
                          return _buildAnnouncementCard(ann);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard(Map<String, dynamic> ann) {
    final String senderName = ann['sender_name'] ?? 'Teacher';
    final String initial = senderName.isNotEmpty ? senderName[0].toUpperCase() : 'T';
    
    // Tag UI
    String tagLabel = 'Class';
    if (ann['target_type'] == 'individual') {
      tagLabel = 'Private';
    } else if (ann['target_type'] == 'low_attendance') {
      tagLabel = 'Low Attendance';
    } else if (ann['class_name'] != null) {
      tagLabel = ann['class_name'];
    } else if (ann['class_code'] != null) {
      tagLabel = ann['class_code'];
    }

    final bool isUrgent = ann['is_urgent'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF0E0C1), // Slightly darker beige card color
        borderRadius: BorderRadius.circular(16),
        border: isUrgent ? Border.all(color: Colors.red, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFB03A2E), // Red avatar background
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
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
                        Text(
                          senderName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        if (isUrgent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                            child: const Text('URGENT', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ]
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tagLabel,
                      style: const TextStyle(color: Color(0xFF2C7A7B), fontSize: 13),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _editAnnouncement(ann);
                  } else if (value == 'delete') {
                    _deleteAnnouncement(ann['id']);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // We can optionally show the title here if it exists. The image shows the message directly.
          if (ann['title'] != null && ann['title'].toString().isNotEmpty) ...[
            Text(
              ann['title'],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            ann['content'] ?? '',
            style: const TextStyle(color: Colors.black87, height: 1.3),
          ),
          const SizedBox(height: 8),
          Text(
            ann['created_at'] != null
                ? DateTime.parse(ann['created_at']).toLocal().toString().substring(0, 16)
                : '',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
      ),
    );
  }
}