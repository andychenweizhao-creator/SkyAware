import 'dart:ui';
import 'package:flutter/material.dart';

class CollapsibleLayerMenu extends StatefulWidget {
  final Function(String) onToggleLayer;
  final bool Function(String) isLayerActive;
  final bool showFullData;
  final ValueChanged<bool> onToggleFullData;
  final double topPosition;
  
  // Altitude Input Props
  final int? altitude;
  final TextEditingController? altitudeController;
  final ValueChanged<String>? onAltitudeChanged;
  
  // Reset Action
  final VoidCallback? onReset;

  const CollapsibleLayerMenu({
    super.key,
    required this.onToggleLayer,
    required this.isLayerActive,
    required this.showFullData,
    required this.onToggleFullData,
    this.topPosition = 160.0,
    this.altitude,
    this.altitudeController,
    this.onAltitudeChanged,
    this.onReset,
  });

  @override
  State<CollapsibleLayerMenu> createState() => _CollapsibleLayerMenuState();
}

class _CollapsibleLayerMenuState extends State<CollapsibleLayerMenu> with SingleTickerProviderStateMixin {
  bool _isMenuExpanded = false;

  @override
  Widget build(BuildContext context) {
    // Determine label for collapsed state
    String collapsedLabel = "Layers";
    if (widget.altitude != null) {
      if (widget.altitude! > 10000) {
        collapsedLabel = "FL ${(widget.altitude! / 100).round()}";
      } else {
        collapsedLabel = "${(widget.altitude! / 1000).toStringAsFixed(1)}k ft";
      }
    }

    return Positioned(
      right: 16,
      top: widget.topPosition,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Collapsed State (Floating Pill)
          if (!_isMenuExpanded)
            GestureDetector(
              onTap: () => setState(() => _isMenuExpanded = true),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xB31C1C1E), // Dark Gray, ~70% opacity
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.layers_outlined, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          collapsedLabel,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Expanded State (Menu)
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutQuint,
            alignment: Alignment.topRight,
            child: _isMenuExpanded
                ? Container(
                    width: 320,
                    margin: const EdgeInsets.only(top: 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xCC1C1C1E), // 80% Opacity Dark Gray
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 30,
                                spreadRadius: 5,
                              )
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Header
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "Map Overlays",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: '.SF Pro Text',
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => setState(() => _isMenuExpanded = false),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close, color: Colors.white70, size: 16),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // Section 1: Flight Parameters (Altitude Input)
                              if (widget.altitudeController != null) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Text(
                                          "Plan Altitude",
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const Spacer(),
                                        SizedBox(
                                          width: 100,
                                          child: TextField(
                                            controller: widget.altitudeController,
                                            keyboardType: TextInputType.number,
                                            textAlign: TextAlign.end,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            decoration: const InputDecoration(
                                              hintText: "Enter",
                                              hintStyle: TextStyle(color: Colors.white30, fontSize: 14),
                                              border: InputBorder.none,
                                              isDense: true,
                                              suffixText: " ft",
                                              suffixStyle: TextStyle(color: Colors.greenAccent, fontSize: 14),
                                            ),
                                            onChanged: widget.onAltitudeChanged,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],

                              const Divider(color: Colors.white10, height: 1),

                              // Section 2: Layer Visibility (Grid)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _buildHazardChip("Conv", Colors.red),
                                    _buildHazardChip("Ice", Colors.blue),
                                    _buildHazardChip("Turb", Colors.orange),
                                    _buildHazardChip("Mtn Obs", Colors.brown),
                                    _buildHazardChip("IFR", Colors.purple),
                                    _buildHazardChip("LLWS", Colors.yellow),
                                    _buildHazardChip("Surf Wind", Colors.teal),
                                    _buildHazardChip("TCF", Colors.indigo),
                                    _buildHazardChip("Terrain", Colors.brown),
                                  ],
                                ),
                              ),

                              const Divider(color: Colors.white10, height: 1),

                              // Section 3: Global Settings (Footer)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text("Full Data", style: TextStyle(color: Colors.white, fontSize: 16)),
                                        Switch.adaptive(
                                          value: widget.showFullData,
                                          activeColor: Colors.green,
                                          inactiveTrackColor: Colors.grey.withOpacity(0.3),
                                          onChanged: widget.onToggleFullData,
                                        ),
                                      ],
                                    ),
                                    
                                    // Reset Action
                                    if (widget.onReset != null) ...[
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: TextButton.icon(
                                          onPressed: () {
                                            widget.onReset!();
                                            // Optionally close menu after reset?
                                            // setState(() => _isMenuExpanded = false);
                                          },
                                          icon: const Icon(Icons.refresh, color: Colors.redAccent, size: 18),
                                          label: const Text("Reset Map", style: TextStyle(color: Colors.redAccent)),
                                          style: TextButton.styleFrom(
                                            backgroundColor: Colors.redAccent.withOpacity(0.1),
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                      )
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildHazardChip(String type, Color color) {
    final bool isActive = widget.isLayerActive(type);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onToggleLayer(type),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 125, 
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            color: isActive ? color : Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? color.withOpacity(0.5) : Colors.transparent
            ),
          ),
          child: Row(
            children: [
              Icon(
                isActive ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: isActive ? Colors.white : Colors.white38,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  type,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
