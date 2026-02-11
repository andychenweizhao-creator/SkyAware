import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'; // Added for compute
import 'package:flutter/services.dart'; // Added for rootBundle
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:xml/xml.dart';
import 'package:geolocator/geolocator.dart'; 

import 'InFlightView.dart';
import 'Maps/maps.dart';
import 'WeatherFeature.dart';
import '../../services/terrain_service.dart';
import 'CollapsibleLayerMenu.dart';
import '../../services/ai_airport_service.dart';
import '../../UI/AppAnimations.dart';
import '../../UI/AirportDetailSheet.dart';
import '../../UI/AirportStatusPopup.dart'; 
import '../../services/airport_database_service.dart'; 
import '../../services/ai_grading_service.dart'; 
import '../../services/weather_service.dart'; 

enum AppMode { preflight, inFlight }

class HazardInfo {
  final LatLng point;
  final double terrainAlt;
  HazardInfo(this.point, this.terrainAlt);
}

class DashBoard extends StatefulWidget {
  final ValueChanged<bool>? onEmergencyStateChanged;

  const DashBoard({super.key, this.onEmergencyStateChanged});

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
  Position? _currentPosition; 

  // Terrain Analysis
  bool _showTerrainAnalysis = false;
  List<HazardInfo> _preflightHazards = [];
  final TerrainService _terrainService = TerrainService();

  // Local Airport Database & Grading
  bool _showAirports = false; 
  List<Marker> _airportMarkers = [];
  Timer? _mapDebounce; 
  StreamSubscription? _mapEventSubscription; 
  Timer? _weatherTimer; 

  // Gemini AI Model
  GenerativeModel? _model;
  final String _kGeminiApiKey = 'AIzaSyBqqjz5thRK3Lt6xQcivugnHReGkbgK9rY';

  @override
  void initState() {
    super.initState();
    // Initialize the Gemini Model
    if (_kGeminiApiKey.isNotEmpty && _kGeminiApiKey != 'YOUR_GEMINI_API_KEY') {
      try {
        _model = GenerativeModel(
          model: 'gemini-3-pro-preview', 
          apiKey: _kGeminiApiKey,
          safetySettings: [
            HarmCategory.harassment,
            HarmCategory.hateSpeech,
            HarmCategory.sexuallyExplicit,
            HarmCategory.dangerousContent,
          ].map((category) => SafetySetting(category, HarmBlockThreshold.none)).toList(),
        );
      } catch (e) {
        print("Gemini Init Error: $e");
      }
    }
    
    // Load Airport Database & Initial Update
    AirportDatabaseService().loadDatabase().then((_) {
      if (_showAirports) {
        _updateVisibleAirports();
      }
    });

    // Subscribe to Map Events
    _mapEventSubscription = _mapController.mapEventStream.listen((event) {
      if (event is MapEventMoveEnd) {
        _mapDebounce?.cancel();
        _mapDebounce = Timer(const Duration(milliseconds: 500), () {
          _updateVisibleAirports();
        });
      }
    });
    
    _initLocationService(); 
    _startWeatherTimer(); 
  }

  @override
  void dispose() {
    _mapEventSubscription?.cancel();
    _mapDebounce?.cancel();
    _weatherTimer?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    _altController.dispose();
    super.dispose();
  }

  void _startWeatherTimer() {
    _weatherTimer = Timer.periodic(const Duration(minutes: 20), (timer) {
      if (_showAirports) {
        _updateVisibleAirports();
      }
    });
  }

  // --- NEW: Location Service ---
  Future<void> _initLocationService() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    if (permission == LocationPermission.deniedForever) return; 

