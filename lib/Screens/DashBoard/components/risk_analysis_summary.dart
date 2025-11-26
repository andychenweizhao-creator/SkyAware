import 'package:flutter/material.dart';
import '../../../Service/WeatherEngine.dart';
import 'weather_analysis_logic.dart';

class RiskAnalysisSummary extends StatelessWidget {
  final List<WeatherPoint> weatherPoints;
  final double? referenceAltitudeFt;
  final bool usePlannedAlt;

  const RiskAnalysisSummary({
    super.key,
    required this.weatherPoints,
    required this.referenceAltitudeFt,
    this.usePlannedAlt = false,
  });

  @override
  Widget build(BuildContext context) {
    if (weatherPoints.isEmpty) {
      return const SizedBox.shrink(); // No data yet
    }

    // 1. Compile Risks & Stats
    final List<Map<String, dynamic>> risks = [];
    double minVis = 999.0;
    double minCeiling = 99999.0;
    double maxWind = 0.0;
    double maxPrecip = 0.0;
    int riskCount = 0;

    for (int i = 0; i < weatherPoints.length; i++) {
      final wp = weatherPoints[i];
      final analysis = WeatherAnalysisLogic.buildVfrAnalysisForPoint(
        wp.weather,
        referenceAltitudeFt: referenceAltitudeFt,
        usePlannedAlt: usePlannedAlt,
      );
      
      final hazards = analysis['hazards'] as List<dynamic>;
      final double? c = analysis['clouds'] as double?;
      final double? v = analysis['vis'] as double?;
      final double? w = analysis['windSpeed'] as double?;
      final double? p = analysis['precip'] as double?;

      if (c != null && c < minCeiling) minCeiling = c;
      if (v != null && v < minVis) minVis = v;
      if (w != null && w > maxWind) maxWind = w;
      if (p != null && p > maxPrecip) maxPrecip = p;

      if (hazards.isNotEmpty) {
        riskCount++;
        // Use approx distance for location
        final distKm = (i * 15); 
        
        for (var h in hazards) {
            // Avoid duplicate messages for the *exact same* hazard type in sequence
            // But allows same hazard type if it appears far away.
            // Simple approach: Check if we just added this exact msg.
            if (risks.isNotEmpty && risks.last['msg'] == h.toString() && (risks.last['km'] as int) >= distKm - 30) {
               continue; // Skip if same error was reported in last 30km
            }
            
            risks.add({
                'msg': h.toString(),
                'km': distKm,
            });
        }
      }
    }

    bool isClean = risks.isEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2A35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isClean ? Colors.greenAccent : Colors.redAccent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(isClean ? Icons.check_circle : Icons.warning_amber_rounded, 
                   color: isClean ? Colors.greenAccent : Colors.redAccent, size: 28),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isClean ? "VFR Route Clear" : "Route Risks Detected",
                    style: TextStyle(
                      color: isClean ? Colors.greenAccent : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  if (!isClean)
                    Text("${risks.length} hazards identified along route", 
                         style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Weather Data Summary Grid
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat("Min Ceiling", minCeiling < 99999 ? "${minCeiling.round()} ft" : "Unlimited", Colors.blueAccent),
                    _buildStat("Min Visibility", minVis < 999 ? "${minVis.toStringAsFixed(1)} SM" : "10+ SM", minVis < 3 ? Colors.redAccent : Colors.white),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat("Max Wind", "${maxWind.toStringAsFixed(0)} kt", maxWind > 30 ? Colors.orangeAccent : Colors.white),
                    _buildStat("Precip Chance", "${maxPrecip.toStringAsFixed(0)}%", maxPrecip > 50 ? Colors.blueAccent : Colors.white),
                  ],
                ),
              ],
            ),
          ),
          
          // Hazard List
          if (!isClean) ...[
            const SizedBox(height: 16),
            const Text("HAZARD LOG:", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            const Divider(color: Colors.white12),
            ...risks.take(5).map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      "@ ${r['km']} km",
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r['msg'],
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            )),
            if (risks.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(child: Text("+ ${risks.length - 5} more hazards...", style: const TextStyle(color: Colors.white38, fontSize: 12))),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color valueColor) {
    return SizedBox(
      width: 100,
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }
}
