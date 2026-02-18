import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' hide Path; // HIDE Path to avoid conflict with dart:ui.Path
import 'package:geolocator/geolocator.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:provider/provider.dart';
import 'package:skyaware/UI/theme_controller.dart';
import 'Maps/maps.dart';
import 'WeatherFeature.dart';
import '../../services/terrain_service.dart';
import 'CollapsibleLayerMenu.dart';
import '../../services/airport_database_service.dart'; // Local DB

import '../../UI/AppAnimations.dart';
import '../../UI/AirportDetailSheet.dart';
import '../../UI/AirportStatusPopup.dart'; // NEW: Reusable Popup
import '../../services/ai_emergency_service.dart';
import '../../UI/EmergencyOverlay.dart';
import '../../services/weather_service.dart'; // Ensure WeatherService is imported
import '../../main.dart'; // Import for AviationColors

class HazardInfo {
  final LatLng point;
  final double terrainAltFeet;
  final double planeAltFeet;
  HazardInfo(this.point, this.terrainAltFeet, this.planeAltFeet);
}

// --- Leg Data Class ---
class LegData {
  final LatLng start;
  final LatLng end;
  final double bearing;
  final double distanceNm;
  final LatLng midPoint;
  final String endWptId;

  LegData({
    required this.start, 
    required this.end, 
    required this.bearing, 
    required this.distanceNm, 
    required this.midPoint, 
    required this.endWptId
  });
}

class InFlightView extends StatefulWidget {
  final VoidCallback onExit;
  final List<RoutePoint> routePoints;
  final List<Polygon> weatherPolygons;
  final MapController? mapController;
  final ValueChanged<bool>? onEmergencyStateChanged;
  final Position? initialPosition;

