import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import '../services/terrain_service.dart';
import 'CollapsibleLayerMenu.dart';
import 'InFlightView.dart';
import 'Maps/maps.dart';
import 'WeatherFeature.dart';

enum AppMode { preflight, inFlight }

class HazardInfo {
  final LatLng point;
  final double terrainAlt;
  HazardInfo(this.point, this.terrainAlt);
}

class DashBoard extends StatefulWidget {
  const DashBoard({super.key});

  @override
  State<DashBoard> createState() => _DashBoardState();
}

class _DashBoardState extends State<DashBoard> {
  final MapController _mapController = MapController();
  final Map<String, List<WeatherFeature>> _activeLayers = {};
  List<RoutePoint> _routePoints = [];
  bool _showFullData = false;
  int? _cruiseAltitudeFeet;
  final TextEditingController _altController = TextEditingController();
  AppMode _currentMode = AppMode.preflight;

  // Terrain Analysis
  bool _showTerrainAnalysis = false;
  List<HazardInfo> _preflightHazards = [];
  final TerrainService _terrainService = TerrainService();

  // Gemini AI Model
  GenerativeModel? _model;
  final String _kGeminiApiKey = 'YOUR_GEMINI_API_KEY'; // IMPORTANT: REPLACE WITH YOUR KEY

