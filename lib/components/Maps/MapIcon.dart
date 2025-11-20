import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Placeholder classes for missing types
class LegRisk {
  final double total;
  final String weatherText;

  LegRisk(this.total, this.weatherText);
}

class WeatherPoint {
  final LatLng position;
  final LegWx weather;

  WeatherPoint(this.position, this.weather);
}

class LegWx {}

class TerrainSample {
  final double elevationFt;
  final LatLng position;

  TerrainSample(this.elevationFt, this.position);
}

class _WeatherBubble extends StatelessWidget {
  final int index;
  final LegRisk risk;

  const _WeatherBubble({
    required this.index,
    required this.risk,
  });

  Color _colorFor(double r) {
    if (r > 0.7) return Colors.redAccent;
    if (r > 0.4) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  String _level(double r) {
    if (r > 0.7) return 'HIGH';
    if (r > 0.4) return 'MED';
    return 'LOW';
  }

  @override
  Widget build(BuildContext context) {
    final level = _level(risk.total);
    final color = _colorFor(risk.total);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF111820).withAlpha((255 * 0.96).round()),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题：Leg + 风险等级
            Row(
              children: [
                Icon(
                  Icons.cloud,
                  size: 12,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  'LEG ${index + 1} • $level',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 具体天气内容（多行）
            Text(
              risk.weatherText,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// =======================================
//           FULLSCREEN MAP
// =======================================

class FullscreenMap extends StatefulWidget {
  final List<LatLng> flightPath;
  final List<String> waypointNames;
  final LatLng? departureAirport;
  final LatLng? arrivalAirport;
  final Position? currentPosition;
  final Map<String, String> tileSources;
  final String mapStyle;
  final List<LegRisk> legRisks;
  final List<WeatherPoint> weatherPoints;
  final List<TerrainSample> terrainSamples;
  final double? recommendedAltitudeFt;
  final double? plannedAltitudeFt;


  const FullscreenMap({
    super.key,
    required this.flightPath,
    required this.waypointNames,
    required this.departureAirport,
    required this.arrivalAirport,
    required this.currentPosition,
    required this.tileSources,
    required this.mapStyle,
    required this.legRisks,
    required this.weatherPoints,
    required this.terrainSamples,
    required this.recommendedAltitudeFt,
    this.plannedAltitudeFt,
  });

  @override
  State<FullscreenMap> createState() => _FullscreenMapState();
}

class _FullscreenMapState extends State<FullscreenMap> {
  late String _currentMapStyle = 'osm';
  late MapController _fullscreenController = MapController();
  late WebViewController _webController;

  // Added fields for terrain profile
  List<TerrainSample> _terrainSamples = [];
  double? _recommendedAltitudeFt;

  @override
  void initState() {
    super.initState();
    _currentMapStyle = widget.mapStyle;
    _fullscreenController = MapController();
    if (widget.mapStyle == 'wunderground') {
      _webController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse("https://www.wunderground.com"));
    }
    // Pass values from widget (dynamic for compatibility)
    _terrainSamples = widget.terrainSamples;
    _recommendedAltitudeFt = widget.recommendedAltitudeFt;
  }

  // TERRAIN POPUP FUNCTION (copy)
  void _showTerrainPopup(TerrainSample t) {
    final elevation = t.elevationFt;
    final airspeed = widget.currentPosition?.speed ?? 0;

    double? referenceAltitude;
    if (airspeed < 10) {
      referenceAltitude = widget.plannedAltitudeFt;
    } else {
      referenceAltitude = widget.currentPosition?.altitude != null
          ? widget.currentPosition!.altitude * 3.28084
          : null;
    }

    final clearance = referenceAltitude != null ? referenceAltitude - elevation : null;
    final bool isMountainous = elevation > 4000;
    final double required = isMountainous ? 2000 : 1000;

    String risk;
    if (clearance != null) {
      if (clearance < 500) {
        risk = "⚠️ EXTREME TERRAIN RISK (<500 ft)";
      } else if (clearance < required) {
        risk = "🟠 BELOW VFR CLEARANCE (${required.toStringAsFixed(0)} ft required)";
      } else {
        risk = "🟢 VFR SAFE TERRAIN";
      }
    } else {
      risk = "UNKNOWN (No altitude reference)";
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A35),
        title: const Text("Terrain Profile Point",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🌍 Lat: ${t.position.latitude.toStringAsFixed(4)}',
                style: const TextStyle(color: Colors.white70)),
            Text('🌍 Lon: ${t.position.longitude.toStringAsFixed(4)}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('🗻 Elevation: ${t.elevationFt.toStringAsFixed(0)} ft',
                style: const TextStyle(color: Colors.white70)),
            if (referenceAltitude != null)
              Text('✈ Reference Alt: ${referenceAltitude.toStringAsFixed(0)} ft',
                  style: const TextStyle(color: Colors.white70)),
            if (clearance != null)
              Text('📉 Clearance: ${clearance.toStringAsFixed(0)} ft',
                  style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(risk, style: const TextStyle(color: Colors.orangeAccent)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK",
                style: TextStyle(color: Colors.lightBlueAccent)),
          ),
        ],
      ),
    );
  }
@override
Widget build(BuildContext context) {
return Container();
}
}