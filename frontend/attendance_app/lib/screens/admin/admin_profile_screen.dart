import 'package:flutter/material.dart';
import '../../services/profile_service.dart';
import '../../services/class_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/admin_web_layout.dart';
import '../../widgets/profile_widgets.dart';
import 'widgets/admin_entrance.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  final ProfileService _profileService = ProfileService();
  final ClassService _classService = ClassService();
  final AuthService _authService = AuthService();

  bool isLoading = true;
  String? _errorMessage;
  String userName = 'Admin';
  String userEmail = 'Not available';
  String userRole = 'Admin';
  int teacherCount = 0;
  int studentCount = 0;

  static const _roleColor = ProfileColors.tealDark;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() {
      isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _profileService.getUserProfile(),
        _classService.getAdminStats(),
      ]);

      final profile = results[0];
      final stats = results[1] as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          final role = (profile?['role'] ?? '').toString();
          final name = (profile?['username'] ?? '').toString();
          final email = (profile?['email'] ?? '').toString();
          userName = name.isNotEmpty ? name : 'Admin';
          userEmail = email.isNotEmpty ? email : 'Not available';
          userRole = role.isNotEmpty
              ? role[0].toUpperCase() + role.substring(1)
              : 'Admin';
          teacherCount =
              int.tryParse(stats['teachers_count']?.toString() ?? '') ?? 0;
          studentCount =
              int.tryParse(stats['students_count']?.toString() ?? '') ?? 0;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
          _errorMessage = 'Could not load your profile. Please try again.';
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

  List<Widget> _statCards() => [
    ProfileStatCard(
      title: 'Total Teachers',
      value: teacherCount.toString(),
      icon: Icons.person_rounded,
      accentColor: const Color(0xFFF59E0B),
    ),
    ProfileStatCard(
      title: 'Total Students',
      value: studentCount.toString(),
      icon: Icons.people_alt_rounded,
      accentColor: const Color(0xFF10B981),
    ),
  ];

  Widget _identityBlock({required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ProfileAvatar(
          initial: userName.isNotEmpty ? userName[0].toUpperCase() : 'A',
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

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: ProfileColors.textMuted),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadProfileData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileBody() {
    return AdminEntrance(
      child: SingleChildScrollView(
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
    return AdminEntrance(
      child: SingleChildScrollView(
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
    final Widget content = isLoading
        ? const Center(
            child: CircularProgressIndicator(color: ProfileColors.teal),
          )
        : _errorMessage != null
            ? _buildErrorState()
            : (MediaQuery.of(context).size.width >= 1024
                  ? _buildDesktopBody()
                  : _buildMobileBody());

    return AdminWebLayout(
      currentRoute: 'Profile',
      mobileTitle: const Text(
        'My Profile',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: ProfileColors.textPrimary,
        ),
      ),
      mobileActions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: ProfileColors.textPrimary),
          onPressed: _loadProfileData,
          tooltip: 'Refresh',
        ),
      ],
      mobileChild: Scaffold(
        backgroundColor: ProfileColors.background,
        body: content,
      ),
      desktopBody: Stack(
        children: [
          Positioned.fill(child: Container(color: ProfileColors.background)),
          SafeArea(child: content),
        ],
      ),
    );
  }
}
