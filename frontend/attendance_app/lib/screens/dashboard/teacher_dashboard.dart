import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../widgets/magical_dashboard_card.dart';

class TeacherDashboardPage extends StatefulWidget {
  const TeacherDashboardPage({super.key});

  @override
  State<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends State<TeacherDashboardPage> {
  final AuthService _authService = AuthService();
  bool isSidebarExpanded = false;
  String teacherName = "Loading...";
  String username = "";
  bool isLoading = true;

  final List<Map<String, dynamic>> dashboardCards = [
    {
      'title': 'Class Insights',
      'subtitle': 'Track attendance patterns',
      'icon': Icons.bar_chart_rounded,
      'color': Colors.cyan,
    },
    {
      'title': 'My Classes',
      'subtitle': 'Manage and monitor classes',
      'icon': Icons.people_alt_rounded,
      'color': Colors.green,
    },
    {
      'title': 'Create Session',
      'subtitle': 'Start new attendance session',
      'icon': Icons.timer_rounded,
      'color': Colors.orange,
    },
    {
      'title': 'Announcements',
      'subtitle': 'Share updates with students',
      'icon': Icons.chat_rounded,
      'color': Colors.purple,
    },
    {
      'title': 'Reports Export',
      'subtitle': 'Generate class reports',
      'icon': Icons.file_download_rounded,
      'color': Colors.indigo,
    },
    {
      'title': 'Attendance',
      'subtitle': 'Mark and review attendance',
      'icon': Icons.check_circle_rounded,
      'color': Colors.teal,
    },
    {
      'title': 'Resources',
      'subtitle': 'Upload materials',
      'icon': Icons.folder_rounded,
      'color': Colors.deepOrange,
    },
    {
      'title': 'Settings',
      'subtitle': 'App preferences',
      'icon': Icons.settings_rounded,
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
          teacherName = user['name'] ?? user['username'] ?? 'Teacher';
          username = user['username'] ?? '';
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          teacherName = 'Teacher';
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
            // Top gradient app bar
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
                          'Teacher Dashboard',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                        if (!isLoading)
                          Text(
                            'Welcome, $teacherName',
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

            // Body
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
                              _buildSidebarItem(Icons.people, 'My Classes'),
                              _buildSidebarItem(Icons.analytics, 'Analysis'),
                              _buildSidebarItem(Icons.announcement, 'Announcements'),
                              _buildSidebarItem(Icons.settings, 'Settings'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Main area
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

                            // Grid of dashboard cards
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