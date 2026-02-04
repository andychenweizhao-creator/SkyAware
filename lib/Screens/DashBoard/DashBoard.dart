import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:xml/xml.dart';

import 'InFlightView.dart';
import 'Maps/maps.dart';
import 'WeatherFeature.dart';
import '../../services/terrain_service.dart';
import 'CollapsibleLayerMenu.dart';



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
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  AppMode _currentMode = AppMode.preflight;

  // Terrain Analysis
  bool _showTerrainAnalysis = false;
  List<HazardInfo> _preflightHazards = [];
  final TerrainService _terrainService = TerrainService();

  // Gemini AI Model
  GenerativeModel? _model;
  final String _kGeminiApiKey = 'AIzaSyB_nwHRCKO9RgAgOXTPfeL5o_UbL3GW3X4'; // IMPORTANT: REPLACE WITH YOUR KEY

  @override
  void initState() {
    super.initState();
    // Initialize the Gemini Model
    if (_kGeminiApiKey.isNotEmpty && _kGeminiApiKey != 'YOUR_GEMINI_API_KEY') {
      _model = GenerativeModel(
        model: 'gemini-3-pro-preview', // Correct exact name from user's list
        apiKey: _kGeminiApiKey,
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _altController.dispose();
    super.dispose();
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

  // Getter flattens the map of features into a single list of polygons for rendering.
  List<Polygon> get _allPolygons =>
      _activeLayers.values.expand((features) => features.map((f) => f.polygon)).toList();

  List<WeatherFeature> _getVisibleFeatures() {
    // Flatten all features from all active layers into a single list.
    final allFeatures = _activeLayers.values.expand((features) => features).toList();

    // Strict Priority 1 & 2: Show all data if override is on or no route is loaded.
    if (_showFullData || _routePoints.isEmpty) {
      return allFeatures;
    }

    // Strict Priority 3: Route exists but altitude is missing — show nothing.
    if (_cruiseAltitudeFeet == null) {
      return [];
    }

    // Strict Priority 4: Smart filter based on cruise altitude.
    final altitude = _cruiseAltitudeFeet!;
    final List<WeatherFeature> filteredFeatures = [];

    for (final feature in allFeatures) {
      final (base, top) = _parseAltitudeRange(feature.rawProperties);
      if (altitude >= base && altitude <= top) {
        filteredFeatures.add(feature);
      }
    }

    return filteredFeatures;
  }

  List<Polygon> get _displayedPolygons {
    return _getVisibleFeatures().map((f) => f.polygon).toList();
  }

  Future<void> _importGarminRoute() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['fpl', 'gpx', 'xml'],
        withData: !kIsWeb, // Read bytes on web, use path on mobile
      );

      if (result == null) {
        return; // User canceled
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
        final List<RoutePoint> parsedPoints = [];

        for (int i = 0; i < waypoints.length; i++) {
          final wp = waypoints.elementAt(i);
          final latEl = wp.findElements('lat').singleOrNull;
          final lonEl = wp.findElements('lon').singleOrNull;
          final idEl = wp.findElements('identifier').singleOrNull;

          if (latEl != null && lonEl != null) {
            final lat = double.tryParse(latEl.innerText);
            final lon = double.tryParse(lonEl.innerText);
            final id = idEl?.innerText ?? "WPT\${i+1}";

            if (lat != null && lon != null) {
              String type = 'waypoint';
              if (i == 0) type = 'origin';
              else if (i == waypoints.length - 1) type = 'destination';

              parsedPoints.add(RoutePoint(
                id: id,
                point: LatLng(lat, lon),
                type: type
              ));
            }
          }
        }

        if (parsedPoints.isNotEmpty) {
          _handleRouteImported(parsedPoints);
        } else {
           if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('No waypoints found in file.'))
             );
           }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error parsing file: $e'))
        );
      }
    }
  }

  void _handleRouteImported(List<RoutePoint> points) {
    setState(() {
      _routePoints = points;
    });

    if (points.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(points.map((p) => p.point).toList());
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50.0),
        ),
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Route with ${points.length} waypoints loaded.')),
    );
  }

  // void _navigateToPreFlightPage() {
  //   Navigator.push(
  //     context,
  //     MaterialPageRoute(
  //       builder: (context) => PreFlightPage(onRouteParsed: _handleRouteImported),
  //     ),
  //   );
  // }

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
          onExit: () {
            setState(() {
              _currentMode = AppMode.preflight;
            });
          },
          routePoints: _routePoints,
          weatherPolygons: _displayedPolygons,
          mapController: _mapController,
        );
      case AppMode.preflight:
      default:
      // Convert hazards to markers
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
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))
                    ],
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
                        boxShadow: [
                          BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)
                        ]
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
            Positioned.fill(
                child: Maps(
                  mapController: _mapController,
                  weatherPolygons: _displayedPolygons,
                  routePoints: _routePoints,
                  hazardMarkers: hazardMarkers,
                  onMapTap: _handleMapTap,
                )),
            // Preflightview(
            //   mapController: _mapController,
            //   onNavigateToPreFlight: _navigateToPreFlightPage,
            // ),

            // Side Menu (Now includes Reset logic)
            CollapsibleLayerMenu(
              onToggleLayer: _toggleWeatherLayer,
              isLayerActive: (type) => type == "Terrain" ? _showTerrainAnalysis : _activeLayers.containsKey(type),
              showFullData: _showFullData,
              onToggleFullData: (val) => setState(() => _showFullData = val),
              topPosition: 160.0,
              altitude: _cruiseAltitudeFeet,
              altitudeController: _altController,
              onAltitudeChanged: (value) async {
                setState(() {
                  _cruiseAltitudeFeet = int.tryParse(value.trim());
                });
                // Re-analyze if altitude changes while terrain mode is on
                if (_showTerrainAnalysis) {
                  await _analyzeTerrainRisks();
                }
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

            // Left-Side Import Button
            Positioned(
              left: 16,
              bottom: 100 + safeAreaBottomPadding,
              child: _GlassImportButton(
                onPressed: _importGarminRoute,
              ),
            ),

            // Right-Side Floating Action Button (New Design)
            Positioned(
              right: 16,
              bottom: MediaQuery.of(context).size.height * 0.3, // Approx 30% from bottom
              child: CollapsibleActionFab(
                onPressed: () {
                  setState(() {
                    _currentMode = AppMode.inFlight;
                  });
                },
              ),
            ),
          ],
        );
    }
  }

  void _handleMapTap(LatLng tappedPoint) {
    // 1. Get only the features that are currently visible on the map.
    final visibleFeatures = _getVisibleFeatures();
    final List<WeatherFeature> hitFeatures = [];

    // 2. Iterate ONLY through the visible features.
    for (final feature in visibleFeatures) {
      // 3. Mathematical Check: Is the point inside this polygon?
      if (isPointInPolygon(tappedPoint, feature.polygon.points)) {
        hitFeatures.add(feature); // Add to list (Collision detected!)
      }
    }

    // 4. Trigger AI if we hit any of the VISIBLE polygons.
    if (hitFeatures.isNotEmpty) {
      print("⚡️ Tap Hit ${hitFeatures.length} layers. Triggering Co-Pilot...");
      // Pass the full list (including overlaps) to Gemini
      _analyzeHazardsWithGemini(hitFeatures);
    } else {
      print("📍 Tap on clear airspace (No visible data found).");
    }
  }

  /// Uses the robust Ray-Casting algorithm (also known as the Even-Odd Rule)
  /// to accurately determine if a point is inside a polygon. This method is robust against concave polygons
  /// and correctly handles edge cases, such as horizontal edges, which resolves the previous inconsistency.
  bool isPointInPolygon(LatLng point, List<LatLng> polygonPoints) {
    bool isInside = false;
    final double pointLat = point.latitude;
    final double pointLon = point.longitude;

    // We iterate through each edge of the polygon. `j` is the previous vertex to `i`.
    // The polygon is pre-closed by the parsing logic (first point == last point), so we
    // can iterate up to the second-to-last vertex.
    for (int i = 0, j = polygonPoints.length - 2; i < polygonPoints.length - 1; j = i++) {
      final double vertILat = polygonPoints[i].latitude;
      final double vertILon = polygonPoints[i].longitude;
      final double vertJLat = polygonPoints[j].latitude;
      final double vertJLon = polygonPoints[j].longitude;

      // Check if the edge straddles the horizontal ray at the point's latitude.
      // This is the core of the algorithm.
      final bool crossesLatitude = (vertILat > pointLat) != (vertJLat > pointLat);

      if (crossesLatitude) {
        // If it crosses, we calculate the longitude of the intersection point.
        // This is derived from the line equation. Division by zero is impossible here
        // because `crossesLatitude` is only true if `vertILat` and `vertJLat` are different.
        final double intersectionLon = (vertJLon - vertILon) * (pointLat - vertILat) / (vertJLat - vertILat) + vertILon;

        // A valid crossing occurs if the intersection point is to the right of the tap point.
        if (pointLon < intersectionLon) {
          // Each crossing flips the state from inside to outside or vice versa.
          isInside = !isInside;
        }
      }
    }

    return isInside;
  }

  /// Triggers the AI analysis and displays the result in a bottom sheet.
  Future<void> _analyzeHazardsWithGemini(List<WeatherFeature> features) async {
    // Show a loading modal immediately
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.4,
          maxChildSize: 0.9,
          minChildSize: 0.2,
          builder: (BuildContext context, ScrollController scrollController) {
            return FutureBuilder<String>(
              future: _getAiSummary(features),
              builder: (context, snapshot) {
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1A2F).withOpacity(0.9),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey[700],
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Co-Pilot Analysis',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text(
                                "🤖 Co-Pilot is analyzing...",
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      if (snapshot.hasError)
                        Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                      if (snapshot.hasData)
                        Text(snapshot.data!, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<String> _getAiSummary(List<WeatherFeature> features) async {
    if (_model == null) {
      return "AI model not initialized. Please add your Gemini API key.";
    }

    // 1. Prepare the data for the AI
    final rawData = features.map((f) => f.rawProperties).toList();
    final jsonData = jsonEncode(rawData);

    // 2. Create the prompt
    final prompt = """
    You are a flight safety Co-Pilot. The user tapped a location with these weather hazards: $jsonData. Analyze the Severity, Cloud Tops/Bases, and give a tactical recommendation. Be concise.
    """;

    final content = [Content.text(prompt)];
    final response = await _model!.generateContent(content);
    return response.text ?? "Could not generate a summary.";
  }

  (int base, int top) _parseAltitudeRange(Map<String, dynamic> rawData) {
    String extractString(List<String> keys, String defaultValue) {
      for (final key in keys) {
        if (rawData.containsKey(key) && rawData[key] != null) {
          final v = rawData[key].toString().trim();
          if (v.isNotEmpty && v != "?" && v.toLowerCase() != "null") {
            return v;
          }
        }
      }
      return defaultValue;
    }

    // Base: base/base_ft. "SFC" or missing => 0.
    final baseStr = extractString(['base', 'base_ft', 'from', 'low'], 'SFC');
    // Top: top/top_ft. Missing/"MSL" => 60000.
    final topStr = extractString(['top', 'top_ft', 'to', 'high'], 'MSL');

    int parseAltString(String altStr, {required bool isTop}) {
      final s = altStr.trim().toUpperCase();

      // Base rules
      if (!isTop) {
        if (s == 'SFC' || s == 'GND') return 0;
      }

      // Top rules
      if (isTop) {
        if (s == 'MSL' || s == 'TOP' || s == 'UNL' || s == 'UNLIMITED') return 60000;
      }

      // Remove any non-numeric characters (e.g., "FL180", "18000FT")
      final numeric = RegExp(r'\d+').stringMatch(s);
      final intValue = numeric == null ? null : int.tryParse(numeric);

      if (intValue != null) {
        // Handle aviation shorthand like "030" => 3000, "180" => 18000
        if (intValue < 1000) return intValue * 100;
        return intValue;
      }

      return isTop ? 60000 : 0;
    }

    final base = parseAltString(baseStr, isTop: false);
    final top = parseAltString(topStr, isTop: true);

    return (base, top);
  }

  (Color fill, Color border) _getWeatherColor(String type) {
    switch (type.toLowerCase()) {
      case 'conv': case 'tcf': return (Colors.red.withAlpha(77), Colors.redAccent);
      case 'ice': return (Colors.blue.withAlpha(77), Colors.lightBlueAccent);
      case 'turb': case 'llws': return (Colors.orange.withAlpha(77), Colors.orangeAccent);
      case 'mtn obs': return (Colors.brown.withAlpha(77), Colors.brown);
      case 'ifr': return (Colors.purple.withAlpha(77), Colors.purpleAccent);
      case 'surf wind': return (Colors.teal.withAlpha(77), Colors.tealAccent);
      default: return (Colors.grey.withAlpha(77), Colors.white);
    }
  }

  Future<void> _fetchWeatherData(String type) async {
    // Define URIs based on type
    final uris = <Uri>[];
    switch (type.toLowerCase()) {
      case 'conv': uris.add(Uri.parse('https://aviationweather.gov/api/data/airsigmet?format=geojson&type=sigmet&hazard=conv')); break;
      case 'ice': uris.add(Uri.parse('https://aviationweather.gov/api/data/gairmet?format=geojson&hazard=ice')); break;
      case 'turb':
        uris.add(Uri.parse('https://aviationweather.gov/api/data/gairmet?product=tango&format=geojson&hazard=turb-lo&fore=3'));
        uris.add(Uri.parse('https://aviationweather.gov/api/data/gairmet?product=tango&format=geojson&hazard=turb-hi&fore=3'));
        break;
      case 'mtn obs': uris.add(Uri.parse('https://aviationweather.gov/api/data/gairmet?format=geojson&hazard=mtn_obs&fore=3')); break;
      case 'ifr': uris.add(Uri.parse('https://aviationweather.gov/api/data/gairmet?format=geojson&hazard=ifr&fore=3')); break;
      case 'llws': uris.add(Uri.parse('https://aviationweather.gov/api/data/gairmet?product=tango&format=geojson&hazard=llws&fore=3')); break;
      case 'surf wind': uris.add(Uri.parse('https://aviationweather.gov/api/data/gairmet?format=geojson&hazard=sfc-wind&fore=3')); break;
      case 'tcf': uris.add(Uri.parse('https://aviationweather.gov/api/data/tcf?format=geojson')); break;
      default: uris.add(Uri.parse('https://aviationweather.gov/api/data/airsigmet?format=geojson'));
    }

    final List<WeatherFeature> parsedFeatures = [];
    final colors = _getWeatherColor(type);

    for (final uri in uris) {
      try {
        final response = await http.get(uri);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final features = data is Map ? data['features'] : [];
          for (var feature in features) {
            if (feature['geometry'] != null) {
              _processGeometry(feature, parsedFeatures, colors.$1, colors.$2);
            }
          }
        } else {
          print("Failed to fetch $uri: ${response.statusCode}");
        }
      } catch (e) {
        print("Network/Parsing Error for $uri: $e");
      }
    }

    if (mounted) {
      setState(() => _activeLayers[type] = parsedFeatures);
    }
  }

  Future<void> _toggleWeatherLayer(String type) async {
    // 1) Terrain toggle
    if (type == "Terrain") {
      // Compute next state BEFORE setState so we can safely use it afterward.
      final bool enableTerrain = !_showTerrainAnalysis;

      setState(() {
        _showTerrainAnalysis = enableTerrain;

        // If terrain turned off, clear hazards immediately.
        if (!_showTerrainAnalysis) {
          _preflightHazards.clear();
        }
      });

      // Run analysis after UI updates.
      if (enableTerrain) {
        await _analyzeTerrainRisks();
      }
      return;
    }

    // 2) Weather layer toggle (optimistic UI update)
    bool shouldFetch = false;
    setState(() {
      if (_activeLayers.containsKey(type)) {
        // Turn OFF immediately
        _activeLayers.remove(type);
      } else {
        // Turn ON immediately (button colors update right away)
        _activeLayers[type] = [];
        shouldFetch = true;
      }
    });

    // Fetch in background (after state update)
    if (shouldFetch) {
      await _fetchWeatherData(type);
    }
  }

  void _processGeometry(Map<String, dynamic> feature, List<WeatherFeature> list, Color fill, Color border) {
    final geometry = feature['geometry'];
    if (geometry == null) return;

    final rawProps = feature['properties'] as Map<String, dynamic>? ?? {};
    final rawCoords = geometry['coordinates'];
    final rawType = geometry['type'].toString();

    // --- CONSOLE LOGGING ---
    String hazard = rawProps['hazard'] ?? rawProps['label'] ?? rawProps['type'] ?? 'Unknown';
    String top = "${rawProps['top'] ?? rawProps['top_ft'] ?? rawProps['to'] ?? '?'}";
    String base = "${rawProps['base'] ?? rawProps['base_ft'] ?? rawProps['from'] ?? 'SFC'}";

    // 1. Flatten coordinates to handle both Polygon and MultiPolygon
    List allPoints = [];
    if (rawType.toLowerCase() == 'polygon' && rawCoords is List && rawCoords.isNotEmpty) {
      allPoints = rawCoords[0]; // First ring
    } else if (rawType.toLowerCase() == 'multipolygon' && rawCoords is List) {
      for (var poly in rawCoords) {
        if (poly is List && poly.isNotEmpty) {
          allPoints.addAll(poly[0]); // Flatten all rings
        }
      }
    }

    // 2. Calculate Bounds
    double minLat = 90.0, maxLat = -90.0;
    double minLon = 180.0, maxLon = -180.0;

    if (allPoints.isNotEmpty) {
      for (var pt in allPoints) {
        if (pt is List && pt.length >= 2) {
          // GeoJSON is [Lon, Lat]
          double lon = (pt[0] as num).toDouble();
          double lat = (pt[1] as num).toDouble();

          minLat = min(minLat, lat);
          maxLat = max(maxLat, lat);
          minLon = min(minLon, lon);
          maxLon = max(maxLon, lon);
        }
      }
    }

    // 3. Log the "Area"
    print("☁️ [Loaded] $hazard");
    if (allPoints.isNotEmpty) {
      print(" 🗺️ Area Bounds: [${minLat.toStringAsFixed(2)}, ${minLon.toStringAsFixed(2)}] ⬌ [${maxLat.toStringAsFixed(2)}, ${maxLon.toStringAsFixed(2)}]");
    }
    print(" ↕️ Altitude: $base - $top");
    print("--------------------------------------------------");
    // --- END LOGGING ---

    final type = geometry['type'].toString().toLowerCase();
    if (type == 'polygon') {
      _parsePolygonCoordinates(geometry['coordinates'], list, fill, border, rawProps);
    } else if (type == 'multipolygon') {
      for (var polygonCoords in geometry['coordinates']) {
        _parsePolygonCoordinates(polygonCoords, list, fill, border, rawProps);
      }
    }
  }

  void _parsePolygonCoordinates(
      dynamic coordinates, List<WeatherFeature> list, Color fill, Color border, Map<String, dynamic> props) {
    if (coordinates is! List || coordinates.isEmpty) return;
    final outerRing = coordinates[0];
    if (outerRing is List) {
      final points = <LatLng>[];
      for (var point in outerRing) {
        if (point is List && point.length >= 2) {
          points.add(LatLng((point[1] as num).toDouble(), (point[0] as num).toDouble()));
        }
      }
      if (points.length >= 3) {
        if (points.first != points.last) points.add(points.first);
        final polygon = Polygon(
            points: points, color: fill, borderColor: border, borderStrokeWidth: 2.0);
        list.add(WeatherFeature(polygon: polygon, rawProperties: props));
      }
    }
  }

  Widget _buildHazardBtn(String type, Color color) {
    // Check for Terrain toggle specifically
    final bool isActive = type == "Terrain" ? _showTerrainAnalysis : _activeLayers.containsKey(type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleWeatherLayer(type),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 70,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.8) : color.withAlpha(51),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? Colors.white : color.withAlpha(128)),
          ),
          alignment: Alignment.center,
          child: Text(type,
              style: TextStyle(
                  color: color == Colors.yellow ? Colors.yellowAccent : color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  shadows: [
                    Shadow(blurRadius: 2, color: Colors.black.withAlpha(128), offset: const Offset(0, 1)),
                  ]),
              textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
//  COLLAPSIBLE ACTION FAB (New Implementation)
// --------------------------------------------------------------------------
class CollapsibleActionFab extends StatefulWidget {
  final VoidCallback onPressed;
  final bool autoCollapse;

  const CollapsibleActionFab({
    super.key,
    required this.onPressed,
    this.autoCollapse = true,
  });

  @override
  State<CollapsibleActionFab> createState() => _CollapsibleActionFabState();
}

class _CollapsibleActionFabState extends State<CollapsibleActionFab> {
  bool _isExpanded = false;
  Timer? _collapseTimer;

  void _onTap() {
    if (_isExpanded) {
      // Trigger Action
      widget.onPressed();
    } else {
      // Expand
      setState(() => _isExpanded = true);
      if (widget.autoCollapse) {
        _startAutoCollapse();
      }
    }
  }

  void _startAutoCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isExpanded) {
        setState(() => _isExpanded = false);
      }
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
        width: _isExpanded ? 220 : 64, // Increased width to fit text
        height: 56,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: _isExpanded ? Colors.greenAccent : Colors.white.withOpacity(0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _isExpanded ? Colors.greenAccent.withOpacity(0.2) : Colors.black.withOpacity(0.3),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start, // Keep content aligned left
              children: [
                // --- Icon ---
                // This container ensures the icon is always centered in its 56x56 space
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: Center(
                    child: Icon(
                      Icons.flight_takeoff,
                      color: Colors.greenAccent,
                      size: 24,
                    ),
                  ),
                ),
                // --- Text ---
                // The text is always in the tree but fades in/out
                Flexible(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isExpanded ? 1.0 : 0.0, // Animate opacity
                    curve: Curves.easeOut,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 16.0), // Padding for expanded text
                      child: Text(
                        "Enter In-Flight", // Updated Text
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.fade, // Use fade to prevent hard edges
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

class _GlassImportButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _GlassImportButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: const Icon(Icons.upload_file, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}
