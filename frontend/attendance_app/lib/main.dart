import 'package:flutter/material.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/dashboard/student_dashboard.dart';
import 'screens/dashboard/teacher_dashboard.dart';
import 'screens/teacher/session_create_screen.dart';
import 'screens/teacher/my_classes_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Attendance App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignUpPage(),
        '/student': (context) => const StudentDashboardPage(),
        '/teacher': (context) => const TeacherDashboardPage(),
        '/teacher/my-classes': (context) => const MyClassesScreen(),
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
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
    );
  }
}