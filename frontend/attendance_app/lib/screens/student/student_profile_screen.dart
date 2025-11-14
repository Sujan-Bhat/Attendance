import 'package:flutter/material.dart';
import '../../services/profile_service.dart';
import '../../services/auth_service.dart';

class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen>
    with TickerProviderStateMixin {
  final ProfileService _profileService = ProfileService();
  final AuthService _authService = AuthService();

  late AnimationController _haloController;
  late Animation<double> _haloAnim;
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
      // Get user profile
      final profile = await _profileService.getUserProfile();
      
      // Get enrolled classes
      final classes = await _profileService.getStudentClasses();
      
      // Get attendance stats
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
    _haloController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenW = MediaQuery.of(context).size.width;
    final bool isMobile = screenW < 600;

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF00BCD4), Color(0xFF00838F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                // App Bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          'My Profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
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
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(height: 20),
                              
                              // Profile Avatar with Halo
                              AnimatedBuilder(
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
                                        radius: isMobile ? 60 : 80,
                                        backgroundColor: Colors.white,
                                        child: Text(
                                          userName.isNotEmpty ? userName[0].toUpperCase() : 'S',
                                          style: TextStyle(
                                            fontSize: isMobile ? 48 : 64,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF00838F),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              
                              const SizedBox(height: 20),
                              
                              // Name & Role
                              FadeTransition(
                                opacity: _fadeIn,
                                child: Column(
                                  children: [
                                    Text(
                                      userName,
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      userRole,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 30),
                              
                              // Stats Cards
                              Center(
                                child: Wrap(
                                  spacing: 18,
                                  runSpacing: 18,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    _profileStatCard(
                                      "Enrolled Classes",
                                      totalClasses.toString(),
                                      Colors.orange,
                                    ),
                                    _profileStatCard(
                                      "Attendance Rate",
                                      "$attendanceRate%",
                                      Colors.teal,
                                    ),
                                    _profileStatCard(
                                      "Total Sessions",
                                      totalAttendance.toString(),
                                      Colors.purple,
                                    ),
                                    _profileStatCard(
                                      "Present",
                                      presentCount.toString(),
                                      Colors.green,
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 30),
                              
                              // Email Info
                              FadeTransition(
                                opacity: _fadeIn,
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white30),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.email_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Email Address',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              userEmail,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              
                              const SizedBox(height: 40),
                              
                              // Action Buttons
                              FadeTransition(
                                opacity: _fadeIn,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _profileActionButton(
                                      Icons.logout,
                                      "Logout",
                                      Colors.redAccent,
                                      _logout,
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 40),
                            ],
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

  Widget _profileStatCard(String title, String value, Color color) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.85), color],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _profileActionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 6,
      ),
      icon: Icon(icon, size: 20, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }
}