import 'dart:ui';
import 'package:flutter/material.dart';
import '../../services/profile_service.dart';
import '../../services/class_service.dart';
import '../../widgets/admin_web_layout.dart';
import '../../widgets/magical_profile_widgets.dart';
import '../../services/auth_service.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen>
    with TickerProviderStateMixin {
  final ProfileService _profileService = ProfileService();
  final ClassService _classService = ClassService();
  final AuthService _authService = AuthService();

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
      duration: const Duration(milliseconds: 1000),
    );
    _fadeIn = CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic);
    _fadeController.forward();
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

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Logout', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to logout?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
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

  @override
  Widget build(BuildContext context) {
    final double screenW = MediaQuery.of(context).size.width;
    final bool isMobile = screenW < 600;

    Widget mainContent = Stack(
      children: [
        const Positioned.fill(child: MagicalBackground()),
        
        SafeArea(
          child: Column(
            children: [
              // App Bar equivalent for Web Layout consistency
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 20,
                  vertical: isMobile ? 10 : 14,
                ),
                color: Colors.transparent,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Back',
                    ),
                    SizedBox(width: isMobile ? 8 : 12),
                    const Expanded(
                      child: Text(
                        'My Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _loadProfileData,
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
                      )
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                        child: FadeTransition(
                          opacity: _fadeIn,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(height: 20),
                              
                              // Hero Avatar
                              MagicalAvatar(
                                initial: userName.isNotEmpty ? userName[0].toUpperCase() : 'A',
                                radius: isMobile ? 60 : 80,
                              ),
                              
                              const SizedBox(height: 30),
                              
                              // Name & Role
                              Text(
                                userName,
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFF8B5CF6).withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  userRole.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF8B5CF6),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              
                              const SizedBox(height: 40),
                              
                              // Stats Cards
                              Center(
                                child: Wrap(
                                  spacing: 20,
                                  runSpacing: 20,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    MagicalGlassCard(
                                      title: "Total Teachers",
                                      value: teacherCount.toString(),
                                      accentColor: const Color(0xFFF59E0B),
                                      width: isMobile ? 150 : 180,
                                    ),
                                    MagicalGlassCard(
                                      title: "Total Students",
                                      value: studentCount.toString(),
                                      accentColor: const Color(0xFF10B981),
                                      width: isMobile ? 150 : 180,
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 40),
                              
                              // Email Info (Glass panel)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                  child: Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.email_outlined,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Email Address',
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.6),
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                userEmail,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              
                              const SizedBox(height: 40),
                              
                              // Logout Button
                              GestureDetector(
                                onTap: _logout,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                                      SizedBox(width: 12),
                                      Text(
                                        "Logout",
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );

    Widget mobileChild = Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF0F172A),
      body: mainContent,
    );

    return AdminWebLayout(
      currentRoute: 'Profile',
      mobileChild: mobileChild,
      desktopBody: mainContent,
    );
  }
}
