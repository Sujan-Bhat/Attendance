import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/student_drawer.dart';
import '../../widgets/enhanced_dashboard_card.dart';
import '../student/my_classes_screen.dart';
import '../student/qr_scanner_screen.dart';
import '../student/qr_scanner_screen.dart';
import '../student/attendance_history_screen.dart';
import '../student/student_profile_screen.dart';
import '../student/student_announcements_screen.dart';
import '../student/pattern_sessions_screen.dart';
import '../../services/class_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/offline_indicator.dart';
import '../../services/face_auth_service.dart';
import '../student/face_verification_screen.dart';

class StudentDashboardPage extends StatefulWidget {
  const StudentDashboardPage({super.key});

  @override
  State<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends State<StudentDashboardPage> {
  final AuthService _authService = AuthService();
  final ProfileService _profileService = ProfileService();
  final ClassService _classService = ClassService();

  bool isSidebarExpanded = false;
  String studentName = "Loading...";
  String username = "";
  bool isLoading = true;
  int totalClasses = 0;
  double attendanceRate = 0.0;

  // Cache management
  Map<String, dynamic>? _cachedUserData;
  DateTime? _lastFetch;

  final List<Map<String, dynamic>> dashboardCards = [
    {
      'title': 'My Classes',
      'subtitle': 'View enrolled classes',
      'icon': Icons.school_rounded,
      'gradientColors': [const Color(0xFF3B82F6), Colors.white],
    },
    {
      'title': 'Scan QR',
      'subtitle': 'Start new Attendance Session',
      'icon': Icons.qr_code_scanner_rounded,
      'gradientColors': [const Color(0xFFA6FF39), Colors.white],
    },
    {
      'title': 'Attendance History',
      'subtitle': 'View past records',
      'icon': Icons.history_rounded,
      'gradientColors': [const Color(0xFFC26BDF), Colors.white],
    },
    {
      'title': 'Profile',
      'subtitle': 'Manage your account',
      'icon': Icons.person_rounded,
      'gradientColors': [const Color(0xFFE9609D), Colors.white],
    },
    {
      'title': 'Announcements',
      'subtitle': 'View notices and updates',
      'icon': Icons.campaign_rounded,
      'gradientColors': [const Color(0xFFEF8AF6), Colors.white],
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkPendingJoinCode();
  }

  static bool _isJoining = false;

  Future<void> _checkPendingJoinCode() async {
    if (_isJoining) return;
    final code = await StorageService.read(key: 'pending_join_code');
    if (code != null && code.isNotEmpty) {
      _isJoining = true;
      try {
        await StorageService.delete(key: 'pending_join_code');
        // Show loading
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Joining class $code...')));
        }
        final result = await _classService.joinClass(code);
        if (mounted) {
          if (result['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message']),
                backgroundColor: Colors.green,
              ),
            );
            await _loadUserData(forceRefresh: true);
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StudentMyClassesScreen(),
                ),
              ).then((_) {
                _loadUserData(forceRefresh: true);
              });
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message']),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } finally {
        // Reset flag after a short delay to prevent double-firing
        Future.delayed(const Duration(seconds: 2), () {
          _isJoining = false;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted && !isLoading) {
      _loadUserData();
    }
  }

  //  UPDATED: Fetch real data from backend
  Future<void> _loadUserData({bool forceRefresh = false}) async {
    // Use cache if available and recent (less than 5 minutes old)
    if (!forceRefresh &&
        _cachedUserData != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 5)) {
      setState(() {
        studentName = _cachedUserData!['first_name'] ?? 'Student';
        username = _cachedUserData!['username'] ?? '';
        totalClasses = _cachedUserData!['total_classes'] ?? 0;
        attendanceRate = _cachedUserData!['attendance_rate'] ?? 0.0;
        isLoading = false;
      });
      return;
    }

    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      // Fetch user profile data
      final userData = await _authService.getCurrentUser();

      // Fetch student's enrolled classes
      final classes = await _profileService.getStudentClasses();

      // Fetch student's attendance statistics
      final stats = await _profileService.getStudentStats();

      if (!mounted) return;

      final rate =
          double.tryParse(stats['attendance_rate']?.toString() ?? '0.0') ?? 0.0;

      setState(() {
        _cachedUserData = {
          ...?userData,
          'total_classes': classes.length,
          'attendance_rate': rate,
        };
        _lastFetch = DateTime.now();

        studentName =
            userData?['first_name'] ?? userData?['username'] ?? 'Student';
        username = userData?['username'] ?? '';

        // Set real data from backend
        totalClasses = classes.length;
        attendanceRate = rate;

        isLoading = false;
      });

      print(
        '📊 Dashboard Stats: $totalClasses classes, ${attendanceRate.toStringAsFixed(1)}% attendance',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        studentName = 'Error loading';
        username = '';
        totalClasses = 0;
        attendanceRate = 0.0;
        isLoading = false;
      });
      print('Error loading user data: $e');
    }
  }

  void _handleCardTap(String title) {
    switch (title) {
      case 'My Classes':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const StudentMyClassesScreen(),
          ),
        ).then((_) {
          _loadUserData(forceRefresh: true);
        });
        break;

      case 'Scan QR':
        _handleScanQR();
        break;

      case 'Attendance History':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AttendanceHistoryScreen(),
          ),
        );
        break;

      case 'Profile':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const StudentProfileScreen()),
        ).then((_) {
          _loadUserData(forceRefresh: true);
        });
        break;

      case 'Announcements':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const StudentAnnouncementsScreen()),
        );
        break;

      default:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$title - Coming soon!')));
    }
  }

  Future<void> _handleScanQR() async {
    final faceAuth = FaceAuthService();
    bool hasSavedFace = await faceAuth.hasSavedFace();

    if (!mounted) return;

    // Launch Face Verification or Registration based on saved face
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceVerificationScreen(isRegistration: !hasSavedFace),
      ),
    );

    if (result == true && mounted) {
      // If they just registered, they are effectively verified for this session.
      // If they were already registered, they just passed verification.
      // In either case, proceed directly to the QR scanner.
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const QRScannerScreen()),
      ).then((_) {
        _loadUserData(forceRefresh: true);
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!hasSavedFace 
                ? 'Face Registration cancelled or failed.' 
                : 'Face Verification failed.'),
          ),
        );
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
      drawer: isMobile || isTablet
          ? const StudentDrawer(currentRoute: 'Dashboard')
          : null,
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
                              child: _buildDashboardGrid(
                                crossAxisCount,
                                isMobile,
                              ),
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
              onPressed: () =>
                  setState(() => isSidebarExpanded = !isSidebarExpanded),
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
            child: const Icon(
              Icons.school_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, $studentName',
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
        const OfflineIndicator(),
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
            'Enrolled Classes',
            totalClasses.toString(),
            Icons.class_rounded,
            [const Color(0xFF66E9E1), Colors.white],
            const Color(0xFF0097A7),
            isMobile,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            'Attendance Rate',
            '${attendanceRate.toStringAsFixed(1)}%',
            Icons.check_circle_rounded,
            [const Color(0xFFA8E6A7), Colors.white],
            const Color(0xFF1EBA57),
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
    List<Color> gradientColors,
    Color borderColor,
    bool isMobile,
  ) {
    return Container(
      height: isMobile ? 100 : 120,
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: isMobile ? 12 : 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(23), // Matched to Figma 23px
        border: Border.all(
          color: borderColor,
          width: 2,
        ), // Matched to Figma 2px
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: borderColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: borderColor, size: isMobile ? 24 : 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: isMobile ? 24 : 28,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: isMobile ? 12 : 14,
                      color: Colors.grey[600],
                    ),
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
              gradientColors: card['gradientColors'] as List<Color>,
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

  Widget _buildSidebarItem(
    IconData icon,
    String title, {
    bool isMobile = false,
  }) {
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
}
