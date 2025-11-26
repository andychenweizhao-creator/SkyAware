import 'package:flutter/material.dart';
import 'Risk_Assesments.dart'; // Relative import

class AltitudeWeatherProfile extends StatelessWidget {
  final List<LegRisk> legRisks;
  final List<String> waypointNames;

  const AltitudeWeatherProfile({
    super.key,
    required this.legRisks,
    required this.waypointNames,
  });

  @override
  Widget build(BuildContext context) {
    if (legRisks.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFF1A242F),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.air_rounded, color: Colors.lightBlueAccent, size: 18),
          const SizedBox(width: 6),
          const Text(
            'Altitude Profile',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: List.generate(legRisks.length, (i) {
                final fromName = i < waypointNames.length ? waypointNames[i] : 'WP${i+1}';
                final toName = (i+1) < waypointNames.length ? waypointNames[i+1] : 'WP${i+2}';

                final clouds = legRisks[i].cloudBaseFt ?? 0;
                final wind = legRisks[i].windDirDeg != null && legRisks[i].windSpeedKt != null
                    ? '${legRisks[i].windDirDeg}° / ${legRisks[i].windSpeedKt}kt'
                    : '—';
                final vis = legRisks[i].visibilitySm != null
                    ? '${legRisks[i].visibilitySm} sm'
                    : '—';

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '$fromName → $toName',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 9,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),

                          // CLOUD BASE BAR
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blueGrey, width: 0.8),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Clouds',
                                  style: TextStyle(
                                    color: Colors.lightBlueAccent,
                                    fontSize: 9,
                                  ),
                                ),
                                Text(
                                  clouds > 0 ? '$clouds ft' : '—',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 2),

                          // WIND BAR
                          Container(
                            height: 16,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(6),
                              border:
                              Border.all(color: Colors.lightBlueAccent, width: 0.8),
                            ),
                            child: Center(
                              child: Text(
                                wind,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 2),

                          // VISIBILITY
                          Text(
                            'Vis $vis',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
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
