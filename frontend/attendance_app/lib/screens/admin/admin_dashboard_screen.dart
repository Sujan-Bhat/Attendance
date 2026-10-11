import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../widgets/admin_web_layout.dart';
import '../../widgets/offline_indicator.dart';
import 'admin_navigation.dart';
import 'widgets/admin_animated_card.dart';
import 'widgets/admin_entrance.dart';
import 'widgets/admin_header_actions.dart';

abstract class _AppColors {
  static const tealDark = Color(0xFF007C91);
  static const teal = Color(0xFF0097A7);
  static const tealLight = Color(0xFF0288A3);
  static const textPrimary = Color(0xFF1F2937);
  static const textMuted = Color(0xFF6B7280);
}

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

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final AuthService _authService = AuthService();
  final ClassService _classService = ClassService();

  bool _isLoading = false;
  String _adminName = 'Admin';
  String _username = '';
  int _studentCount = 0;
  int _teacherCount = 0;

  Map<String, dynamic>? _cachedUserData;
  DateTime? _lastFetch;

  /// Non-null when the stats request failed; the counts are then left at
  /// their last known value instead of silently rendering as zero.
  String? _statsError;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  static const _cards = <_DashboardCard>[
    _DashboardCard(
      title: 'Manage Students',
      subtitle: 'View or Edit Student Details',
      icon: Icons.people_alt_rounded,
      color: Color(0xFFF59E0B),
      gradient: [Color(0xFFF59E0B), Colors.white],
    ),
    _DashboardCard(
      title: 'Manage Teachers',
      subtitle: 'View and Edit Teacher Details',
      icon: Icons.person_rounded,
      color: Color(0xFF0FA797),
      gradient: [Color(0xFF14B8A6), Colors.white],
    ),
    _DashboardCard(
      title: 'Manage Classes',
      subtitle: 'Browse Classes and Students',
      icon: Icons.class_rounded,
      color: Color(0xFF6C5CE7),
      gradient: [Color(0xFF9C8BFF), Colors.white],
    ),
    _DashboardCard(
      title: 'Attendance Management',
      subtitle: 'Session-wise attendance by class',
      icon: Icons.analytics_rounded,
      color: Color(0xFF2F80ED),
      gradient: [Color(0xFF5B9DF9), Colors.white],
    ),
    _DashboardCard(
      title: 'Profile',
      subtitle: 'View your Profile',
      icon: Icons.person_outline_rounded,
      color: Color(0xFF8F8E95),
      gradient: [Color(0xFFACACB4), Colors.white],
    ),
  ];

  /// Display name with robust fallback: first_name -> username -> 'Admin'.
  /// Treats empty strings as missing (unlike a bare ?? operator).
  String displayName(Map<String, dynamic>? data) {
    final first = (data?['first_name'] ?? '').toString().trim();
    if (first.isNotEmpty) return first;
    final username = (data?['username'] ?? '').toString().trim();
    return username.isNotEmpty ? username : 'Admin';
  }

  Future<void> _loadUserData({bool forceRefresh = false}) async {
    final cacheValid =
        _cachedUserData != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 5);

    if (!forceRefresh && cacheValid) {
      if (!mounted) return;
      setState(() {
        _adminName = displayName(_cachedUserData!);
        _username = _cachedUserData!['username'] ?? '';
        _isLoading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final userData = await _authService.getCurrentUser();

      if (!mounted) return;
      setState(() {
        _cachedUserData = userData;
        _lastFetch = DateTime.now();
        _adminName = displayName(userData);
        _username = userData?['username'] ?? '';
      });
    } catch (e) {
      debugPrint('Error loading admin profile: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }

    try {
      final stats = await _classService.getAdminStats();

      if (!mounted) return;
      setState(() {
        _studentCount =
            int.tryParse(stats['students_count']?.toString() ?? '') ?? 0;
        _teacherCount =
            int.tryParse(stats['teachers_count']?.toString() ?? '') ?? 0;
        _statsError = null;
        _isLoading = false;
      });
    } catch (e) {
      // Fetched separately from the profile so a stats failure still shows
      // the admin's name instead of blanking the whole screen.
      debugPrint('Error loading admin stats: $e');
      if (!mounted) return;
      setState(() {
        _statsError = 'Counts are unavailable right now.';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleCardTap(String title) {
    // Navigation replaces this route, so there is nothing left to refresh
    // after the jump — the destination screen loads its own data.
    return navigateToAdminScreen(context, title);
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;

    return AdminWebLayout(
      currentRoute: 'Dashboard',
      mobileTitle: _buildMobileTitle(isMobile),
      mobileActions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: _AppColors.textPrimary),
          onPressed: () => _loadUserData(forceRefresh: true),
          tooltip: 'Refresh',
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: _AppColors.textPrimary),
          onPressed: _logout,
          tooltip: 'Logout',
        ),
      ],
      mobileChild: _buildMobileBody(isMobile),
      desktopBody: _buildDesktopBody(),
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
      await _authService.logout();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Widget _buildMobileTitle(bool isMobile) {
    return Row(
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
            Icons.admin_panel_settings_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Welcome, ${_username.isEmpty ? _adminName : _username}',
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
              color: _AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBody(bool isMobile) {
    final crossAxisCount = isMobile ? 1 : 2;

    return Stack(
      children: [
        AdminEntrance(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatsSection(isMobile),
                  if (_statsError != null) ...[
                    const SizedBox(height: 12),
                    _buildStatsErrorHint(),
                  ],
                  const SizedBox(height: 24),
                  _buildSectionHeader(),
                  const SizedBox(height: 16),
                  _buildDashboardGrid(crossAxisCount),
                ],
              ),
            ),
          ),
        ),
        if (_isLoading) _buildLoadingOverlay(),
      ],
    );
  }

  Widget _buildDesktopBody() {
    return Stack(
      children: [
        AdminEntrance(
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
                  if (_statsError != null) ...[
                    const SizedBox(height: 14),
                    _buildStatsErrorHint(),
                  ],
                  const SizedBox(height: 48),
                  _buildSectionHeader(),
                  const SizedBox(height: 24),
                  _buildDashboardGrid(3),
                ],
              ),
            ),
          ),
        ),
        if (_isLoading) _buildLoadingOverlay(),
      ],
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

  Widget _buildDashboardGrid(int crossAxisCount) {
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
      itemBuilder: (context, idx) {
        final card = _cards[idx];
        return AdminAnimatedCard(
          title: card.title,
          subtitle: card.subtitle,
          icon: card.icon,
          color: card.color,
          gradient: card.gradient,
          onTap: () => _handleCardTap(card.title),
        );
      },
    );
  }

  Widget _buildStatsSection(bool isMobile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final studentCard = _studentStatCard();
        final teacherCard = _teacherStatCard();

        if (constraints.maxWidth < 700) {
          return Column(
            children: [studentCard, const SizedBox(height: 16), teacherCard],
          );
        }
        return Row(
          children: [
            Expanded(child: studentCard),
            const SizedBox(width: 16),
            Expanded(child: teacherCard),
          ],
        );
      },
    );
  }  Widget _buildStatsRow() => Row(
        children: [
          Expanded(child: _studentStatCard()),
          const SizedBox(width: 24),
          Expanded(child: _teacherStatCard()),
        ],
      );

  Widget _buildStatsErrorHint() => Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: _AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statsError!,
              style: const TextStyle(
                fontSize: 13,
                color: _AppColors.textMuted,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ],
      );

  Widget _studentStatCard() => _buildStatCard(
    value: _studentCount.toString(),
    label: 'Total Students',
    iconColor: const Color(0xFF14DCCA),
    gradientColors: [const Color(0xFF65E8E1), Colors.white],
    borderColor: _AppColors.teal,
  );

  Widget _teacherStatCard() => _buildStatCard(
    value: _teacherCount.toString(),
    label: 'Total Teachers',
    iconColor: const Color(0xFF22C55E),
    gradientColors: [const Color(0xFFA8E6A7), Colors.white],
    borderColor: const Color(0xFF1EBA57),
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
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 40,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: _AppColors.textMuted,
                    fontSize: 17,
                    fontFamily: 'Inter',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
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
            Icons.admin_panel_settings_rounded,
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
                'Welcome, $_adminName',
                style: const TextStyle(
                  color: _AppColors.tealDark,
                  fontSize: 38,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              if (_username.isNotEmpty)
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
        AdminHeaderActions(onRefresh: () => _loadUserData(forceRefresh: true)),
      ],
    );
  }
}