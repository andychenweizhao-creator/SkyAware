import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../../components/WeatherIconResolver.dart';
import '../../../Service/WeatherEngine.dart';
import '../../../Service/terrain_engine.dart';
import 'weather_analysis_logic.dart';
import 'weather_hover_bubble.dart';
import 'terrain_popup.dart';
import 'flight_mode.dart';

class FlightPlanMap extends StatefulWidget {
  final List<LatLng> flightPath;
  final List<String> waypointNames;
  final List<WeatherPoint> weatherPoints;
  final List<TerrainSample> terrainSamples;
  final Position? currentPosition;
  final double? referenceAltitudeFt;
  final FlightMode flightMode;
  final VoidCallback onUpload;
  final VoidCallback onFullscreen;
  final VoidCallback onRefreshWeather;
  final bool isRefreshing;

  const FlightPlanMap({
    super.key,
    required this.flightPath,
    required this.waypointNames,
    required this.weatherPoints,
    required this.terrainSamples,
    required this.currentPosition,
    required this.referenceAltitudeFt,
    required this.flightMode,
    required this.onUpload,
    required this.onFullscreen,
    required this.onRefreshWeather,
    required this.isRefreshing,
  });

  @override
  State<FlightPlanMap> createState() => _FlightPlanMapState();
}

class _FlightPlanMapState extends State<FlightPlanMap> {
  final MapController _mapController = MapController();
  late WebViewController _webController;
  String _mapStyle = 'osm';
  WeatherPoint? _hoverWeather;
  final Distance _distance = const Distance();
  
  // Default start zoom
  double _currentZoom = 9.2;

  final Map<String, String> _tileSources = {
    'osm': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'terrain': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    'satellite':
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    'wunderground': 'webview',
  };

