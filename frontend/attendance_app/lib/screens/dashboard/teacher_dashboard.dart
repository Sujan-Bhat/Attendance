import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../widgets/enhanced_dashboard_card.dart';
import '../teacher/my_classes_screen.dart';
import '../teacher/session_create_screen.dart';
import '../teacher/teacher_attendance_history_screen.dart';
import '../teacher/teacher_profile_screen.dart';

class TeacherDashboardPage extends StatefulWidget {
  const TeacherDashboardPage({super.key});

  @override
  State<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends State<TeacherDashboardPage>
    with RouteAware {
  final AuthService _authService = AuthService();
  final ClassService _classService = ClassService();

  bool isSidebarExpanded = false;
  String teacherName = "Loading...";
  String username = "";
  bool isLoading = true;
  int totalClasses = 0;
  int activeSessions = 0;

  // Cache management
  Map<String, dynamic>? _cachedUserData;
  DateTime? _lastFetch;

  // REMOVED: 'Class Insights' and 'Reports' cards
  final List<Map<String, dynamic>> dashboardCards = [
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
      'title': 'Attendance History',
      'subtitle': 'View and edit attendance',
      'icon': Icons.check_circle_rounded,
      'color': Colors.teal,
    },
    {
      'title': 'Profile',
      'subtitle': 'View your profile',
      'icon': Icons.person_rounded,
      'color': Colors.blueGrey,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted && !isLoading) {
      _loadUserData();
    }
  }

  Future<void> _loadUserData({bool forceRefresh = false}) async {
    // Use cache if available and recent (less than 5 minutes old)
    if (!forceRefresh &&
        _cachedUserData != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 5)) {
      setState(() {
        teacherName = _cachedUserData!['first_name'] ?? 'Teacher';
        username = _cachedUserData!['username'] ?? '';
        isLoading = false;
      });
      return;
    }

    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      final userData = await _authService.getCurrentUser();
      final classes = await _classService.getMyClasses();

      if (!mounted) return;

      setState(() {
        _cachedUserData = userData;
        _lastFetch = DateTime.now();
        
        teacherName = userData?['first_name'] ?? 'Teacher';
        username = userData?['username'] ?? '';
        totalClasses = classes.length;
        activeSessions = 0; // TODO: Fetch from backend
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        teacherName = 'Error loading';
        username = '';
        isLoading = false;
      });
      print('Error loading user data: $e');
    }
  }

  void _handleCardTap(String title) async {
    switch (title) {
      case 'My Classes':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const MyClassesScreen(),
          ),
        ).then((_) {
          // Refresh data when returning from My Classes
          _loadUserData(forceRefresh: true);
        });
        break;

      case 'Create Session':
        try {
          // Show inline loading state
          setState(() => isLoading = true);
          
          final classes = await _classService.getMyClasses();
          
          setState(() => isLoading = false);

          if (classes.isEmpty) {
            _showNoClassesSnackBar();
            return;
          }

          final subjects = classes.map((c) => {
            'id': c['id'].toString(),
            'code': c['class_code'] as String,
            'name': c['class_name'] as String,
            'semester': c['semester'] as String,
          }).toList();

          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SessionPage(subjects: subjects),
              ),
            ).then((_) {
              // Refresh data when returning from SessionPage
              _loadUserData(forceRefresh: true);
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() => isLoading = false);
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error loading classes: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
        break;

      case 'Attendance History':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const TeacherAttendanceHistoryScreen(),
          ),
        );
        break;

      case 'Profile':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const TeacherProfileScreen(),
          ),
        ).then((_) {
          _loadUserData(forceRefresh: true);
        });
        break;

      //  REMOVED: Class Insights and Reports cases
      
      default:
        _showComingSoonSnackBar(title);
    }
  }

  void _showNoClassesSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No classes found. Please create a class first.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showComingSoonSnackBar(String title) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title - Coming Soon!'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
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

    if (confirm == true) {
      // Clear cache before logout
      setState(() {
        _cachedUserData = null;
        _lastFetch = null;
      });

      await _authService.logout();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;
    final isTablet = screenW >= 600 && screenW < 1024;
    final isDesktop = screenW >= 1024;

    int crossAxisCount = isMobile ? 1 : (isTablet ? 2 : 3);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      appBar: isMobile || isTablet ? _buildTopBar(isMobile) : null,
      drawer: isMobile || isTablet ? _buildMobileDrawer() : null,
      body: Stack(
        children: [
          SafeArea(
            child: Row(
              children: [
                if (isDesktop) _buildDesktopSidebar(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.all(isMobile ? 16 : 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isDesktop) _buildTopBar(false),
                          if (isDesktop) const SizedBox(height: 24),
                          _buildStatsSection(isMobile),
                          const SizedBox(height: 24),
                          _buildSectionHeader(isMobile),
                          const SizedBox(height: 16),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1100),
                              child: _buildDashboardGrid(crossAxisCount, isMobile),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Inline loading indicator
          if (isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildTopBar(bool isMobile) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: isMobile
          ? null
          : IconButton(
              icon: const Icon(Icons.menu, color: Color(0xFF1F2937)),
              onPressed: () => setState(() => isSidebarExpanded = !isSidebarExpanded),
            ),
      title: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF007C91), Color(0xFF0097A7)],
              ),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(8),
            child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back, $teacherName',
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1F2937),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isMobile)
                  Text(
                    '@$username',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Color(0xFF1F2937)),
          onPressed: () => _loadUserData(forceRefresh: true),
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Color(0xFF1F2937)),
          onPressed: _logout,
        ),
      ],
    );
  }

  Widget _buildStatsSection(bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Classes',
            totalClasses.toString(),
            Icons.class_rounded,
            const Color(0xFF0097A7),
            isMobile,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            'Active Sessions',
            activeSessions.toString(),
            Icons.timer_rounded,
            const Color(0xFFFF6B6B),
            isMobile,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isMobile,
  ) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: isMobile ? 24 : 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isMobile ? 24 : 28,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1F2937),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isMobile ? 12 : 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overview',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF007C91), Color(0xFF0097A7)],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: isMobile ? 18 : 22,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDashboardGrid(int crossAxisCount, bool isMobile) {
    return GridView.builder(
      itemCount: dashboardCards.length,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: isMobile ? 0.96 : 1.22,
      ),
      itemBuilder: (context, idx) {
        final card = dashboardCards[idx];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: EnhancedDashboardCard(
              title: card['title'] as String,
              subtitle: card['subtitle'] as String,
              icon: card['icon'] as IconData,
              color: card['color'] as Color,
              onTap: () => _handleCardTap(card['title'] as String),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopSidebar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isSidebarExpanded ? 220 : 70,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E1E2C), Color(0xFF2D2D44)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: dashboardCards.length,
              itemBuilder: (context, index) {
                final card = dashboardCards[index];
                return _buildSidebarItem(
                  card['icon'] as IconData,
                  card['title'] as String,
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String title, {bool isMobile = false}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70, size: isMobile ? 24 : 20),
      title: isSidebarExpanded || isMobile
          ? Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            )
          : null,
      onTap: () => _handleCardTap(title),
    );
  }

  Widget _buildMobileDrawer() {
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
                    child: Icon(Icons.person, size: 35, color: Color(0xFF007C91)),
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
            ...dashboardCards.map((card) => _buildDrawerItem(
              card['icon'] as IconData,
              card['title'] as String,
            )),
            const Divider(color: Colors.white24),
            _buildDrawerItem(Icons.logout, 'Logout'),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.pop(context); // Close drawer
        if (title == 'Logout') {
          _logout();
        } else {
          _handleCardTap(title);
        }
      },
    );
  }
}