import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/unit_settings_service.dart';

class CollapsibleLayerMenu extends StatefulWidget {
  final Function(String) onToggleLayer;
  final bool Function(String) isLayerActive;
  final bool showFullData;
  final Function(bool) onToggleFullData;
  final double topPosition;
  final int? altitude;
  final TextEditingController altitudeController;
  final Function(String) onAltitudeChanged;
  final VoidCallback onReset;

  const CollapsibleLayerMenu({
    super.key,
    required this.onToggleLayer,
    required this.isLayerActive,
    required this.showFullData,
    required this.onToggleFullData,
    required this.topPosition,
    this.altitude,
    required this.altitudeController,
    required this.onAltitudeChanged,
    required this.onReset,
  });

  @override
  State<CollapsibleLayerMenu> createState() => _CollapsibleLayerMenuState();
}

class _CollapsibleLayerMenuState extends State<CollapsibleLayerMenu> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    // Determine Theme Mode
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Define Colors based on Mode
    final backgroundColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subTextColor = isDarkMode ? Colors.white54 : Colors.black54;
    final iconColor = isDarkMode ? Colors.cyanAccent : Colors.black87;
    final borderColor = isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black12;
    final shadowColor = isDarkMode ? Colors.black.withOpacity(0.5) : Colors.black12;
    final dividerColor = isDarkMode ? Colors.white24 : Colors.black12;
    final inputFillColor = isDarkMode ? Colors.black38 : const Color(0xFFF5F5F7);
    final inputBorderColor = isDarkMode ? Colors.white12 : Colors.black12;
    final hintColor = isDarkMode ? Colors.white30 : Colors.black38;

    // Access unit settings
    final units = Provider.of<UnitSettingsProvider>(context);
    final isFeet = units.altitudeUnit == AltitudeUnit.feet;
    final unitLabel = isFeet ? "ft" : "m";

    return Positioned(
      top: widget.topPosition,
      right: 16,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: Alignment.topRight,
        child: Container(
          width: _isExpanded ? 240 : 56,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header / Toggle Button
              InkWell(
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_isExpanded)
                        Text(
                          "Flight Layers",
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      Icon(
                        _isExpanded ? Icons.layers_clear : Icons.layers,
                        color: iconColor,
                      ),
                    ],
                  ),
                ),
              ),

              if (_isExpanded) ...[
                Divider(height: 1, color: dividerColor),
                
                // Altitude Input
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("CRUISE ALTITUDE", style: TextStyle(color: subTextColor, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: inputFillColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: inputBorderColor),
                        ),
                        child: TextField(
                          controller: widget.altitudeController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: "Enter Alt ($unitLabel)",
                            hintStyle: TextStyle(color: hintColor),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            suffix: Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Text(
                                widget.altitude != null 
                                  ? (isFeet 
                                      ? "ft" 
                                      : "m")
                                  : unitLabel, 
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 12)
                              ),
                            ),
                          ),
                          onChanged: (val) {
                            if (val.isEmpty) {
                              widget.onAltitudeChanged("");
                              return;
                            }
                            
                            int? inputVal = int.tryParse(val);
                            if (inputVal != null) {
                              if (!isFeet) {
                                // Convert m -> ft
                                int ft = (inputVal / 0.3048).round();
                                widget.onAltitudeChanged(ft.toString());
                              } else {
                                widget.onAltitudeChanged(val);
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                Divider(height: 1, color: dividerColor),

                // Layer Toggles
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildToggle("Airports", isDarkMode ? Colors.white : Colors.black, isDarkMode),
                      _buildToggle("CONV", Colors.red, isDarkMode),
                      _buildToggle("TURB", Colors.orange, isDarkMode),
                      _buildToggle("ICE", Colors.blue, isDarkMode),
                      _buildToggle("IFR", Colors.purple, isDarkMode),
                      _buildToggle("MTN OBS", Colors.brown, isDarkMode),
                      _buildToggle("LLWS", Colors.amber, isDarkMode),
                      _buildToggle("Terrain", Colors.green, isDarkMode),
                    ],
                  ),
                ),

                Divider(height: 1, color: dividerColor),

                // Full Data Toggle
                SwitchListTile(
                  title: Text("Show All Altitudes", style: TextStyle(color: textColor, fontSize: 12)),
                  value: widget.showFullData,
                  activeColor: Colors.cyanAccent,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  dense: true,
                  onChanged: widget.onToggleFullData,
                ),

                Divider(height: 1, color: dividerColor),

                // Reset Button
                InkWell(
                  onTap: widget.onReset,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    child: const Text(
                      "RESET MAP",
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggle(String label, Color color, bool isDarkMode) {
    final bool isActive = widget.isLayerActive(label);
    
    // In Light mode, we want the inactive text to be visible (black54)
    // In Dark mode, white54.
    final inactiveTextColor = isDarkMode ? Colors.white54 : Colors.black54;
    final inactiveBorderColor = isDarkMode ? Colors.white24 : Colors.black12;

    return GestureDetector(
      onTap: () => widget.onToggleLayer(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.2) : Colors.transparent,
          border: Border.all(
            color: isActive ? color : inactiveBorderColor,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? color : inactiveTextColor,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
