import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import 'terrain_engine.dart';
import 'WeatherEngine.dart';
import '../components/WeatherIconResolver.dart';

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
  bool _isRefreshingWeather = false;
  List<WeatherPoint> _weatherPoints = [];

  @override
  void initState() {
    super.initState();
    _refreshWeather();
  }

  Future<void> _refreshWeather() async {
    if (widget.flightPath.isEmpty) return;

    setState(() {
      _isRefreshingWeather = true;
    });

    final weatherPoints = await WeatherEngine.fetchRouteWeather(widget.flightPath, referenceAltitudeFt: _getReferenceAltitudeFt());
    if (mounted) {
      setState(() {
        _weatherPoints = weatherPoints;
        _isRefreshingWeather = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MarkerLayer(
          markers: [
            // TERRAIN RISK MARKERS
            ...widget.terrainSamples.where((t) {
              double? referenceAltitude = _getReferenceAltitudeFt();
              if (referenceAltitude == null) return false;
              double clearance = referenceAltitude - t.elevationFt;
              bool isMountainous = t.elevationFt > 4000;
              double required = isMountainous ? 2000 : 1000;
              return clearance < required;
            }).map((t) {
              double? referenceAltitude = _getReferenceAltitudeFt();
              double clearance = (referenceAltitude ?? 0) - t.elevationFt;
              Color c = (clearance < 500) ? Colors.redAccent : Colors.orangeAccent;
              IconData icon = (clearance < 500) ? Icons.warning_rounded : Icons.report_problem_rounded;

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

            // WEATHER MARKERS
            ..._weatherPoints.map((wp) {
              return Marker(
                width: 38,
                height: 38,
                point: wp.position,
                child: GestureDetector(
                  onTap: () => _showWeatherPopup(wp),
                  child: Icon(
                    WeatherIconResolver.getIcon(wp.weather.weatherCode),
                    color: WeatherIconResolver.getColor(wp.weather.weatherCode),
                    size: 30,
                  ),
                ),
              );
            }),

            // DEPARTURE/ARRIVAL
            if (widget.departureAirport != null)
              Marker(
                point: widget.departureAirport!,
                width: 80,
                height: 80,
                child: const Icon(Icons.flight_takeoff, color: Colors.greenAccent, size: 40),
              ),
            if (widget.arrivalAirport != null)
              Marker(
                point: widget.arrivalAirport!,
                width: 80,
                height: 80,
                child: const Icon(Icons.flight_land, color: Colors.redAccent, size: 40),
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
            onPressed: _isRefreshingWeather ? null : _refreshWeather,
            child: _isRefreshingWeather
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0))
                : const Icon(Icons.refresh, color: Colors.white),
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
    double? referenceAltitude = _getReferenceAltitudeFt();
    double elevation = t.elevationFt;
    double? clearance = referenceAltitude != null ? referenceAltitude - elevation : null;
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
        title: const Text("Terrain Profile Point", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🌍 Lat: ${t.position.latitude.toStringAsFixed(4)}', style: const TextStyle(color: Colors.white70)),
            Text('🌍 Lon: ${t.position.longitude.toStringAsFixed(4)}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('🗻 Elevation: ${t.elevationFt.toStringAsFixed(0)} ft', style: const TextStyle(color: Colors.white70)),
            if (referenceAltitude != null)
              Text('✈ Reference Alt: ${referenceAltitude.toStringAsFixed(0)} ft', style: const TextStyle(color: Colors.white70)),
            if (clearance != null)
              Text('📉 Clearance: ${clearance.toStringAsFixed(0)} ft', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(risk, style: const TextStyle(color: Colors.orangeAccent)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(color: Colors.lightBlueAccent)),
          ),
        ],
      ),
    );
  }

  void _showWeatherPopup(WeatherPoint wp) {
    final wx = wp.weather;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A35),
        title: const Text("Weather Point", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🌍 Lat: ${wp.position.latitude.toStringAsFixed(4)}', style: const TextStyle(color: Colors.white70)),
            Text('🌍 Lon: ${wp.position.longitude.toStringAsFixed(4)}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            if (wx.cloudBaseFt != null)
              Text('☁️ Cloud Base: ${wx.cloudBaseFt!.toStringAsFixed(0)} ft', style: const TextStyle(color: Colors.white70)),
            if (wx.visibilitySm != null)
              Text('👁️ Visibility: ${wx.visibilitySm!.toStringAsFixed(1)} SM', style: const TextStyle(color: Colors.white70)),
            if (wx.windDirDeg != null && wx.windSpeedKt != null)
              Text('💨 Wind: ${wx.windDirDeg}° at ${wx.windSpeedKt!.toStringAsFixed(0)} kts', style: const TextStyle(color: Colors.white70)),
            if (wx.precipPct != null)
              Text('💧 Precip: ${wx.precipPct!.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white70)),
            if (wx.convective)
              const Text('⚡️ Convective Activity', style: TextStyle(color: Colors.purpleAccent)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(color: Colors.lightBlueAccent)),
          ),
        ],
      ),
    );
  }

  double? _getReferenceAltitudeFt() {
    // Use current GPS altitude if available in-flight, otherwise planned altitude.
    if (widget.currentPosition != null && widget.currentPosition!.altitude != null) {
      return widget.currentPosition!.altitude * 3.28084; // meters to feet
    }
    return widget.plannedAltitudeFt;
  }
}
