import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/dashboard/student_dashboard.dart';
import 'screens/dashboard/teacher_dashboard.dart';
import 'screens/teacher/session_create_screen.dart';
import 'screens/teacher/my_classes_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();

  String initialRoute = '/login';

  // Try to get initial link from AppLinks
  try {
    final appLinks = AppLinks();
    final initialUri = await appLinks.getInitialLink();
    if (initialUri != null && initialUri.path.startsWith('/join/')) {
      final code = initialUri.path.split('/join/').last;
      await StorageService.write(key: 'pending_join_code', value: code);
    }
  } catch (e) {
    debugPrint('Error getting initial deep link: $e');
  }

  // Also extract initial path from the web URL if present (hash routing fallback)
  final currentPath = Uri.base.fragment;
  if (currentPath.startsWith('/join/')) {
    final code = currentPath.split('/join/').last;
    await StorageService.write(key: 'pending_join_code', value: code);
  }

  final userJson = await StorageService.read(key: 'user');
  if (userJson != null && userJson.isNotEmpty) {
    try {
      final user = jsonDecode(userJson);
      if (user['role'] == 'student') {
        initialRoute = '/student';
      } else if (user['role'] == 'teacher') {
        initialRoute = '/teacher';
      } else if (user['role'] == 'admin') {
        initialRoute = '/admin';
      }
    } catch (e) {
      debugPrint('Error parsing saved user: $e');
    }
  }

  runApp(MyApp(initialRoute: initialRoute));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class MyApp extends StatefulWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) async {
      debugPrint('onAppLink: $uri');
      if (uri.path.startsWith('/join/')) {
        final code = uri.path.split('/join/').last;
        await StorageService.write(key: 'pending_join_code', value: code);

        if (navigatorKey.currentState != null) {
          String nextRoute = '/login';
          final userJson = await StorageService.read(key: 'user');
          if (userJson != null && userJson.isNotEmpty) {
            try {
              final user = jsonDecode(userJson);
              if (user['role'] == 'student') {
                nextRoute = '/student';
              } else if (user['role'] == 'teacher') {
                nextRoute = '/teacher';
              } else if (user['role'] == 'admin') {
                nextRoute = '/admin';
              }
            } catch (e) {
              debugPrint('Error parsing saved user: $e');
            }
          }
          navigatorKey.currentState!.pushReplacementNamed(nextRoute);
        }
      }
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Attendance App',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      initialRoute: widget.initialRoute,
      routes: {
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignUpPage(),
        '/student': (context) => const StudentDashboardPage(),
        '/teacher': (context) => const TeacherDashboardPage(),
        '/teacher/my-classes': (context) => const MyClassesScreen(),
        '/admin': (context) => const AdminDashboardPage(),
        '/teacher/create-session': (context) => const SessionPage(
          // Add required subjects parameter later use backend (for testing)
          subjects: [
            {'code': 'CS101', 'name': 'Computer Science'},
            {'code': 'MA102', 'name': 'Mathematics'},
            {'code': 'PH103', 'name': 'Physics'},
            {'code': 'EN104', 'name': 'English'},
            {'code': 'CH105', 'name': 'Chemistry'},
            {'code': 'BIO106', 'name': 'Biology'},
          ],
        ),
      },
      onGenerateRoute: (settings) {
        if (settings.name != null && settings.name!.startsWith('/join/')) {
          final code = settings.name!.split('/join/').last;
          // Save for when they log in
          StorageService.write(key: 'pending_join_code', value: code);
          // Redirect based on role
          return MaterialPageRoute(
            builder: (_) => widget.initialRoute == '/student'
                ? const StudentDashboardPage()
                : const LoginPage(),
          );
        }
        return null;
      },
      onUnknownRoute: (settings) =>
          MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }
}
