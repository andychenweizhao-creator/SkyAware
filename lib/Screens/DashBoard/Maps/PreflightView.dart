import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../../main.dart'; // Import for AviationColors

class Preflightview extends StatefulWidget {
  final MapController? mapController;
  final VoidCallback onNavigateToPreFlight;

  const Preflightview({
    super.key,
    this.mapController,
    required this.onNavigateToPreFlight,
  });

  @override
  State<Preflightview> createState() => _PreflightviewState();
}

class _PreflightviewState extends State<Preflightview> {
  bool _isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aviationColors = theme.extension<AviationColors>()!;
    final isDark = theme.brightness == Brightness.dark;

    return Stack(
      children: [
        // REMOVED HEADER

        // 2. Sliding Menu Panel (Animated - Bottom)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          bottom: _isMenuOpen ? 120 : -220, // Adjusted to sit above nav bar
          left: 20,
          right: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGlassCard(
                title: "Pre-Flight Planning",
                subtitle: "Weather Briefing & Risk Forecast",
                icon: Icons.flight_takeoff,
                iconColor: aviationColors.mapButtonIcon ?? theme.colorScheme.primary,
                onTap: widget.onNavigateToPreFlight,
                theme: theme,
                aviationColors: aviationColors,
                isDark: isDark,
              ),
            ],
          ),
        ),

        // 3. Trigger Button (Moved to Top Center)
        Positioned(
          top: 100, // Below where Header was
          left: 0,
          right: 0,
          child: Center(
            child: _buildTriggerButton(theme, aviationColors, isDark),
          ),
        ),

        // 4. Zoom Controls (Center Right)
        if (widget.mapController != null)
          Positioned(
            right: 20,
            top: MediaQuery.of(context).size.height / 2 - 60,
            child: _buildZoomControls(theme, aviationColors, isDark),
          ),
      ],
    );
  }

  Widget _buildZoomControls(ThemeData theme, AviationColors aviationColors, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: (aviationColors.mapButtonBg ?? (isDark ? Colors.black : Colors.white)).withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
            boxShadow: isDark
                ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, spreadRadius: 2)]
                : [BoxShadow(color: Colors.grey.withOpacity(0.4), blurRadius: 8, spreadRadius: 1, offset: const Offset(0, 2))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildZoomBtn(Icons.add, () {
                 widget.mapController?.move(
                    widget.mapController!.camera.center,
                    widget.mapController!.camera.zoom + 1);
              }, theme, aviationColors),
              Container(
                width: 40,
                height: 1,
                color: theme.dividerColor.withOpacity(0.2),
              ),
              _buildZoomBtn(Icons.remove, () {
                widget.mapController?.move(
                    widget.mapController!.camera.center,
                    widget.mapController!.camera.zoom - 1);
              }, theme, aviationColors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoomBtn(IconData icon, VoidCallback onTap, ThemeData theme, AviationColors aviationColors) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(icon, color: aviationColors.mapButtonIcon ?? theme.colorScheme.primary, size: 24),
        ),
      ),
    );
  }

  Widget _buildTriggerButton(ThemeData theme, AviationColors aviationColors, bool isDark) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isMenuOpen = !_isMenuOpen;
        });
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: (aviationColors.mapButtonBg ?? (isDark ? Colors.black : Colors.white)).withOpacity(0.9),
              shape: BoxShape.circle,
              border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
              boxShadow: isDark
                  ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, spreadRadius: 2, offset: const Offset(0, 4))]
                  : [BoxShadow(color: Colors.grey.withOpacity(0.4), blurRadius: 8, spreadRadius: 1, offset: const Offset(0, 4))],
            ),
            child: Icon(
              _isMenuOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              color: aviationColors.mapButtonIcon ?? theme.colorScheme.primary,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    required ThemeData theme,
    required AviationColors aviationColors,
    required bool isDark,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            highlightColor: iconColor.withOpacity(0.1),
            splashColor: iconColor.withOpacity(0.2),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (aviationColors.mapButtonBg ?? (isDark ? Colors.black : Colors.white)).withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
                boxShadow: isDark
                    ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, spreadRadius: 2, offset: const Offset(0, 5))]
                    : [BoxShadow(color: Colors.grey.withOpacity(0.4), blurRadius: 8, spreadRadius: 1, offset: const Offset(0, 5))],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 32),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: theme.colorScheme.onSurface.withOpacity(0.3),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}