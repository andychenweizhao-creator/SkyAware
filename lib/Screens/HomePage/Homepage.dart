import 'package:flutter/material.dart';
import 'dart:ui';
import '../../Login /login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _Homepage();
}

class _Homepage extends State<HomePage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A2F),
      body: Stack(
        children: [
          // Global Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0A1A2F), Color(0xFF1C2C54), Color(0xFF0A1A2F)],
              ),
            ),
          ),
          // Orbs
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0A84FF).withOpacity(0.1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0A84FF).withOpacity(0.2),
                    blurRadius: 80.0,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 32),
                  _buildLoginLink(),
                  const SizedBox(height: 100), // Bottom padding for nav bar
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Icon(Icons.flight_takeoff, color: Colors.white, size: 48),
        const SizedBox(height: 16),
        const Text(
          "SkyAware",
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -1.0,
          ),
        ),
        Text(
          "Aviation Intelligence System",
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginLink() {
    return TextButton(
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginPage()));
      },
      child: Text(
        "Login for Flight Planning",
        style: TextStyle(color: Colors.white.withOpacity(0.5)),
      ),
    );
  }
}
