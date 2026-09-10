import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/offline_indicator.dart';

/// Shared header actions for admin screens: offline indicator, refresh and
/// logout, matching the dashboard header.
class AdminHeaderActions extends StatelessWidget {
  final VoidCallback onRefresh;
  final bool showLogout;

  const AdminHeaderActions({
    super.key,
    required this.onRefresh,
    this.showLogout = true,
  });

  Future<void> _confirmLogout(
    BuildContext context,
    AuthService authService,
  ) async {
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
      await authService.logout();
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const OfflineIndicator(),
        IconButton(
          icon: const Icon(Icons.refresh, color: Color(0xFF1F2937)),
          onPressed: onRefresh,
          tooltip: 'Refresh',
        ),
        if (showLogout)
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF1F2937)),
            onPressed: () => _confirmLogout(context, authService),
            tooltip: 'Logout',
          ),
      ],
    );
  }
}