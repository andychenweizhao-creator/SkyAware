import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:skyaware/UI/theme_controller.dart';
import '../../models/UserModel.dart';
import '../../services/FirebaseService.dart';
import '../Login/login_page.dart';
import 'unit_preferences_section.dart';
import '../../main.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> with SingleTickerProviderStateMixin {
  bool _notificationsEnabled = true;

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
    final themeController = Provider.of<ThemeController>(context);
    final theme = Theme.of(context);
    final aviationColors = theme.extension<AviationColors>()!;
    final isDark = theme.brightness == Brightness.dark;

    final textColor = theme.colorScheme.onSurface;
    final secondaryTextColor = theme.colorScheme.onSurface.withOpacity(0.6);
    final containerColor = (aviationColors.mapButtonBg ?? theme.cardColor).withOpacity(0.1);
    final borderColor = theme.dividerColor.withOpacity(0.1);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Settings', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.scaffoldBackgroundColor,
                  theme.colorScheme.surface,
                  theme.scaffoldBackgroundColor,
                ],
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
                color: theme.primaryColor.withOpacity(0.1),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withOpacity(0.2),
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
                color: theme.colorScheme.secondary.withOpacity(0.1),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.secondary.withOpacity(0.2),
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
                return Center(child: CircularProgressIndicator(color: textColor));
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
                          _buildProfileSection(currentUser, theme, aviationColors, textColor, secondaryTextColor, containerColor, borderColor),
                          
                          const SizedBox(height: 24),

                          // Unit Preferences Section
                          UnitPreferencesSection(
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            containerColor: containerColor,
                            borderColor: borderColor,
                            isDark: isDark, // Kept for now as UnitPreferencesSection might use it, but logic should ideally be inside
                            onUnitChange: (key,value){
                              _updatePreference(key: key, value: value);
                            }
                          ),

                          const SizedBox(height: 24),
                          
                          // Settings Groups
                          _buildSettingsGroup(
                            title: "General",
                            textColor: secondaryTextColor,
                            containerColor: containerColor,
                            borderColor: borderColor,
                            children: [
                              _buildSettingsTile(
                                icon: Icons.notifications_outlined,
                                title: "Notifications",
                                textColor: textColor,
                                iconBgColor: containerColor,
                                trailing: Switch(
                                  value: _notificationsEnabled,
                                  onChanged: (val) => setState(() => _notificationsEnabled = val),
                                  activeColor: theme.primaryColor,
                                ),
                              ),
                              _buildSettingsTile(
                                icon: Icons.dark_mode_outlined,
                                title: "Dark Mode",
                                textColor: textColor,
                                iconBgColor: containerColor,
                                trailing: Switch(
                                  value: isDark,
                                  onChanged: (val) {
                                    themeController.toggleTheme(val);
                                    _updatePreference(key: 'darkMode', value: val);
                                  },
                                  activeColor: theme.primaryColor,
                                )
                              ),
                              _buildSettingsTile(
                                icon: Icons.language,
                                title: "Language",
                                textColor: textColor,
                                iconBgColor: containerColor,
                                trailing: Text("English", style: TextStyle(color: secondaryTextColor)),
                                onTap: () {},
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 20),
                          
                          _buildSettingsGroup(
                            title: "Support & About",
                            textColor: secondaryTextColor,
                            containerColor: containerColor,
                            borderColor: borderColor,
                            children: [
                              _buildSettingsTile(
                                icon: Icons.help_outline,
                                title: "Help & Support",
                                textColor: textColor,
                                iconBgColor: containerColor,
                                onTap: () {},
                              ),
                              _buildSettingsTile(
                                icon: Icons.info_outline,
                                title: "About SkyAware",
                                textColor: textColor,
                                iconBgColor: containerColor,
                                onTap: () {},
                              ),
                              _buildSettingsTile(
                                icon: Icons.privacy_tip_outlined,
                                title: "Privacy Policy",
                                textColor: textColor,
                                iconBgColor: containerColor,
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
                                icon: const Icon(Icons.logout, color: Colors.white), // Always white for logout (red button)
                                label: const Text("Log Out"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.error.withOpacity(0.2),
                                  foregroundColor: theme.colorScheme.error,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: theme.colorScheme.error.withOpacity(0.5)),
                                  ),
                                ),
                              ),
                            ),
                          
                          const SizedBox(height: 20),
                          Text(
                            "Version 1.0.0",
                            style: TextStyle(color: secondaryTextColor, fontSize: 12),
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
  _updatePreference({
    required String key,
    required dynamic value
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return;
    }
    Usermodel user ;
    final fs = Firebaseservice();
    final userData = await fs.getUserData();
    if(userData != null) {
      user = Usermodel.fromMap(userData);
    } else {
      user = Usermodel(
          DarkMode: DarkLight.Light,
          DistanceUnit: DistanceSpeedUnit.nauticalMilesKnots,
          Altitude: AltitudeUnit.feet,
          Pressure: PressureUnit.hpa,
          Temperature: TemperatureUnit.celsius,
      );
    }

    print("This is the key");
    print(key);

    switch (key) {
      case 'darkMode':
        user.DarkMode = value ? DarkLight.Dark : DarkLight.Light;
        break;
        case 'DistanceUnit':
          user.DistanceUnit = value;
          break;
        case 'Altitude':
          user.Altitude = value;
          break;
        case 'Pressure':
          user.Pressure = value;
          break;
        case 'Temperature':
          user.Temperature = value;
          break;
    }
    await fs.setUserData(user.toMap());
  }


  Widget _buildProfileSection(User? user, ThemeData theme, AviationColors aviationColors, Color textColor, Color secondaryTextColor, Color containerColor, Color borderColor) {
    if (user == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: [
            Icon(Icons.account_circle_outlined, size: 60, color: secondaryTextColor),
            const SizedBox(height: 16),
            Text(
              "Sign in to sync your flight plans and preferences.",
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryTextColor, fontSize: 14),
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
                  backgroundColor: theme.primaryColor,
                  foregroundColor: theme.colorScheme.onPrimary,
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
        color: containerColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: theme.primaryColor, width: 2),
            ),
            child: CircleAvatar(
              radius: 35,
              backgroundColor: containerColor,
              backgroundImage: (user.photoURL != null && user.photoURL!.isNotEmpty)
                  ? NetworkImage(user.photoURL!)
                  : null,
              child: (user.photoURL == null || user.photoURL!.isEmpty)
                  ? Text(
                      user.displayName?.isNotEmpty == true
                          ? user.displayName![0].toUpperCase()
                          : "U",
                      style: TextStyle(fontSize: 28, color: textColor),
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
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  user.email ?? "",
                  style: TextStyle(
                    color: secondaryTextColor,
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
                        style: TextStyle(color: theme.primaryColor.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios, size: 10, color: theme.primaryColor.withOpacity(0.9)),
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

  Widget _buildSettingsGroup({
    required String title,
    required List<Widget> children,
    required Color textColor,
    required Color containerColor,
    required Color borderColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
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
    required Color textColor,
    required Color iconBgColor,
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
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: textColor, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: textColor, fontSize: 16),
                ),
              ),
              if (trailing != null)
                trailing
              else
                Icon(Icons.arrow_forward_ios, color: textColor.withOpacity(0.3), size: 14),
            ],
          ),
        ),
      ),
    );
  }
}
