import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../WeatherIconResolver.dart';
import '../../Service/WeatherEngine.dart';
import '../../Service/terrain_engine.dart';
import '../../Screens/DashBoard/components/Risk_Assesments.dart' hide LegWx;
import '../../Screens/DashBoard/components/weather_analysis_logic.dart';
import '../../Screens/DashBoard/components/weather_hover_bubble.dart';
import '../../Screens/DashBoard/components/terrain_popup.dart';
import '../../Screens/DashBoard/components/flight_mode.dart';
import '../../Screens/DashBoard/components/flight_controls.dart';

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
  late MapController _mapController;
  late WebViewController _webController;
  late TextEditingController _altitudeController;
  
  String _currentStyle = 'osm';
  WeatherPoint? _hoverWeather;
  final Distance _distance = const Distance();
  double _currentZoom = 8.0;
  
  // Local state for controls
  FlightMode _currentMode = FlightMode.preflight;
  double? _currentPlannedAlt;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _currentStyle = widget.mapStyle;
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse("https://www.wunderground.com/wundermap"));
      
    // Initialize with passed values
    _currentPlannedAlt = widget.plannedAltitudeFt;
    _altitudeController = TextEditingController(text: _currentPlannedAlt?.toStringAsFixed(0) ?? "");
    
    // Attempt to guess mode
    if (widget.currentPosition != null && (widget.currentPosition!.speed > 5)) {
        _currentMode = FlightMode.inflight;
    } else {
        _currentMode = FlightMode.preflight;
    }
  }

  @override
  void dispose() {
    _altitudeController.dispose();
    super.dispose();
  }

  double _getReferenceAltitude() {
    if (_currentMode == FlightMode.inflight && widget.currentPosition != null) {
        return widget.currentPosition!.altitude * 3.28084;
    }
    return _currentPlannedAlt ?? widget.recommendedAltitudeFt ?? 15000;
  }
  
  bool _isPreflight() {
    return _currentMode == FlightMode.preflight || _currentMode == FlightMode.auto;
  }

  Color _getWeatherRiskColor(String category) {
    switch (category) {
      case 'LIFR': return Colors.redAccent;
      case 'IFR': return Colors.orangeAccent;
      case 'MVFR': return Colors.blueAccent;
      case 'VFR': return Colors.greenAccent;
      default: return Colors.grey;
    }
  }

  double _getSmartIconSize() {
    if (_currentZoom >= 13) return 32.0;
    if (_currentZoom >= 10) return 24.0;
    if (_currentZoom >= 7) return 18.0;
    return 12.0;
  }

  double _getSmartMergeDistance(double iconSize) {
    final metersPerPx = 156543.0 / math.pow(2, _currentZoom);
    double calculated = (iconSize * 1.5 * metersPerPx) / 1000.0; 
    return calculated;
  }

  List<TerrainSample> _mergeTerrainRisks(List<TerrainSample> risks) {
    if (risks.isEmpty) return [];
    
    final double iconSize = _getSmartIconSize();
    final double segmentLengthKm = _getSmartMergeDistance(iconSize);
    
    List<TerrainSample> merged = [];
    List<TerrainSample> currentCluster = [risks.first];
    
    LatLng clusterStartPos = risks.first.position;

    void finalizeCluster() {
        if (currentCluster.isEmpty) return;
        TerrainSample maxRiskSample = currentCluster.reduce((a, b) => a.elevationFt > b.elevationFt ? a : b);
        int midIndex = currentCluster.length ~/ 2;
        final pos = currentCluster[midIndex].position;
        merged.add(TerrainSample(pos, maxRiskSample.elevationFt));
    }

    for (int i = 1; i < risks.length; i++) {
      final curr = risks[i];
      final distFromStart = _distance.as(LengthUnit.Kilometer, clusterStartPos, curr.position);
      final distFromPrev = _distance.as(LengthUnit.Kilometer, risks[i-1].position, curr.position);

      if (distFromStart <= segmentLengthKm && distFromPrev < 10.0) {
        currentCluster.add(curr);
      } else {
        finalizeCluster();
        currentCluster = [curr];
        clusterStartPos = curr.position;
      }
    }
    
    finalizeCluster();
    return merged;
  }

  void _zoom(double amount) {
    final currentZoom = _mapController.camera.zoom;
    final currentCenter = _mapController.camera.center;
    _mapController.move(currentCenter, currentZoom + amount);
  }

  @override
  Widget build(BuildContext context) {
    final double iconSize = _getSmartIconSize();
    final double weatherMergeKm = _getSmartMergeDistance(iconSize);
    final double refAlt = _getReferenceAltitude();

    // Terrain Filtering & Merging
    final rawRisks = widget.terrainSamples.where((t) {
      return (refAlt - t.elevationFt) < 1000; 
    }).toList();
    final displayRisks = _mergeTerrainRisks(rawRisks);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Fullscreen Map", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E2A35),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: Colors.black87,
      body: Stack(
        children: [
          if (_currentStyle == 'wunderground')
            WebViewWidget(controller: _webController)
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.flightPath.isNotEmpty ? widget.flightPath.first : const LatLng(37.96, -112.32),
                initialZoom: 8,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                onPositionChanged: (pos, hasGesture) {
                  if (pos.zoom != null && (pos.zoom! - _currentZoom).abs() > 0.5) {
                    setState(() { _currentZoom = pos.zoom!; });
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: widget.tileSources[_currentStyle]!,
                  userAgentPackageName: 'com.andy.skyaware',
                ),
                PolylineLayer(polylines: [
                  Polyline(points: widget.flightPath, color: Colors.blue, strokeWidth: 4)
                ]),
                MarkerLayer(markers: [
                  ...widget.flightPath.map((p) => Marker(
                      point: p, 
                      child: const Icon(Icons.location_on, color: Colors.white, size: 24)
                  )),
                  if (widget.currentPosition != null)
                    Marker(
                      point: LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude),
                      child: const Icon(Icons.airplanemode_active, color: Colors.cyanAccent, size: 32),
                    ),

                  // Weather Markers
                  ...WeatherAnalysisLogic.mergeWeatherPointsAdaptive(
                    widget.weatherPoints,
                    baseMergeKm: weatherMergeKm, 
                    isPreflight: _isPreflight(),
                  ).map((wp) {
                    final analysis = WeatherAnalysisLogic.buildVfrAnalysisForPoint(
                      wp.weather,
                      referenceAltitudeFt: refAlt,
                      usePlannedAlt: _isPreflight(),
                    );
                    
                    final category = analysis['category'] as String;
                    final List<dynamic> hazards = analysis['hazards'] as List<dynamic>;

                    if (hazards.isEmpty) {
                      return Marker(point: wp.position, width: 0, height: 0, child: const SizedBox());
                    }

                    final riskColor = _getWeatherRiskColor(category);

                    return Marker(
                      point: wp.position,
                      width: iconSize,
                      height: iconSize,
                      child: GestureDetector(
                        onTap: () => setState(() => _hoverWeather = (_hoverWeather == wp ? null : wp)),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black54,
                            border: Border.all(color: riskColor, width: 2),
                          ),
                          child: Icon(
                            WeatherIconResolver.getIcon(wp.weather.weatherCode),
                            color: riskColor, 
                            size: iconSize * 0.7,
                          ),
                        ),
                      ),
                    );
                  }).where((m) => m.width > 0),

                  // Terrain Markers
                  ...displayRisks.map((t) {
                    return Marker(
                      point: t.position,
                      width: iconSize,
                      height: iconSize,
                      child: GestureDetector(
                          onTap: () => showTerrainPopup(context, t, referenceAltitudeFt: refAlt),
                          child: Icon(Icons.warning, color: Colors.redAccent, size: iconSize)
                      ),
                    );
                  }),
                ]),
              ],
            ),
          
          // Flight Controls (Top Center/Left)
          Positioned(
            top: 10, left: 10, right: 60, // Avoid Zoom buttons on right
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E2A35).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: FlightControls(
                currentMode: _currentMode,
                onModeChanged: (m) => setState(() => _currentMode = m),
                altitudeController: _altitudeController,
                onAltitudeChanged: (v) => setState(() => _currentPlannedAlt = double.tryParse(v)),
              ),
            ),
          ),

          // Hover Bubble
          if (_hoverWeather != null)
            Positioned(
              bottom: 80, left: 20,
              child: GestureDetector(
                onTap: () => setState(() => _hoverWeather = null),
                child: WeatherHoverBubble(
                  wx: _hoverWeather!.weather,
                  referenceAltitudeFt: refAlt,
                  usePlannedAlt: _isPreflight(),
                ),
              ),
            ),

          // Map Style Selector
          Positioned(
            bottom: 20, left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: DropdownButton<String>(
                value: _currentStyle,
                dropdownColor: Colors.black87,
                underline: const SizedBox(),
                style: const TextStyle(color: Colors.white),
                icon: const Icon(Icons.layers, color: Colors.white),
                items: widget.tileSources.keys.map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase()))).toList(),
                onChanged: (v) { if(v!=null) setState(() => _currentStyle = v); },
              ),
            ),
          ),

          // Zoom Controls
          Positioned(
            bottom: 20, right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'fs_zoom_in',
                  backgroundColor: Colors.grey[800],
                  mini: true,
                  onPressed: () => _zoom(1.0),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'fs_zoom_out',
                  backgroundColor: Colors.grey[800],
                  mini: true,
                  onPressed: () => _zoom(-1.0),
                  child: const Icon(Icons.remove, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
