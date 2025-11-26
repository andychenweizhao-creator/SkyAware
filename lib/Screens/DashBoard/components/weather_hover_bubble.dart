import 'package:flutter/material.dart';
import '../../../components/WeatherIconResolver.dart';
import 'Risk_Assesments.dart' hide LegWx;
import '../../../Service/WeatherEngine.dart';
import 'weather_analysis_logic.dart';

class WeatherHoverBubble extends StatelessWidget {
  final LegWx wx;
  final double? referenceAltitudeFt;
  final bool usePlannedAlt;

  const WeatherHoverBubble({
    super.key, 
    required this.wx,
    this.referenceAltitudeFt,
    this.usePlannedAlt = false,
  });

  @override
  Widget build(BuildContext context) {
    final wxData = WeatherAnalysisLogic.buildVfrAnalysisForPoint(
      wx,
      referenceAltitudeFt: referenceAltitudeFt,
      usePlannedAlt: usePlannedAlt,
    );
    final String category = wxData['category'] as String;
    // final String suitability = wxData['suitability'] as String;
    final List<dynamic> hazards = wxData['hazards'] as List<dynamic>;
    
    Color catColor = Colors.grey;
    if (category == 'VFR') catColor = Colors.greenAccent;
    else if (category == 'MVFR') catColor = Colors.blueAccent;
    else if (category == 'IFR') catColor = Colors.orangeAccent;
    else if (category == 'LIFR') catColor = Colors.redAccent;

    bool isSafe = hazards.isEmpty;

    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2A35).withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSafe ? Colors.greenAccent : Colors.redAccent, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(children: [
            Icon(
              isSafe ? Icons.check_circle : Icons.warning_amber_rounded, 
              color: isSafe ? Colors.greenAccent : Colors.redAccent, 
              size: 24
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isSafe ? "VFR COMPLIANT" : "VFR RISK DETECTED", 
                style: TextStyle(
                  color: isSafe ? Colors.greenAccent : Colors.redAccent, 
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                )
              ),
            ),
          ]),
          const SizedBox(height: 4),
          if (referenceAltitudeFt != null)
            Text(
              "At Altitude: ${referenceAltitudeFt!.round()} ft",
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          const Divider(color: Colors.white24, height: 16),

          // Hazards List
          if (hazards.isNotEmpty)
            ...hazards.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("• ", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      h.toString(), 
                      style: const TextStyle(color: Colors.white, fontSize: 13)
                    ),
                  ),
                ],
              ),
            ))
          else 
            const Text(
              "Conditions meet VFR requirements for cloud clearance and visibility at this altitude.",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),

          const SizedBox(height: 12),
          // Surface Conditions Footer
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("SURFACE", style: TextStyle(color: Colors.white38, fontSize: 10)),
                  Text(category, style: TextStyle(color: catColor, fontWeight: FontWeight.bold)),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (wx.cloudBaseFt != null) 
                    Text("CIG: ${wx.cloudBaseFt!.round()} ft", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  if (wx.visibilitySm != null)
                    Text("VIS: ${wx.visibilitySm!.toStringAsFixed(1)} SM", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
