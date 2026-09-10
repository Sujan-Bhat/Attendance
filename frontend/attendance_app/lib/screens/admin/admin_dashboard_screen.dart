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
      title: 'Profile',
      subtitle: 'View your Profile',
      icon: Icons.person_outline_rounded,
      color: Color(0xFF8F8E95),
      gradient: [Color(0xFFACACB4), Colors.white],
    ),
  ];

  Future<void> _loadUserData({bool forceRefresh = false}) async {
    final cacheValid =
        _cachedUserData != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 5);

    if (!forceRefresh && cacheValid) {
      if (!mounted) return;
      setState(() {
        _adminName = _cachedUserData!['first_name'] ?? 'Admin';
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
        _classService.getAdminStats(),
      ]);

      if (!mounted) return;
      final userData = results[0];
      final stats = results[1]!;

      setState(() {
        _cachedUserData = userData;
        _lastFetch = DateTime.now();
        _adminName = userData?['first_name'] ?? 'Admin';
        _username = userData?['username'] ?? '';
        _studentCount =
            int.tryParse(stats['students_count']?.toString() ?? '') ?? 0;
        _teacherCount =
            int.tryParse(stats['teachers_count']?.toString() ?? '') ?? 0;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading admin dashboard data: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleCardTap(String title) async {
    await navigateToAdminScreen(context, title);
    _loadUserData(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;

    return AdminWebLayout(
      currentRoute: 'Dashboard',
      showMobileAppBar: false,
      mobileChild: _buildMobileBody(isMobile),
      desktopBody: _buildDesktopBody(),
    );
  }

  Widget _buildMobileBody(bool isMobile) {
    final crossAxisCount = isMobile ? 1 : 2;

    return Stack(
      children: [
        Column(
          children: [
            _buildMobileTopBar(),
            Expanded(
              child: SafeArea(
                top: false,
                child: AdminEntrance(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.all(isMobile ? 12 : 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStatsSection(isMobile),
                          const SizedBox(height: 24),
                          _buildSectionHeader(isCompact: isMobile),
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
              ),
            ),
          ],
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

  Widget _buildSectionHeader({bool isCompact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overview',
          style: TextStyle(
            fontSize: isCompact ? 20 : 26,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Container(
              width: isCompact ? 4 : 12,
              height: isCompact ? 24 : 43,
              decoration: ShapeDecoration(
                color: _AppColors.tealLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(isCompact ? 2 : 6),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: isCompact ? 18 : 33,
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
    final isCompact = isMobile || crossAxisCount == 2;
    final childAspectRatio = isMobile
        ? 0.96
        : (crossAxisCount == 2 ? 1.22 : 1.6);

    return GridView.builder(
      itemCount: _cards.length,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: isCompact ? 18 : 42,
        crossAxisSpacing: isCompact ? 18 : 55,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (context, idx) {
        final card = _cards[idx];
        final animated = AdminAnimatedCard(
          title: card.title,
          subtitle: card.subtitle,
          icon: card.icon,
          color: card.color,
          gradient: card.gradient,
          compact: isCompact,
          onTap: () => _handleCardTap(card.title),
        );
        if (isCompact) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: animated,
            ),
          );
        }
        return animated;
      },
    );
  }

  /// Mobile top bar — now a proper elevated surface (matches the AppBar
  /// treatment on the teacher dashboard) instead of floating bare text
  /// over the page background.
  Widget _buildMobileTopBar() {
    return Material(
      elevation: 1,
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
          child: Row(
            children: [
              Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(
                    Icons.menu_rounded,
                    color: _AppColors.tealDark,
                  ),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                  tooltip: 'Menu',
                ),
              ),
              const SizedBox(width: 4),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, $_username',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Admin',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const OfflineIndicator(),
              AdminHeaderActions(
                onRefresh: () => _loadUserData(forceRefresh: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsSection(bool isMobile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = isMobile || constraints.maxWidth < 700;
        if (constraints.maxWidth < 700) {
          return Column(
            children: [
              _studentStatCard(isCompact: isCompact),
              const SizedBox(height: 16),
              _teacherStatCard(isCompact: isCompact),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: _studentStatCard(isCompact: isCompact)),
            const SizedBox(width: 16),
            Expanded(child: _teacherStatCard(isCompact: isCompact)),
          ],
        );
      },
    );
  }

  Widget _buildStatsRow() => Row(
    children: [
      Expanded(child: _studentStatCard()),
      const SizedBox(width: 24),
      Expanded(child: _teacherStatCard()),
    ],
  );

  Widget _studentStatCard({bool isCompact = false}) => _buildStatCard(
    value: _studentCount.toString(),
    label: 'Total Students',
    iconColor: const Color(0xFF14DCCA),
    gradientColors: [const Color(0xFF65E8E1), Colors.white],
    borderColor: _AppColors.teal,
    isCompact: isCompact,
  );

  Widget _teacherStatCard({bool isCompact = false}) => _buildStatCard(
    value: _teacherCount.toString(),
    label: 'Total Teachers',
    iconColor: const Color(0xFF22C55E),
    gradientColors: [const Color(0xFFA8E6A7), Colors.white],
    borderColor: const Color(0xFF1EBA57),
    isCompact: isCompact,
  );

  Widget _buildStatCard({
    required String value,
    required String label,
    required Color iconColor,
    required List<Color> gradientColors,
    required Color borderColor,
    bool isCompact = false,
  }) {
    return Container(
      height: isCompact ? 100 : 108,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 24),
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
        shadows: [
          BoxShadow(
            color: borderColor.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: isCompact ? 52 : 68,
            height: isCompact ? 52 : 68,
            decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
            padding: const EdgeInsets.all(10),
            child: Icon(
              Icons.bar_chart_rounded,
              color: Colors.white,
              size: isCompact ? 24 : 28,
            ),
          ),
          SizedBox(width: isCompact ? 12 : 38),
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
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: isCompact ? 28 : 40,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: _AppColors.textMuted,
                    fontSize: isCompact ? 13 : 17,
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