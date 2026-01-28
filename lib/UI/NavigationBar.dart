import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skyaware/Screens/Weather/WeatherPage.dart';
import '../Screens/HomePage/Homepage.dart';
import '../Screens/DashBoard/DashBoard.dart';
import '../Screens/Settings/Settings.dart';

class Navigationbar extends StatefulWidget{
  const Navigationbar({super.key});

  @override
  State<StatefulWidget> createState() {
    return NavigationbarState();
  }
}

class NavigationbarState extends State<Navigationbar>{
  int currentIndex = 0;

  final List<Widget> _pages = [
    const HomePage(),
    const DashBoard(),
    const WeatherPage(),
    const Settings(),
  ];

  void onTabTapped(int index) {
    setState(() {
      currentIndex = index;
    });
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildGlassNavigationBar(),
    );
  }

  Widget _buildGlassNavigationBar() {
    return Container(
      // Lift it off the bottom to make it floating
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      height: 70, // Explicit height
      decoration: BoxDecoration(
        color: Colors.transparent, // Container itself is transparent
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
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
                // Use a very dark, low opacity tint to allow background to shine through but stay legible
                color: const Color(0xFF0A1A2F).withOpacity(0.4), 
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: Colors.white.withOpacity(0.15),
                  width: 1.0,
                ),
              ),
            ),
            // Layer C: The Actual Row of Icons
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(0, Icons.home_rounded, "Home"),
                  _buildNavItem(1, Icons.dashboard_rounded, "Dashboard"),
                  _buildNavItem(2, Icons.cloud_rounded, "Weather"),
                  _buildNavItem(3, Icons.settings_rounded, "Settings"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = currentIndex == index;
    return GestureDetector(
      onTap: () => onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: isSelected ? 20 : 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.15) : Colors.transparent,
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
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
