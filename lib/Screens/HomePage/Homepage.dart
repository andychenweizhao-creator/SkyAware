import 'dart:ui';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../UI/AppAnimations.dart';
import '../../services/unit_settings_service.dart';
import '../../services/ai_airport_service.dart'; // IMPORT THIS

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // State
  bool _isLoading = false;
  bool _hasSearched = false; // Tracks Cold Start state
  Map<String, dynamic>? _metarData;
  double? _lat;
  double? _lon;
  int _utcOffsetSeconds = 0; // Added for Location Local Time
  String _errorMessage = '';
  String? _gpsLocationName; // Current User Location
  int _searchRadius = 50; // Default to 50 nm

  String _currentAirportCode = "";
  late final TextEditingController _searchController;

  // Clock State
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  // Gemini AI
  GenerativeModel? _model;
  String _aiInsight = "";
  int? _aiSafetyScore;
  int _aiRequestId = 0; // To handle out-of-order responses

  // API Key for Gemini
  final String _apiKey = "AIzaSyBqqjz5thRK3Lt6xQcivugnHReGkbgK9rY";

  static const Duration _geminiTimeout = Duration(seconds: 25);
  static const Duration _geminiRetryDelay = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();

    // Start Real-time Clock
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });

    // Fetch User GPS Location
    _fetchUserLocation();

    // Initialize Gemini Model with Strict Safety Settings (Off)
    try {
      if (_apiKey.isNotEmpty) {
        _model = GenerativeModel(
          model: 'gemini-3-pro-preview',
          apiKey: _apiKey,
          generationConfig: GenerationConfig(responseMimeType: 'application/json'),
          safetySettings: [
            HarmCategory.harassment,
            HarmCategory.hateSpeech,
            HarmCategory.sexuallyExplicit,
            HarmCategory.dangerousContent,
          ].map((category) => SafetySetting(category, HarmBlockThreshold.none)).toList(),
        );
      }
    } catch (e) {
      debugPrint("Error initializing Gemini: $e");
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserLocation() async {
    if (mounted) setState(() => _gpsLocationName = "Locating...");
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
         if (mounted) setState(() => _gpsLocationName = "Location Off");
         return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
           if (mounted) setState(() => _gpsLocationName = "Permission Denied");
           return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
         if (mounted) setState(() => _gpsLocationName = "Location Denied");
         return;
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      
      if (placemarks.isNotEmpty && mounted) {
        Placemark place = placemarks[0];
        String loc = "${place.locality ?? ''}, ${place.administrativeArea ?? ''}".trim();
        // Cleanup formatting
        if (loc.startsWith(",")) loc = loc.substring(1).trim();
        if (loc.endsWith(",")) loc = loc.substring(0, loc.length - 1).trim();
        if (loc.isEmpty) loc = "Unknown Location";
        
        setState(() {
          _gpsLocationName = loc;
        });
      }
    } catch (e) {
      debugPrint("Error fetching location: $e");
      if (mounted) setState(() => _gpsLocationName = "Location Error");
    }
  }

  Future<void> _fetchNearbyAirports() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 1. Check Permissions & Service First
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location services are disabled.")));
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location permission denied")));
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location permission permanently denied. Enable in Settings.")));
       return;
    }

    if (_model == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("AI Model not initialized. Cannot fetch airports.")));
      return;
    }

    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(child: CircularProgressIndicator(color: theme.primaryColor)),
    );

    try {
      // 2. Get Location with Timeout
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      
      double lat = position.latitude;
      double lon = position.longitude;

      // Simulator Fallback (Googleplex is around 37.422, -122.084)
      if ((lat == 0 && lon == 0) || (lat > 37.4 && lat < 37.43 && lon < -122.08 && lon > -122.09)) {
         lat = 33.8885;
         lon = -117.8131;
         debugPrint("Using Simulator Fallback Coordinates: Yorba Linda (KFUL nearby)");
      }
      
      // 3. Use AI Airport Service (REFACTORED)
      final airports = await AiAirportService.searchNearbyAirports(lat, lon, _searchRadius, _model!);
      
      if (!mounted) return;
      Navigator.of(context).pop(); // Dismiss loading

      if (airports.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No airports found by Co-pilot.")));
        return;
      }

      // Show Selection Sheet (Service already formatted the data correctly)
      if (mounted) {
        _showAirportSelectionSheet(airports, theme, isDark, lat, lon);
      }

    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Dismiss loading
        debugPrint("Error finding nearby airports with AI: $e");
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Co-pilot could not locate airports.")));
      }
    }
  }

  void _showAirportSelectionSheet(List<Map<String, dynamic>> airports, ThemeData theme, bool isDark, double userLat, double userLon) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E).withOpacity(0.98) : Colors.white.withOpacity(0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
          ),
          child: Column(
            children: [
              // Handle
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.radar, color: theme.primaryColor),
                        const SizedBox(width: 8),
                        Text("Nearest Stations", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.map_outlined),
                      tooltip: "View on Google Maps",
                      onPressed: () async {
                         final Uri url = Uri.parse("https://www.google.com/maps/search/airports/@$userLat,$userLon,11z");
                         if (await canLaunchUrl(url)) {
                           await launchUrl(url, mode: LaunchMode.externalApplication);
                         } else {
                           if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not launch Google Maps")));
                         }
                      },
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                  itemCount: airports.length,
                  itemBuilder: (context, index) {
                    final item = airports[index];
                    final props = item['data']['properties'];
                    final double distMeters = item['distance'];
                    // Convert meters to Nautical Miles
                    final double distNm = distMeters * 0.000539957;
                    
                    final String icao = props['id'] ?? 'Unknown';
                    final String name = props['site'] ?? 'Unknown Station';

                    // Extract coordinates for the specific airport
                    final geom = item['data']['geometry'];
                    final coords = geom['coordinates'];
                    final double stLat = (coords[1] as num).toDouble();
                    final double stLon = (coords[0] as num).toDouble();

                    return InkWell(
                      onTap: () {
                        Navigator.pop(context); // Close sheet
                        _searchController.text = icao;
                        setState(() {
                          _currentAirportCode = icao;
                        });
                        _fetchMetarData();
                      },
                      onLongPress: () async {
                         // Open specific airport in Maps
                         final Uri url = Uri.parse("https://www.google.com/maps/search/?api=1&query=$stLat,$stLon");
                         if (await canLaunchUrl(url)) {
                           await launchUrl(url, mode: LaunchMode.externalApplication);
                         }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Row(
                          children: [
                            // Left: Distance
                            SizedBox(
                              width: 60,
                              child: Text(
                                "${distNm.toStringAsFixed(1)} nm",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: theme.primaryColor,
                                ),
                              ),
                            ),
                            // Middle: Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    icao,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Right: Icon
                            Icon(Icons.chevron_right, color: theme.colorScheme.onSurface.withOpacity(0.3), size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _fetchMetarData() async {
    if (_currentAirportCode.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus(); // Close keyboard

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _hasSearched = true;
      _aiInsight = "Copilot is analyzing current weather conditions...";
      _aiSafetyScore = null;
      _metarData = null; // Clear previous data
      _utcOffsetSeconds = 0; // Reset offset
    });

    try {
      // Cache Busting added
      final response = await http.get(
        Uri.parse('https://aviationweather.gov/api/data/metar?ids=$_currentAirportCode&format=geojson&taf=false&hours=0&_=${DateTime.now().millisecondsSinceEpoch}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;

        if (features.isNotEmpty) {
          final feature = features[0];
          final geometry = feature['geometry'];
          final properties = feature['properties'];

          // Extract Coordinates [lon, lat]
          List<dynamic>? coords = geometry['coordinates'];

          if (mounted) {
            setState(() {
              _metarData = properties;
              if (coords != null && coords.length >= 2) {
                _lon = (coords[0] as num).toDouble();
                _lat = (coords[1] as num).toDouble();
                
                // Fetch Timezone Offset for this location
                _fetchTimezoneOffset(_lat!, _lon!);
              }
              _isLoading = false;
            });

            // Trigger AI Analysis
            final int requestId = ++_aiRequestId;
            _analyzeWeatherWithGemini(properties, requestId);
          }
        } else {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Airport $_currentAirportCode not found.';
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Failed to fetch data (${response.statusCode}).';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Connection Error: $e';
        });
      }
    }
  }

  Future<void> _fetchTimezoneOffset(double lat, double lon) async {
    try {
      final uri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=is_day&timezone=auto');
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _utcOffsetSeconds = (data['utc_offset_seconds'] as num?)?.toInt() ?? 0;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching timezone offset: $e");
    }
  }

  Future<void> _analyzeWeatherWithGemini(Map<String, dynamic> metarData, int requestId) async {
    if (_model == null) {
      if (mounted && requestId == _aiRequestId) {
        setState(() {
          _aiInsight = "AI Co-Pilot not configured.";
        });
      }
      return;
    }

    try {
      // Deduction System Prompt
      final prompt = """
      Act as a Chief Pilot. Analyze this METAR data: ${json.encode(metarData)}.
      Calculate a 'Safety Score' (0-100) for a General Aviation pilot.
      Start with 100. Deduct points: 
      - Ceiling < 3000ft (-20 pts)
      - Visibility < 3SM (-20 pts)
      - Wind > 15kt (-10 pts)
      - Rain/Snow present (-15 pts)
      
      Return a specific integer (e.g., 84, 65). DO NOT return 0 or 100 unless conditions are extreme.
      
      Return ONLY valid JSON: {"score": <int>, "summary": "<string, max 30 words>"}
      """;

      final content = [Content.text(prompt)];
      
      // Retry logic
      GenerateContentResponse response;
      try {
        response = await _model!.generateContent(content).timeout(_geminiTimeout);
      } on TimeoutException {
        await Future.delayed(_geminiRetryDelay);
        response = await _model!.generateContent(content).timeout(_geminiTimeout);
      }

      if (!mounted || requestId != _aiRequestId) return;
      if (response.text == null) return;

      // Robust Regex Parsing
      final text = response.text!;
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);

      if (jsonMatch != null) {
         final jsonString = jsonMatch.group(0)!;
         try {
           final Map<String, dynamic> aiResponse = json.decode(jsonString);
           if (mounted && requestId == _aiRequestId) {
             setState(() {
               _aiSafetyScore = aiResponse['score'] as int?;
               _aiInsight = aiResponse['summary']?.toString() ?? "Analysis available.";
             });
           }
         } catch (e) {
           debugPrint("JSON Parse Error: $e");
           // Fallback to raw text if JSON fails
           setState(() => _aiInsight = text);
         }
      } else {
        setState(() => _aiInsight = text);
      }

    } catch (e) {
      debugPrint("Gemini Error: $e");
      if (mounted && requestId == _aiRequestId) {
        setState(() {
          _aiInsight = "Co-Pilot offline. Using fallback data.";
        });
      }
    }
  }

  // NOAA-based Sun Calc (Handles UTC Midnight Crossing)
  Map<String, DateTime> _calculateSunTimes(double lat, double lon) {
    final now = DateTime.now().toUtc();
    final startOfYear = DateTime.utc(now.year, 1, 1);
    final dayOfYear = now.difference(startOfYear).inDays + 1;

    // Fractional Year (radians)
    final gamma = (2 * math.pi / 365.0) * (dayOfYear - 1 + (now.hour - 12) / 24.0);

    // Equation of Time (minutes)
    final eqTime = 229.18 * (0.000075 + 0.001868 * math.cos(gamma) - 0.032077 * math.sin(gamma) 
                   - 0.014615 * math.cos(2 * gamma) - 0.040849 * math.sin(2 * gamma));

    // Solar Declination (radians)
    final decl = 0.006918 - 0.399912 * math.cos(gamma) + 0.070257 * math.sin(gamma)
                 - 0.006758 * math.cos(2 * gamma) + 0.000907 * math.sin(2 * gamma)
                 - 0.002697 * math.cos(3 * gamma) + 0.00148 * math.sin(3 * gamma);

    // Hour Angle
    final latRad = lat * (math.pi / 180.0);
    final zenith = 90.833 * (math.pi / 180.0);
    
    double cosHA = (math.cos(zenith) - math.sin(latRad) * math.sin(decl)) / 
                   (math.cos(latRad) * math.cos(decl));

    if (cosHA > 1.0) cosHA = 1.0;
    if (cosHA < -1.0) cosHA = -1.0;

    final haDeg = math.acos(cosHA) * (180.0 / math.pi);
    final solarNoonMins = 720.0 - 4.0 * lon - eqTime;

    double sunriseMins = solarNoonMins - 4.0 * haDeg;
    double sunsetMins = solarNoonMins + 4.0 * haDeg;

    // Convert to DateTime (UTC)
    double sunriseHours = (sunriseMins / 60.0) % 24.0;
    if (sunriseHours < 0) sunriseHours += 24.0;
    
    double sunsetHours = (sunsetMins / 60.0) % 24.0;
    if (sunsetHours < 0) sunsetHours += 24.0;

    DateTime sunrise = DateTime.utc(now.year, now.month, now.day,
      sunriseHours.floor(), ((sunriseHours % 1) * 60).round());
      
    DateTime sunset = DateTime.utc(now.year, now.month, now.day,
      sunsetHours.floor(), ((sunsetHours % 1) * 60).round());

    // Fix: If sunset is before sunrise (crossing midnight), add a day
    if (sunset.isBefore(sunrise)) {
       sunset = sunset.add(const Duration(days: 1));
    }

    return {'sunrise': sunrise, 'sunset': sunset};
  }

  Color _getScoreColor(int score, bool isDark) {
    if (isDark) {
      if (score >= 90) return Colors.greenAccent;
      if (score >= 75) return Colors.lightGreenAccent;
      if (score >= 60) return Colors.yellowAccent;
      if (score >= 40) return Colors.orangeAccent;
      return Colors.redAccent;
    } else {
      if (score >= 90) return Colors.green;
      if (score >= 75) return Colors.lightGreen;
      if (score >= 60) return Colors.amber;
      if (score >= 40) return Colors.deepOrange;
      return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Background Glow
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.primaryColor.withOpacity(0.15),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withOpacity(0.2),
                    blurRadius: 100.0,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                StaggeredEntrance(
                  index: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        _buildHeader(theme),
                        const SizedBox(height: 20),
                        // Search Bar
                        _buildAirportBar(theme, isDark),
                        // Airport Name below search
                        if (_hasSearched && _metarData != null)
                           Padding(
                             padding: const EdgeInsets.only(top: 12, left: 4),
                             child: Row(
                               children: [
                                 Text(
                                   "Search airport: ",
                                   style: TextStyle(
                                     color: theme.colorScheme.onSurface.withOpacity(0.6),
                                     fontSize: 14,
                                   ),
                                 ),
                                 Expanded(
                                   child: Text(
                                     _metarData!['site'] ?? _metarData!['id'] ?? "Unknown",
                                     style: TextStyle(
                                       color: theme.colorScheme.onSurface,
                                       fontSize: 14,
                                       fontWeight: FontWeight.bold,
                                     ),
                                     maxLines: 1,
                                     overflow: TextOverflow.ellipsis,
                                   ),
                                 ),
                               ],
                             ),
                           ),
                      ],
                    ),
                  ),
                ),

                // Content Area
                Expanded(
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator(color: theme.colorScheme.onSurface))
                      : !_hasSearched
                          ? _buildColdStartPlaceholder(theme)
                          : _errorMessage.isNotEmpty
                              ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.redAccent, fontSize: 16)))
                              : RefreshIndicator(
                                  onRefresh: _fetchMetarData,
                                  color: theme.colorScheme.onSurface,
                                  backgroundColor: theme.scaffoldBackgroundColor,
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    physics: const BouncingScrollPhysics(),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 1. Sun Phase
                                        StaggeredEntrance(index: 1, child: _buildSunPhaseWidget(theme)),
                                        const SizedBox(height: 32),

                                        // 2. Safety Gauge
                                        StaggeredEntrance(index: 2, child: Center(child: _buildSafetyGauge(theme, isDark))),
                                        const SizedBox(height: 32),

                                        // 3. Metrics Grid
                                        StaggeredEntrance(index: 3, child: _buildMetricsGrid(theme, isDark)),
                                        const SizedBox(height: 24),

                                        // 4. Runway
                                        StaggeredEntrance(index: 4, child: _buildRunwayWidget(theme, isDark)),
                                        const SizedBox(height: 24),

                                        // 5. AI Insight
                                        StaggeredEntrance(index: 5, child: _buildAiInsightCard(theme)),
                                        const SizedBox(height: 80),
                                      ],
                                    ),
                                  ),
                                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logic for Before Search
              if (!_hasSearched) ...[
                if (_gpsLocationName != null) 
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Icon(Icons.near_me_rounded, size: 14, color: theme.primaryColor),
                        const SizedBox(width: 4),
                        // Small location text
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _gpsLocationName!,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                Text(
                  "Good Morning, Captain",
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Ready for departure?",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ] else ...[
                // Logic for After Search (Only Big Location)
                if (_gpsLocationName != null) 
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Row(
                      children: [
                        Icon(Icons.near_me_rounded, size: 24, color: theme.primaryColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _gpsLocationName!,
                              style: TextStyle(
                                fontSize: 24,
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        _buildClock(theme),
      ],
    );
  }

  Widget _buildClock(ThemeData theme) {
    final localTime = DateFormat('HH:mm').format(_now);
    final zuluTime = DateFormat('HH:mm').format(_now.toUtc());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              localTime,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w300,
                color: theme.colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              "L",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: theme.primaryColor,
              ),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              zuluTime,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              "Z",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.orangeAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAirportBar(ThemeData theme, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: SpringButton(
            child: _buildGlassCard(
              isDark: isDark,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                cursorColor: isDark ? Colors.greenAccent : Colors.green,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: "Enter ICAO (e.g. KSFO)",
                  hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.38)),
                  icon: Icon(Icons.location_on, color: isDark ? Colors.greenAccent : Colors.green),
                  suffixIcon: Icon(Icons.search, color: theme.colorScheme.onSurface),
                ),
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    setState(() {
                      _currentAirportCode = value.toUpperCase();
                    });
                    _fetchMetarData();
                  }
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Combo Button for Range & Search
        SpringButton(
          child: _buildGlassCard(
            isDark: isDark,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Range Selector
                PopupMenuButton<int>(
                  initialValue: _searchRadius,
                  onSelected: (value) {
                    setState(() {
                      _searchRadius = value;
                    });
                  },
                  itemBuilder: (context) => [25, 50, 100, 200].map((r) => PopupMenuItem(
                    value: r,
                    child: Text("$r nm"),
                  )).toList(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                    child: Row(
                      children: [
                        Text(
                          "$_searchRadius nm",
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurface.withOpacity(0.7), size: 18),
                      ],
                    ),
                  ),
                ),
                // Divider
                Container(
                  height: 24,
                  width: 1,
                  color: theme.colorScheme.onSurface.withOpacity(0.2),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                ),
                // Near Me Button
                IconButton(
                  icon: Icon(Icons.near_me, color: theme.primaryColor),
                  onPressed: _fetchNearbyAirports,
                  tooltip: "Find Nearby",
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColdStartPlaceholder(ThemeData theme) {
    return StaggeredEntrance(
      index: 1,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 80, color: theme.colorScheme.onSurface.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              "Enter ICAO code to view intelligence",
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSunPhaseWidget(ThemeData theme) {
    if (_lat == null || _lon == null) return const SizedBox.shrink();

    final sunTimes = _calculateSunTimes(_lat!, _lon!);
    final sunrise = sunTimes['sunrise']!;
    final sunset = sunTimes['sunset']!;
    final now = DateTime.now().toUtc();

    double progress = 0.0;
    if (now.isBefore(sunrise)) {
      progress = 0.0;
    } else if (now.isAfter(sunset)) {
      progress = 1.0;
    } else {
      final total = sunset.difference(sunrise).inMinutes;
      final current = now.difference(sunrise).inMinutes;
      if (total > 0) progress = current / total;
    }

    String timeText;
    if (now.isBefore(sunrise)) {
      final diff = sunrise.difference(now);
      timeText = "Sunrise in ${diff.inHours}h ${diff.inMinutes % 60}m";
    } else if (now.isBefore(sunset)) {
      final diff = sunset.difference(now);
      timeText = "Sunset in ${diff.inHours}h ${diff.inMinutes % 60}m";
    } else {
      final diff = now.difference(sunset);
      timeText = "Sunset was ${diff.inHours}h ${diff.inMinutes % 60}m ago";
    }

    // New format function using fetched offset
    String formatSunTime(DateTime utcDt) {
       // Convert UTC to Location Local using fetched offset
       DateTime local = utcDt.add(Duration(seconds: _utcOffsetSeconds));
       return "${local.hour.toString().padLeft(2,'0')}:${local.minute.toString().padLeft(2,'0')} L";
    }

    // Animate Expansion
    return SpringButton(
      child: _buildGlassCard(
        isDark: theme.brightness == Brightness.dark,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Sunrise Column
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("SR ${formatSunTime(sunrise)}", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.54), fontSize: 12)),
                    Text("   ${DateFormat('HH:mm').format(sunrise)} Z", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.38), fontSize: 10)),
                  ],
                ),
                
                Text(timeText, style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                
                // Sunset Column
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                     Text("SS ${formatSunTime(sunset)}", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.54), fontSize: 12)),
                     Text("   ${DateFormat('HH:mm').format(sunset)} Z", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.38), fontSize: 10)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 4,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: constraints.maxWidth * progress),
                      duration: const Duration(seconds: 2),
                      curve: Curves.easeOutExpo,
                      builder: (context, val, child) {
                        return Container(
                          height: 4,
                          width: val,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Colors.orange, Colors.yellow]),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }
                    );
                  }
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                     return TweenAnimationBuilder<double>(
                       tween: Tween<double>(begin: 0, end: progress),
                       duration: const Duration(seconds: 2),
                       curve: Curves.easeOutExpo,
                       builder: (context, val, child) {
                         return Align(
                           alignment: Alignment(val * 2 - 1, 0),
                           child: Container(
                             padding: const EdgeInsets.all(4),
                             decoration: const BoxDecoration(
                               color: Colors.yellow,
                               shape: BoxShape.circle,
                               boxShadow: [BoxShadow(color: Colors.orangeAccent, blurRadius: 10)],
                             ),
                             child: const Icon(Icons.wb_sunny_rounded, color: Colors.orange, size: 14),
                           ),
                         );
                       }
                     );
                  }
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetyGauge(ThemeData theme, bool isDark) {
    return SpringButton(
      child: SizedBox(
        width: 200,
        height: 200,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          child: _aiSafetyScore != null
              ? _buildScoreGauge(_aiSafetyScore!, theme, isDark)
              : _buildAnalyzingState(theme),
        ),
      ),
    );
  }

  Widget _buildAnalyzingState(ThemeData theme) {
    return Container(
      key: const ValueKey("analyzing"),
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surface.withOpacity(0.05),
        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              color: theme.primaryColor,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Analyzing\nAI Safety Score...",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.primaryColor.withOpacity(0.8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreGauge(int score, ThemeData theme, bool isDark) {
    final color = _getScoreColor(score, isDark);
    return Stack(
      key: const ValueKey("score"),
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 200,
          height: 200,
          child: CircularProgressIndicator(
            value: 1.0,
            strokeWidth: 15,
            color: theme.colorScheme.onSurface.withOpacity(0.05),
            strokeCap: StrokeCap.round,
          ),
        ),
        SizedBox(
          width: 200,
          height: 200,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: score / 100.0),
            duration: const Duration(seconds: 2),
            curve: Curves.easeOutExpo,
            builder: (context, value, child) {
              return CircularProgressIndicator(
                value: value,
                strokeWidth: 15,
                color: color,
                backgroundColor: Colors.transparent,
                strokeCap: StrokeCap.round,
              );
            },
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedCounter(
              value: score,
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
                height: 1.0,
              )
            ),
            Text(
              "AI SAFETY SCORE",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color.withOpacity(0.9),
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricsGrid(ThemeData theme, bool isDark) {
    if (_metarData == null) return const SizedBox.shrink();
    final units = Provider.of<UnitSettingsProvider>(context);

    // 1. Flight Category
    final fltcat = _metarData!['fltcat']?.toString() ?? 'N/A';
    Color catColor = theme.colorScheme.onSurface;
    switch (fltcat) {
      case 'VFR': catColor = isDark ? Colors.greenAccent : Colors.green; break;
      case 'MVFR': catColor = Colors.blueAccent; break;
      case 'IFR': catColor = isDark ? Colors.redAccent : Colors.red; break;
      case 'LIFR': catColor = Colors.purpleAccent; break;
      default: catColor = Colors.grey;
    }

    // 2. Altimeter
    final altimMb = _metarData!['altim'];
    String altimDisplay = "29.92 inHg";
    if (altimMb is num) {
      if (units.pressureUnit == PressureUnit.inHg) {
        altimDisplay = "${(altimMb * 0.02953).toStringAsFixed(2)} inHg";
      } else {
        altimDisplay = "${altimMb.round()} hPa";
      }
    }

    // 3. Temp / Dewp
    final temp = _metarData!['temp']?.toString() ?? '0';
    final dewp = _metarData!['dewp']?.toString() ?? '0';
    Color tempColor = theme.colorScheme.onSurface;
    String tempDisplay = "$temp°C / $dewp°C";
    
    try {
      double t = double.parse(temp);
      double d = double.parse(dewp);
      
      // Determine color based on spread in Celsius
      if ((t - d).abs() < 3) tempColor = Colors.orangeAccent;

      if (units.temperatureUnit == TemperatureUnit.fahrenheit) {
        t = (t * 9 / 5) + 32;
        d = (d * 9 / 5) + 32;
        tempDisplay = "${t.round()}°F / ${d.round()}°F";
      } else {
        tempDisplay = "${t.round()}°C / ${d.round()}°C";
      }
    } catch (_) {}

    // 4. Wind
    dynamic rawDir = _metarData!['wdir'];
    dynamic rawSpd = _metarData!['wspd'];
    String windDirDisplay = rawDir is num ? "${rawDir.toString().padLeft(3, '0')}°" : "VRB";
    String windSpdDisplay = rawSpd?.toString() ?? "0";
    String windUnitLabel = "kt";

    if (rawSpd is num) {
      double speed = rawSpd.toDouble();
      if (units.distanceSpeedUnit == DistanceSpeedUnit.kilometersKph) {
        speed = speed * 1.852; // kt to km/h
        windUnitLabel = "kph";
      } else if (units.distanceSpeedUnit == DistanceSpeedUnit.milesMph) {
        speed = speed * 1.15078; // kt to mph
        windUnitLabel = "mph";
      }
      windSpdDisplay = speed.round().toString();
    }
    
    final windDisplay = "$windDirDisplay @ $windSpdDisplay$windUnitLabel";

    // 5. Sky (Ceiling Unit)
    String skyCond = "SKC";
    if (_metarData!.containsKey('clouds')) {
      final List<dynamic> clouds = _metarData!['clouds'] ?? [];
      if (clouds.isNotEmpty) {
        final layer = clouds[0];
        String baseStr = layer['base']?.toString() ?? '';
        if (baseStr.isNotEmpty && units.altitudeUnit == AltitudeUnit.meters) {
           int? feet = int.tryParse(baseStr);
           if (feet != null) {
             baseStr = (feet * 0.3048).round().toString();
           }
        }
        skyCond = "${layer['cover']} $baseStr".trim();
      }
    } else {
       final cover = _metarData!['cover']?.toString() ?? 'SKC';
       final ceil = _metarData!['ceil'];
       String ceilStr = '';
       if (ceil != null && ceil is num) {
          if (units.altitudeUnit == AltitudeUnit.meters) {
            ceilStr = (ceil * 0.3048).round().toString();
          } else {
            ceilStr = ceil.toInt().toString();
          }
       }
       skyCond = "$cover $ceilStr".trim();
    }
    
    // 6. Vis / Wx
    // Typically Aviation Weather API returns visibility in SM (Statute Miles)
    String visDisplay = _metarData!['visib']?.toString() ?? '10+';
    String visUnit = "SM";
    
    // Try to parse visibility to convert if needed
    // Often it can be "10+" or fractions "1/2"
    // For simplicity, we only convert simple numbers or "10+"
    if (units.distanceSpeedUnit == DistanceSpeedUnit.kilometersKph) {
       // Convert SM to km
       // Very rough handling for "10+"
       if (visDisplay == "10+") {
         visDisplay = "16+";
         visUnit = "km";
       } else {
         final v = double.tryParse(visDisplay);
         if (v != null) {
           visDisplay = (v * 1.60934).toStringAsFixed(1);
           visUnit = "km";
         }
       }
    }
    
    final wx = _metarData!['wx']?.toString() ?? '';

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.4,
      children: [
        _buildMetricCard("FLIGHT CAT", fltcat, theme, isDark, icon: Icons.flight, color: catColor, isPill: true),
        _buildMetricCard("ALTIMETER", altimDisplay, theme, isDark, icon: Icons.speed),
        _buildMetricCard("TEMP / DEWP", tempDisplay, theme, isDark, icon: Icons.thermostat, color: tempColor),
        _buildMetricCard("WIND", windDisplay, theme, isDark, icon: Icons.air),
        _buildMetricCard("SKY COND", skyCond, theme, isDark, icon: Icons.cloud),
        _buildMetricCard("VIS / WX", "$visDisplay $visUnit $wx".trim(), theme, isDark, icon: Icons.visibility),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, ThemeData theme, bool isDark, {
    IconData? icon,
    Color? color,
    bool isPill = false,
  }) {
    // Default color to onSurface if not specified
    final contentColor = color ?? theme.colorScheme.onSurface;

    return SpringButton(
      child: _buildGlassCard(
        isDark: isDark,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.bold)),
                if (icon != null) Icon(icon, color: theme.colorScheme.onSurface.withOpacity(0.4), size: 16),
              ],
            ),
            if (isPill)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: contentColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: contentColor.withOpacity(0.5)),
                ),
                child: Text(value, style: TextStyle(color: contentColor, fontWeight: FontWeight.bold, fontSize: 18)),
              )
            else
              Text(value, style: TextStyle(color: contentColor, fontWeight: FontWeight.bold, fontSize: 20), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildRunwayWidget(ThemeData theme, bool isDark) {
    if (_metarData == null) return const SizedBox.shrink();
    final units = Provider.of<UnitSettingsProvider>(context);
    
    double windDir = 0;
    double windSpd = 0;
    double runwayHeading = 360;

    if (_metarData!['wdir'] is num) {
      windDir = (_metarData!['wdir'] as num).toDouble();
      runwayHeading = (windDir / 10).round() * 10.0;
      if (runwayHeading == 0) runwayHeading = 360;
    }
    if (_metarData!['wspd'] is num) {
      windSpd = (_metarData!['wspd'] as num).toDouble();
    }
    
    // Convert for display in the text below
    String windSpdDisplay = windSpd.toStringAsFixed(0);
    String windUnitLabel = "kt";
    
    if (units.distanceSpeedUnit == DistanceSpeedUnit.kilometersKph) {
      windSpdDisplay = (windSpd * 1.852).toStringAsFixed(0);
      windUnitLabel = "kph";
    } else if (units.distanceSpeedUnit == DistanceSpeedUnit.milesMph) {
      windSpdDisplay = (windSpd * 1.15078).toStringAsFixed(0);
      windUnitLabel = "mph";
    }

    final runwayNum = (runwayHeading / 10).toInt();
    final runwayNumOpp = runwayNum > 18 ? runwayNum - 18 : runwayNum + 18;
    final arrowRotation = (windDir - runwayHeading + 180) * (math.pi / 180.0);

    return SpringButton(
      child: _buildGlassCard(
        isDark: isDark,
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(color: theme.colorScheme.surface.withOpacity(isDark ? 0.05 : 0.5), shape: BoxShape.circle),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 12, height: 60,
                    decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(4)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(runwayNum.toString().padLeft(2,'0'), style: const TextStyle(color: Colors.white, fontSize: 8)),
                        Text(runwayNumOpp.toString().padLeft(2,'0'), style: const TextStyle(color: Colors.white, fontSize: 8)),
                      ],
                    ),
                  ),
                  Transform.rotate(
                    angle: arrowRotation,
                    child: const Icon(Icons.arrow_downward_rounded, color: Colors.orangeAccent, size: 40),
                  )
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("IDEAL RUNWAY ${runwayNum.toString().padLeft(2,'0')}", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.54), fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text("Wind ${windDir.toStringAsFixed(0)}@$windSpdDisplay$windUnitLabel", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildAiInsightCard(ThemeData theme) {
    return SpringButton(
      child: _buildGlassCard(
        isDark: theme.brightness == Brightness.dark,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 20),
                const SizedBox(width: 12),
                Text("Co-Pilot Insight", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              ],
            ),
            const SizedBox(height: 12),
            Text(_aiInsight, style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.8), height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, EdgeInsets padding = EdgeInsets.zero, required bool isDark}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05), width: 1),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withOpacity(0.1) : Colors.black.withOpacity(0.05), 
                blurRadius: 10
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