  @override
  void initState() {
    super.initState();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse("https://www.wunderground.com/wundermap"));
  }

  @override
  void didUpdateWidget(covariant FlightPlanMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flightPath != oldWidget.flightPath &&
        widget.flightPath.isNotEmpty) {
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(widget.flightPath),
            padding: const EdgeInsets.all(50),
          ),
        );
      } catch (_) {}
    }
  }

  Color _getWeatherRiskColor(String category) {
    switch (category) {
      case 'LIFR':
        return Colors.redAccent;
      case 'IFR':
        return Colors.orangeAccent;
      case 'MVFR':
        return Colors.blueAccent;
      case 'VFR':
        return Colors.greenAccent;
      default:
        return Colors.grey;
    }
  }

  // --- Intelligent Scaling Logic ---

  double _getSmartIconSize() {
    // Zoom In (14+) -> Large Icons (32)
    // Zoom Out (5-) -> Small Icons (12)
    if (_currentZoom >= 13) return 32.0;
    if (_currentZoom >= 10) return 24.0;
    if (_currentZoom >= 7) return 18.0;
    return 12.0;
  }

  double _getSmartMergeDistance(double iconSize) {
    // Calculate meters per pixel at current latitude (approx at equator for simplicity or mid-lat)
    // Resolution = 156543.03 meters/pixel * cos(lat) / 2^zoom.
    // Using simple equator approx: 156543 / 2^zoom
    final metersPerPx = 156543.0 / math.pow(2, _currentZoom);
    
    // We want icons to NOT overlap. 
    // Spacing (m) = IconSize (px) * Buffer (1.2) * metersPerPx
    // This ensures that as we zoom in (metersPerPx drops), spacing drops -> Higher Density.
    // As we zoom out (metersPerPx increases), spacing increases -> Lower Density.
    
    // At Zoom 5 (m/px ~ 4891), Size 12 -> Spacing ~ 70km
    // At Zoom 13 (m/px ~ 19), Size 32 -> Spacing ~ 0.7km
    
    // Enforce a minimum floor to avoid clutter
    double calculated = (iconSize * 1.5 * metersPerPx) / 1000.0; // in km
    
    return calculated;
  }

  // --- Terrain Merging Logic ---
  List<TerrainSample> _mergeTerrainRisks(List<TerrainSample> risks) {
    if (risks.isEmpty) return [];
    
    final double iconSize = _getSmartIconSize();
    final double segmentLengthKm = _getSmartMergeDistance(iconSize);
    
    List<TerrainSample> merged = [];
    List<TerrainSample> currentCluster = [risks.first];
    
    LatLng clusterStartPos = risks.first.position;

    void finalizeCluster() {
        if (currentCluster.isEmpty) return;
        
        // Intelligent Priority: Use MAX elevation
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
    // 1. Calculate Smart Props
    final double iconSize = _getSmartIconSize();
    final double weatherMergeKm = _getSmartMergeDistance(iconSize);

    // 2. Filter terrain samples first (only keep risks)
    final rawRisks = widget.terrainSamples.where((t) {
      final ref = widget.referenceAltitudeFt;
      if (ref == null) return false;
      return (ref - t.elevationFt) < 1000; 
    }).toList();

    // 3. Merge them
    final displayRisks = _mergeTerrainRisks(rawRisks);

    return Container(
      height: 600,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Stack(
        children: [
          if (_mapStyle == 'wunderground')
            WebViewWidget(controller: _webController)
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.flightPath.isNotEmpty
                    ? widget.flightPath.first
                    : const LatLng(37.96, -112.32),
                initialZoom: 9.2,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.all),
                onPositionChanged: (pos, hasGesture) {
                  if (pos.zoom != null && (pos.zoom! - _currentZoom).abs() > 0.5) {
                    setState(() {
                      _currentZoom = pos.zoom!;
                    });
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: _tileSources[_mapStyle]!,
                  userAgentPackageName: 'com.example.skyaware',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                        points: widget.flightPath,
                        strokeWidth: 4,
                        color: Colors.blue)
                  ],
                ),
                MarkerLayer(markers: [
                  ...widget.flightPath.map((p) => Marker(
                      point: p,
                      child: const Icon(Icons.location_on,
                          color: Colors.white, size: 16))),
                  
                  // WEATHER MARKERS
                  ...WeatherAnalysisLogic.mergeWeatherPointsAdaptive(
                    widget.weatherPoints,
                    baseMergeKm: weatherMergeKm, 
                    isPreflight: widget.flightMode == FlightMode.preflight,
                  ).map((wp) {
                    final analysis = WeatherAnalysisLogic.buildVfrAnalysisForPoint(
                      wp.weather,
                      referenceAltitudeFt: widget.referenceAltitudeFt,
                      usePlannedAlt: widget.flightMode == FlightMode.preflight,
                    );
                    
                    final category = analysis['category'] as String;
                    final List<dynamic> hazards = analysis['hazards'] as List<dynamic>;

                    if (hazards.isEmpty) {
                      return Marker(
                        point: wp.position,
                        width: 0,
                        height: 0,
                        child: const SizedBox(), 
                      );
                    }

                    final riskColor = _getWeatherRiskColor(category);

                    return Marker(
                        point: wp.position,
                        width: iconSize,
                        height: iconSize,
                        child: GestureDetector(
                          onTap: () => setState(() =>
                              _hoverWeather = (_hoverWeather == wp ? null : wp)),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black54,
                              border: Border.all(color: riskColor, width: 2),
                            ),
                            child: Icon(
                              WeatherIconResolver.getIcon(wp.weather.weatherCode),
                              color: riskColor, 
                              size: iconSize * 0.7, // Scale icon inside container
                            ),
                          ),
                        ),
                      );
                  }).where((m) => m.width > 0),

                  // TERRAIN MARKERS 
                  ...displayRisks.map((t) {
                    return Marker(
                      point: t.position,
                      width: iconSize,
                      height: iconSize,
                      child: GestureDetector(
                          onTap: () => showTerrainPopup(
                                context, 
                                t, 
                                referenceAltitudeFt: widget.referenceAltitudeFt
                              ),
                          child: Icon(Icons.warning,
                              color: Colors.redAccent, size: iconSize)));
                  }),
                ]),
              ],
            ),
          if (_hoverWeather != null)
            Positioned(
              bottom: 20,
              left: 20,
              child: GestureDetector(
                onTap: () => setState(() => _hoverWeather = null),
                child: WeatherHoverBubble(
                  wx: _hoverWeather!.weather,
                  referenceAltitudeFt: widget.referenceAltitudeFt,
                  usePlannedAlt: widget.flightMode == FlightMode.preflight,
                ),
              ),
            ),
          // RIGHT SIDE BUTTONS
          Positioned(
            top: 10,
            right: 10,
            child: Column(
              children: [
                FloatingActionButton(
                    mini: true,
                    heroTag: 'upload',
                    onPressed: widget.onUpload,
                    child: const Icon(Icons.upload_file)),
                const SizedBox(height: 8),
                FloatingActionButton(
                    mini: true,
                    heroTag: 'refresh',
                    backgroundColor: Colors.orangeAccent,
                    onPressed: widget.isRefreshing ? null : widget.onRefreshWeather,
                    child: widget.isRefreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ))
                        : const Icon(Icons.refresh, color: Colors.white)),
                const SizedBox(height: 8),
                FloatingActionButton(
                    mini: true,
                    heroTag: 'full',
                    onPressed: widget.onFullscreen,
                    child: const Icon(Icons.fullscreen)),
                const SizedBox(height: 8),
                // ZOOM IN
                FloatingActionButton(
                  mini: true,
                  heroTag: 'zoom_in',
                  backgroundColor: Colors.grey[800],
                  onPressed: () => _zoom(1.0),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
                const SizedBox(height: 8),
                // ZOOM OUT
                FloatingActionButton(
                  mini: true,
                  heroTag: 'zoom_out',
                  backgroundColor: Colors.grey[800],
                  onPressed: () => _zoom(-1.0),
                  child: const Icon(Icons.remove, color: Colors.white),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 10,
            left: 10,
            child: Container(
              color: Colors.black54,
              child: DropdownButton<String>(
                value: _mapStyle,
                items: _tileSources.keys
                    .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.toUpperCase(),
                            style: const TextStyle(color: Colors.white))))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _mapStyle = v);
                },
                dropdownColor: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
