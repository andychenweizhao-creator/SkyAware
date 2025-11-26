import 'package:flutter/material.dart';
import 'Risk_Assesments.dart'; // Use relative import as it's in the same dir

class RouteWeatherProfile extends StatelessWidget {
  final List<LegRisk> legRisks;
  final List<String> waypointNames;

  const RouteWeatherProfile({
    super.key,
    required this.legRisks,
    required this.waypointNames,
  });

  String _categoryFor(LegRisk r) {
    final double? clouds = r.cloudBaseFt?.toDouble();
    final double? vis = r.visibilitySm?.toDouble();
    final double cloudsSafe = clouds ?? 15000;
    final double visSafe = vis ?? 10.0;

    if (cloudsSafe < 500 || visSafe < 1.0) return 'LIFR';
    else if (cloudsSafe < 1000 || visSafe < 3.0) return 'IFR';
    else if (cloudsSafe < 3000 || visSafe < 5.0) return 'MVFR';
    else return 'VFR';
  }

  Color _colorForCategory(String category) {
    switch (category) {
      case 'LIFR':
        return Colors.purpleAccent;
      case 'IFR':
        return Colors.redAccent;
      case 'MVFR':
        return Colors.blueAccent;
      case 'VFR':
        return Colors.greenAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (legRisks.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF1E2A35),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.cloud, color: Colors.white70, size: 18),
          const SizedBox(width: 6),
          const Text(
            'Route Weather',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: List.generate(legRisks.length, (i) {
                final category = _categoryFor(legRisks[i]);
                final color = _colorForCategory(category);
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 14,
                    color: color,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
