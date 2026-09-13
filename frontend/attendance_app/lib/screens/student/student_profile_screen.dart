import 'dart:ui';
import 'package:flutter/material.dart';
import '../../services/profile_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/student_drawer.dart';
import '../../widgets/magical_profile_widgets.dart';

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
      print('Error loading profile: $e');
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
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

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF0F172A),
      drawer: isMobile ? const StudentDrawer(currentRoute: 'Profile') : null,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'My Profile',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(
              isMobile ? Icons.menu_rounded : Icons.arrow_back_rounded,
              color: Colors.white,
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
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: MagicalBackground()),
          
          SafeArea(
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
                            initial: userName.isNotEmpty ? userName[0].toUpperCase() : 'S',
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
                              color: const Color(0xFF38BDF8).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF38BDF8).withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              userRole.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF38BDF8),
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
                                  title: "Enrolled Classes",
                                  value: totalClasses.toString(),
                                  accentColor: const Color(0xFFF59E0B),
                                  width: isMobile ? 150 : 180,
                                ),
                                MagicalGlassCard(
                                  title: "Attendance Rate",
                                  value: "$attendanceRate%",
                                  accentColor: const Color(0xFF10B981),
                                  width: isMobile ? 150 : 180,
                                ),
                                MagicalGlassCard(
                                  title: "Total Sessions",
                                  value: totalAttendance.toString(),
                                  accentColor: const Color(0xFF8B5CF6),
                                  width: isMobile ? 150 : 180,
                                ),
                                MagicalGlassCard(
                                  title: "Present",
                                  value: presentCount.toString(),
                                  accentColor: const Color(0xFF38BDF8),
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
    );
  }
}
