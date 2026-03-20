import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'UI/NavigationBar.dart';
import 'dart:io';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'UI/theme_controller.dart';
import 'services/unit_settings_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Screens/Login/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isIOS) {
    WebViewPlatform.instance = WebKitWebViewPlatform();
  }
  
  // 1. Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 2. Activate App Check
  await FirebaseAppCheck.instance.activate(
    // Uses the debug provider so you can test on emulators/local devices safely.
    // Note: For production releases, you will change this to AndroidProvider.playIntegrity
    androidProvider: AndroidProvider.debug, 
    appleProvider: AppleProvider.debug,
  );

  // 3. Sign in anonymously so the Cloud Function has a UID for your usage cap!
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
      print("Signed in automatically!");
    }
  } catch (e) {
    print("Auth error: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => UnitSettingsProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Stream<User?> _authStream;

  @override
  void initState() {
    super.initState();
    // Cache the stream so it doesn't get recreated on every theme change rebuild
    _authStream = FirebaseAuth.instance.authStateChanges();
  }

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
        extensions: <ThemeExtension<dynamic>>[
          AviationColors.lightAviationColors,
        ],
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
        extensions: <ThemeExtension<dynamic>>[
          AviationColors.darkAviationColors,
        ],
      ),
      themeMode: themeController.themeMode,
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<User?>(
        stream: _authStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          
          if (snapshot.hasData && snapshot.data != null) {
            return const Navigationbar();
          } else {
            return const LoginPage();
          }
        },
      ),
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

@immutable
class AviationColors extends ThemeExtension<AviationColors> {
  const AviationColors({
    required this.vfr,
    required this.mvfr,
    required this.ifr,
    required this.lifr,
    required this.mapButtonBg,
    required this.mapButtonIcon,
    required this.distanceMenuBg,
    required this.distanceMenuText,
  });

  final Color? vfr;
  final Color? mvfr;
  final Color? ifr;
  final Color? lifr;
  final Color? mapButtonBg;
  final Color? mapButtonIcon;
  final Color? distanceMenuBg;
  final Color? distanceMenuText;

  @override
  AviationColors copyWith({
    Color? vfr,
    Color? mvfr,
    Color? ifr,
    Color? lifr,
    Color? mapButtonBg,
    Color? mapButtonIcon,
    Color? distanceMenuBg,
    Color? distanceMenuText,
  }) {
    return AviationColors(
      vfr: vfr ?? this.vfr,
      mvfr: mvfr ?? this.mvfr,
      ifr: ifr ?? this.ifr,
      lifr: lifr ?? this.lifr,
      mapButtonBg: mapButtonBg ?? this.mapButtonBg,
      mapButtonIcon: mapButtonIcon ?? this.mapButtonIcon,
      distanceMenuBg: distanceMenuBg ?? this.distanceMenuBg,
      distanceMenuText: distanceMenuText ?? this.distanceMenuText,
    );
  }

  @override
  AviationColors lerp(AviationColors? other, double t) {
    if (other is! AviationColors) {
      return this;
    }
    return AviationColors(
      vfr: Color.lerp(vfr, other.vfr, t),
      mvfr: Color.lerp(mvfr, other.mvfr, t),
      ifr: Color.lerp(ifr, other.ifr, t),
      lifr: Color.lerp(lifr, other.lifr, t),
      mapButtonBg: Color.lerp(mapButtonBg, other.mapButtonBg, t),
      mapButtonIcon: Color.lerp(mapButtonIcon, other.mapButtonIcon, t),
      distanceMenuBg: Color.lerp(distanceMenuBg, other.distanceMenuBg, t),
      distanceMenuText: Color.lerp(distanceMenuText, other.distanceMenuText, t),
    );
  }

  // Light Mode Logic
  static const lightAviationColors = AviationColors(
    vfr: Color(0xFF2E7D32), // Darker Green (Colors.green[800])
    mvfr: Color(0xFF1565C0), // Blue (Colors.blue[800])
    ifr: Color(0xFFC62828), // Red (Colors.red[800])
    lifr: Color(0xFFAD1457), // Magenta (Colors.pink[800])
    mapButtonBg: Colors.white,
    mapButtonIcon: Color(0xFF0D47A1), // Deep Blue (Colors.blue[900])
    distanceMenuBg: Color(0xFFEEEEEE),
    distanceMenuText: Colors.black,
  );

  // Dark Mode Logic
  static const darkAviationColors = AviationColors(
    vfr: Color(0xFF00E676), // Bright/Neon Green (Colors.greenAccent[400])
    mvfr: Color(0xFF2979FF), // Bright Blue (Colors.blueAccent[400])
    ifr: Color(0xFFFF1744), // Bright Red (Colors.redAccent[400])
    lifr: Color(0xFFF50057), // Bright Magenta (Colors.pinkAccent[400])
    mapButtonBg: Color(0xFF333333),
    mapButtonIcon: Colors.cyanAccent,
    distanceMenuBg: Color(0xFF424242),
    distanceMenuText: Colors.white,
  );
}
