import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:provider/provider.dart';
import 'package:skyaware/UI/theme_controller.dart';
import 'Maps/maps.dart';
import 'WeatherFeature.dart';
import '../../services/terrain_service.dart';
import 'CollapsibleLayerMenu.dart';
import '../../services/airport_database_service.dart'; // Local DB
import '../../services/ai_grading_service.dart'; // AI Grading
import '../../UI/AppAnimations.dart';
import '../../UI/AirportDetailSheet.dart';
import '../../services/ai_emergency_service.dart';
import '../../UI/EmergencyOverlay.dart';

class HazardInfo {
  final LatLng point;
  final double terrainAltFeet;
  final double planeAltFeet;
  HazardInfo(this.point, this.terrainAltFeet, this.planeAltFeet);
}

class InFlightView extends StatefulWidget {
  final VoidCallback onExit;
  final List<RoutePoint> routePoints;
  final List<Polygon> weatherPolygons;
  final MapController? mapController;
  final ValueChanged<bool>? onEmergencyStateChanged;

  const InFlightView({
    super.key,
    required this.onExit,
    this.routePoints = const [],
    this.weatherPolygons = const [],
    this.mapController,
    this.onEmergencyStateChanged,
  });

  @override
  State<InFlightView> createState() => _InFlightViewState();
}

class _InFlightViewState extends State<InFlightView> with SingleTickerProviderStateMixin {
  final Map<String, List<WeatherFeature>> _activeLayers = {};
  GenerativeModel? _model;
  final String _kGeminiApiKey = 'AIzaSyB_nwHRCKO9RgAgOXTPfeL5o_UbL3GW3X4'; // IMPORTANT: REPLACE WITH YOUR KEY
  
  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;
  double? _currentAltitudeFeet;
  bool _showFullData = false;

  final TextEditingController _altitudeController = TextEditingController();

  // Terrain Awareness
  final TerrainService _terrainService = TerrainService();
  bool _showTerrainAnalysis = false;
  List<HazardInfo> _activeHazards = [];
  DateTime? _lastTerrainCheck;
  AnimationController? _flashController;
  Timer? _mapDebounce;

  // Airport Layer State
  bool _showAirports = false;
  List<Marker> _airportMarkers = [];

  // EMERGENCY STATE
  bool _isEmergencyMode = false;
  Map<String, dynamic>? _emergencyData;
  List<LatLng> _emergencyRoute = [];

