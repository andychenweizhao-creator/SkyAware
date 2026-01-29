import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'UI/NavigationBar.dart';
import 'dart:io';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'UI/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isIOS) {
    WebViewPlatform.instance = WebKitWebViewPlatform();
  }
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeController(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);

    return MaterialApp(
      title: 'SkyAware',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),
        primaryColor: const Color(0xFF0A84FF),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0A84FF),
          secondary: Color(0xFF7D2AE8),
          surface: Colors.white,
          background: Color(0xFFF0F2F5),
          onBackground: Color(0xFF0A1A2F),
          onSurface: Color(0xFF0A1A2F),
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CinematicPageTransitionsBuilder(),
            TargetPlatform.iOS: CinematicPageTransitionsBuilder(),
          },
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A1A2F),
        primaryColor: const Color(0xFF0A84FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0A84FF),
          secondary: Color(0xFF7D2AE8),
          surface: Color(0xFF1C2C54),
          background: Color(0xFF0A1A2F),
          onBackground: Colors.white,
          onSurface: Colors.white,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CinematicPageTransitionsBuilder(),
            TargetPlatform.iOS: CinematicPageTransitionsBuilder(),
          },
        ),
      ),
      themeMode: themeController.themeMode,
      debugShowCheckedModeBanner: false,
      home: const Navigationbar(),
    );
  }
}

class CinematicPageTransitionsBuilder extends PageTransitionsBuilder {
  const CinematicPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      builder: (context, child) {
        // Entrance: Scale 1.1 -> 1.0, Opacity 0.0 -> 1.0
        final entranceCurve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        final entranceScale = Tween<double>(begin: 1.1, end: 1.0).evaluate(entranceCurve);
        final entranceOpacity = Tween<double>(begin: 0.0, end: 1.0).evaluate(entranceCurve);

        // Exit (Background): Scale 1.0 -> 0.95, Opacity 1.0 -> 0.0
        final exitCurve = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInCubic);
        final exitScale = Tween<double>(begin: 1.0, end: 0.95).evaluate(exitCurve);
        final exitOpacity = Tween<double>(begin: 1.0, end: 0.0).evaluate(exitCurve);

        // Combined logic: 
        // If secondaryAnimation is running (we are being covered), we use exit values.
        // If animation is running (we are appearing), we use entrance values.
        // Since we want both valid at same time (e.g. transparent route), we multiply.
        // However, usually one dominates.
        
        final currentScale = entranceScale * (secondaryAnimation.value > 0 ? exitScale : 1.0);
        final currentOpacity = entranceOpacity * exitOpacity;

        return Opacity(
          opacity: currentOpacity,
          child: Transform.scale(
            scale: currentScale,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
