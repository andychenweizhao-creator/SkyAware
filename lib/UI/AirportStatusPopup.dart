import 'package:flutter/material.dart';
import '../services/airport_database_service.dart';

class AirportStatusPopup extends StatelessWidget {
  final Airport airport;
  final VoidCallback onRoute;
  final VoidCallback onAnalyze;

  const AirportStatusPopup({
    super.key,
    required this.airport,
    required this.onRoute,
    required this.onAnalyze,
  });

  Color _parseHexColor(String hexString) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0A1A2F).withOpacity(0.95),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.2))
      ),
      title: Row(
        children: [
          const Icon(Icons.local_airport, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Text(airport.ident, style: const TextStyle(color: Colors.white)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(airport.name, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text("Flight Rules: ", style: TextStyle(color: Colors.white)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _parseHexColor(airport.riskColor ?? '#808080'),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  airport.riskReason ?? 'N/A',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onRoute,
          child: const Text("Route")
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.analytics, size: 16),
          label: const Text("Detailed Analysis"),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, foregroundColor: Colors.white),
          onPressed: onAnalyze,
        ),
      ],
    );
  }
}
