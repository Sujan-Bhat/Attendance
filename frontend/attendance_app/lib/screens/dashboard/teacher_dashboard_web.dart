import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../teacher/my_classes_screen.dart';
import '../teacher/session_create_screen.dart';
import '../teacher/teacher_attendance_history_screen.dart';
import '../teacher/teacher_profile_screen.dart';
import '../teacher/teacher_announcements_screen.dart';
import '../analytics/teacher_analytics_screen.dart';
import '../../widgets/teacher_web_layout.dart';
import '../../widgets/offline_indicator.dart';

// ─── App colour constants ──────────────
abstract class _AppColors {
  static const tealDark = Color(0xFF007C91);
  static const teal = Color(0xFF0097A7);
  static const tealLight = Color(0xFF0288A3);
  static const background = Color(0xFFF7FAFC);
  static const darkBg = Color(0xFF1E1E2D);
  static const textPrimary = Color(0xFF1F2937);
  static const textMuted = Color(0xFF6B7280);
}

// ─── Typed card model ───────────────────────
class _DashboardCard {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<Color> gradient;

  const _DashboardCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.gradient,
  });
}

// ─── Animated Web Card ────────────────────────────────────────────────────────
class AnimatedWebCard extends StatefulWidget {
  final _DashboardCard card;
  final VoidCallback onTap;

  const AnimatedWebCard({super.key, required this.card, required this.onTap});

  @override
  State<AnimatedWebCard> createState() => _AnimatedWebCardState();
}

