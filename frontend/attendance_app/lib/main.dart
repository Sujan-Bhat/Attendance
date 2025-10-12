import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance Demo',
      home: Scaffold(
        appBar: AppBar(title: const Text('Attendance (Web Preview)')),
        body: const Center(child: Text('Flutter Web is running!Apple is sweet')),
      ),
    );
  }
}