  const InFlightView({
    super.key,
    required this.onExit,
    this.routePoints = const [],
    this.weatherPolygons = const [],
    this.mapController,
    this.onEmergencyStateChanged,
    this.initialPosition,
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
  
  // Follow Mode State
  bool _isFollowing = true; 

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
  Timer? _weatherTimer; // Background timer for flight category refresh

  // EMERGENCY STATE
  bool _isEmergencyMode = false;
  Map<String, dynamic>? _emergencyData;
  List<LatLng> _emergencyRoute = [];
  
  // Local Mutable Route (so we can edit it in-flight)
  late List<RoutePoint> _activeRoutePoints;

  @override
  void initState() {
    super.initState();
    _activeRoutePoints = List.from(widget.routePoints); // Clone initial route

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

    // Initialize position from parent if available
    if (widget.initialPosition != null) {
      _currentPosition = widget.initialPosition;
      _currentAltitudeFeet = widget.initialPosition!.altitude * 3.28084;
      _altitudeController.text = _currentAltitudeFeet!.toStringAsFixed(0);
    }

    _initLocationService();
    _startWeatherTimer(); // Start background refresh
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
    _weatherTimer?.cancel();
    _altitudeController.dispose();
    super.dispose();
  }

  void _startWeatherTimer() {
    // Refresh flight categories every 20 minutes to prevent stale data
    _weatherTimer = Timer.periodic(const Duration(minutes: 20), (timer) {
      if (_showAirports) {
        _updateAirportLayer();
      }
    });
  }
  
  // --- Helper: Route Math ---
  List<LegData> _calculateLegStats() {
    if (_activeRoutePoints.isEmpty) return [];
    
    final List<LegData> legs = [];
    final Distance distCalc = const Distance();
    
    // Leg 0: Plane -> First Waypoint (Active Leg)
    if (_currentPosition != null) {
      final p1 = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      final p2 = _activeRoutePoints.first.point;
      
      // Only add if not extremely close to prevent flicker
      if (distCalc.as(LengthUnit.Meter, p1, p2) > 100) {
        final double distM = distCalc.as(LengthUnit.Meter, p1, p2);
        final double bearing = distCalc.bearing(p1, p2);
        final mid = LatLng((p1.latitude + p2.latitude)/2, (p1.longitude + p2.longitude)/2);
        
        legs.add(LegData(
          start: p1, 
          end: p2, 
          bearing: (bearing + 360) % 360, 
          distanceNm: distM / 1852.0, 
          midPoint: mid,
          endWptId: _activeRoutePoints.first.name ?? _activeRoutePoints.first.id
        ));
      }
    }
    
    // Subsequent Legs
    for (int i = 0; i < _activeRoutePoints.length - 1; i++) {
      final p1 = _activeRoutePoints[i].point;
      final p2 = _activeRoutePoints[i+1].point;
      
      final double distM = distCalc.as(LengthUnit.Meter, p1, p2);
      final double bearing = distCalc.bearing(p1, p2);
      final mid = LatLng((p1.latitude + p2.latitude)/2, (p1.longitude + p2.longitude)/2);
      
      legs.add(LegData(
        start: p1, 
        end: p2, 
        bearing: (bearing + 360) % 360, 
        distanceNm: distM / 1852.0, 
        midPoint: mid,
        endWptId: _activeRoutePoints[i+1].name ?? _activeRoutePoints[i+1].id
      ));
    }
    
    return legs;
  }

  // --- UI: Aircraft Marker ---
  Marker _buildAircraftMarker() {
    if (_currentPosition == null) return Marker(point: const LatLng(0,0), child: const SizedBox());
    
    return Marker(
      point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      width: 40,
      height: 40,
      child: Transform.rotate(
        angle: (_currentPosition!.heading) * (pi / 180),
        child: CustomPaint(
          painter: NavigraphArrowPainter(),
        ),
      ),
    );
  }

  // --- Route Logic Helpers ---
  Map<String, double> _getAirportActionStats(Airport airport) {
    final latLng = LatLng(airport.lat, airport.lon);
    final stats = _simulateCompareStats(RoutePoint(id: airport.ident, point: latLng, type: 'airport'));
    return {
        'direct': stats['direct_total'] ?? 0.0,
        'stopover': stats['insert_total'] ?? 0.0,
        'divert': stats['truncate_total'] ?? 0.0
    };
  }
  
  int _findBestInsertionIndex(LatLng newPoint) {
    if (_activeRoutePoints.isEmpty) return 0;
    
    final Distance distCalc = const Distance();
    double minIncrease = double.infinity;
    int bestIndex = _activeRoutePoints.length; 

    for (int i = 0; i < _activeRoutePoints.length - 1; i++) {
      final p1 = _activeRoutePoints[i].point;
      final p2 = _activeRoutePoints[i + 1].point;

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

  Map<String, double> _simulateCompareStats(RoutePoint target) {
    final Distance distCalc = const Distance();
    
    LatLng startPos;
    if (_currentPosition != null) {
      startPos = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    } else if (_activeRoutePoints.isNotEmpty) {
      startPos = _activeRoutePoints.first.point;
    } else {
      return {'insert_total': 0.0, 'direct_total': 0.0, 'truncate_total': 0.0};
    }

    double calcDist(List<RoutePoint> points) {
        double total = 0.0;
        LatLng prev = startPos;
        for (var p in points) {
            total += distCalc.as(LengthUnit.Meter, prev, p.point);
            prev = p.point;
        }
        return total / 1852.0;
    }

    List<RoutePoint> insertRoute = List.from(_activeRoutePoints);
    double insertTotal = double.infinity;
    if (insertRoute.isEmpty) {
        insertTotal = distCalc.as(LengthUnit.Meter, startPos, target.point) / 1852.0;
    } else {
         for (int i = 0; i <= insertRoute.length; i++) {
             List<RoutePoint> temp = List.from(insertRoute);
             temp.insert(i, target);
             double d = calcDist(temp);
             if (d < insertTotal) insertTotal = d;
         }
    }

    List<RoutePoint> directRoute = [];
    directRoute.add(target);
    
    int splitIndex = _activeRoutePoints.indexWhere((p) => p.id == target.id);
    int tailStartIndex = (splitIndex == -1) ? _findBestInsertionIndex(target.point) : splitIndex + 1;
    
    if (tailStartIndex < _activeRoutePoints.length) {
        directRoute.addAll(_activeRoutePoints.sublist(tailStartIndex));
    }
    double directTotal = calcDist(directRoute);

    List<RoutePoint> truncateRoute = List.from(_activeRoutePoints);
    int truncIndex = _findBestInsertionIndex(target.point);
    if (truncIndex < truncateRoute.length) {
        truncateRoute = truncateRoute.take(truncIndex).toList();
    }
    truncateRoute.add(target);
    double truncateTotal = calcDist(truncateRoute);

    return {
      'insert_total': insertTotal,
      'direct_total': directTotal,
      'truncate_total': truncateTotal,
    };
  }
  
  void _executeDirectTo(RoutePoint target) {
    List<RoutePoint> newRoute = [];
    if (_currentPosition != null) {
      newRoute.add(RoutePoint(
        id: "ACTUAL", 
        point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 
        type: 'virtual',
        name: "ACTUAL POS"
      ));
    }
    newRoute.add(target);
    int splitIndex = _activeRoutePoints.indexWhere((p) => p.id == target.id);
    int tailStartIndex = (splitIndex == -1) ? _findBestInsertionIndex(target.point) : splitIndex + 1;
    if (tailStartIndex < _activeRoutePoints.length) {
      newRoute.addAll(_activeRoutePoints.sublist(tailStartIndex));
    }
    setState(() {
      _activeRoutePoints = newRoute;
    });
  }

  void _setDestinationTruncate(RoutePoint point) {
    setState(() {
      int index = _findBestInsertionIndex(point.point);
      if (index < _activeRoutePoints.length) {
        _activeRoutePoints = _activeRoutePoints.take(index).toList();
      }
      _activeRoutePoints.add(RoutePoint(id: point.id, point: point.point, type: 'destination', name: point.name));
    });
  }

  void _addStopover(Airport airport) {
    setState(() {
      final latLng = LatLng(airport.lat, airport.lon);
      int index = _findBestInsertionIndex(latLng);
      if (index > _activeRoutePoints.length) index = _activeRoutePoints.length;
      _activeRoutePoints.insert(index, RoutePoint(id: airport.ident, point: latLng, type: 'waypoint', name: airport.name));
    });
  }

  void _insertWaypoint(RoutePoint target) {
      setState(() {
        int index = _findBestInsertionIndex(target.point);
        if (index > _activeRoutePoints.length) index = _activeRoutePoints.length;
        _activeRoutePoints.insert(index, target);
      });
  }

  void _removePoint(String id) {
    setState(() {
      _activeRoutePoints.removeWhere((p) => p.id == id);
    });
  }
  
  void _checkWaypointArrival(LatLng currentPos) {
    if (_activeRoutePoints.isEmpty) return;

    final target = _activeRoutePoints.first;
    final dist = const Distance().as(LengthUnit.Meter, currentPos, target.point);

    // Threshold: 1 NM approx 1852 meters. User said 1.0 NM or 2000 meters.
    if (dist < 2000) {
      setState(() {
        final reachedPoint = _activeRoutePoints.removeAt(0);
        
        String nextLabel = "Destination";
        if (_activeRoutePoints.isNotEmpty) {
          nextLabel = _activeRoutePoints.first.name ?? _activeRoutePoints.first.id;
        } else {
          nextLabel = "End of Route";
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Arrived at ${reachedPoint.name ?? reachedPoint.id}. Next: $nextLabel"),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green[900],
          )
        );
      });
    }
  }
  
  void _showRouteOptions(BuildContext context, RoutePoint routePoint) {
    bool isInRoute = _activeRoutePoints.any((rp) => rp.id == routePoint.id);
    final stats = _simulateCompareStats(routePoint);

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
              Text(
                routePoint.name ?? routePoint.id,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const Divider(color: Colors.white24, height: 32),
              
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
                      _removePoint(routePoint.id);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text("Remove from Route"),
                  ),
                ),
              
              const SizedBox(height: 12),
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
                      _executeDirectTo(routePoint);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.near_me),
                    label: Column(
                      children: [
                        const Text("Direct To (From Here)", style: TextStyle(fontWeight: FontWeight.bold)),
                        Text("Total: ${stats['direct_total']!.toStringAsFixed(1)} NM", style: const TextStyle(fontSize: 10, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),

              if (!isInRoute) ...[
                 const SizedBox(height: 12),
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
                      _insertWaypoint(routePoint);
                      Navigator.pop(ctx);
                    },
                     icon: const Icon(Icons.add_location_alt),
                     label: Column(
                        children: [
                          const Text("Insert Waypoint", style: TextStyle(fontWeight: FontWeight.bold)),
                          Text("Total: ${stats['insert_total']!.toStringAsFixed(1)} NM", style: const TextStyle(fontSize: 10, color: Colors.white70)),
                        ],
                      ),
                  ),
                ),
                
                const SizedBox(height: 12),
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
                      _setDestinationTruncate(routePoint);
                      Navigator.pop(ctx);
                    },
                     icon: const Icon(Icons.flag),
                     label: Column(
                        children: [
                          const Text("Set as Destination", style: TextStyle(fontWeight: FontWeight.bold)),
                          Text("Total: ${stats['truncate_total']!.toStringAsFixed(1)} NM", style: const TextStyle(fontSize: 10, color: Colors.white70)),
                        ],
                      ),
                  ),
                ),
              ],
            ],
          ),
        );
      }
    );
  }
  
  void _showAirportQuickView(BuildContext context, Airport airport) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AirportStatusPopup(
          airport: airport,
          onRoute: () {
            Navigator.pop(ctx);
            _showRouteOptions(context, RoutePoint(
              id: airport.ident,
              point: LatLng(airport.lat, airport.lon),
              type: 'airport',
              name: airport.name
            ));
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
  
  Future<void> _startEmergencyFlow() async {
    if (_model == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("AI Unavailable")));
      return;
    }

    String aircraftType = "Cessna 172S"; 
    String emergencyType = "Engine Failure"; 
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
    
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Analyzing Emergency Route...")));
    }

    try {
      final candidates = AirportDatabaseService().getNearestAirports(
        _currentPosition!.latitude, 
        _currentPosition!.longitude, 
        10
      );

      if (candidates.isEmpty) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No airports found nearby!")));
         return;
      }

      final aiResult = await AiEmergencyService.calculateEmergencyRoute(
        lat: _currentPosition!.latitude,
        lon: _currentPosition!.longitude,
        alt: _currentAltitudeFeet ?? 0,
        heading: _currentPosition!.heading,
        aircraftType: acType,
        emergencyType: emType,
        candidates: candidates,
        model: _model!,
      );

      final coords = aiResult['coordinates'];
      if (coords != null) {
        final destLat = (coords['lat'] as num).toDouble();
        final destLon = (coords['lon'] as num).toDouble();
        
        final Distance distCalc = const Distance();
        final LatLng currentPos = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
        final LatLng target = LatLng(destLat, destLon);

        final double distMeters = distCalc.as(LengthUnit.Meter, currentPos, target);
        final double distNm = distMeters / 1852.0;

        final double rawBearing = distCalc.bearing(currentPos, target);
        final double normalizedBearing = (rawBearing + 360) % 360;

        double speedKts = (_currentPosition!.speed) * 1.94384;
        if (speedKts < 10) speedKts = 100; 
        
        double timeHours = distNm / speedKts;
        int eteMinutes = (timeHours * 60).round();

        aiResult['navigation'] = {
          'distance_nm': double.parse(distNm.toStringAsFixed(1)), 
          'bearing_to': normalizedBearing.round(),
          'ete_minutes': eteMinutes,
          'target_id': aiResult['selected_airport_id']
        };

        List<LatLng> routePoints = [
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            LatLng(destLat, destLon)
        ];

        setState(() {
          _isEmergencyMode = true;
          _emergencyData = aiResult; 
          _emergencyRoute = routePoints;
        });
        
        widget.onEmergencyStateChanged?.call(true);

        widget.mapController?.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(_emergencyRoute),
            padding: const EdgeInsets.all(80),
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

  Future<void> _updateAirportLayer() async {
    if (!_showAirports) return;

    final bounds = widget.mapController?.camera.visibleBounds;
    if (bounds == null) return;

    final visibleAirports = AirportDatabaseService().getAirportsInBounds(bounds);
    
    final limitedAirports = visibleAirports.take(20).toList();

    if (mounted) {
      setState(() {
        _airportMarkers = limitedAirports.map((airport) => _buildAirportMarker(airport)).toList();
      });
    }

    if (limitedAirports.isNotEmpty) {
      final codes = limitedAirports.map((a) => a.ident).toList();
      try {
        final categories = await WeatherService.getFlightCategories(codes);
        
        if (mounted && _showAirports) {
          setState(() {
            _airportMarkers = limitedAirports.map((airport) {
              final category = categories[airport.ident];
              if (category != null) {
                // Update riskReason only
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

  Marker _buildAirportMarker(Airport airport) {
    // Access Theme
    final aviationColors = Theme.of(context).extension<AviationColors>()!;
    
    Color markerColor = Colors.grey;
    if (airport.type == 'large_airport') markerColor = Colors.blue;
    else if (airport.type == 'medium_airport') markerColor = Colors.cyan;
    
    if (airport.riskReason != null) {
      switch (airport.riskReason!.toUpperCase()) {
        case 'VFR': markerColor = aviationColors.vfr ?? Colors.green; break;
        case 'MVFR': markerColor = aviationColors.mvfr ?? Colors.blue; break;
        case 'IFR': markerColor = aviationColors.ifr ?? Colors.red; break;
        case 'LIFR': markerColor = aviationColors.lifr ?? Colors.purple; break;
      }
    } else if (airport.riskColor != null) {
        // Fallback to parsed hex if available and riskReason is null (though riskReason should be set)
        markerColor = _parseHexColor(airport.riskColor!);
    }

    return Marker(
      point: LatLng(airport.lat, airport.lon),
      width: 120,
      height: 80,
      child: GestureDetector(
        onTap: () {
          _showAirportQuickView(context, airport);
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
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
    
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        if (!mounted) return;
        
        setState(() {
          _currentPosition = position;
          _currentAltitudeFeet = position.altitude * 3.28084;
          _altitudeController.text = _currentAltitudeFeet!.toStringAsFixed(0);
        });
        
        // --- ADDED Waypoint Check Here ---
        _checkWaypointArrival(LatLng(position.latitude, position.longitude));
        
        if (!_isEmergencyMode && _isFollowing) {
          widget.mapController?.move(
            LatLng(position.latitude, position.longitude), 
            widget.mapController?.camera.zoom ?? 6.0
          );
        }

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

  LatLng _calculateDestinationPoint(LatLng start, double distanceMeters, double bearingDegrees) {
    const double radiusEarth = 6371000; 
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
    final List<LatLng> probePoints = [planePos]; 
    
    final double currentZoom = widget.mapController?.camera.zoom ?? 6.0;

    List<double> distances;
    int angleStep;

    if (currentZoom > 13.0) {
      distances = [5000, 15000, 30000, 50000]; 
      angleStep = 45; 
    } else if (currentZoom >= 10.0) {
      distances = [20000, 50000];
      angleStep = 60; 
    } else {
      distances = [50000];
      angleStep = 90; 
    }

    for (final dist in distances) {
      for (int bearing = 0; bearing < 360; bearing += angleStep) {
        probePoints.add(_calculateDestinationPoint(planePos, dist, bearing.toDouble()));
      }
    }

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

  List<Polygon> get _allPolygons =>
      _getVisibleFeatures().map((f) => f.polygon).toList();

  List<WeatherFeature> _getVisibleFeatures() {
    final allFeatures = _activeLayers.values.expand((features) => features).toList();

    if (_showFullData) {
      return allFeatures;
    }

    if (_currentPosition == null || _currentAltitudeFeet == null) {
      return allFeatures;
    }

    final altitude = _currentAltitudeFeet!;
    final aircraftLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    const distanceCalc = Distance();
    
    final List<WeatherFeature> filteredFeatures = [];

    for (final feature in allFeatures) {
      final (base, top) = _parseAltitudeRange(feature.rawProperties);
      if (altitude < base || altitude > top) {
        continue; 
      }
      
      if (isPointInPolygon(aircraftLatLng, feature.polygon.points)) {
          filteredFeatures.add(feature);
          continue;
      }
      
      bool isWithinRange = false;
      for (final point in feature.polygon.points) {
          if (distanceCalc.as(LengthUnit.Meter, aircraftLatLng, point) <= 50000) { 
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

    final baseStr = extractString(['base', 'base_ft', 'from', 'low'], 'SFC');
    final topStr = extractString(['top', 'top_ft', 'to', 'high'], 'MSL');

    int parseAltString(String altStr, {required bool isTop}) {
      final s = altStr.trim().toUpperCase();

      if (!isTop) {
        if (s == 'SFC' || s == 'GND') return 0;
      }

      if (isTop) {
        if (s == 'MSL' || s == 'TOP' || s == 'UNL' || s == 'UNLIMITED') return 60000;
      }

      final numeric = RegExp(r'\d+').stringMatch(s);
      final intValue = numeric == null ? null : int.tryParse(numeric);

      if (intValue != null) {
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

    setState(() {
       _activeLayers[type] = []; 
    });
    
    await _fetchWeatherData(type);
  }

  void _processGeometry(Map<String, dynamic> feature, List<WeatherFeature> list, Color fill, Color border) {
    final geometry = feature['geometry'];
    if (geometry == null) return;

    final rawProps = feature['properties'] as Map<String, dynamic>? ?? {};
    final rawCoords = geometry['coordinates'];
    final rawType = geometry['type'].toString();

    List allPoints = [];
    if (rawType.toLowerCase() == 'polygon' && rawCoords is List && rawCoords.isNotEmpty) {
      allPoints = rawCoords[0]; 
    } else if (rawType.toLowerCase() == 'multipolygon' && rawCoords is List) {
      for (var poly in rawCoords) {
        if (poly is List && poly.isNotEmpty) {
          allPoints.addAll(poly[0]); 
        }
      }
    }

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
    final aviationColors = Theme.of(context).extension<AviationColors>()!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final List<BoxShadow> shadows = isDark
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 2,
            )
          ]
        : [
            BoxShadow(
              color: Colors.grey.withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            )
          ];

    return GestureDetector(
      onTap: widget.onExit,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (aviationColors.mapButtonBg ?? Colors.white).withOpacity(0.9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
              boxShadow: shadows,
            ),
            child: Icon(Icons.arrow_back_ios_new, color: aviationColors.mapButtonIcon, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildMaydayButton() {
    return GestureDetector(
      onTap: _startEmergencyFlow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Text("MAYDAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
      ),
    );
  }

  Widget _buildStatusPill() {
    final aviationColors = Theme.of(context).extension<AviationColors>()!;
    final theme = Theme.of(context);
    
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
            color: (aviationColors.mapButtonBg ?? Colors.black).withOpacity(0.8),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: aviationColors.mapButtonIcon ?? Colors.greenAccent,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: aviationColors.mapButtonIcon ?? Colors.green, blurRadius: 4)],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "In-Flight",
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
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
  
  Widget _buildZoomControls() {
    final aviationColors = Theme.of(context).extension<AviationColors>()!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final List<BoxShadow> shadows = isDark
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 2,
            )
          ]
        : [
            BoxShadow(
              color: Colors.grey.withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            )
          ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: (aviationColors.mapButtonBg ?? Colors.black).withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
            boxShadow: shadows,
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
                color: theme.dividerColor.withOpacity(0.2),
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
    final aviationColors = Theme.of(context).extension<AviationColors>()!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(icon, color: aviationColors.mapButtonIcon ?? Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildFollowButton() {
    final aviationColors = Theme.of(context).extension<AviationColors>()!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final List<BoxShadow> shadows = isDark
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 2,
            )
          ]
        : [
            BoxShadow(
              color: Colors.grey.withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            )
          ];

    return GestureDetector(
      onTap: () {
        setState(() {
          _isFollowing = true;
        });
        if (_currentPosition != null) {
          widget.mapController?.move(
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            widget.mapController?.camera.zoom ?? 6.0
          );
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (aviationColors.mapButtonBg ?? Colors.black).withOpacity(0.9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isFollowing ? (aviationColors.mapButtonIcon ?? Colors.blueAccent) : theme.dividerColor.withOpacity(0.2),
                width: 1.5
              ),
              boxShadow: shadows,
            ),
            child: Icon(
              _isFollowing ? Icons.gps_fixed : Icons.gps_not_fixed,
              color: _isFollowing ? (aviationColors.mapButtonIcon ?? Colors.blueAccent) : theme.colorScheme.onSurface.withOpacity(0.6),
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  List<Marker> _buildRouteMarkers() {
    if (_activeRoutePoints.isEmpty) return [];

    return _activeRoutePoints.map((rp) {
      return Marker(
        point: rp.point,
        width: 120.0,
        height: 60.0,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {
            _showRouteOptions(context, rp);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. The Label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white24, width: 0.5),
                ),
                child: Text(
                  rp.name ?? rp.id, 
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              
              // 2. The Dot
              Container(
                width: 12, 
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.cyanAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.5), 
                      blurRadius: 6,
                      spreadRadius: 1
                    )
                  ]
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final theme = Theme.of(context); // Get global theme
    // Note: themeController.isDarkMode is still used for tileUrl logic or could use theme.brightness
    final isDark = theme.brightness == Brightness.dark;

    final String tileUrl = isDark 
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
        : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

    // Calculate Route Stats for UI
    final legData = _calculateLegStats();
    
    // Calculate Global Stats
    double totalDist = 0;
    for (var leg in legData) { totalDist += leg.distanceNm; }
    
    double gsKts = (_currentPosition?.speed ?? 0) * 1.94384;
    if (gsKts < 10) gsKts = 0; // Show 0 if barely moving
    
    double eteMinutes = 0;
    if (gsKts > 5) {
      eteMinutes = (totalDist / gsKts) * 60;
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          FlutterMap(
            mapController: widget.mapController,
            options: MapOptions(
              initialCenter: const LatLng(38.0, -98.0), // Center of US
              initialZoom: 6.0,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
              onTap: (_, point) => _handleMapTap(point),
              onLongPress: (tapPos, latLng) {
                // Generate a temporary ID
                String newId = "USR-${DateTime.now().millisecondsSinceEpoch % 1000}"; 
                final rp = RoutePoint(id: newId, point: latLng, type: 'waypoint', name: newId);
                _showRouteOptions(context, rp);
              },
              onPositionChanged: (position, hasGesture) {
                if (hasGesture) {
                   if (_isFollowing) {
                     setState(() => _isFollowing = false);
                   }
                  _mapDebounce?.cancel();
                  _mapDebounce = Timer(const Duration(milliseconds: 500), () {
                    if (!mounted) return;
                    
                    if (_currentPosition != null && _currentAltitudeFeet != null && _showTerrainAnalysis) {
                      final planePos = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
                      _scanTerrainSurroundings(planePos, _currentAltitudeFeet!);
                    }
                    
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
              PolygonLayer(
                polygons: _allPolygons, 
              ),

              if (_activeRoutePoints.isNotEmpty)
                PolylineLayer<Object>(
                  polylines: [
                    Polyline<Object>(
                      points: _activeRoutePoints.map((rp) => rp.point).toList(),
                      strokeWidth: 4.0,
                      color: Colors.cyanAccent.withOpacity(0.8), // Matches dot color
                      borderColor: Colors.black.withOpacity(0.5),
                      borderStrokeWidth: 1.0,
                    ),
                  ],
                ),
              
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
                
              if (_activeRoutePoints.isNotEmpty)
                MarkerLayer(markers: _buildRouteMarkers()),

              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    _buildAircraftMarker(), 
                  ],
                ),
                
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

              if (_airportMarkers.isNotEmpty)
                MarkerLayer(markers: _airportMarkers),
            ],
          ),
          
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isEmergencyMode) ...[
                      _buildBackButton(),
                      const SizedBox(width: 12),
                      _buildMaydayButton(),
                    ],
                    const Spacer(),
                    _buildStatusPill(),
                  ],
                ),
              ),
            ),
          ),

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
          
          if (!_isEmergencyMode)
            Positioned(
              right: 16,
              bottom: 180, // Moved up from 100 to avoid crowding the bottom panel
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                   _buildFollowButton(),
                   const SizedBox(height: 16),
                   _buildZoomControls(),
                ],
              ),
            ),
          
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
            
          if (!_isEmergencyMode)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FlightInfoPanel(
                gsKts: gsKts,
                track: _currentPosition?.heading ?? 0,
                dtgNm: totalDist,
                eteMinutes: eteMinutes,
                legs: legData,
                altitude: _currentAltitudeFeet,
              ),
            ),
        ],
      ),
    );
  }
}

// --- NEW: Navigraph Arrow Painter ---
class NavigraphArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint fillPaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final Path path = Path();
    // Draw a sharp arrow pointing UP (0 degrees)
    path.moveTo(size.width / 2, 0); // Tip
    path.lineTo(size.width, size.height); // Bottom Right
    path.lineTo(size.width / 2, size.height * 0.8); // Indent at bottom (Stealth shape)
    path.lineTo(0, size.height); // Bottom Left
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- NEW: Flight Info Panel Widget ---
class FlightInfoPanel extends StatefulWidget {
  final double gsKts;
  final double track;
  final double dtgNm;
  final double eteMinutes;
  final List<LegData> legs;
  final double? altitude;

  const FlightInfoPanel({
    super.key,
    required this.gsKts,
    required this.track,
    required this.dtgNm,
    required this.eteMinutes,
    required this.legs,
    this.altitude,
  });

  @override
  State<FlightInfoPanel> createState() => _FlightInfoPanelState();
}

class _FlightInfoPanelState extends State<FlightInfoPanel> with SingleTickerProviderStateMixin {
  // Toggles between "Just Arrow" (false) and "Arrow + Row" (true)
  bool _isDataPanelVisible = true; 

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aviationColors = theme.extension<AviationColors>()!;

    // Define Colors based on Mode
    final backgroundColor = (aviationColors.mapButtonBg ?? theme.colorScheme.surface).withOpacity(0.95);
    final borderColor = theme.dividerColor.withOpacity(0.2);
    final shadowColor = theme.shadowColor.withOpacity(0.2);
    final iconColor = theme.colorScheme.onSurface.withOpacity(0.6);
    // Button styling colors
    final buttonBgColor = (aviationColors.mapButtonBg ?? Colors.black).withOpacity(0.9);
    final buttonIconColor = aviationColors.mapButtonIcon ?? theme.colorScheme.primary;

    // Incorporate Safe Area for proper layout on modern phones
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    
    // We remove the explicit height calculation and AnimatedContainer to avoid RenderFlex overflow.
    // Instead, we use Container + AnimatedSize + explicit Bottom Padding inside content.

    return Container(
      decoration: _isDataPanelVisible
        ? BoxDecoration(
            color: backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(top: BorderSide(color: borderColor)),
            boxShadow: [
              BoxShadow(color: shadowColor, blurRadius: 10, offset: const Offset(0, -2))
            ]
          )
        : null, // No decoration when collapsed (transparent)
      child: SafeArea(
        top: false, // Only care about bottom safe area (home indicator)
        bottom: false, // We handle bottom padding manually to allow floating button
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min, // prevent column from expanding
            children: [
              // 1. Toggle Arrow (Replaces Handle)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isDataPanelVisible = !_isDataPanelVisible;
                  });
                },
                behavior: HitTestBehavior.opaque, // Hit test on full width
                child: Container(
                  width: 60, // Fixed width
                  height: 32, // Smaller height for button look
                  margin: EdgeInsets.only(
                    top: 8, 
                    bottom: _isDataPanelVisible ? 0 : bottomPadding + 16
                  ),
                  decoration: _isDataPanelVisible 
                    ? null // Transparent/Minimal when expanded
                    : BoxDecoration(
                        color: buttonBgColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                        boxShadow: [
                           BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))
                        ],
                      ),
                  alignment: Alignment.center,
                  child: Icon(
                    _isDataPanelVisible ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    color: _isDataPanelVisible ? iconColor : buttonIconColor,
                    size: 24,
                  ),
                ),
              ),
              
              // 2. Data Row (Conditionally Rendered)
              if (_isDataPanelVisible)
                Padding(
                  // We removed the manual 'bottomPadding' addition here because SafeArea handles it.
                  // Re-added manual bottom padding since SafeArea(bottom: false)
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomPadding), 
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: _buildStatBox("GS", "${widget.gsKts.toStringAsFixed(0)}", "KT", theme, aviationColors)),
                      Expanded(child: _buildStatBox("ALT", widget.altitude?.toStringAsFixed(0) ?? "---", "FT", theme, aviationColors)),
                      Expanded(child: _buildStatBox("TRK", "${widget.track.round()}°", "", theme, aviationColors)),
                      Expanded(child: _buildStatBox("DTG", widget.dtgNm.toStringAsFixed(1), "NM", theme, aviationColors)),
                      Expanded(child: _buildStatBox("ETE", _formatDuration(widget.eteMinutes), "", theme, aviationColors)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatBox(String label, String value, String unit, ThemeData theme, AviationColors aviationColors) {
    final labelColor = theme.colorScheme.onSurface.withOpacity(0.6);
    // Use mapButtonIcon (typically bright blue/cyan in dark mode, deep blue in light) or primary color
    final valueColor = aviationColors.mapButtonIcon ?? theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center, // Center align to prevent overflow
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: labelColor, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        // Use Flexible/FittedBox to ensure text scales down if too wide
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: TextStyle(color: valueColor, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(unit, style: TextStyle(color: valueColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ]
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(double minutes) {
    if (minutes <= 0) return "--:--";
    if (minutes > 99 * 60) return ">99h";
    final h = (minutes / 60).floor();
    final m = (minutes % 60).round();
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";
  }
}