    // Listen to location updates
    Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 100)
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });
  }

  // --- NEW: Navigation Calculator ---
  Map<String, String> _calculateNavData(LatLng targetPoint) {
    LatLng startPoint;
    double speedKts = 0.0;

    if (_routePoints.isNotEmpty) {
      startPoint = _routePoints.last.point;
      // If measuring from last waypoint, assume planning speed
      speedKts = 120.0; 
    } else {
      // From current position
      if (_currentPosition == null) {
        return {"dist": "--", "hdg": "--", "ete": "--"};
      }
      startPoint = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      speedKts = _currentPosition!.speed * 1.94384; // m/s to knots
      // Constraint: If speed < 10 kts (stopped), assume a planning speed of 120 kts.
      if (speedKts < 10) speedKts = 120.0;
    }
    
    final Distance distanceCalc = const Distance();
    
    // Distance in Nautical Miles (1 NM = 1852 meters)
    final double distMeters = distanceCalc.as(LengthUnit.Meter, startPoint, targetPoint);
    final double distNm = distMeters / 1852.0;
    
    // Heading (Bearing)
    final double bearing = distanceCalc.bearing(startPoint, targetPoint);
    final double normalizedBearing = (bearing + 360) % 360;
    
    // ETE (Time) in minutes
    // Time (hours) = Distance (NM) / Speed (kts)
    final double timeHours = distNm / speedKts;
    final int timeMinutes = (timeHours * 60).round();
    
    return {
      "dist": "${distNm.toStringAsFixed(1)} NM",
      "hdg": "${normalizedBearing.toStringAsFixed(0)}°",
      "ete": "$timeMinutes min"
    };
  }

  // --- NEW: Route Management Methods ---
  
  void _addWaypoint(LatLng point, String id, String type) {
    setState(() {
      _routePoints.add(RoutePoint(
        id: id,
        point: point,
        type: type,
        name: id // Optional name
      ));
    });
  }

  void _setDestination(LatLng point, String id) {
    setState(() {
      // If route has points, remove the old destination (if exists) or append as new last point.
      // Assuming destination is always the last point if type is 'destination'
      if (_routePoints.isNotEmpty && _routePoints.last.type == 'destination') {
        _routePoints.removeLast();
      }
      
      _routePoints.add(RoutePoint(
        id: id, 
        point: point, 
        type: 'destination'
      ));
    });
  }

  void _removePoint(String id) {
    setState(() {
      _routePoints.removeWhere((p) => p.id == id);
    });
  }
  
  // --- NEW: EFB Logic (Insert, Direct To, Stats) ---

  int _findBestInsertionIndex(LatLng newPoint) {
    if (_routePoints.isEmpty) return 0;
    if (_routePoints.length == 1) return 1;

    final Distance distCalc = const Distance();
    double minIncrease = double.infinity;
    int bestIndex = _routePoints.length; // Default to end

    for (int i = 0; i < _routePoints.length - 1; i++) {
      final p1 = _routePoints[i].point;
      final p2 = _routePoints[i + 1].point;

      final double originalDist = distCalc.as(LengthUnit.Meter, p1, p2);
      final double newDist = distCalc.as(LengthUnit.Meter, p1, newPoint) + 
                             distCalc.as(LengthUnit.Meter, newPoint, p2);
      
      final double increase = newDist - originalDist;

      if (increase < minIncrease) {
        minIncrease = increase;
        bestIndex = i + 1;
      }
    }
    
    return bestIndex;
  }

  // ----------------------------------------------------------------------
  // NEW: Advanced Simulation Logic
  // ----------------------------------------------------------------------

  // 1. The Predictor
  double _simulateRouteDistance(List<RoutePoint> hypotheticalRoute) {
    if (hypotheticalRoute.isEmpty) return 0.0;

    final Distance distCalc = const Distance();
    double totalMeters = 0.0;
    LatLng previousPoint;

    // Start from current position if available, else first point
    if (_currentPosition != null) {
      previousPoint = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    } else {
      previousPoint = hypotheticalRoute.first.point;
    }

    for (final rp in hypotheticalRoute) {
      totalMeters += distCalc.as(LengthUnit.Meter, previousPoint, rp.point);
      previousPoint = rp.point;
    }

    return totalMeters / 1852.0; // Convert to NM
  }

  // 2. The Brain
  Map<String, double> _getAirportActionStats(Airport airport) {
    final latLng = LatLng(airport.lat, airport.lon);
    
    // Scenario A: Direct To
    // Route: [Current -> Airport]
    final routeA = [RoutePoint(id: airport.ident, point: latLng, type: 'waypoint')];
    final distA = _simulateRouteDistance(routeA);

    // Scenario B: Add as Stopover (Rubber-band)
    final index = _findBestInsertionIndex(latLng);
    final routeB = List<RoutePoint>.from(_routePoints);
    routeB.insert(index < routeB.length ? index : routeB.length, 
      RoutePoint(id: airport.ident, point: latLng, type: 'waypoint')
    );
    final distB = _simulateRouteDistance(routeB);

    // Scenario C: Set as Destination - Truncate
    final indexC = _findBestInsertionIndex(latLng);
    final routeC = List<RoutePoint>.from(_routePoints);
    
    if (indexC < routeC.length) {
      routeC.removeRange(indexC, routeC.length); // Remove everything after insertion
    }
    routeC.add(RoutePoint(id: airport.ident, point: latLng, type: 'destination'));
    final distC = _simulateRouteDistance(routeC);

    return {
      'direct': distA,
      'stopover': distB,
      'truncate': distC,
    };
  }

  // 3. Truncate Logic
  void _setDestinationTruncate(RoutePoint point) {
    setState(() {
      int index = _findBestInsertionIndex(point.point);
      
      // If index is valid, keep points 0 to index-1 (take(index))
      if (index < _routePoints.length) {
        _routePoints = _routePoints.take(index).toList();
      }
      
      // Force type
      final dest = RoutePoint(id: point.id, point: point.point, type: 'destination', name: point.name);
      _routePoints.add(dest);
    });
  }

  // ----------------------------------------------------------------------
  
  // NEW: Updated Execute Direct To Logic
  void _executeDirectTo(RoutePoint target) {
    List<RoutePoint> newRoute = [];
    
    // 1. Determine Start Point
    if (_currentMode == AppMode.inFlight && _currentPosition != null) {
      newRoute.add(RoutePoint(
        id: "ACTUAL", 
        point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 
        type: 'virtual',
        name: "ACTUAL POS"
      ));
    } else {
      if (_routePoints.isNotEmpty) {
        newRoute.add(_routePoints.first); // Origin
      }
    }

    // 2. Add Target
    newRoute.add(target);

    // 3. Append "Tail" (Points after the target)
    // Find where this target fits (or exists) in the old list
    int splitIndex = _routePoints.indexWhere((p) => p.id == target.id);
    
    // If it's a new point, simulate where it WOULD be (best insertion index)
    // The "Tail" are points that would come AFTER this new point.
    int tailStartIndex;
    if (splitIndex == -1) {
      tailStartIndex = _findBestInsertionIndex(target.point);
    } else {
      tailStartIndex = splitIndex + 1;
    }

    // Add everything remaining
    if (tailStartIndex < _routePoints.length) {
      newRoute.addAll(_routePoints.sublist(tailStartIndex));
    }

    setState(() {
      _routePoints = newRoute;
    });
  }

  Map<String, String> _simulateRouteStats(LatLng newPoint, bool isDirectTo) {
    final Distance distCalc = const Distance();
    double totalDistMeters = 0.0;
    
    if (isDirectTo) {
        // 1. Start Point
        LatLng startPos;
        if (_currentMode == AppMode.inFlight && _currentPosition != null) {
            startPos = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
        } else if (_routePoints.isNotEmpty) {
            startPos = _routePoints.first.point;
        } else {
            return {"total_dist": "0 NM", "leg_dist": "0 NM"};
        }
        
        // 2. Leg to Target
        double legDist = distCalc.as(LengthUnit.Meter, startPos, newPoint);
        totalDistMeters += legDist;
        
        // 3. Tail
        // Check if existing
        int existingIndex = _routePoints.indexWhere((p) => p.point == newPoint || p.id == "TEMP"); // Loose check
        
        int tailIndex;
        if (existingIndex != -1) {
            tailIndex = existingIndex + 1;
        } else {
            tailIndex = _findBestInsertionIndex(newPoint);
        }
        
        LatLng prev = newPoint;
        for (int i = tailIndex; i < _routePoints.length; i++) {
            totalDistMeters += distCalc.as(LengthUnit.Meter, prev, _routePoints[i].point);
            prev = _routePoints[i].point;
        }
        
        return {
            "total_dist": "${(totalDistMeters / 1852.0).toStringAsFixed(1)} NM",
            "leg_dist": "${(legDist / 1852.0).toStringAsFixed(1)} NM"
        };

    } else {
      // Scenario B: Insert
      // Route: [... -> p1 -> newPoint -> p2 -> ...]
      List<LatLng> tempPoints = _routePoints.map((r) => r.point).toList();
      int insertIndex = _findBestInsertionIndex(newPoint);
      if (insertIndex > tempPoints.length) insertIndex = tempPoints.length;
      tempPoints.insert(insertIndex, newPoint);
      
      // Calculate total
      for (int i = 0; i < tempPoints.length - 1; i++) {
        totalDistMeters += distCalc.as(LengthUnit.Meter, tempPoints[i], tempPoints[i+1]);
      }
      return {
        "total_dist": "${(totalDistMeters / 1852.0).toStringAsFixed(1)} NM",
        "leg_dist": "---" // Not purely leg based
      };
    }
  }

  void _executeRouteChange(RoutePoint newPoint, bool isDirectTo) {
    if (isDirectTo) {
      _executeDirectTo(newPoint);
    } else {
      setState(() {
        // Insert
        int index = _findBestInsertionIndex(newPoint.point);
        _routePoints.insert(index, newPoint);
      });
    }
  }

  // --- NEW: Route Options Modal ---

  void _showRouteOptions(BuildContext context, RoutePoint? routePoint, Airport? airport) {
    // Extract data from whichever object is provided
    final LatLng point = routePoint?.point ?? LatLng(airport!.lat, airport.lon);
    final String id = routePoint?.id ?? airport!.ident;
    final String? name = routePoint?.name ?? airport?.name;

    // 1. Calculate Nav Data
    final navData = _calculateNavData(point);
    
    // Check if point is already in route (Match by ID or Coordinates)
    bool isInRoute = _routePoints.any((rp) => rp.id == id); // Simple ID check
    
    // Get Stats for Insert Mode (Default)
    final insertStats = _simulateRouteStats(point, false);
    // Get Stats for Direct Mode
    final directStats = _simulateRouteStats(point, true);
    
    // If we have an airport, let's get the advanced comparison stats
    Map<String, double>? advStats;
    if (airport != null) {
      advStats = _getAirportActionStats(airport);
    }

    // Direct To Label
    String directLabel = _currentMode == AppMode.inFlight 
        ? "Direct To (From Here)" 
        : "Direct To (From Origin)";

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1A2F).withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.2))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Header
              Text(
                id,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              if (name != null)
                Text(
                  name,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 10),
              
              // 2. Stats Rows
               Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                     ListTile(
                       leading: const Icon(Icons.near_me, color: Colors.purpleAccent),
                       title: Text(directLabel, style: const TextStyle(color: Colors.white)),
                       subtitle: Text("Total: ${directStats['total_dist']} | Leg: ${directStats['leg_dist']} | ETE: ${navData['ete']}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                       dense: true,
                     ),
                     ListTile(
                       leading: const Icon(Icons.route, color: Colors.blueAccent),
                       title: const Text("Total Route (If Added)", style: TextStyle(color: Colors.white)),
                       subtitle: Text("Total: ${insertStats['total_dist']}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                       dense: true,
                     ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // 3. Logic Branching Buttons
              
              // Condition A: Always show Remove if in route (Imported or Manual)
              if (isInRoute) 
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withOpacity(0.2),
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.redAccent),
                    ),
                    onPressed: () {
                      _removePoint(id);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text("Remove from Route"),
                  ),
                ),
                
              const SizedBox(height: 12),
              
              // Condition B: Direct To (Show in BOTH modes now)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purpleAccent.withOpacity(0.2),
                    foregroundColor: Colors.purpleAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.purpleAccent),
                  ),
                  onPressed: () {
                    final rp = RoutePoint(id: id, point: point, type: 'waypoint', name: name);
                    _executeDirectTo(rp); 
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.near_me),
                  label: Text(directLabel),
                ),
              ),
                
              const SizedBox(height: 12),

              // Standard Options (Insert) - Always show if not in route
              if (!isInRoute) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent.withOpacity(0.2),
                      foregroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.blueAccent),
                    ),
                    onPressed: () {
                      final type = (airport != null) ? 'waypoint' : 'waypoint'; 
                      final newRp = RoutePoint(id: id, point: point, type: type, name: name);
                      
                      _executeRouteChange(newRp, false); // Insert
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.add_location_alt),
                    label: Text("Insert Waypoint (${advStats != null ? '${advStats['stopover']!.toStringAsFixed(0)} NM' : ''})"),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Set Destination
                // Show if NOT in route OR (InFlight mode AND custom point/new) to allow diverting
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent.withOpacity(0.2),
                      foregroundColor: Colors.greenAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.greenAccent),
                    ),
                    onPressed: () {
                        final newRp = RoutePoint(id: id, point: point, type: 'destination', name: name);
                        _setDestinationTruncate(newRp);
                        Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.flag),
                    label: Text("Set as Destination (${advStats != null ? '${advStats['truncate']!.toStringAsFixed(0)} NM' : ''})"),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // --- NEW: Explicit Airport Options Modal ---
  void _showAirportQuickView(BuildContext context, Airport airport) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AirportStatusPopup(
          airport: airport,
          onRoute: () {
            Navigator.pop(ctx);
            // Redirect to the existing Route Options logic
            _showRouteOptions(context, RoutePoint(id: airport.ident, point: LatLng(airport.lat, airport.lon), type: 'airport', name: airport.name), airport);
          },
          onAnalyze: () {
            Navigator.pop(ctx);
            _showDetailedAnalysis(context, airport);
          },
        );
      },
    );
  }

  void _showDetailedAnalysis(BuildContext context, Airport airport) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AirportDetailSheet(
        icao: airport.ident, 
        aiModel: _model
      ),
    );
  }
  
  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white38, size: 16),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }
  
  Widget _buildVerticalDivider() {
    return Container(width: 1, height: 30, color: Colors.white12);
  }

  // --- NEW: Airport Layer Logic ---

  Future<void> _updateVisibleAirports() async {
    if (!_showAirports) return;

    // 1. Get Visible Bounds
    final bounds = _mapController.camera.visibleBounds;
    
    // 2. Query Local Database
    final visibleAirports = AirportDatabaseService().getAirportsInBounds(bounds);
    
    // Limit to reasonable number for UI and AI (e.g. 20) to prevent clutter/cost
    final limitedAirports = visibleAirports.take(20).toList();

    // 3. Render Initial Markers with Type Colors
    if (mounted) {
      setState(() {
        _airportMarkers = limitedAirports.map((airport) => _buildAirportMarker(airport)).toList();
      });
    }

    // 4. Fetch Flight Categories
    final codes = limitedAirports.map((a) => a.ident).toList();
    if (codes.isNotEmpty) {
      try {
        final categories = await WeatherService.getFlightCategories(codes);
        
        // 5. Update Markers with Flight Category Colors
        if (mounted) {
          setState(() {
            _airportMarkers = limitedAirports.map((airport) {
              // Apply category if exists
              final category = categories[airport.ident];
              if (category != null) {
                airport.riskColor = _getCategoryColorHex(category);
                airport.riskReason = category;
              }
              return _buildAirportMarker(airport);
            }).toList();
          });
        }
      } catch (e) {
        print("Error fetching flight categories: $e");
      }
    }
  }

  String _getCategoryColorHex(String category) {
    switch (category.toUpperCase()) {
      case 'VFR': return '#10B981'; // Emerald Green
      case 'MVFR': return '#3B82F6'; // Royal Blue
      case 'IFR': return '#EF4444'; // Soft Red
      case 'LIFR': return '#D946EF'; // Magenta
      default: return '#808080'; // Gray
    }
  }

  Marker _buildAirportMarker(Airport airport) {
    Color markerColor = Colors.grey; // Default
    
    // Default Color Logic based on Type
    if (airport.type == 'large_airport') {
      markerColor = Colors.blue;
    } else if (airport.type == 'medium_airport') {
      markerColor = Colors.cyan;
    }

    // AI/Category Override
    if (airport.riskColor != null) {
      markerColor = _parseHexColor(airport.riskColor!);
    }

    return Marker(
      point: LatLng(airport.lat, airport.lon),
      width: 120, // Wide enough for label
      height: 80,
      child: GestureDetector(
        onTap: () {
          // --- NEW: Use Airport Quick View ---
          _showAirportQuickView(context, airport);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_airport, color: markerColor, size: 30),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black, // Opaque black for high contrast
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: markerColor, width: 1),
              ),
              child: Text(
                airport.ident, // Strict ICAO Display
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 11, 
                  fontWeight: FontWeight.w900, // Bold for readability
                  fontFamily: 'monospace' // Monospace for technical look
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
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

  // --- End Airport Layer Logic ---

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
            // NOTIFY NAVIGATION BAR (Show it)
            widget.onEmergencyStateChanged?.call(false);
          },
          routePoints: _routePoints,
          weatherPolygons: _displayedPolygons,
          mapController: _mapController,
          onEmergencyStateChanged: widget.onEmergencyStateChanged,
          initialPosition: _currentPosition, // Pass current position
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
                  airportMarkers: _airportMarkers, // Pass markers here
                  onMapTap: _handleMapTap,
                  // --- NEW: Handle Long Press for Route Options ---
                  onMapLongPress: (tapPos, point) {
                     String newId = "USR-${DateTime.now().second}"; 
                    _showRouteOptions(context, RoutePoint(id: newId, point: point, type: 'waypoint', name: newId), null);
                  },
                  // --- NEW: Handle Route Point Tap (Imported or Manual) ---
                  onRoutePointTap: (routePoint) {
                    _showRouteOptions(context, routePoint, null);
                  },
                  aiModel: _model, // Pass AI model here
                )),

            // Side Menu (Now includes Reset logic)
            CollapsibleLayerMenu(
              onToggleLayer: _toggleWeatherLayer,
              isLayerActive: (type) {
                if (type == "Terrain") return _showTerrainAnalysis;
                if (type == "Airports") return _showAirports;
                return _activeLayers.containsKey(type);
              },
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
                  _showAirports = false;
                  _airportMarkers = []; 
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
                  // NOTIFY NAVIGATION BAR (Hide it)
                  widget.onEmergencyStateChanged?.call(true);
                },
              ),
            ),
          ],
        );
    }
  }

  void _handleMapTap(LatLng tappedPoint) {
    // Logic handles tap on map
    // ... same as before
    final visibleFeatures = _getVisibleFeatures();
    final List<WeatherFeature> hitFeatures = [];

    for (final feature in visibleFeatures) {
      if (isPointInPolygon(tappedPoint, feature.polygon.points)) {
        hitFeatures.add(feature);
      }
    }

    if (hitFeatures.isNotEmpty) {
      _analyzeHazardsWithGemini(hitFeatures);
    }
  }

  /// Uses the robust Ray-Casting algorithm
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

  /// Triggers the AI analysis and displays the result in a bottom sheet.
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
      final bool enableTerrain = !_showTerrainAnalysis;
      setState(() {
        _showTerrainAnalysis = enableTerrain;
        if (!_showTerrainAnalysis) {
          _preflightHazards.clear();
        }
      });
      if (enableTerrain) {
        await _analyzeTerrainRisks();
      }
      return;
    }

    // 2) Airport Toggle (New)
    if (type == "Airports") {
      setState(() {
        _showAirports = !_showAirports;
        if (!_showAirports) _airportMarkers = [];
      });
      if (_showAirports) {
        await _updateVisibleAirports();
      }
      return;
    }

    // 3) Weather layer toggle
    bool shouldFetch = false;
    setState(() {
      if (_activeLayers.containsKey(type)) {
        _activeLayers.remove(type);
      } else {
        _activeLayers[type] = [];
        shouldFetch = true;
      }
    });

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
