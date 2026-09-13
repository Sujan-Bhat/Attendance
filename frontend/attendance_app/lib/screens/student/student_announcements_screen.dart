import 'package:flutter/material.dart';
import '../../services/announcement_service.dart';

class StudentAnnouncementsScreen extends StatefulWidget {
  const StudentAnnouncementsScreen({super.key});

  @override
  State<StudentAnnouncementsScreen> createState() => _StudentAnnouncementsScreenState();
}

class _StudentAnnouncementsScreenState extends State<StudentAnnouncementsScreen> {
  final AnnouncementService _announcementService = AnnouncementService();
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _filteredAnnouncements = [];
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  String _filterType = 'All'; // 'All', 'class', 'individual', 'Urgent'

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
    _searchController.addListener(_filterList);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAnnouncements() async {
    setState(() => _isLoading = true);
    try {
      final announcements = await _announcementService.getAnnouncements();
      setState(() {
        _announcements = announcements;
        _filteredAnnouncements = announcements;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading announcements: $e'), backgroundColor: Colors.red),
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
          matchesFilter = ann['target_type'] == 'class' || ann['target_type'] == 'low_attendance';
        } else if (_filterType == 'individual') {
          matchesFilter = ann['target_type'] == 'individual';
        } else if (_filterType == 'Urgent') {
          matchesFilter = ann['is_urgent'] == true;
        }

        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Announcements'),
            const Text(
              "Stay updated with recent news from your teachers.",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E5B53),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnnouncements,
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFFF4EDDC),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Search & Filter Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search notices...',
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
                      items: ['All', 'class', 'individual', 'Urgent'].map((String val) {
                        return DropdownMenuItem<String>(
                          value: val,
                          child: Text(
                            val == 'class' ? 'Class' : val == 'individual' ? 'Private' : val,
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

              // Announcements list
              Expanded(
                child: _isLoading
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
        ),
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
      tagLabel = 'Attendance Notice';
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
                backgroundColor: const Color(0xFFB03A2E),
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
            ],
          ),
          const SizedBox(height: 12),
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
