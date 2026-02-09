import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skyaware/Screens/Weather/WeatherPage.dart';
import '../../Screens/HomePage/Homepage.dart';
import '../../Screens/DashBoard/DashBoard.dart';
import '../../Screens/Settings/Settings.dart';

class Navigationbar extends StatefulWidget{
  const Navigationbar({super.key});

  @override
  State<StatefulWidget> createState() {
    return NavigationbarState();
  }
}

class NavigationbarState extends State<Navigationbar>{
  int currentIndex = 0;
  bool _hideNavBar = false; // State to toggle nav bar visibility

  void onTabTapped(int index) {
    setState(() {
      currentIndex = index;
    });
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild pages on every build to propagate theme changes to Settings
    // Pass callback to DashBoard
    final List<Widget> pages = [
      const HomePage(),
      DashBoard(
        onEmergencyStateChanged: (isEmergency) {
          // Delay setState to avoid building while building if called directly from build
          // But here it's called from callbacks in DashBoard children, so mostly fine.
          // Using microtask just in case it happens during a build phase.
          Future.microtask(() {
            if (mounted) {
              setState(() {
                _hideNavBar = isEmergency;
              });
            }
          });
        },
      ),
      const WeatherPage(),
      const Settings(),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: currentIndex,
        children: pages,
      ),
      // Hide nav bar if emergency mode is active
      bottomNavigationBar: _hideNavBar ? null : _buildGlassNavigationBar(context),
    );
  }

  Widget _buildGlassNavigationBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark 
        ? const Color(0xFF0A1A2F).withValues(alpha: 0.8) 
        : Colors.white.withValues(alpha: 0.85);
    
    final borderColor = isDark 
        ? Colors.white.withValues(alpha: 0.15) 
        : Colors.black.withValues(alpha: 0.1);
    
    final shadowColor = isDark 
        ? Colors.black.withValues(alpha: 0.5) 
        : Colors.grey.withValues(alpha: 0.3);

    return Container(
      // Lift it off the bottom to make it floating
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      height: 70, // Explicit height
      decoration: BoxDecoration(
        color: Colors.transparent, // Container itself is transparent
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 30,
            spreadRadius: -5,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      // ClipRRect creates the rounded pill shape
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: Stack(
          children: [
            // Layer A: The Blur Effect (BackdropFilter)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
              child: Container(color: Colors.transparent),
            ),
            // Layer B: The Tint (Semi-Transparent Color)
            Container(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: borderColor,
                  width: 1.0,
                ),
              ),
            ),
            // Layer C: The Actual Row of Icons
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(0, Icons.home_rounded, "Home", isDark, theme),
                  _buildNavItem(1, Icons.dashboard_rounded, "Dashboard", isDark, theme),
                  _buildNavItem(2, Icons.cloud_rounded, "Weather", isDark, theme),
                  _buildNavItem(3, Icons.settings_rounded, "Settings", isDark, theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, bool isDark, ThemeData theme) {
    final isSelected = currentIndex == index;
    
    // Icon colors
    final selectedIconColor = isDark ? Colors.white : theme.primaryColor;
    final unselectedIconColor = isDark 
        ? Colors.white.withValues(alpha: 0.5) 
        : Colors.black.withValues(alpha: 0.5);

    // Background selection color
    final selectionBgColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : theme.primaryColor.withValues(alpha: 0.1);

    return GestureDetector(
      onTap: () => onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: isSelected ? 20 : 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? selectionBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                icon,
                color: isSelected ? selectedIconColor : unselectedIconColor,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
