import 'package:flutter/material.dart';

class switchThemeMode extends StatefulWidget {
  final ThemeMode darkMode;
  final Function toggleTheme;

  const switchThemeMode({
    super.key,
    required this.darkMode,
    required this.toggleTheme,
  });

  @override
  State<switchThemeMode> createState() => _switchThemeModeState();
}

class _switchThemeModeState extends State<switchThemeMode> {
  @override
  Widget build(BuildContext context) {
    // Calculate the current state based on the passed theme mode
    bool isDarkMode = widget.darkMode == ThemeMode.dark;

    return Switch(
      value: isDarkMode,
      onChanged: (val) {
        // Pass the new value to the callback
        widget.toggleTheme(val);
      },
      activeColor: const Color(0xFF0A84FF),
    );
  }
}
