import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../screens/admin/admin_navigation.dart';

class _AppColors {
  static const darkBg = Color(0xFF1E1E2C);
  static const tealDark = Color(0xFF007C91);
}

class AdminWebLayout extends StatefulWidget {
  final Widget mobileChild;
  final Widget desktopBody;
  final String currentRoute;
  final bool showMobileAppBar;
  final Widget? mobileTitle;
  final List<Widget>? mobileActions;

  const AdminWebLayout({
    super.key,
    required this.mobileChild,
    required this.desktopBody,
    required this.currentRoute,
    this.showMobileAppBar = true,
    this.mobileTitle,
    this.mobileActions,
  });

  @override
  State<AdminWebLayout> createState() => _AdminWebLayoutState();
}

class _AdminWebLayoutState extends State<AdminWebLayout> {
  final AuthService _authService = AuthService();

  /// Expanding/collapsing is per-screen (non-static) so the choice does not
  /// leak across screens or between login sessions.
  bool _isSidebarExpanded = false;

  String _userName = 'Admin';
  String _username = '';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    try {
      final user = await _authService.getCurrentUser();
      if (!mounted || user == null) return;
      final first = (user['first_name'] ?? '').toString().trim();
      final username = (user['username'] ?? '').toString().trim();
      setState(() {
        _userName = first.isNotEmpty
            ? first
            : (username.isNotEmpty ? username : 'Admin');
        _username = username;
      });
    } catch (_) {}
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

  Widget _buildSidebarItem(IconData icon, String title) {
    final isSelected = widget.currentRoute == title;
    final showLabel = _isSidebarExpanded;

    final Widget item = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => title == 'Logout' ? _logout() : _handleCardTap(title),
          child: Container(
            height: 48,
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Icon(
                    icon,
                    color: isSelected ? _AppColors.tealDark : Colors.white70,
                    size: 24,
                  ),
                ),
                if (showLabel) ...[
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: isSelected
                            ? _AppColors.tealDark
                            : Colors.white70,
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      // Only collapsed rows need a tooltip: an empty message still renders
      // an empty bubble beside every labelled row.
      child: showLabel ? item : Tooltip(message: title, child: item),
    );
  }

  Future<void> _handleCardTap(String title) async {
    if (title == widget.currentRoute) return;
    await navigateToAdminScreen(context, title);
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E1E2C), Color(0xFF2D2D44)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_AppColors.tealDark, Color(0xFF0097A7)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.admin_panel_settings_rounded,
                      size: 35,
                      color: _AppColors.tealDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_username.isNotEmpty)
                    Text(
                      '@$_username',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            ...kAdminNavItems.map((item) {
              final isActive = widget.currentRoute == item.title;
              return ListTile(
                leading: Icon(item.icon, color: Colors.white70, size: 22),
                title: Text(
                  item.title,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: isActive,
                selectedTileColor: Colors.white.withOpacity(0.1),
                onTap: () async {
                  Navigator.pop(context);
                  if (isActive) return;
                  await navigateToAdminScreen(context, item.title);
                },
              );
            }),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white70, size: 22),
              title: const Text('Logout',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopSidebar() {
    return GestureDetector(
      onTap: () => setState(() => _isSidebarExpanded = !_isSidebarExpanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _isSidebarExpanded ? 220 : 72,
        decoration: const BoxDecoration(
          color: _AppColors.darkBg,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(2, 0),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: IconButton(
                icon: const Icon(
                  Icons.menu_rounded,
                  color: Colors.white70,
                  size: 28,
                ),
                onPressed: () =>
                    setState(() => _isSidebarExpanded = !_isSidebarExpanded),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: kAdminNavItems
                    .map((c) => _buildSidebarItem(c.icon, c.title))
                    .toList(),
              ),
            ),
            _buildSidebarItem(Icons.logout, 'Logout'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isDesktop = screenW >= 1024;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F9FC),
        body: Stack(
          children: [
            SafeArea(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: EdgeInsets.only(left: _isSidebarExpanded ? 220.0 : 72.0),
                child: widget.desktopBody,
              ),
            ),
            if (_isSidebarExpanded)
              GestureDetector(
                onTap: () => setState(() => _isSidebarExpanded = false),
                child: Container(color: Colors.transparent),
              ),
            SafeArea(child: _buildDesktopSidebar()),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: widget.showMobileAppBar
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded, color: _AppColors.tealDark),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              title: widget.mobileTitle,
              actions: widget.mobileActions,
            )
          : null,
      drawer: _buildMobileDrawer(),
      body: widget.mobileChild,
    );
  }
}
