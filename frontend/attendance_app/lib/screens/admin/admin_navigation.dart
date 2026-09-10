import 'package:flutter/material.dart';

import 'admin_dashboard_screen.dart';
import 'manage_classes_screen.dart';
import 'manage_students_screen.dart';
import 'manage_teachers_screen.dart';
import 'admin_profile_screen.dart';

const List<AdminNavItem> kAdminNavItems = [
  AdminNavItem(title: 'Dashboard', icon: Icons.dashboard_rounded),
  AdminNavItem(title: 'Manage Students', icon: Icons.people_alt_rounded),
  AdminNavItem(title: 'Manage Teachers', icon: Icons.person_rounded),
  AdminNavItem(title: 'Manage Classes', icon: Icons.class_rounded),
  AdminNavItem(title: 'Profile', icon: Icons.person_outline_rounded),
];

class AdminNavItem {
  final String title;
  final IconData icon;

  const AdminNavItem({required this.title, required this.icon});
}

PageRouteBuilder _fadeRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 150),
    reverseTransitionDuration: const Duration(milliseconds: 150),
  );
}

Widget _pageForRoute(String title) {
  switch (title) {
    case 'Dashboard':
      return const AdminDashboardPage();
    case 'Manage Students':
      return const ManageStudentsScreen();
    case 'Manage Teachers':
      return const ManageTeachersScreen();
    case 'Manage Classes':
      return const ManageClassesScreen();
    case 'Profile':
      return const AdminProfileScreen();
    default:
      return const AdminDashboardPage();
  }
}

Future<void> navigateToAdminScreen(BuildContext context, String title) {
  return Navigator.push(context, _fadeRoute(_pageForRoute(title)));
}
