import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';  
import '../../widgets/magical_dashboard_card.dart';
import '../teacher/my_classes_screen.dart';
import '../teacher/session_create_screen.dart';

class TeacherDashboardPage extends StatefulWidget {
  const TeacherDashboardPage({super.key});

  @override
  State<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends State<TeacherDashboardPage> {
  final AuthService _authService = AuthService();
  final ClassService _classService = ClassService();
  
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

  void _handleCardTap(String title) async {
    switch (title) {
      case 'Create Session':
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );

        final classes = await _classService.getMyClasses();
        
        if (mounted) Navigator.pop(context);

        if (classes.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.warning_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('No classes found. Please create a class first.'),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange.shade600,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
                action: SnackBarAction(
                  label: 'Create Class',
                  textColor: Colors.white,
                  onPressed: () => Navigator.pushNamed(context, '/teacher/my-classes'),
                ),
              ),
            );
          }
          return;
        }

        final subjects = classes.map((classData) {
          return {
            'id': classData['id'].toString(),
            'code': classData['class_code'] as String,
            'name': classData['class_name'] as String,
            'semester': classData['semester'] as String,
          };
        }).toList();

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => SessionPage(subjects: subjects)),
          );
        }
        break;

      case 'My Classes':
        Navigator.pushNamed(context, '/teacher/my-classes');
        break;

      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title - Coming soon!')),
        );
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    //  RESPONSIVE BREAKPOINTS
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    
    final isMobile = screenW < 600;
    final isTablet = screenW >= 600 && screenW < 1024;
    final isDesktop = screenW >= 1024;
    
    // ADAPTIVE GRID COLUMNS
    final crossAxisCount = isMobile ? 1 : (isTablet ? 2 : (screenW < 1400 ? 3 : 4));
    
    //  ADAPTIVE SPACING
    final cardPadding = isMobile ? 12.0 : (isTablet ? 16.0 : 20.0);
    final gridSpacing = isMobile ? 12.0 : (isTablet ? 16.0 : 18.0);
    
    // ADAPTIVE SIDEBAR
    final sidebarWidth = isMobile ? 0.0 : (isSidebarExpanded ? 200.0 : 70.0);
    
    // ADAPTIVE ASPECT RATIO
    final cardAspectRatio = isMobile ? 1.4 : (isTablet ? 1.15 : 1.25);

    return Scaffold(
      // MOBILE: Drawer instead of sidebar
      drawer: isMobile
          ? Drawer(
              child: Container(
                color: const Color(0xFF1E1E2C),
                child: ListView(
                  padding: EdgeInsets.zero,
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
                          const Icon(Icons.school_rounded, color: Colors.white, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            teacherName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            username,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    _buildSidebarItem(Icons.dashboard, 'Dashboard', isMobile: true),
                    _buildSidebarItem(Icons.people, 'My Classes', isMobile: true),
                    _buildSidebarItem(Icons.analytics, 'Analysis', isMobile: true),
                    _buildSidebarItem(Icons.announcement, 'Announcements', isMobile: true),
                    _buildSidebarItem(Icons.settings, 'Settings', isMobile: true),
                    const Divider(color: Colors.white24),
                    ListTile(
                      leading: const Icon(Icons.logout_rounded, color: Colors.white70),
                      title: const Text('Logout', style: TextStyle(color: Colors.white)),
                      onTap: _logout,
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 20,
                vertical: isMobile ? 10 : 14,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF007C91), Color(0xFF0097A7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  // MOBILE: Show menu icon for drawer
                  if (isMobile)
                    Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.menu_rounded, color: Colors.white),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    )
                  else
                    Icon(Icons.school_rounded, color: Colors.white, size: isMobile ? 24 : 28),
                  
                  SizedBox(width: isMobile ? 8 : 12),
                  
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Teacher Dashboard',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 18 : 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                        if (!isLoading && !isMobile)
                          Text(
                            'Welcome, $teacherName',
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                      ],
                    ),
                  ),
                  
                  // DESKTOP: Show logout button
                  if (!isMobile)
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, color: Colors.white),
                      onPressed: _logout,
                      tooltip: 'Logout',
                    ),
                ],
              ),
            ),

            // BODY WITH CONDITIONAL SIDEBAR
            Expanded(
              child: Row(
                children: [
                  // ✅ SIDEBAR (Desktop/Tablet only)
                  if (!isMobile)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: sidebarWidth,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E1E2C),
                        boxShadow: [
                          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(2, 0)),
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

                  // MAIN CONTENT AREA
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: EdgeInsets.all(cardPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // RESPONSIVE HEADER
                            Text(
                              'Overview',
                              style: TextStyle(
                                fontSize: isMobile ? 18 : 20,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1F2937),
                              ),
                            ),
                            SizedBox(height: isMobile ? 12 : 18),

                            //  RESPONSIVE GRID
                            GridView.builder(
                              itemCount: dashboardCards.length,
                              physics: const NeverScrollableScrollPhysics(),
                              shrinkWrap: true,
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: gridSpacing,
                                crossAxisSpacing: gridSpacing,
                                childAspectRatio: cardAspectRatio,
                              ),
                              itemBuilder: (context, idx) {
                                final card = dashboardCards[idx];
                                return MagicalDashboardCard(
                                  title: card['title'] as String,
                                  subtitle: card['subtitle'] as String,
                                  icon: card['icon'] as IconData,
                                  color: card['color'] as Color,
                                  onTap: () => _handleCardTap(card['title'] as String),
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

  Widget _buildSidebarItem(IconData icon, String title, {bool isMobile = false}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: (isSidebarExpanded || isMobile)
          ? Text(title, style: const TextStyle(color: Colors.white))
          : null,
      onTap: () {
        // Close drawer on mobile
        if (isMobile) {
          Navigator.pop(context);
        }
        
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