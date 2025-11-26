import 'package:flutter/material.dart';
import 'flight_mode.dart';

class FlightControls extends StatelessWidget {
  final FlightMode currentMode;
  final ValueChanged<FlightMode> onModeChanged;
  final TextEditingController altitudeController;
  final ValueChanged<String> onAltitudeChanged;

  const FlightControls({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    required this.altitudeController,
    required this.onAltitudeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Row(
        children: [
          // Mode Selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: ToggleButtons(
              constraints: const BoxConstraints(minWidth: 60, minHeight: 30),
              borderRadius: BorderRadius.circular(6),
              isSelected: [
                currentMode == FlightMode.auto,
                currentMode == FlightMode.preflight,
                currentMode == FlightMode.inflight,
              ],
              onPressed: (index) {
                if (index == 0) onModeChanged(FlightMode.auto);
                if (index == 1) onModeChanged(FlightMode.preflight);
                if (index == 2) onModeChanged(FlightMode.inflight);
              },
              color: Colors.white60,
              selectedColor: Colors.black,
              fillColor: Colors.orangeAccent,
              children: const [
                Text('AUTO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Text('PRE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Text('FLY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Altitude Input (Only visible if relevant)
          if (currentMode == FlightMode.preflight || currentMode == FlightMode.auto)
            Expanded(
              child: TextField(
                controller: altitudeController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Planned Alt (ft)',
                  labelStyle: const TextStyle(color: Colors.white54),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.orangeAccent),
                  ),
                  suffixText: 'ft',
                  suffixStyle: const TextStyle(color: Colors.white30),
                ),
                onChanged: onAltitudeChanged,
              ),
            ),
          if (currentMode == FlightMode.inflight)
            const Expanded(
              child: Text(
                "Using GPS Altitude",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.greenAccent, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}
