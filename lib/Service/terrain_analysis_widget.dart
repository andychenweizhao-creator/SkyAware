import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import 'TerrianEngines.dart';
import 'weather_service.dart';

class TerrainAnalysisWidget extends StatefulWidget {
  final List<TerrainSample> terrainSamples;
  final Position? currentPosition;
  final double? plannedAltitudeFt;
  final LatLng? departureAirport;
  final LatLng? arrivalAirport;
  final List<LatLng> flightPath;
  final List<dynamic> legRisks;

  const TerrainAnalysisWidget({
    super.key,
    required this.terrainSamples,
    this.currentPosition,
    this.plannedAltitudeFt,
    this.departureAirport,
    this.arrivalAirport,
    required this.flightPath,
    required this.legRisks,
  });

  @override
  _TerrainAnalysisWidgetState createState() => _TerrainAnalysisWidgetState();
}

class _TerrainAnalysisWidgetState extends State<TerrainAnalysisWidget> {
  final MapController _fullscreenController = MapController();
  String _currentMapStyle = 'osm';
  bool _isRefreshingWeather = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MarkerLayer(
          markers: [
            // TERRAIN RISK MARKERS (FAA VFR logic)
            if (widget.terrainSamples.isNotEmpty)
              ...widget.terrainSamples.where((t) {
                double? clearance;
                double elevation = t.elevationFt;

                // 统一用 helper 获取参考高度（preflight: 输入；in-flight: GPS）
                double? referenceAltitude = _getReferenceAltitudeFt();
                if (referenceAltitude == null) return false;

                clearance = referenceAltitude - elevation;

                // VFR strict logic: Only mark hazardous terrain
                // FAA: 1000ft clearance general, 2000ft mountainous
                bool isMountainous = elevation > 4000; // Simplified terrain classification
                double required = isMountainous ? 2000 : 1000;

                return clearance < required;
              }).map((t) {
                double elevation = t.elevationFt;
                double? referenceAltitude = _getReferenceAltitudeFt();

                double clearance = (referenceAltitude ?? 0) - elevation;

                Color c;
                IconData icon;

                if (clearance < 500) {
                  c = Colors.redAccent;
                  icon = Icons.warning_rounded;
                } else {
                  c = Colors.orangeAccent;
                  icon = Icons.report_problem_rounded;
                }

                return Marker(
                  width: 38,
                  height: 38,
                  point: t.position,
                  child: GestureDetector(
                    onTap: () => _showTerrainPopup(t),
                    child: Icon(icon, color: c, size: 26),
                  ),
                );
              }),
            // departure
            if (widget.departureAirport != null)
              Marker(
                point: widget.departureAirport!,
                width: 80,
                height: 80,
                child: const Icon(
                  Icons.flight_takeoff,
                  color: Colors.greenAccent,
                  size: 40,
                ),
              ),
            // arrival
            if (widget.arrivalAirport != null)
              Marker(
                point: widget.arrivalAirport!,
                width: 80,
                height: 80,
                child: const Icon(
                  Icons.flight_land,
                  color: Colors.redAccent,
                  size: 40,
                ),
              ),
          ],
        ),
        Positioned(
          right: 15,
          bottom: 180,
          child: FloatingActionButton(
            heroTag: "refresh_weather_full",
            mini: true,
            backgroundColor: Colors.orangeAccent,
            onPressed: () async {
              if (widget.flightPath.isNotEmpty) {
                final weatherPoints =
                await WeatherEngine.fetchRouteWeather(widget.flightPath);
                setState(() {
                  // widget.weatherPoints is final
                });
              }
            },
            child: const Icon(Icons.refresh, color: Colors.white),
          ),
        ),
        Positioned(
          right: 15,
          bottom: 120,
          child: Column(
            children: [
              FloatingActionButton(
                heroTag: "zoom_in",
                mini: true,
                backgroundColor: Colors.blueGrey,
                onPressed: () => _fullscreenController.move(
                  _fullscreenController.camera.center,
                  _fullscreenController.camera.zoom + 1,
                ),
                child: const Icon(Icons.add, color: Colors.white),
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                heroTag: "zoom_out",
                mini: true,
                backgroundColor: Colors.blueGrey,
                onPressed: () => _fullscreenController.move(
                  _fullscreenController.camera.center,
                  _fullscreenController.camera.zoom - 1,
                ),
                child: const Icon(Icons.remove, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showTerrainPopup(TerrainSample t) {
    // Determine reference altitude (planned or actual) and clearance
    double? referenceAltitude = _getReferenceAltitudeFt();
    double elevation = t.elevationFt;
    double? clearance =
    referenceAltitude != null ? referenceAltitude - elevation : null;
    String risk;
    bool isMountainous = elevation > 4000;
    double required = isMountainous ? 2000 : 1000;
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
        title: const Text(
          "Terrain Profile Point",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
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
              Text(
                  '✈ Reference Alt: ${referenceAltitude.toStringAsFixed(0)} ft',
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

  double? _getReferenceAltitudeFt() {
    return widget.plannedAltitudeFt;
  }
}

class LegWx {
  final double? cloudBaseFt;
  final double? visibilitySm;
  final int? windDirDeg;
  final double? windSpeedKt;
  final double? precipPct;
  final int weatherCode;

  LegWx({
    this.cloudBaseFt,
    this.visibilitySm,
    this.windDirDeg,
    this.windSpeedKt,
    this.precipPct,
    required this.weatherCode,
  });
}

class LegRisk {
  final double total;
  final LatLng from;
  final LatLng to;

  LegRisk(this.total, this.from, this.to);
}