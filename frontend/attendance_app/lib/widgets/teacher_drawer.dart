import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/dashboard/teacher_dashboard_mobile.dart';
import '../screens/teacher/my_classes_screen.dart';
import '../screens/teacher/session_create_screen.dart';
import '../screens/teacher/teacher_attendance_history_screen.dart';
import '../screens/teacher/teacher_profile_screen.dart';
import '../screens/common/ble_test_screen.dart';
import '../services/auth_service.dart';
import '../services/class_service.dart';

class TeacherDrawer extends StatefulWidget {
  final String currentRoute;

  const TeacherDrawer({Key? key, required this.currentRoute}) : super(key: key);

  @override
  _TeacherDrawerState createState() => _TeacherDrawerState();
}

class _TeacherDrawerState extends State<TeacherDrawer> {
  String teacherName = 'Loading...';
  String username = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final authService = AuthService();
      final user = await authService.getCurrentUser();
      if (mounted) {
        setState(() {
          teacherName = user?['first_name'] ?? 'Teacher';
          username = user?['username'] ?? 'teacher';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          teacherName = 'Teacher';
          username = 'teacher';
        });
      }
    }
  }

  void _logout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final authService = AuthService();
    await authService.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  void _handleCardTap(String title) async {
    if (title == widget.currentRoute)
      return; // Do nothing if already on the route

    if (title == 'Create Session') {
      final classService = ClassService();
      try {
        final classes = await classService.getMyClasses();
        if (classes.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No classes found. Please create a class first.'),
              ),
            );
          }
          return;
        }

        final subjects = classes
            .map(
              (c) => {
                'id': c['id'].toString(),
                'code': c['class_code'] as String,
                'name': c['class_name'] as String,
                'semester': c['semester'] as String,
              },
            )
            .toList();

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SessionPage(subjects: subjects),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error loading classes: $e')));
        }
      }
      return;
    }

    Widget? nextScreen;
    switch (title) {
      case 'Dashboard':
        nextScreen = const TeacherDashboardMobile();
        break;
      case 'My Classes':
        nextScreen = const MyClassesScreen();
        break;
      case 'Attendance History':
        nextScreen = const TeacherAttendanceHistoryScreen();
        break;
      case 'Profile':
        nextScreen = const TeacherProfileScreen();
        break;
      case 'BLE Test':
        nextScreen = const BleTestScreen();
        break;
    }

    if (nextScreen != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => nextScreen!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboardCards = [
      {'title': 'Dashboard', 'icon': Icons.dashboard},
      {'title': 'My Classes', 'icon': Icons.people},
      {'title': 'Create Session', 'icon': Icons.timer},
      {'title': 'Attendance History', 'icon': Icons.history},
      {'title': 'Profile', 'icon': Icons.person},
      {'title': 'BLE Test', 'icon': Icons.bluetooth_audio},
    ];

    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E1E2C), Color(0xFF2D2D44)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF007C91), Color(0xFF0097A7)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: 35,
                      color: Color(0xFF007C91),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    teacherName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@$username',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ...dashboardCards.map(
              (card) => _buildDrawerItem(
                card['icon'] as IconData,
                card['title'] as String,
              ),
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white70),
              title: const Text(
                'Logout',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title) {
    final isSelected = title == widget.currentRoute;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.white : Colors.white70),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: Colors.white.withOpacity(0.1),
      onTap: () {
        Navigator.pop(context); // Close drawer
        _handleCardTap(title);
      },
    );
  }
}
