import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../Login/login_page.dart';


class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> with SingleTickerProviderStateMixin {
  bool _notificationsEnabled = true;
  bool _darkMode = true;
  
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad));
    
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Logged out successfully")),
      );
    }
    setState(() {}); 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A2F),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0A1A2F), Color(0xFF1C2C54), Color(0xFF0A1A2F)],
              ),
            ),
          ),
          // Decorative Orbs
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
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7D2AE8).withOpacity(0.1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7D2AE8).withOpacity(0.2),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          
          // Content
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.userChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }

              final User? currentUser = snapshot.data;

              return FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Column(
                        children: [
                          // Profile Section
                          _buildProfileSection(currentUser),
                          
                          const SizedBox(height: 24),
                          
                          // Settings Groups
                          _buildSettingsGroup(
                            title: "General",
                            children: [
                              _buildSettingsTile(
                                icon: Icons.notifications_outlined,
                                title: "Notifications",
                                trailing: Switch(
                                  value: _notificationsEnabled,
                                  onChanged: (val) => setState(() => _notificationsEnabled = val),
                                  activeColor: const Color(0xFF0A84FF),
                                ),
                              ),
                              _buildSettingsTile(
                                icon: Icons.dark_mode_outlined,
                                title: "Dark Mode",
                                trailing: Switch(
                                  value: _darkMode,
                                  onChanged: (val) => setState(() => _darkMode = val),
                                  activeColor: const Color(0xFF0A84FF),
                                ),
                              ),
                              _buildSettingsTile(
                                icon: Icons.language,
                                title: "Language",
                                trailing: const Text("English", style: TextStyle(color: Colors.white54)),
                                onTap: () {},
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 20),
                          
                          _buildSettingsGroup(
                            title: "Support & About",
                            children: [
                              _buildSettingsTile(
                                icon: Icons.help_outline,
                                title: "Help & Support",
                                onTap: () {},
                              ),
                              _buildSettingsTile(
                                icon: Icons.info_outline,
                                title: "About SkyAware",
                                onTap: () {},
                              ),
                              _buildSettingsTile(
                                icon: Icons.privacy_tip_outlined,
                                title: "Privacy Policy",
                                onTap: () {},
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 30),
                          
                          if (currentUser != null)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _logout,
                                icon: const Icon(Icons.logout, color: Colors.white),
                                label: const Text("Log Out"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent.withOpacity(0.2),
                                  foregroundColor: Colors.redAccent,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
                                  ),
                                ),
                              ),
                            ),
                          
                          const SizedBox(height: 20),
                          Text(
                            "Version 1.0.0",
                            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection(User? user) {
    if (user == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            const Icon(Icons.account_circle_outlined, size: 60, color: Colors.white54),
            const SizedBox(height: 16),
            const Text(
              "Sign in to sync your flight plans and preferences.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A84FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Login/ Sign Up"),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF0A84FF), width: 2),
            ),
            child: CircleAvatar(
              radius: 35,
              backgroundColor: Colors.white.withOpacity(0.1),
              backgroundImage: (user.photoURL != null && user.photoURL!.isNotEmpty)
                  ? NetworkImage(user.photoURL!)
                  : null,
              child: (user.photoURL == null || user.photoURL!.isEmpty)
                  ? Text(
                      user.displayName?.isNotEmpty == true
                          ? user.displayName![0].toUpperCase()
                          : "U",
                      style: const TextStyle(fontSize: 28, color: Colors.white),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName ?? "Pilot",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  user.email ?? "",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    // Navigate to profile edit page if available
                  },
                  child: Row(
                    children: [
                      Text(
                        "Edit Profile",
                        style: TextStyle(color: const Color(0xFF0A84FF).withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios, size: 10, color: const Color(0xFF0A84FF).withOpacity(0.9)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              if (trailing != null)
                trailing
              else
                Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.3), size: 14),
            ],
          ),
        ),
      ),
    );
  }
}