  @override
  void initState() {
    super.initState();
    if (_kGeminiApiKey.isNotEmpty && _kGeminiApiKey != 'YOUR_GEMINI_API_KEY') {
      _model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _kGeminiApiKey,
      );
    }
  }

  @override
  void dispose() {
    _altController.dispose();
    super.dispose();
  }

  /// NEW: Handles picking and parsing of Garmin FPL files.
  Future<void> _importGarminRoute() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['fpl'],
        withData: !kIsWeb,
      );

      if (result == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File picking cancelled.')),
        );
        return;
      }

      String? fileContent;
      if (kIsWeb) {
        if (result.files.single.bytes != null) {
          fileContent = String.fromCharCodes(result.files.single.bytes!);
        }
      } else {
        if (result.files.single.path != null) {
          final filePath = result.files.single.path!;
          fileContent = await File(filePath).readAsString();
        }
      }

      if (fileContent != null) {
        final document = XmlDocument.parse(fileContent);
        final waypoints = document.findAllElements('waypoint');
        final routePoints = <RoutePoint>[];

        for (var i = 0; i < waypoints.length; i++) {
          final waypoint = waypoints.elementAt(i);
          final idElement = waypoint.findElements('identifier').singleOrNull;
          final latElement = waypoint.findElements('lat').singleOrNull;
          final lonElement = waypoint.findElements('lon').singleOrNull;

          if (idElement != null && latElement != null && lonElement != null) {
            final id = idElement.innerText;
            final lat = double.tryParse(latElement.innerText);
            final lon = double.tryParse(lonElement.innerText);
            if (lat != null && lon != null) {
              String type = 'waypoint';
              if (i == 0) {
                type = 'origin';
              } else if (i == waypoints.length - 1) {
                type = 'destination';
              }
              routePoints.add(RoutePoint(id: id, point: LatLng(lat, lon), type: type));
            }
          }
        }
        _handleRouteImported(routePoints);
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the selected file.')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error parsing file: $e')),
      );
    }
  }

  Future<void> _analyzeTerrainRisks() async {
    if (_routePoints.isEmpty || _cruiseAltitudeFeet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please load a route and set altitude first.')),
      );
      // Turn off if requirements not met
      setState(() => _showTerrainAnalysis = false);
      return;
    }

    // Clear previous
    setState(() => _preflightHazards = []);

    final List<HazardInfo> hazards = [];

    // Check each waypoint
    for (var point in _routePoints) {
      final elevation = await _terrainService.getElevationFeet(
        point.point.latitude,
        point.point.longitude,
      );

      if (elevation != null) {
        final clearance = _cruiseAltitudeFeet!.toDouble() - elevation;
        if (clearance < 500) {
          hazards.add(HazardInfo(point.point, elevation));
        }
      }
    }

    if (mounted) {
      setState(() {
        _preflightHazards = hazards;
      });

      if (hazards.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Found ${hazards.length} terrain conflicts along route!'), backgroundColor: Colors.red),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No terrain conflicts detected at waypoints.'), backgroundColor: Colors.green),
        );
      }
    }
  }

  List<WeatherFeature> _getVisibleFeatures() {
    final allFeatures = _activeLayers.values.expand((features) => features).toList();
    if (_showFullData || _routePoints.isEmpty) return allFeatures;
    if (_cruiseAltitudeFeet == null) return [];
    
    final altitude = _cruiseAltitudeFeet!;
    return allFeatures.where((feature) {
      final (base, top) = _parseAltitudeRange(feature.rawProperties);
      return altitude >= base && altitude <= top;
    }).toList();
  }

  List<Polygon> get _displayedPolygons {
    return _getVisibleFeatures().map((f) => f.polygon).toList();
  }

  void _handleRouteImported(List<RoutePoint> points) {
    if (!mounted) return;
    setState(() {
      _routePoints = points;

      if (points.isNotEmpty) {
        // 1. Calculate Bounds
        final bounds = LatLngBounds.fromPoints(points.map((p) => p.point).toList());
        
        // 2. Move Camera
        // A small delay ensures the map widget has time to update with the new route.
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(50.0), // Add breathing room
              ),
            );
          }
        });
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Route with ${points.length} waypoints loaded.')),
    );

    // Prompt for cruise altitude
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: _altController.text);
        return AlertDialog(
          title: const Text('Enter Cruise Altitude (ft)'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'e.g., 25000'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final altitude = int.tryParse(controller.text.trim());
                if (mounted) {
                  setState(() {
                    _cruiseAltitudeFeet = altitude;
                    _altController.text = altitude?.toString() ?? '';
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A2F),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (_currentMode) {
      case AppMode.inFlight:
        return InFlightView(
          onExit: () => setState(() => _currentMode = AppMode.preflight),
          routePoints: _routePoints,
          weatherPolygons: _displayedPolygons,
          mapController: _mapController,
        );
      case AppMode.preflight:
      default:
        final hazardMarkers = _showTerrainAnalysis ? _preflightHazards.map((hazard) {
          return Marker(
            point: hazard.point,
            width: 50,
            height: 50,
            child: GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("⚠️ Terrain Conflict"),
                    content: Text(
                      "Location: ${hazard.point.latitude.toStringAsFixed(4)}, ${hazard.point.longitude.toStringAsFixed(4)}\n"
                      "Your Altitude: $_cruiseAltitudeFeet ft\n"
                      "Terrain Height: ${hazard.terrainAlt.toStringAsFixed(0)} ft\n"
                      "Clearance: ${(_cruiseAltitudeFeet! - hazard.terrainAlt).toStringAsFixed(0)} ft (UNSAFE)"
                    ),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
                  ),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.5),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)]
                    ),
                    child: const Icon(Icons.terrain, color: Colors.white, size: 24),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    color: Colors.black54,
                    child: const Text("LOW ALT", style: TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          );
        }).toList() : <Marker>[];

        final safeAreaBottomPadding = MediaQuery.of(context).padding.bottom;
      
        return Stack(
          children: [
            Maps(
              mapController: _mapController,
              weatherPolygons: _displayedPolygons,
              routePoints: _routePoints,
              hazardMarkers: hazardMarkers,
              onMapTap: _handleMapTap,
            ),
            
            CollapsibleLayerMenu(
              onToggleLayer: _toggleWeatherLayer,
              isLayerActive: (type) => type == "Terrain" ? _showTerrainAnalysis : _activeLayers.containsKey(type),
              showFullData: _showFullData,
              onToggleFullData: (val) => setState(() => _showFullData = val),
              topPosition: 160.0,
              altitude: _cruiseAltitudeFeet,
              altitudeController: _altController,
              onAltitudeChanged: (value) async {
                setState(() => _cruiseAltitudeFeet = int.tryParse(value.trim()));
                if (_showTerrainAnalysis) await _analyzeTerrainRisks();
              },
              onReset: () {
                setState(() {
                  _routePoints = [];
                  _cruiseAltitudeFeet = null;
                  _altController.clear();
                  _activeLayers.clear();
                  _showTerrainAnalysis = false;
                  _preflightHazards.clear();
                });
                _mapController.move(const LatLng(38.0, -98.0), 4.0);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Map Reset')),
                );
              },
            ),

            // NEW: Direct Import Button (Bottom-Left)
            Positioned(
              left: 16,
              bottom: 100 + safeAreaBottomPadding, // Symmetrical vertical alignment
              child: _GlassImportButton(onTap: _importGarminRoute),
            ),

            // In-Flight Mode Button (Bottom-Right)
            Positioned(
              right: 16,
              bottom: 100 + safeAreaBottomPadding, // Symmetrical vertical alignment
              child: CollapsibleActionFab(
                onPressed: () => setState(() => _currentMode = AppMode.inFlight),
              ),
            ),
          ],
        );
    }
  }
  
  void _handleMapTap(LatLng tappedPoint) {
    final visibleFeatures = _getVisibleFeatures();
    final hitFeatures = visibleFeatures.where((feature) => isPointInPolygon(tappedPoint, feature.polygon.points)).toList();
    if (hitFeatures.isNotEmpty) {
      _analyzeHazardsWithGemini(hitFeatures);
    }
  }

  bool isPointInPolygon(LatLng point, List<LatLng> polygonPoints) {
    bool isInside = false;
    for (int i = 0, j = polygonPoints.length - 2; i < polygonPoints.length - 1; j = i++) {
      if (((polygonPoints[i].latitude > point.latitude) != (polygonPoints[j].latitude > point.latitude)) &&
          (point.longitude < (polygonPoints[j].longitude - polygonPoints[i].longitude) * (point.latitude - polygonPoints[i].latitude) / (polygonPoints[j].latitude - polygonPoints[i].latitude) + polygonPoints[i].longitude)) {
        isInside = !isInside;
      }
    }
    return isInside;
  }
  
  Future<void> _analyzeHazardsWithGemini(List<WeatherFeature> features) async {
    // Implementation omitted for brevity
  }

  Future<String> _getAiSummary(List<WeatherFeature> features) async {
    if (_model == null) return "AI model not initialized.";
    final rawData = jsonEncode(features.map((f) => f.rawProperties).toList());
    final prompt = "You are a flight safety Co-Pilot. Analyze these weather hazards: $rawData. Give a concise, tactical recommendation.";
    final response = await _model!.generateContent([Content.text(prompt)]);
    return response.text ?? "Could not generate a summary.";
  }

  (int base, int top) _parseAltitudeRange(Map<String, dynamic> rawData) {
    // Implementation omitted for brevity
    return (0, 60000);
  }

  (Color, Color) _getWeatherColor(String type) {
    // Implementation omitted for brevity
    return (Colors.grey.withAlpha(77), Colors.white);
  }

  Future<void> _fetchWeatherData(String type) async {
    // Implementation omitted for brevity
  }

  Future<void> _toggleWeatherLayer(String type) async {
    if (type == "Terrain") {
      final bool enableTerrain = !_showTerrainAnalysis;
      setState(() {
        _showTerrainAnalysis = enableTerrain;
        if (!enableTerrain) _preflightHazards.clear();
      });
      if (enableTerrain) await _analyzeTerrainRisks();
      return;
    }
    
    setState(() {
      if (_activeLayers.containsKey(type)) {
        _activeLayers.remove(type);
      } else {
        _activeLayers[type] = []; // Optimistic UI
        _fetchWeatherData(type);
      }
    });
  }
}