class _AnimatedWebCardState extends State<AnimatedWebCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _translateAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.04,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _translateAnimation = Tween<double>(
      begin: 0.0,
      end: -8.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _translateAnimation.value),
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  decoration: ShapeDecoration(
                    gradient: LinearGradient(
                      begin: const Alignment(-0.05, -0.07),
                      end: const Alignment(1.18, 1.28),
                      colors: widget.card.gradient,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(43),
                      side: const BorderSide(
                        color: Color(0xFFE5E7EB),
                        width: 1.5,
                      ),
                    ),
                    shadows: [
                      BoxShadow(
                        color: widget.card.color.withOpacity(
                          _isHovered ? 0.6 : 0.1,
                        ),
                        blurRadius: _isHovered ? 25 : 10,
                        spreadRadius: _isHovered ? 2 : 0,
                        offset: Offset(0, _isHovered ? 12 : 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          border: Border.all(
                            color: widget.card.color.withOpacity(0.70),
                            width: 1.5,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Transform.rotate(
                          angle: _rotationAnimation.value,
                          child: Icon(
                            widget.card.icon,
                            color: widget.card.color,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.card.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 20,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.card.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Page ────────────────────────────────────────────────────────────────────
class TeacherDashboardWeb extends StatefulWidget {
  const TeacherDashboardWeb({super.key});

  @override
  State<TeacherDashboardWeb> createState() => _TeacherDashboardWebState();
}

class _TeacherDashboardWebState extends State<TeacherDashboardWeb> {
  PageRouteBuilder _fadeRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 150),
    );
  }

  final AuthService _authService = AuthService();
  final ClassService _classService = ClassService();

  bool _isSidebarExpanded = false;
  String _teacherName = 'Loading...';
  String _username = '';
  bool _isLoading = true;
  int _totalClasses = 0;
  int _activeSessions = 0;

  Map<String, dynamic>? _cachedUserData;
  DateTime? _lastFetch;

  // Compile-time constant list
  static const _cards = <_DashboardCard>[
    _DashboardCard(
      title: 'My Classes',
      subtitle: 'Manage and Monitor classes',
      icon: Icons.people_alt_rounded,
      color: Color(0xFF22C55E),
      gradient: [Color(0xFF1EB957), Colors.white],
    ),
    _DashboardCard(
      title: 'Create Session',
      subtitle: 'Start new Attendance Session',
      icon: Icons.timer_rounded,
      color: Color(0xFFF59E0B),
      gradient: [Color(0xFFF59E0B), Colors.white],
    ),
    _DashboardCard(
      title: 'Attendance History',
      subtitle: 'View and Edit Attendance',
      icon: Icons.check_circle_rounded,
      color: Color(0xFF0FA797),
      gradient: [Color(0xFF14B8A6), Colors.white],
    ),
    _DashboardCard(
      title: 'Profile',
      subtitle: 'View your Profile',
      icon: Icons.person_rounded,
      color: Color(0xFF999EA5),
      gradient: [Color(0xFF9CA3AF), Colors.white],
    ),
    _DashboardCard(
      title: 'Announcements',
      subtitle: 'Announce to class',
      icon: Icons.campaign_rounded,
      color: Color(0xFFF566C5),
      gradient: [Color(0xFFE597F3), Colors.white],
    ),
    _DashboardCard(
      title: 'Analytics',
      subtitle: 'Reports and Highlights',
      icon: Icons.insights_rounded,
      color: Color(0xFF78D855),
      gradient: [Color(0xFFB0ED69), Colors.white],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData({bool forceRefresh = false}) async {
    final cacheValid =
        _cachedUserData != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 5);

    if (!forceRefresh && cacheValid) {
      if (!mounted) return;
      setState(() {
        _teacherName = _cachedUserData!['first_name'] ?? 'Teacher';
        _username = _cachedUserData!['username'] ?? '';
        _isLoading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _authService.getCurrentUser(),
        _classService.getMyClasses(),
      ]);

      if (!mounted) return;
      final userData = results[0] as Map<String, dynamic>?;
      final classes = results[1] as List;

      setState(() {
        _cachedUserData = userData;
        _lastFetch = DateTime.now();
        _teacherName = userData?['first_name'] ?? 'Teacher';
        _username = userData?['username'] ?? '';
        _totalClasses = classes.length;
        _activeSessions = 0;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _teacherName = 'Teacher';
        _username = '';
        _isLoading = false;
      });
      _showSnackBar('Failed to load data. Please try again.', Colors.red);
    }
  }

  Future<void> _handleCardTap(String title) async {
    switch (title) {
      case 'My Classes':
        await Navigator.push(context, _fadeRoute(const MyClassesScreen()));
        _loadUserData(forceRefresh: true);
        break;
      case 'Create Session':
        await _navigateToCreateSession();
        break;
      case 'Attendance History':
        await Navigator.push(
          context,
          _fadeRoute(const TeacherAttendanceHistoryScreen()),
        );
        _loadUserData(forceRefresh: true);
        break;
      case 'Profile':
        await Navigator.push(context, _fadeRoute(const TeacherProfileScreen()));
        _loadUserData(forceRefresh: true);
        break;
      case 'Announcements':
        await Navigator.push(context, _fadeRoute(const TeacherAnnouncementsScreen()));
        break;
      case 'Analytics':
        await Navigator.push(
          context,
          _fadeRoute(const TeacherAnalyticsScreen()),
        );
        break;
      default:
        _showSnackBar('$title card was clicked!', Colors.purple);
    }
  }

  Future<void> _navigateToCreateSession() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final classes = await _classService.getMyClasses();
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (classes.isEmpty) {
        _showSnackBar(
          'No classes found. Please create a class first.',
          Colors.orange,
        );
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

      if (!mounted) return;
      await Navigator.push(
        context,
        _fadeRoute(SessionPage(subjects: subjects)),
      );
      _loadUserData(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Error loading classes: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _cachedUserData = null;
      _lastFetch = null;
      await _authService.logout();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;
    final isDesktop = screenW >= 1024;

    if (isDesktop) return _buildDesktopLayout();

    final crossAxisCount = isMobile ? 1 : 2;

    return Scaffold(
      backgroundColor: _AppColors.background,
      appBar: _buildTopBar(isMobile),
      drawer: _buildMobileDrawer(),
      body: Stack(
        children: [
          SafeArea(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutQuint,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 40 * (1 - value)),
                  child: Opacity(opacity: value, child: child),
                );
              },
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 16 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatsSection(isMobile),
                      const SizedBox(height: 24),
                      _buildSectionHeader(),
                      const SizedBox(height: 16),
                      _buildDashboardGrid(crossAxisCount, isMobile),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return TeacherWebLayout(
      currentRoute: 'Dashboard',
      mobileChild: const SizedBox.shrink(),
      desktopBody: Stack(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutQuint,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 40 * (1 - value)),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 20, 40, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDesktopHeader(),
                    const SizedBox(height: 32),
                    _buildStatsRow(),
                    const SizedBox(height: 48),
                    _buildSectionHeader(),
                    const SizedBox(height: 24),
                    _buildDashboardGrid(3, false),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() => Container(
    color: Colors.black26,
    child: const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(24),
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
  );

  Widget _buildStatsSection(bool isMobile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalCard = _buildStatCard(
          value: _totalClasses.toString(),
          label: 'Total Classes',
          iconColor: const Color(0xFF14DCCA),
          gradientColors: [const Color(0xFF65E8E1), Colors.white],
          borderColor: _AppColors.teal,
        );
        final sessionCard = _buildStatCard(
          value: _activeSessions.toString(),
          label: 'Active Sessions',
          iconColor: const Color(0xFFFF9191),
          gradientColors: [const Color(0xFFFBC9C9), Colors.white],
          borderColor: const Color(0xFFF3ABAB),
        );

        if (constraints.maxWidth < 700) {
          return Column(
            children: [totalCard, const SizedBox(height: 16), sessionCard],
          );
        }
        return Row(
          children: [
            Expanded(child: totalCard),
            const SizedBox(width: 16),
            Expanded(child: sessionCard),
          ],
        );
      },
    );
  }

  Widget _buildStatsRow() => Row(
    children: [
      Expanded(
        child: _buildStatCard(
          value: _totalClasses.toString(),
          label: 'Total Classes',
          iconColor: const Color(0xFF14DCCA),
          gradientColors: [const Color(0xFF65E8E1), Colors.white],
          borderColor: _AppColors.teal,
        ),
      ),
      const SizedBox(width: 24),
      Expanded(
        child: _buildStatCard(
          value: _activeSessions.toString(),
          label: 'Active Sessions',
          iconColor: const Color(0xFFFF9191),
          gradientColors: [const Color(0xFFFBC9C9), Colors.white],
          borderColor: const Color(0xFFF3ABAB),
        ),
      ),
    ],
  );

  Widget _buildStatCard({
    required String value,
    required String label,
    required Color iconColor,
    required List<Color> gradientColors,
    required Color borderColor,
  }) {
    return Container(
      height: 108,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: ShapeDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-0.13, 0),
          end: const Alignment(1.12, 1),
          colors: gradientColors,
        ),
        shape: RoundedRectangleBorder(
          side: BorderSide(width: 2, color: borderColor),
          borderRadius: BorderRadius.circular(23),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
            padding: const EdgeInsets.all(10),
            child: const Icon(
              Icons.bar_chart_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 38),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 40,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: _AppColors.textMuted,
                  fontSize: 17,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
          style: TextStyle(
            fontSize: 26,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Container(
              width: 12,
              height: 43,
              decoration: ShapeDecoration(
                color: _AppColors.tealLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 33,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDashboardGrid(int crossAxisCount, bool isMobile) {
    final childAspectRatio = crossAxisCount == 1
        ? 1.5
        : (crossAxisCount == 2 ? 1.3 : 1.6);
    return GridView.builder(
      itemCount: _cards.length,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 42,
        crossAxisSpacing: 55,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (context, idx) => AnimatedWebCard(
        card: _cards[idx],
        onTap: () => _handleCardTap(_cards[idx].title),
      ),
    );
  }

  PreferredSizeWidget _buildTopBar(bool isMobile) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: Row(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_AppColors.tealDark, _AppColors.teal],
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
            child: Text(
              'Welcome, $_username',
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.bold,
                color: _AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        const OfflineIndicator(),
        IconButton(
          icon: const Icon(Icons.refresh, color: _AppColors.textPrimary),
          onPressed: () => _loadUserData(forceRefresh: true),
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: _AppColors.textPrimary),
          onPressed: _logout,
        ),
      ],
    );
  }

  Widget _buildDesktopHeader() {
    return Row(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_AppColors.tealDark, _AppColors.teal],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(63.5),
          ),
          child: const Icon(
            Icons.school_rounded,
            color: Colors.white,
            size: 38,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome, $_username',
                style: const TextStyle(
                  color: _AppColors.tealDark,
                  fontSize: 38,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '@$_username',
                style: const TextStyle(
                  fontSize: 16,
                  color: _AppColors.textMuted,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
        const OfflineIndicator(),
        IconButton(
          icon: const Icon(Icons.refresh, color: _AppColors.textPrimary),
          onPressed: () => _loadUserData(forceRefresh: true),
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: _AppColors.textPrimary),
          onPressed: _logout,
        ),
      ],
    );
  }

  Widget _buildSidebarItem(
    IconData icon,
    String title, {
    bool isMobile = false,
  }) {
    final showLabel = _isSidebarExpanded || isMobile;
    return Tooltip(
      message: showLabel ? '' : title,
      child: ListTile(
        leading: Icon(icon, color: Colors.white70, size: isMobile ? 24 : 20),
        title: showLabel
            ? Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              )
            : null,
        onTap: () => title == 'Logout' ? _logout() : _handleCardTap(title),
      ),
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      child: Container(
        decoration: const BoxDecoration(color: _AppColors.darkBg),
        child: ListView(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_AppColors.tealDark, _AppColors.teal],
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
                      Icons.school_rounded,
                      size: 35,
                      color: _AppColors.tealDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _teacherName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ..._cards.map(
              (c) => _buildSidebarItem(c.icon, c.title, isMobile: true),
            ),
            const Divider(color: Colors.white24),
            _buildSidebarItem(Icons.logout, 'Logout', isMobile: true),
          ],
        ),
      ),
    );
  }
}
