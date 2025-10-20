import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../widgets/magical_dashboard_card.dart';

class StudentDashboardPage extends StatefulWidget {
  const StudentDashboardPage({super.key});

  @override
  State<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends State<StudentDashboardPage> {
  final AuthService _authService = AuthService();
  bool isSidebarExpanded = false;
  String studentName = "Loading...";
  String username = "";
  bool isLoading = true;

  final List<Map<String, dynamic>> dashboardCards = [
    {
      'title': 'My Classes',
      'subtitle': 'View your enrolled classes',
      'icon': Icons.class_rounded,
      'color': Colors.teal,
    },
    {
      'title': 'Assignments',
      'subtitle': 'Check pending homework',
      'icon': Icons.assignment_rounded,
      'color': Colors.orange,
    },
    {
      'title': 'My Attendance Analysis',
      'subtitle': 'Track your attendance record',
      'icon': Icons.grade_rounded,
      'color': Colors.cyan,
    },
    {
      'title': 'Attendance',
      'subtitle': 'See attendance history',
      'icon': Icons.check_circle_rounded,
      'color': Colors.green,
    },
    {
      'title': 'Announcements',
      'subtitle': 'Latest updates from teachers',
      'icon': Icons.announcement_rounded,
      'color': Colors.purple,
    },
    {
      'title': 'Resources',
      'subtitle': 'Download study materials',
      'icon': Icons.folder_rounded,
      'color': Colors.indigo,
    },
    {
      'title': 'Profile',
      'subtitle': 'Edit your info & settings',
      'icon': Icons.person_rounded,
      'color': Colors.blueGrey,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user != null && mounted) {
        setState(() {
          studentName = user['name'] ?? user['username'] ?? 'Student';
          username = user['username'] ?? '';
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          studentName = 'Student';
          isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _authService.logout();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenW = MediaQuery.of(context).size.width;

    int crossAxisCount;
    if (screenW < 600) {
      crossAxisCount = 1;
    } else if (screenW < 1000) {
      crossAxisCount = 2;
    } else {
      crossAxisCount = 3;
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top AppBar (dark cyan gradient)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF007C91), Color(0xFF0097A7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
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
                  const Icon(Icons.school_rounded, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Student Dashboard',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                        if (!isLoading)
                          Text(
                            'Welcome, $studentName',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Logout button
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Colors.white),
                    onPressed: _logout,
                    tooltip: 'Logout',
                  ),
                ],
              ),
            ),

            Expanded(
              child: Row(
                children: [
                  // Sidebar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: isSidebarExpanded ? 200 : 70,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E1E2C),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(2, 0),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 14),
                        IconButton(
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: isSidebarExpanded
                                ? const Icon(Icons.arrow_back_ios_new_rounded,
                                    color: Colors.white, key: ValueKey(1))
                                : const Icon(Icons.menu_rounded,
                                    color: Colors.white, key: ValueKey(2)),
                          ),
                          onPressed: () =>
                              setState(() => isSidebarExpanded = !isSidebarExpanded),
                        ),
                        const SizedBox(height: 24),
                        Expanded(
                          child: ListView(
                            children: [
                              _buildSidebarItem(Icons.dashboard, 'Dashboard'),
                              _buildSidebarItem(Icons.class_, 'My Classes'),
                              _buildSidebarItem(Icons.assignment, 'Assignments'),
                              _buildSidebarItem(Icons.grade, 'Analysis'),
                              _buildSidebarItem(Icons.settings, 'Settings'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Main body
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Overview',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 18),

                            GridView.builder(
                              itemCount: dashboardCards.length,
                              physics: const NeverScrollableScrollPhysics(),
                              shrinkWrap: true,
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 18,
                                crossAxisSpacing: 18,
                                childAspectRatio: (screenW < 600) ? 1.05 : 1.25,
                              ),
                              itemBuilder: (context, idx) {
                                final card = dashboardCards[idx];
                                return MagicalDashboardCard(
                                  title: card['title'] as String,
                                  subtitle: card['subtitle'] as String,
                                  icon: card['icon'] as IconData,
                                  color: card['color'] as Color,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: isSidebarExpanded
          ? Text(title, style: const TextStyle(color: Colors.white))
          : null,
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title clicked'),
            duration: const Duration(milliseconds: 800),
          ),
        );
      },
    );
  }
}