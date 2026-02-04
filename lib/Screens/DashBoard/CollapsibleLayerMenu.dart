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
            color: const Color(0xFF0A1A2F).withOpacity(0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
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
                        const Text(
                          "Flight Layers",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      Icon(
                        _isExpanded ? Icons.layers_clear : Icons.layers,
                        color: Colors.cyanAccent,
                      ),
                    ],
                  ),
                ),
              ),

              if (_isExpanded) ...[
                const Divider(height: 1, color: Colors.white24),
                
                // Altitude Input
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("CRUISE ALTITUDE", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: TextField(
                          controller: widget.altitudeController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: "Enter Alt ($unitLabel)",
                            hintStyle: const TextStyle(color: Colors.white30),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            suffix: Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Text(
                                widget.altitude != null 
                                  ? (isFeet 
                                      ? "ft" 
                                      : "m") // Display unit based on value, actually this is static hint
                                  : unitLabel, 
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 12)
                              ),
                            ),
                          ),
                          onChanged: (val) {
                            // If user is in meters mode, we need to convert to feet before passing back?
                            // The Dashboard expects feet in _cruiseAltitudeFeet (implied by name).
                            // Let's assume input is in current units, convert to feet for logic.
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

                const Divider(height: 1, color: Colors.white24),

                // Layer Toggles
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildToggle("CONV", Colors.red),
                      _buildToggle("TURB", Colors.orange),
                      _buildToggle("ICE", Colors.blue),
                      _buildToggle("IFR", Colors.purple),
                      _buildToggle("MTN OBS", Colors.brown),
                      _buildToggle("LLWS", Colors.amber),
                      _buildToggle("Terrain", Colors.green), // Special Terrain Toggle
                    ],
                  ),
                ),

                const Divider(height: 1, color: Colors.white24),

                // Full Data Toggle
                SwitchListTile(
                  title: const Text("Show All Altitudes", style: TextStyle(color: Colors.white, fontSize: 12)),
                  value: widget.showFullData,
                  activeColor: Colors.cyanAccent,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  dense: true,
                  onChanged: widget.onToggleFullData,
                ),

                const Divider(height: 1, color: Colors.white24),

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

  Widget _buildToggle(String label, Color color) {
    final bool isActive = widget.isLayerActive(label);
    return GestureDetector(
      onTap: () => widget.onToggleLayer(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.2) : Colors.transparent,
          border: Border.all(
            color: isActive ? color : Colors.white24,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? color : Colors.white54,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
