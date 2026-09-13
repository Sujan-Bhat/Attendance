import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/dashboard/student_dashboard.dart';
import '../screens/student/my_classes_screen.dart';
import '../screens/student/qr_scanner_screen.dart';
import '../screens/student/pattern_sessions_screen.dart';
import '../screens/student/attendance_history_screen.dart';
import '../screens/student/student_profile_screen.dart';
import '../screens/common/ble_test_screen.dart';
import '../services/auth_service.dart';

class StudentDrawer extends StatefulWidget {
  final String currentRoute;

  const StudentDrawer({Key? key, required this.currentRoute}) : super(key: key);

  @override
  _StudentDrawerState createState() => _StudentDrawerState();
}

class _StudentDrawerState extends State<StudentDrawer> {
  String studentName = 'Loading...';
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
          studentName = user?['first_name'] ?? 'Student';
          username = user?['username'] ?? 'student';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          studentName = 'Student';
          username = 'student';
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

  void _handleCardTap(String title) {
    if (title == widget.currentRoute)
      return; // Do nothing if already on the route

    Widget? nextScreen;
    switch (title) {
      case 'Dashboard':
        nextScreen = const StudentDashboardPage();
        break;
      case 'My Classes':
        nextScreen = const StudentMyClassesScreen();
        break;
      case 'Scan QR':
        nextScreen = const QRScannerScreen();
        break;
      case 'Attendance History':
        nextScreen = const AttendanceHistoryScreen();
        break;
      case 'Profile':
        nextScreen = const StudentProfileScreen();
        break;
      case 'BLE Test':
        nextScreen = const BleTestScreen();
        break;
    }

    if (nextScreen != null) {
      if (title == 'Dashboard') {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => nextScreen!),
          (route) => false,
        );
      } else {
        // Pop back to the Dashboard (first route) to clear current screens like QR Scanner
        Navigator.of(context).popUntil((route) => route.isFirst);
        // Push the new screen on top of the Dashboard
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => nextScreen!),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboardCards = [
      {'title': 'Dashboard', 'icon': Icons.dashboard},
      {'title': 'My Classes', 'icon': Icons.class_rounded},
      {'title': 'Scan QR', 'icon': Icons.qr_code_scanner_rounded},
      {'title': 'Attendance History', 'icon': Icons.history_rounded},
      {'title': 'Profile', 'icon': Icons.person_rounded},
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
                      Icons.school,
                      size: 35,
                      color: Color(0xFF007C91),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    studentName,
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
