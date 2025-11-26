import 'package:flutter/material.dart';
import '../../../Service/terrain_engine.dart';

void showTerrainPopup(BuildContext context, TerrainSample t, {double? referenceAltitudeFt}) {
  final double elevation = t.elevationFt;
  final double? altitude = referenceAltitudeFt;
  
  // VFR Terrain Rule: 
  // - 1000 ft above highest obstacle in congested areas.
  // - 500 ft above in other areas.
  // We generally use 1000 ft as a safe planning minimum.
  const double requiredClearance = 1000.0;
  
  double? clearance;
  String status = "Unknown";
  Color statusColor = Colors.grey;
  List<String> details = [];

  if (altitude != null) {
    clearance = altitude - elevation;
    
    if (clearance < 0) {
      status = "CRITICAL COLLISION RISK";
      statusColor = Colors.redAccent;
      details.add("⚠️ Flight Altitude is BELOW Terrain Elevation!");
      details.add("• Your Altitude: ${altitude.round()} ft");
      details.add("• Terrain Height: ${elevation.round()} ft");
      details.add("• Deficit: ${(clearance.abs()).round()} ft");
    } else if (clearance < 500) {
      status = "VFR VIOLATION (< 500 ft)";
      statusColor = Colors.red;
      details.add("⚠️ Dangerous Proximity to Terrain.");
      details.add("• Clearance: ${clearance.round()} ft");
      details.add("• Required: > 500 ft (Absolute Minimum)");
    } else if (clearance < 1000) {
      status = "CAUTION (< 1000 ft)";
      statusColor = Colors.orange;
      details.add("⚠️ Below recommended 1000 ft clearance.");
      details.add("• Clearance: ${clearance.round()} ft");
    } else {
      status = "SAFE CLEARANCE";
      statusColor = Colors.green;
      details.add("✅ Safe vertical separation.");
      details.add("• Clearance: ${clearance.round()} ft");
    }
  } else {
    details.add("Plan or Fly to see clearance analysis.");
  }

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E2A35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: statusColor, width: 2),
      ),
      title: Row(
        children: [
          Icon(Icons.terrain, color: statusColor),
          const SizedBox(width: 8),
          Expanded(child: Text(status, style: TextStyle(color: statusColor, fontSize: 16, fontWeight: FontWeight.bold))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Terrain Elevation: ${elevation.round()} ft MSL", style: const TextStyle(color: Colors.white, fontSize: 16)),
          const Divider(color: Colors.white24),
          ...details.map((d) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Text(d, style: const TextStyle(color: Colors.white70)),
          )),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("CLOSE", style: TextStyle(color: Colors.lightBlueAccent)),
        )
      ],
    ),
  );
}
