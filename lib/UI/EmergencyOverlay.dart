import 'package:flutter/material.dart';

class EmergencyOverlay extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onClose;

  const EmergencyOverlay({
    super.key,
    required this.data,
    required this.onClose,
  });

  @override
  State<EmergencyOverlay> createState() => _EmergencyOverlayState();
}

class _EmergencyOverlayState extends State<EmergencyOverlay> {
  final Set<String> _checkedItems = {};

  bool _isPhaseComplete(List<dynamic> items) {
    if (items.isEmpty) return false;
    return items.every((item) => _checkedItems.contains(item.toString()));
  }

  void _toggleItem(String item) {
    setState(() {
      if (_checkedItems.contains(item)) {
        _checkedItems.remove(item);
      } else {
        _checkedItems.add(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final nav = widget.data['navigation'] ?? {};
    final airport = widget.data['recommended_airport'] ?? {};
    final plan = widget.data['action_plan'] ?? {};
    
    final bearing = nav['bearing_to']?.toString() ?? '---';
    final distance = nav['distance_nm']?.toString() ?? '--';
    final airportId = airport['id']?.toString() ?? 'UNKNOWN';
    final airportName = airport['name']?.toString() ?? '';
    final rwyLength = airport['rwy_length']?.toString() ?? 'UNK';
    final towerFreq = airport['tower_freq']?.toString() ?? '121.5';

    final phase1 = plan['phase_1_immediate'] as List? ?? [];
    final phase2 = plan['phase_2_approach'] as List? ?? [];
    final phase3 = plan['phase_3_landing'] as List? ?? [];

    return Column(
      children: [
        // 1. TOP SECTION: Navigation Banner
        Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 10,
            bottom: 20,
            left: 16,
            right: 16,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.9),
            border: const Border(
              bottom: BorderSide(color: Colors.redAccent, width: 3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                offset: const Offset(0, 5),
              )
            ],
          ),
          child: Column(
            children: [
              Text(
                "EMERGENCY DIVERT TO: $airportId",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              if (airportName.isNotEmpty)
                Text(
                  airportName,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildInstrumentValue("FLY HEADING", "$bearing°", Colors.redAccent),
                  Container(width: 1, height: 40, color: Colors.white24),
                  _buildInstrumentValue("DISTANCE", "$distance NM", Colors.white),
                  Container(width: 1, height: 40, color: Colors.white24),
                  _buildInstrumentValue("ETE", "${nav['time_enroute_min'] ?? '--'} MIN", Colors.white),
                ],
              ),
            ],
          ),
        ),

        // 2. MIDDLE SECTION: Map Window
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                bottom: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_downward, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text(
                        "FOLLOW RED LINE",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_downward, color: Colors.white, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 3. BOTTOM SECTION: Checklist Panel
        Container(
          height: MediaQuery.of(context).size.height * 0.45,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            border: const Border(
              top: BorderSide(color: Colors.redAccent, width: 3),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: Colors.redAccent.withOpacity(0.2),
                alignment: Alignment.center,
                child: const Text(
                  "ACTION PLAN CHECKLIST",
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  children: [
                    _buildSectionHeader("PHASE 1: IMMEDIATE", phase1, isCritical: true),
                    ...phase1.map((item) => _buildCheckItem(item.toString())),
                    
                    const SizedBox(height: 16),
                    _buildSectionHeader("PHASE 2: APPROACH", phase2),
                    ...phase2.map((item) => _buildCheckItem(item.toString())),

                    const SizedBox(height: 16),
                    _buildSectionHeader("PHASE 3: LANDING", phase3),
                    ...phase3.map((item) => _buildCheckItem(item.toString())),
                    
                     const SizedBox(height: 16),
                    _buildAirportInfo(rwyLength, towerFreq),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: widget.onClose,
                    child: const Text(
                      "CANCEL EMERGENCY",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInstrumentValue(String label, String value, Color valueColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            fontFamily: 'Courier',
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, List<dynamic> items, {bool isCritical = false}) {
    final bool isComplete = _isPhaseComplete(items);
    final Color headerColor = isComplete 
        ? Colors.greenAccent 
        : (isCritical ? Colors.redAccent : Colors.white);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: headerColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
              decorationColor: headerColor.withOpacity(0.5),
            ),
          ),
          if (isComplete)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.greenAccent),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check, color: Colors.greenAccent, size: 12),
                  SizedBox(width: 4),
                  Text(
                    "PHASE COMPLETED",
                    style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text) {
    final bool isChecked = _checkedItems.contains(text);

    return InkWell(
      onTap: () => _toggleItem(text),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(top: 2),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isChecked ? Colors.greenAccent : Colors.transparent,
                border: Border.all(
                  color: isChecked ? Colors.greenAccent : Colors.white54, 
                  width: 2
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: isChecked 
                  ? const Icon(Icons.check, color: Colors.black, size: 16) 
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: isChecked ? 0.5 : 1.0,
                child: Text(
                  text,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.3,
                    decoration: isChecked ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white54,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAirportInfo(String rwy, String freq) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              const Icon(Icons.airlines, color: Colors.cyanAccent, size: 20),
              const SizedBox(height: 4),
              Text("RWY: $rwy", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          Column(
            children: [
              const Icon(Icons.radio, color: Colors.orangeAccent, size: 20),
              const SizedBox(height: 4),
              Text("FREQ: $freq", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
