import 'package:flutter/material.dart';
import 'package:skyaware/components/NavigationBar.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SkyAware',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Color(0xFF0A1A2F),
        useMaterial3: true,
      ),
      home: Navigationbar(),
    );
  }
}
