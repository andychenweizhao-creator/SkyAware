// ========================
//  flight_plan_box.dart
// ========================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'Risk_Assesments.dart' hide LegWx;
import "../../../Service/terrain_engine.dart";
import '../../../Service/WeatherEngine.dart';

import 'terrain_profile_painter.dart';
import 'route_weather_profile.dart';
import '../../../components/Maps/fullscreen_map.dart';
import 'flight_plan_parser.dart';
import 'flight_mode.dart';
import 'flight_plan_map.dart';
import 'flight_controls.dart';
import 'risk_analysis_summary.dart';
import 'weight_balance_calculator.dart';

class FlightPlanBox extends StatefulWidget {
  const FlightPlanBox({super.key});
  @override
  _FlightPlanBoxState createState() => _FlightPlanBoxState();
}

class _FlightPlanBoxState extends State<FlightPlanBox> {
  FlightMode _flightMode = FlightMode.auto;
  bool _isRefreshingWeather = false;
  List<LatLng> _flightPath = [];
  List<String> _waypointNames = [];
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  LatLng? _departureAirport;
  LatLng? _arrivalAirport;
  
  final TextEditingController _altitudeController = TextEditingController();

  final Map<String, String> _tileSources = {
    'osm': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'terrain': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    'satellite': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    'wunderground': 'webview',
  };

  List<LegRisk> _legRisks = [];
  List<WeatherPoint> _weatherPoints = [];
  List<TerrainSample> _terrainSamples = [];
  double? _maxTerrainFt;
  double? _recommendedAltitudeFt;
  double? _plannedAltitudeFt;

  @override
  void initState() {
    super.initState();
    _initLocationStream();
  }

  Future<void> _initLocationStream() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    if (await Geolocator.checkPermission() == LocationPermission.denied) {
      if (await Geolocator.requestPermission() == LocationPermission.denied) return;
    }
    _positionStream = Geolocator.getPositionStream().listen((p) => setState(() => _currentPosition = p));
  }

  double? _getReferenceAltitudeFt() {
    if (_flightMode == FlightMode.inflight) {
      return (_currentPosition?.altitude != null) ? _currentPosition!.altitude * 3.28084 : (_recommendedAltitudeFt ?? 15000);
    }
    if (_flightMode == FlightMode.preflight) {
      return _plannedAltitudeFt ?? _recommendedAltitudeFt ?? 15000;
    }
    // Auto
    final speed = _currentPosition?.speed ?? 0;
    if (speed < 10) {
      return _plannedAltitudeFt ?? _recommendedAltitudeFt ?? 15000;
    }
    return (_currentPosition?.altitude != null) ? _currentPosition!.altitude * 3.28084 : (_recommendedAltitudeFt ?? 15000);
  }

  @override
  void dispose() { 
    _positionStream?.cancel(); 
    _altitudeController.dispose();
    super.dispose(); 
  }

  Future<void> _refreshWeather() async {
    if (_flightPath.isEmpty) return;
    setState(() => _isRefreshingWeather = true);
    try {
      final wx = await WeatherEngine.fetchRouteWeather(_flightPath, referenceAltitudeFt: _getReferenceAltitudeFt());
      setState(() { _weatherPoints = wx; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Weather Updated")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isRefreshingWeather = false);
    }
  }

  Future<void> _handleUpload() async {
    try {
      final result = await FlightPlanParser.pickAndParse();
      if (result == null) return;
      setState(() {
        _flightPath = result.path;
        _waypointNames = result.names;
        _departureAirport = result.path.isNotEmpty ? result.path.first : null;
        _arrivalAirport = result.path.length > 1 ? result.path.last : null;
      });
      
      final terr = await TerrainEngine.fetchRouteTerrain(_flightPath);
      setState(() { 
        _terrainSamples = terr.samples; 
        _maxTerrainFt = terr.maxElevationFt; 
        _recommendedAltitudeFt = terr.recommendedAltitudeFt;
        // Auto-fill planned altitude if empty
        if (_plannedAltitudeFt == null) {
          _plannedAltitudeFt = _recommendedAltitudeFt;
          _altitudeController.text = (_plannedAltitudeFt ?? 0).toStringAsFixed(0);
        }
      });
      await _refreshWeather();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Widget _buildUtilityButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.white.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final refAlt = _getReferenceAltitudeFt();
    final isPreflight = _flightMode == FlightMode.preflight || _flightMode == FlightMode.auto;

    return SingleChildScrollView(
      child: Column(
        children: [
          FlightControls(
            currentMode: _flightMode,
            onModeChanged: (m) {
              setState(() => _flightMode = m);
              _refreshWeather(); // Refresh to apply mode/altitude change to weather analysis
            },
            altitudeController: _altitudeController,
            onAltitudeChanged: (val) {
              setState(() => _plannedAltitudeFt = double.tryParse(val));
              // Debouncing could be added here, but for now manual refresh or relying on mode change is safer for API limits
            },
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: _buildUtilityButton(
                    icon: Icons.scale_rounded,
                    label: "W&B",
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const WeightBalanceCalculator())),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildUtilityButton(
                    icon: Icons.send_rounded,
                    label: "File Plan",
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Flight Plan Filed (Simulated)"))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildUtilityButton(
                    icon: Icons.checklist_rounded,
                    label: "Checklist",
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Checklist Feature Coming Soon"))),
                  ),
                ),
              ],
            ),
          ),

          if (_legRisks.isNotEmpty) RouteWeatherProfile(legRisks: _legRisks, waypointNames: _waypointNames),
          const SizedBox(height: 12),
          
          // RISK ANALYSIS SUMMARY (New Widget)
          RiskAnalysisSummary(
            weatherPoints: _weatherPoints,
            referenceAltitudeFt: refAlt,
            usePlannedAlt: isPreflight,
          ),
          const SizedBox(height: 12),
          FlightPlanMap(
            flightPath: _flightPath,
            waypointNames: _waypointNames,
            weatherPoints: _weatherPoints,
            terrainSamples: _terrainSamples,
            currentPosition: _currentPosition,
            referenceAltitudeFt: refAlt,
            flightMode: _flightMode,
            onUpload: _handleUpload,
            onFullscreen: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FullscreenMap(flightPath: _flightPath, waypointNames: _waypointNames, departureAirport: _departureAirport, arrivalAirport: _arrivalAirport, currentPosition: _currentPosition, tileSources: _tileSources, mapStyle: 'osm', legRisks: _legRisks, weatherPoints: _weatherPoints, terrainSamples: _terrainSamples, recommendedAltitudeFt: _recommendedAltitudeFt, plannedAltitudeFt: _plannedAltitudeFt))),
            onRefreshWeather: _refreshWeather,
            isRefreshing: _isRefreshingWeather,
          ),
          if (_terrainSamples.isNotEmpty && _recommendedAltitudeFt != null) Container(height: 150, color: Colors.black12, child: CustomPaint(painter: TerrainProfilePainter(_terrainSamples, refAlt ?? _recommendedAltitudeFt!))),
        ],
      ),
    );
  }
}
