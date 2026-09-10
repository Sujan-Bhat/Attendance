import 'package:flutter/material.dart';
import '../../services/profile_service.dart';
import '../../services/class_service.dart';
import '../../widgets/admin_web_layout.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen>
    with TickerProviderStateMixin {
  final ProfileService _profileService = ProfileService();
  final ClassService _classService = ClassService();

  late AnimationController _haloController;
  late Animation<double> _haloAnim;
  late AnimationController _fadeController;
  late Animation<double> _fadeIn;

  bool isLoading = true;
  String userName = 'Admin';
  String userEmail = 'Loading...';
  String userRole = 'Admin';
  int teacherCount = 0;
  int studentCount = 0;

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
    _fadeIn = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    _haloController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _haloAnim = Tween<double>(begin: 0.8, end: 1.15).animate(
      CurvedAnimation(parent: _haloController, curve: Curves.easeInOut),
    );
    _haloController.repeat(reverse: true);
  }

  Future<void> _loadProfileData() async {
    setState(() => isLoading = true);

    try {
      final results = await Future.wait([
        _profileService.getUserProfile(),
        _classService.getAdminStats(),
      ]);

      final profile = results[0];
      final stats = results[1] as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          final role = profile?['role'] as String? ?? 'admin';
          userName = (profile?['username'] as String?) ?? 'Admin';
          userEmail = (profile?['email'] as String?) ?? 'Not available';
          userRole = role[0].toUpperCase() + role.substring(1);
          teacherCount = (stats['teachers_count'] as int?) ?? 0;
          studentCount = (stats['students_count'] as int?) ?? 0;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _haloController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;
    final isDesktop = screenW >= 1024;

    return AdminWebLayout(
      currentRoute: 'Profile',
      mobileChild: _buildProfileBody(isMobile, isDesktop),
      desktopBody: _buildProfileBody(isMobile, isDesktop),
    );
  }

  Widget _buildProfileBody(bool isMobile, bool isDesktop) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF0288A3)),
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isMobile, isDesktop),
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: EdgeInsets.all(isMobile ? 16 : 40),
                        child: isDesktop
                            ? _buildDesktopContent()
                            : _buildMobileContent(isMobile),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isMobile, bool isDesktop) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 4 : 16, 8, isMobile ? 4 : 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isMobile ? 24 : 36,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'View your profile Summary',
                style: TextStyle(
                  color: const Color(0xFFA9E1EC),
                  fontSize: isMobile ? 12 : 18,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: isMobile ? 48 : 79,
            height: isMobile ? 48 : 75,
            decoration: ShapeDecoration(
              color: const Color(0xFF44B3B9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadProfileData,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopContent() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildLeftStats()),
            _buildProfileCenter(),
            Expanded(child: _buildRightStats()),
          ],
        ),
        const SizedBox(height: 40),
        _buildEmailCard(),
      ],
    );
  }

  Widget _buildMobileContent(bool isMobile) {
    return Column(
      children: [
        const SizedBox(height: 20),
        _buildProfileAvatar(isMobile),
        const SizedBox(height: 16),
        FadeTransition(
          opacity: _fadeIn,
          child: Column(
            children: [
              Text(
                userName,
                style: TextStyle(
                  color: const Color(0xFFE0F2F5),
                  fontSize: isMobile ? 28 : 37,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                userRole,
                style: TextStyle(
                  color: const Color(0xFFDADBDC),
                  fontSize: isMobile ? 20 : 27,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: [
            _buildStatCard('Total\nTeachers', '$teacherCount'),
            _buildStatCard('Total\nStudents', '$studentCount'),
          ],
        ),
        const SizedBox(height: 24),
        _buildEditProfileCard(isMobile),
        const SizedBox(height: 24),
        _buildEmailCard(),
      ],
    );
  }

  Widget _buildLeftStats() {
    return FadeTransition(
      opacity: _fadeIn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatCard('Total\nTeachers', '$teacherCount'),
          const SizedBox(height: 24),
          _buildStatCard('Total\nStudents', '$studentCount'),
        ],
      ),
    );
  }

  Widget _buildRightStats() {
    return FadeTransition(
      opacity: _fadeIn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildStatCard('Total\nUsers', '${teacherCount + studentCount}'),
          const SizedBox(height: 24),
          _buildEditProfileCard(false),
        ],
      ),
    );
  }

  Widget _buildProfileCenter() {
    return Column(
      children: [
        _buildProfileAvatar(false),
        const SizedBox(height: 24),
        FadeTransition(
          opacity: _fadeIn,
          child: Column(
            children: [
              Text(
                userName,
                style: const TextStyle(
                  color: Color(0xFFE0F2F5),
                  fontSize: 37,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                userRole,
                style: const TextStyle(
                  color: Color(0xFFDADBDC),
                  fontSize: 27,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileAvatar(bool isMobile) {
    return AnimatedBuilder(
      animation: _haloAnim,
      builder: (context, child) {
        return Transform.scale(
          scale: _haloAnim.value,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: isMobile ? 70 : 100,
              backgroundColor: Colors.white,
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : 'A',
                style: TextStyle(
                  fontSize: isMobile ? 80 : 110,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0288A3),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(24),
      decoration: ShapeDecoration(
        color: const Color(0x33FAE6E6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 31,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditProfileCard(bool isCompact) {
    return Container(
      width: isCompact ? double.infinity : 200,
      padding: EdgeInsets.all(isCompact ? 26 : 28),
      decoration: ShapeDecoration(
        color: const Color(0x33C1FEFE),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(23),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Edit\nProfile',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              width: 48,
              height: 48,
              decoration: const ShapeDecoration(
                color: Color(0xFF44B3B9),
                shape: OvalBorder(),
              ),
              child: const Icon(Icons.edit_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailCard() {
    return FadeTransition(
      opacity: _fadeIn,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 32),
        decoration: ShapeDecoration(
          color: const Color(0x7C34A3B6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(35),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const ShapeDecoration(
                color: Color(0xFF44B3B9),
                shape: OvalBorder(),
              ),
              child: const Icon(Icons.email_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                userEmail,
                style: const TextStyle(
                  color: Color(0xFFE0F2F5),
                  fontSize: 22,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
