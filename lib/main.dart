import 'package:flutter/material.dart';
import 'package:skyaware/components/NavigationBar.dart';
import 'dart:io';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isIOS) {
    WebViewPlatform.instance = WebKitWebViewPlatform();
  }
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
