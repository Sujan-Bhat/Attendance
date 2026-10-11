import 'package:flutter/material.dart';
import '../../services/profile_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/teacher_web_layout.dart';
import '../../widgets/teacher_drawer.dart';
import '../../widgets/profile_widgets.dart';

class TeacherProfileScreen extends StatefulWidget {
  const TeacherProfileScreen({super.key});

  @override
  State<TeacherProfileScreen> createState() => _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends State<TeacherProfileScreen>
    with TickerProviderStateMixin {
  final ProfileService _profileService = ProfileService();
  final AuthService _authService = AuthService();

  late AnimationController _fadeController;
  late Animation<double> _fadeIn;

  bool isLoading = true;
  String userName = 'Loading...';
  String userEmail = 'Loading...';
  String userRole = 'Teacher';
  int totalClasses = 0;
  int totalStudents = 0;

  static const _roleColor = Color(0xFF10B981);

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
      final classes = await _profileService.getTeacherClasses();

      int students = 0;
      for (var classData in classes) {
        students += (classData['student_count'] as int?) ?? 0;
      }

      if (mounted) {
        setState(() {
          userName = profile?['username'] ?? 'Teacher';
          userEmail = profile?['email'] ?? 'Not available';
          userRole = 'Teacher';
          totalClasses = classes.length;
          totalStudents = students;
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

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  List<Widget> _statCards() => [
    ProfileStatCard(
      title: 'Classes Managed',
      value: totalClasses.toString(),
      icon: Icons.menu_book_rounded,
      accentColor: const Color(0xFFF59E0B),
    ),
    ProfileStatCard(
      title: 'Total Students',
      value: totalStudents.toString(),
      icon: Icons.people_alt_rounded,
      accentColor: _roleColor,
    ),
  ];

  Widget _entrance(Widget child) {
    return FadeTransition(
      opacity: _fadeIn,
      child: child,
    );
  }

  Widget _identityBlock({required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ProfileAvatar(
          initial: userName.isNotEmpty ? userName[0].toUpperCase() : 'T',
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
        ),
        SizedBox(height: compact ? 20 : 24),
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

  Widget _statsBlock({required bool compact}) {
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
            final cards = _statCards();
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
            return Row(
              children: [
                for (int i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(child: cards[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMobileBody() {
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
                _statsBlock(compact: true),
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
                Expanded(child: _statsBlock(compact: false)),
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

    final Widget content = isLoading
        ? const Center(
            child: CircularProgressIndicator(color: ProfileColors.teal),
          )
        : (MediaQuery.of(context).size.width >= 1024
              ? _buildDesktopBody()
              : _buildMobileBody());

    final Widget mobileChild = Scaffold(
      backgroundColor: ProfileColors.background,
      drawer: isMobile ? const TeacherDrawer(currentRoute: 'Profile') : null,
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 8 : 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    if (isMobile)
                      Builder(
                        builder: (context) => IconButton(
                          icon: const Icon(
                            Icons.menu_rounded,
                            color: ProfileColors.textPrimary,
                          ),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                        ),
                      )
                    else
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: ProfileColors.textPrimary,
                          size: 24,
                        ),
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Back',
                      ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'My Profile',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Inter',
                          color: ProfileColors.textPrimary,
                        ),
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
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );

    return TeacherWebLayout(
      currentRoute: 'Profile',
      mobileChild: mobileChild,
      desktopBody: Stack(
        children: [
          Positioned.fill(child: Container(color: ProfileColors.background)),
          SafeArea(child: content),
        ],
      ),
    );
  }
}