// --------------------------------------------------------------------------
//  UI WIDGETS
// --------------------------------------------------------------------------

/// NEW: A simple, circular glassmorphism button for direct actions.
class _GlassImportButton extends StatelessWidget {
  final VoidCallback onTap;

  const _GlassImportButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
            ),
            child: const Icon(Icons.upload_file, color: Colors.cyanAccent, size: 24),
          ),
        ),
      ),
    );
  }
}

class CollapsibleActionFab extends StatefulWidget {
  final VoidCallback onPressed;
  const CollapsibleActionFab({super.key, required this.onPressed});

  @override
  State<CollapsibleActionFab> createState() => _CollapsibleActionFabState();
}

class _CollapsibleActionFabState extends State<CollapsibleActionFab> {
  bool _isExpanded = false;
  Timer? _collapseTimer;

  void _onTap() {
    if (_isExpanded) {
      widget.onPressed();
    } else {
      setState(() => _isExpanded = true);
      _startAutoCollapse();
    }
  }

  void _startAutoCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _isExpanded = false);
    });
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        width: _isExpanded ? 180 : 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: _isExpanded ? Colors.greenAccent : Colors.white.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Row(
              children: [
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: Center(child: Icon(Icons.flight_takeoff, color: Colors.greenAccent, size: 24)),
                ),
                Flexible(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isExpanded ? 1.0 : 0.0,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 16.0),
                      child: Text(
                        "Enter In-Flight",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.fade,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