  @override
  void initState() {
    super.initState();
    if (_kGeminiApiKey.isNotEmpty && _kGeminiApiKey != 'YOUR_GEMINI_API_KEY') {
      try {
        _model = GenerativeModel(
          model: 'gemini-3-pro-preview',
          apiKey: _kGeminiApiKey,
        );
      } catch (e) {
        print("Gemini Init Error: $e");
      }
    }
    
    // Setup Flashing Animation
    _flashController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 500)
    )..repeat(reverse: true);

    _initLocationService();
  }

  @override
  void dispose() {
    // Ensure nav bar is restored if view is disposed while in emergency
    if (_isEmergencyMode) {
      widget.onEmergencyStateChanged?.call(false);
    }
    _positionStream?.cancel();
    _flashController?.dispose();
    _mapDebounce?.cancel();
    _altitudeController.dispose();
    super.dispose();
  }

  Future<void> _startEmergencyFlow() async {
    if (_model == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("AI Unavailable")));
      return;
    }

    String aircraftType = "Cessna 172S"; // Default
    String emergencyType = "Engine Failure"; // Default
    String customEmergencyText = "";

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String tempAircraft = aircraftType;
        String tempEmergency = emergencyType;
        bool isCustom = false;
        
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.red[900],
              title: const Text("DECLARE EMERGENCY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: "Aircraft Type",
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white, width: 2)),
                      ),
                      style: const TextStyle(color: Colors.white),
                      controller: TextEditingController(text: tempAircraft),
                      onChanged: (v) => tempAircraft = v,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: tempEmergency,
                      dropdownColor: Colors.red[800],
                      style: const TextStyle(color: Colors.white),
                      items: ["Engine Failure", "Electrical Fire", "Medical", "Lost Comms", "Fuel Critical", "Other / Custom"]
                          .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) {
                        setState(() {
                          tempEmergency = v!;
                          isCustom = v == "Other / Custom";
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: "Emergency Type",
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                      ),
                    ),
                    if (isCustom)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: "Specify Emergency",
                            labelStyle: TextStyle(color: Colors.white70),
                            hintText: "e.g. Bird Strike",
                            hintStyle: TextStyle(color: Colors.white30),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white, width: 2)),
                          ),
                          style: const TextStyle(color: Colors.white),
                          onChanged: (v) => customEmergencyText = v,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context), 
                  child: const Text("CANCEL", style: TextStyle(color: Colors.white70))
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red),
                  onPressed: () {
                    aircraftType = tempAircraft;
                    emergencyType = isCustom ? customEmergencyText : tempEmergency;
                    
                    if (emergencyType.trim().isEmpty) {
                      emergencyType = "Unknown Emergency";
                    }
                    
                    Navigator.pop(context);
                    _processEmergency(aircraftType, emergencyType);
                  },
                  child: const Text("DECLARE NOW", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _processEmergency(String acType, String emType) async {
    if (_currentPosition == null) return;

    try {
      final data = await AiEmergencyService.findBestEmergencyLanding(
        lat: _currentPosition!.latitude,
        lon: _currentPosition!.longitude,
        alt: _currentAltitudeFeet ?? 0,
        aircraftType: acType,
        emergencyType: emType,
        model: _model!,
      );

      final airport = data['recommended_airport'];
      if (airport != null) {
        final destLat = (airport['lat'] as num).toDouble();
        final destLon = (airport['lon'] as num).toDouble();
        
        // Parse route if available
        List<LatLng> routePoints = [];
        if (data.containsKey('route') && data['route'] is List) {
          for (var pt in data['route']) {
            if (pt['lat'] != null && pt['lon'] != null) {
              routePoints.add(LatLng((pt['lat'] as num).toDouble(), (pt['lon'] as num).toDouble()));
            }
          }
        }
        
        // Fallback to direct line if no route returned or less than 2 points
        if (routePoints.length < 2) {
             routePoints = [
                LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                LatLng(destLat, destLon)
             ];
        }

        setState(() {
          _isEmergencyMode = true;
          _emergencyData = data;
          _emergencyRoute = routePoints;
        });
        
        // Hide Nav Bar
        widget.onEmergencyStateChanged?.call(true);

        // Zoom map to show path
        widget.mapController?.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(_emergencyRoute),
            padding: const EdgeInsets.all(50),
          ),
        );
      }
    } catch (e) {
      debugPrint("Emergency Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to calculate emergency plan: $e")));
      }
    }
  }

  Color _parseHexColor(String hexString) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      return Colors.grey;
    }
  }

  // --- NEW AIRPORT LOGIC ---

  Future<void> _updateAirportLayer() async {
    if (!_showAirports) return;

    // 1. Get Visible Bounds
    final bounds = widget.mapController?.camera.visibleBounds;
    if (bounds == null) return;

    // 2. Query Local Database
    final visibleAirports = AirportDatabaseService().getAirportsInBounds(bounds);
    
    // Limit to reasonable number
    final limitedAirports = visibleAirports.take(20).toList();

    // 3. Render Initial Markers (Instant)
    if (mounted) {
      setState(() {
        _airportMarkers = limitedAirports.map((airport) => _buildAirportMarker(airport)).toList();
      });
    }

    // 4. Call AI Grading (Async)
    if (_model != null && limitedAirports.isNotEmpty) {
      try {
        final grades = await AiGradingService.gradeAirports(limitedAirports, _model!);
        
        if (mounted && _showAirports) {
          setState(() {
            _airportMarkers = limitedAirports.map((airport) {
              if (grades.containsKey(airport.ident)) {
                airport.riskColor = grades[airport.ident]!['color'];
                airport.riskReason = grades[airport.ident]!['reason'];
              }
              return _buildAirportMarker(airport);
            }).toList();
          });
        }
      } catch (e) {
        print("AI Grading Error: $e");
      }
    }
  }

  Marker _buildAirportMarker(Airport airport) {
    Color markerColor = Colors.grey;
    if (airport.type == 'large_airport') markerColor = Colors.blue;
    else if (airport.type == 'medium_airport') markerColor = Colors.cyan;
    
    if (airport.riskColor != null) {
      markerColor = _parseHexColor(airport.riskColor!);
    }

    return Marker(
      point: LatLng(airport.lat, airport.lon),
      width: 120,
      height: 80,
      child: GestureDetector(
        onTap: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (ctx) => AirportDetailSheet(
              icao: airport.ident,
              aiModel: _model,
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_airport, color: markerColor, size: 30),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: markerColor, width: 1),
              ),
              child: Text(
                airport.ident,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- END NEW AIRPORT LOGIC ---

  Future<void> _initLocationService() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return;
    } 

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        if (!mounted) return;
        
        setState(() {
          _currentPosition = position;
          _currentAltitudeFeet = position.altitude * 3.28084; // Convert meters to feet
          _altitudeController.text = _currentAltitudeFeet!.toStringAsFixed(0);
        });
        
        // Auto-center map on plane
        widget.mapController?.move(
          LatLng(position.latitude, position.longitude), 
          widget.mapController?.camera.zoom ?? 6.0
        );

        // Terrain Check (Throttle 5s)
        final now = DateTime.now();
        if (_lastTerrainCheck == null || now.difference(_lastTerrainCheck!).inSeconds >= 5) {
          _lastTerrainCheck = now;
          if (_currentAltitudeFeet != null && _showTerrainAnalysis) {
            final planePos = LatLng(position.latitude, position.longitude);
            _scanTerrainSurroundings(planePos, _currentAltitudeFeet!);
          }
        }
      },
      onError: (e) => print("GPS Stream Error: $e"),
    );
  }

  /// Calculates a destination point given start point, distance (meters), and bearing (degrees).
  LatLng _calculateDestinationPoint(LatLng start, double distanceMeters, double bearingDegrees) {
    const double radiusEarth = 6371000; // Earth radius in meters
    final double distRatio = distanceMeters / radiusEarth;
    final double bearingRad = degToRadian(bearingDegrees);
    final double startLatRad = degToRadian(start.latitude);
    final double startLonRad = degToRadian(start.longitude);

    final double destLatRad = asin(sin(startLatRad) * cos(distRatio) +
        cos(startLatRad) * sin(distRatio) * cos(bearingRad));

    final double destLonRad = startLonRad +
        atan2(sin(bearingRad) * sin(distRatio) * cos(startLatRad),
            cos(distRatio) - sin(startLatRad) * sin(destLatRad));

    return LatLng(radianToDeg(destLatRad), radianToDeg(destLonRad));
  }

  Future<void> _scanTerrainSurroundings(LatLng planePos, double planeAltFeet) async {
    final List<LatLng> probePoints = [planePos]; // Always check current pos
    
    // Step 1: Get Current Zoom Level
    final double currentZoom = widget.mapController?.camera.zoom ?? 6.0;

    // Step 2: Define Dynamic Sampling Strategy
    List<double> distances;
    int angleStep;

    if (currentZoom > 13.0) {
      // High Zoom (> 13.0, Close view): Max detail.
      distances = [5000, 15000, 30000, 50000]; // Meters
      angleStep = 45; // 8 directions
    } else if (currentZoom >= 10.0) {
      // Medium Zoom (10.0 - 13.0): Balanced.
      distances = [20000, 50000];
      angleStep = 60; // 6 directions
    } else {
      // Low Zoom (< 10.0, Wide view): Minimal detail.
      distances = [50000];
      angleStep = 90; // 4 cardinal directions
    }

    // Step 3: Generate Probe Points
    for (final dist in distances) {
      for (int bearing = 0; bearing < 360; bearing += angleStep) {
        probePoints.add(_calculateDestinationPoint(planePos, dist, bearing.toDouble()));
      }
    }

    // Parallel Execution
    final List<Future<double?>> futures = probePoints
        .map((p) => _terrainService.getElevationFeet(p.latitude, p.longitude))
        .toList();

    final List<double?> elevations = await Future.wait(futures);
    final List<HazardInfo> detectedHazards = [];

    for (int i = 0; i < elevations.length; i++) {
      final elevation = elevations[i];
      if (elevation != null) {
        final clearance = planeAltFeet - elevation;
        if (clearance < 500) {
          detectedHazards.add(HazardInfo(probePoints[i], elevation, planeAltFeet));
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _activeHazards = detectedHazards;
    });
  }

  // Getter flattens the map of features into a single list of polygons for rendering.
  // Now uses _getVisibleFeatures instead of direct access
  List<Polygon> get _allPolygons =>
      _getVisibleFeatures().map((f) => f.polygon).toList();

  List<WeatherFeature> _getVisibleFeatures() {
    // Flatten all features from all active layers into a single list.
    final allFeatures = _activeLayers.values.expand((features) => features).toList();

    // Condition A: Show all data if override is on.
    if (_showFullData) {
      return allFeatures;
    }

    // If no GPS fix yet, behave as if "Full Data" is ON (or show all).
    if (_currentPosition == null || _currentAltitudeFeet == null) {
      return allFeatures;
    }

    // Condition B & C: Filter based on Altitude AND Distance.
    final altitude = _currentAltitudeFeet!;
    final aircraftLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    const distanceCalc = Distance();
    
    final List<WeatherFeature> filteredFeatures = [];

    for (final feature in allFeatures) {
      // 1. Altitude Check
      final (base, top) = _parseAltitudeRange(feature.rawProperties);
      if (altitude < base || altitude > top) {
        continue; // Skip if altitude mismatch
      }
      
      // 2. Distance Check (50km)
      // Check if inside polygon
      if (isPointInPolygon(aircraftLatLng, feature.polygon.points)) {
          filteredFeatures.add(feature);
          continue;
      }
      
      // Check distance to any vertex
      bool isWithinRange = false;
      for (final point in feature.polygon.points) {
          if (distanceCalc.as(LengthUnit.Meter, aircraftLatLng, point) <= 50000) { // 50km
              isWithinRange = true;
              break;
          }
      }
      
      if (isWithinRange) {
          filteredFeatures.add(feature);
      }
    }

    return filteredFeatures;
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

  Future<void> _fetchWeatherData(String type) async {
    // Define URIs based on type
    final uris = <Uri>[];
    switch (type.toLowerCase()) {
       case 'conv': uris.add(Uri.parse('https://aviationweather.gov/api/data/airsigmet?format=geojson&types=sigmet&hazard=conv')); break;
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
    if (type == "Terrain") {
      setState(() {
        _showTerrainAnalysis = !_showTerrainAnalysis;
        
        if (!_showTerrainAnalysis) {
          _activeHazards = [];
        } else if (_currentPosition != null && _currentAltitudeFeet != null) {
          final planePos = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
          _scanTerrainSurroundings(planePos, _currentAltitudeFeet!);
        }
      });
      return;
    }
    
    // NEW: Airport Toggle
    if (type == "Airports") {
      setState(() {
        _showAirports = !_showAirports;
        if (!_showAirports) _airportMarkers = [];
      });
      if (_showAirports) {
        _updateAirportLayer();
      }
      return;
    }

    if (_activeLayers.containsKey(type)) {
      setState(() {
        _activeLayers.remove(type);
      });
      return;
    }

    // Adding layer
    setState(() {
       _activeLayers[type] = []; // Optimistic
    });
    
    await _fetchWeatherData(type);
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

  bool isPointInPolygon(LatLng point, List<LatLng> polygonPoints) {
    bool isInside = false;
    final double pointLat = point.latitude;
    final double pointLon = point.longitude;

    for (int i = 0, j = polygonPoints.length - 2; i < polygonPoints.length - 1; j = i++) {
      final double vertILat = polygonPoints[i].latitude;
      final double vertILon = polygonPoints[i].longitude;
      final double vertJLat = polygonPoints[j].latitude;
      final double vertJLon = polygonPoints[j].longitude;

      final bool crossesLatitude = (vertILat > pointLat) != (vertJLat > pointLat);

      if (crossesLatitude) {
        final double intersectionLon = (vertJLon - vertILon) * (pointLat - vertILat) / (vertJLat - vertILat) + vertILon;
        if (pointLon < intersectionLon) {
          isInside = !isInside;
        }
      }
    }

    return isInside;
  }

  Future<void> _analyzeHazardsWithGemini(List<WeatherFeature> features) async {
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

    final rawData = features.map((f) => f.rawProperties).toList();
    final jsonData = jsonEncode(rawData);

    final prompt = """
    You are a flight safety Co-Pilot. The user tapped a location with these weather hazards: $jsonData. Analyze the Severity, Cloud Tops/Bases, and give a tactical recommendation. Be concise.
    """;

    final content = [Content.text(prompt)];
    final response = await _model!.generateContent(content);
    return response.text ?? "Could not generate a summary.";
  }
  
  // NEW HELPERS FOR MODERN UI
  Widget _buildBackButton() {
    return GestureDetector(
      onTap: widget.onExit,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill() {
    // IF EMERGENCY IS ACTIVE, SHOW RED STATUS
    if (_isEmergencyMode) {
      return AnimatedBuilder(
        animation: _flashController!,
        builder: (context, child) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Color.lerp(Colors.red[900], Colors.red, _flashController!.value),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white),
                boxShadow: const [BoxShadow(color: Colors.red, blurRadius: 15)],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text("EMERGENCY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          );
        }
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.green, blurRadius: 4)],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "In-Flight",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAltitudeHUD() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                "ALTITUDE",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _currentAltitudeFeet != null
                        ? _currentAltitudeFeet!.toStringAsFixed(0)
                        : "---",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    "ft",
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // ADDED: Zoom Controls
  Widget _buildZoomControls() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildZoomBtn(Icons.add, () {
                 widget.mapController?.move(
                    widget.mapController!.camera.center,
                    widget.mapController!.camera.zoom + 1);
              }),
              Container(
                width: 40,
                height: 1,
                color: Colors.white.withOpacity(0.2),
              ),
              _buildZoomBtn(Icons.remove, () {
                widget.mapController?.move(
                    widget.mapController!.camera.center,
                    widget.mapController!.camera.zoom - 1);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoomBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  List<Marker> _buildRouteMarkers() {
    if (widget.routePoints.isEmpty) return [];

    return widget.routePoints.asMap().entries.map((entry) {
      final index = entry.key;
      final rp = entry.value;
      final isAirport = index == 0 || index == widget.routePoints.length - 1;

      return Marker(
        point: rp.point,
        width: 100,
        height: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isAirport ? Icons.local_airport : Icons.circle,
              size: isAirport ? 24 : 8,
              color: isAirport ? Colors.cyanAccent : Colors.grey,
            ),
            const SizedBox(height: 2),
            Text(
              rp.id,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(blurRadius: 2, color: Colors.black)],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final isDark = themeController.isDarkMode;

    final String tileUrl = isDark 
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
        : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF0F2F5),
      body: Stack(
        children: [
          FlutterMap(
            mapController: widget.mapController,
            options: MapOptions(
              initialCenter: const LatLng(38.0, -98.0), // Center of US
              initialZoom: 6.0,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
              onTap: (_, point) => _handleMapTap(point),
              onPositionChanged: (position, hasGesture) {
                if (hasGesture) {
                  _mapDebounce?.cancel();
                  _mapDebounce = Timer(const Duration(milliseconds: 500), () {
                    if (!mounted) return;
                    
                    // Terrain Check
                    if (_currentPosition != null && _currentAltitudeFeet != null && _showTerrainAnalysis) {
                      final planePos = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
                      _scanTerrainSurroundings(planePos, _currentAltitudeFeet!);
                    }
                    
                    // NEW: Airport Check
                    if (_showAirports) {
                      _updateAirportLayer();
                    }
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.andy.skyaware',
              ),
               // Draw the weather polygons
              PolygonLayer(
                polygons: _allPolygons, // Using local active layers
              ),

              // Draw the flight route on top of the weather
              if (widget.routePoints.isNotEmpty)
                PolylineLayer<Object>(
                  polylines: [
                    Polyline<Object>(
                      points: widget.routePoints.map((rp) => rp.point).toList(),
                      strokeWidth: 4.0,
                      color: Colors.blueAccent, // High-visibility color
                      borderColor: Colors.black.withOpacity(0.5),
                      borderStrokeWidth: 1.0,
                    ),
                  ],
                ),
              
              // NEW: EMERGENCY ROUTE LAYER (RED)
              if (_isEmergencyMode && _emergencyRoute.isNotEmpty)
                PolylineLayer<Object>(
                  polylines: [
                    Polyline<Object>(
                      points: _emergencyRoute,
                      strokeWidth: 6.0,
                      color: Colors.redAccent,
                      borderColor: Colors.black,
                      borderStrokeWidth: 2.0,
                      pattern: const StrokePattern.dotted(),
                    ),
                  ],
                ),
                
              if (widget.routePoints.isNotEmpty)
                MarkerLayer(markers: _buildRouteMarkers()),

              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      width: 40,
                      height: 40,
                      child: Transform.rotate(
                        angle: (_currentPosition!.heading) * (pi / 180), // Convert to radians
                        child: const Icon(
                          Icons.airplanemode_active,
                          color: Colors.greenAccent,
                          size: 30,
                        ),
                      ),
                    ),
                  ],
                ),
                
              // Terrain Hazard Marker Layer (Interactive)
              if (_showTerrainAnalysis)
                MarkerLayer(
                  markers: _activeHazards.map((hazard) => Marker(
                    point: hazard.point,
                    width: 60,
                    height: 80,
                    child: GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text("⚠️ TERRAIN ALERT", style: TextStyle(color: Colors.red)),
                            backgroundColor: Colors.grey[900],
                            titleTextStyle: const TextStyle(color: Colors.red, fontSize: 20, fontWeight: FontWeight.bold),
                            contentTextStyle: const TextStyle(color: Colors.white70),
                            content: Text(
                              "Your Altitude: ${hazard.planeAltFeet.toStringAsFixed(0)} ft\n\n"
                              "Terrain Height: ${hazard.terrainAltFeet.toStringAsFixed(0)} ft\n\n"
                              "Clearance: ${(hazard.planeAltFeet - hazard.terrainAltFeet).toStringAsFixed(0)} ft (TOO LOW)"
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CLOSE"))
                            ],
                          ),
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red.withOpacity(0.3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.redAccent.withOpacity(0.6),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                )
                              ],
                            ),
                            child: const Icon(Icons.terrain, color: Colors.red, size: 30),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            "OBSTACLE",
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )).toList(),
                ),

              // AI Airport Markers Layer
              if (_airportMarkers.isNotEmpty)
                MarkerLayer(markers: _airportMarkers),
            ],
          ),
          // Vignette for cockpit feel
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
                  radius: 1.0,
                  center: Alignment.center,
                  stops: const [0.6, 1.0],
                ),
              ),
            ),
          ),
          
          // --- NEW MODERN HUD LAYOUT ---
          
          // 1. Top-Left Back Button (OR MAYDAY BUTTON)
          if (!_isEmergencyMode)
            Positioned(
              top: 60, 
              left: 16,
              child: _buildBackButton(),
            ),
          
          // NEW: MAYDAY BUTTON (Next to back button)
          if (!_isEmergencyMode)
            Positioned(
              top: 60,
              left: 70, // Offset from back button
              child: GestureDetector(
                onTap: _startEmergencyFlow,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(color: Colors.red.withOpacity(0.6), blurRadius: 10, spreadRadius: 2)
                    ],
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Text("MAYDAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                ),
              ),
            ),

          // 2. Top-Center Status
          Positioned(
            top: 60, 
            left: 0, 
            right: 0,
            child: Center(child: _buildStatusPill()),
          ),

          // 3. Top-Right Altitude HUD
          Positioned(
            top: 60, 
            right: 16,
            child: _buildAltitudeHUD(),
          ),

          // 4. Side Menu (Moved down to clear HUD)
          if (!_isEmergencyMode)
            CollapsibleLayerMenu(
              onToggleLayer: _toggleWeatherLayer,
              isLayerActive: (type) => (type == "Terrain" ? _showTerrainAnalysis : (type == "Airports" ? _showAirports : _activeLayers.containsKey(type))),
              showFullData: _showFullData,
              onToggleFullData: (val) => setState(() => _showFullData = val),
              topPosition: 160.0,
              altitudeController: _altitudeController,
              altitude: _currentAltitudeFeet?.toInt(),
              onAltitudeChanged: (val) {
                // No-op for InFlightView as it is GPS driven
              },
              onReset: () {
                setState(() {
                  _activeLayers.clear();
                  _showTerrainAnalysis = false;
                  _activeHazards = [];
                  _showFullData = false;
                  _showAirports = false;
                  _airportMarkers = []; 
                  _isEmergencyMode = false; // Reset emergency
                  _emergencyData = null;
                  _emergencyRoute = [];
                });
                widget.onEmergencyStateChanged?.call(false); // Reset nav bar
              },
            ),
          
          // 5. Zoom Controls (Bottom Right)
          if (!_isEmergencyMode)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).size.height / 2 - 60,
              child: _buildZoomControls(),
            ),
          
          // 6. EMERGENCY OVERLAY (Highest z-index)
          if (_isEmergencyMode && _emergencyData != null)
            Positioned(
              left: 0, 
              right: 0, 
              top: 0, 
              bottom: 0,
              child: EmergencyOverlay(
                data: _emergencyData!,
                onClose: () {
                  setState(() {
                    _isEmergencyMode = false;
                    _emergencyData = null;
                    _emergencyRoute = [];
                  });
                  // Restore Nav Bar
                  widget.onEmergencyStateChanged?.call(false);
                },
              ),
            ),
        ],
      ),
    );
  }
}
