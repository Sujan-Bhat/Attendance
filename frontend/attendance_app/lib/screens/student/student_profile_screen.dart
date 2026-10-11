import 'package:flutter/material.dart';
import '../../services/profile_service.dart';
import '../../services/auth_service.dart';
import 'face_verification_screen.dart';
import '../../widgets/student_drawer.dart';
import '../../widgets/profile_widgets.dart';

class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen>
    with TickerProviderStateMixin {
  final ProfileService _profileService = ProfileService();
  final AuthService _authService = AuthService();

  late AnimationController _fadeController;
  late Animation<double> _fadeIn;

  bool isLoading = true;
  String userName = 'Loading...';
  String userEmail = 'Loading...';
  String userRole = 'Student';
  int totalClasses = 0;
  String attendanceRate = '0.0';
  int totalAttendance = 0;
  int presentCount = 0;

  static const _roleColor = Color(0xFF0288D6);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadProfileData();
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutQuint,
    );
    _fadeController.forward();
  }

  Future<void> _loadProfileData() async {
    setState(() => isLoading = true);

    try {
      final profile = await _profileService.getUserProfile();
      final classes = await _profileService.getStudentClasses();
      final stats = await _profileService.getStudentStats();

      if (mounted) {
        setState(() {
          userName = profile?['username'] ?? 'Student';
          userEmail = profile?['email'] ?? 'Not available';
          userRole = 'Student';
          totalClasses = classes.length;
          attendanceRate = stats['attendance_rate'] ?? '0.0';
          totalAttendance = stats['total'] ?? 0;
          presentCount = stats['present'] ?? 0;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.red,
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

    if (confirm == true && mounted) {
      await _authService.logout();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  void _openFaceRegistration() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FaceVerificationScreen(isRegistration: true),
      ),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  List<Widget> _statCards() => [
    ProfileStatCard(
      title: 'Enrolled Classes',
      value: totalClasses.toString(),
      icon: Icons.menu_book_rounded,
      accentColor: const Color(0xFFF59E0B),
    ),
    ProfileStatCard(
      title: 'Attendance Rate',
      value: '$attendanceRate%',
      icon: Icons.show_chart_rounded,
      accentColor: const Color(0xFF10B981),
    ),
    ProfileStatCard(
      title: 'Total Sessions',
      value: totalAttendance.toString(),
      icon: Icons.event_rounded,
      accentColor: const Color(0xFF8B5CF6),
    ),
    ProfileStatCard(
      title: 'Present',
      value: presentCount.toString(),
      icon: Icons.check_circle_rounded,
      accentColor: ProfileColors.teal,
    ),
  ];

  Widget _entrance(Widget child) {
    return FadeTransition(opacity: _fadeIn, child: child);
  }

  Widget _identityBlock({required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ProfileAvatar(
          initial: userName.isNotEmpty ? userName[0].toUpperCase() : 'S',
          radius: compact ? 48 : 56,
        ),
        SizedBox(height: compact ? 16 : 20),
        Text(
          userName,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 24 : 28,
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter',
            color: ProfileColors.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        ProfileRolePill(role: userRole, color: _roleColor),
        SizedBox(height: compact ? 20 : 24),
        ProfileInfoTile(
          icon: Icons.email_outlined,
          label: 'Email Address',
          value: userEmail,
          accentColor: _roleColor,
        ),
        SizedBox(height: compact ? 20 : 24),
        SizedBox(
          width: double.infinity,
          child: ProfileActionButton(
            icon: Icons.face_retouching_natural,
            label: 'Face ID',
            color: ProfileColors.teal,
            onTap: _openFaceRegistration,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ProfileActionButton(
            icon: Icons.logout_rounded,
            label: 'Logout',
            color: Colors.red,
            onTap: _logout,
          ),
        ),
      ],
    );
  }

  Widget _statsGrid({required bool compact}) {
    final cards = _statCards();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileSectionHeader(
          title: 'Overview',
          subtitle: 'Statistics',
          compact: compact,
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 520) {
              return Column(
                children: [
                  for (int i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    cards[i],
                  ],
                ],
              );
            }
            // 2-column grid for the four stat cards.
            return Column(
              children: [
                for (int row = 0; row < 2; row++) ...[
                  if (row > 0) const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: cards[row * 2]),
                      const SizedBox(width: 16),
                      Expanded(child: cards[row * 2 + 1]),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildNarrowBody() {
    return _entrance(
      SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _identityBlock(compact: true),
                const SizedBox(height: 32),
                _statsGrid(compact: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopBody() {
    return _entrance(
      SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(40, 20, 40, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'My Profile',
                    style: TextStyle(
                      color: ProfileColors.tealDark,
                      fontSize: 38,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    color: ProfileColors.textPrimary,
                  ),
                  onPressed: _loadProfileData,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 340,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: ProfileColors.border,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: _identityBlock(compact: false),
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(child: _statsGrid(compact: false)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final bool isDesktop = MediaQuery.of(context).size.width >= 1024;

    final Widget content = isLoading
        ? const Center(
            child: CircularProgressIndicator(color: ProfileColors.teal),
          )
        : (isDesktop ? _buildDesktopBody() : _buildNarrowBody());

    return Scaffold(
      backgroundColor: ProfileColors.background,
      drawer: isMobile ? const StudentDrawer(currentRoute: 'Profile') : null,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'My Profile',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter',
            color: ProfileColors.textPrimary,
          ),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(
              isMobile ? Icons.menu_rounded : Icons.arrow_back_rounded,
              color: ProfileColors.textPrimary,
            ),
            onPressed: () {
              if (isMobile) {
                Scaffold.of(context).openDrawer();
              } else {
                Navigator.pop(context);
              }
            },
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: ProfileColors.textPrimary),
            onPressed: _loadProfileData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: content,
    );
  }
}
