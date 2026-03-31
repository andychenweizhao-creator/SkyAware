import 'dart:ui';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../UI/AppAnimations.dart';
import '../../services/unit_settings_service.dart';
import '../../services/weather_service.dart'; // Added WeatherService
import '../../services/FirebaseService.dart';
import '../../main.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  User? _currentUser;
  StreamSubscription<User?>? _authSubscription;

  // State
  bool _isLoading = false;
  bool _hasSearched = false; // Tracks Cold Start state
  Map<String, dynamic>? _metarData;
  double? _lat;
  double? _lon;
  int _utcOffsetSeconds = 0; // Added for Location Local Time
  String _errorMessage = '';
  String? _gpsLocationName; // Current User Location
  int _searchRadius = 25; // Default to 25 nm (Updated to match Dashboard)

  String _currentAirportCode = "";
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  bool _isSearchEditMode = false;
  Set<String> _selectedSearches = {};

  // Clock State
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  // Gemini AI
  HttpsCallable? _aiCallable;
  String _aiInsight = "";
  int? _aiSafetyScore;
  int _aiRequestId = 0; // To handle out-of-order responses



  static const Duration _geminiTimeout = Duration(seconds: 25);
  static const Duration _geminiRetryDelay = Duration(milliseconds: 600);

  // Nearest Airport Algorithm State
  String? _nearestAirportIcao;
  double? _nearestAirportDist;
  String? _nearestAirportCategory;
  Timer? _weatherTimer;

  // New Local Search State
  // List<Map<String, dynamic>> _foundAirports = []; // Moved to Sheet Widget
  // bool _isSearchingAirports = false; // Moved to Sheet Widget
  String? _cachedDatabaseContent; // Kept for caching

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    // Initialize synchronously before listening to changes
    _currentUser = FirebaseAuth.instance.currentUser;

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
      }
    });

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


    _aiCallable = FirebaseFunctions.instance.httpsCallable('askGemini');
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _clockTimer?.cancel();
    _weatherTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Good Morning';
    } else if (hour >= 12 && hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  // --- Nearest Airport Algorithm (Background) ---

  Future<void> _updateNearestAirport() async {
    if (_lat == null || _lon == null) return;

    if (_cachedDatabaseContent == null) {
      try {
        _cachedDatabaseContent = await rootBundle.loadString('assets/GlobalAirportDatabase.txt');
      } catch (e) {
        debugPrint("Error loading DB: $e");
        return;
      }
    }

    final params = {
      'content': _cachedDatabaseContent,
      'lat': _lat,
      'lon': _lon,
      'radius': _searchRadius.toDouble(),
    };

    try {
      final results = await compute(_calculateNearestAirports, params);
      
      if (mounted) {
        setState(() {
          if (results.isNotEmpty) {
            _nearestAirportIcao = results.first['icao'];
            _nearestAirportDist = results.first['distance'];
            _fetchNearestAirportStatus(); // Fetch METAR for category
          } else {
            _nearestAirportIcao = null;
            _nearestAirportDist = null;
            _nearestAirportCategory = null;
          }
        });
      }
    } catch (e) {
      debugPrint("Compute error in Homepage: $e");
    }
  }

  Future<void> _fetchNearestAirportStatus() async {
    if (_nearestAirportIcao == null) return;
    try {
      final response = await http.get(
        Uri.parse('https://aviationweather.gov/api/data/metar?ids=$_nearestAirportIcao&format=geojson&taf=false&hours=0&_=${DateTime.now().millisecondsSinceEpoch}'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;
        if (features.isNotEmpty) {
          final properties = features[0]['properties'];
          final String? category = properties['fltcat'];
          if (mounted) {
            setState(() {
              _nearestAirportCategory = category;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching status for nearest airport: $e");
    }
  }

  // --- End Nearest Airport Algorithm ---

  // --- New Fully Self-Contained Local Search Feature ---

  void _showNearestAirportsList(BuildContext context) {
    if (_lat == null || _lon == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location not available yet.")));
       return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NearestAirportsSheet(
        userLat: _lat!,
        userLon: _lon!,
        initialRadius: _searchRadius,
        onAirportSelected: (icao) {
          Navigator.pop(ctx);
          setState(() { 
             _currentAirportCode = icao;
             _searchController.text = icao;
          });
          _fetchMetarData();
        },
      ),
    );
  }

  // --- End New Feature ---

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
      
      if (mounted) {
        setState(() {
          _lat = position.latitude;
          _lon = position.longitude;
        });
        
        // Trigger Nearest Airport Search once location is found
        _updateNearestAirport();
      }

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

            // Save the valid airport search to Firebase
            Firebaseservice().saveAirportSearch(_currentAirportCode);

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
    if (_aiCallable == null) {
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

      final requestData = <String, dynamic>{'prompt': prompt};

      // Retry logic for Firebase Function
      HttpsCallableResult response;
      try {
        response = await _aiCallable!.call(requestData).timeout(_geminiTimeout);
      } on TimeoutException {
        await Future.delayed(_geminiRetryDelay);
        response = await _aiCallable!.call(requestData).timeout(_geminiTimeout);
      }

      if (!mounted || requestId != _aiRequestId) return;

      // Extract text from the backend response
      final text = (response.data['result'] ?? response.data['response']) as String?;
      if (text == null) return;

      // Robust Regex Parsing
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

    } on FirebaseFunctionsException catch (e) {
      debugPrint("Firebase Functions Exception: ${e.code} - ${e.message} - ${e.details}");
      if (mounted && requestId == _aiRequestId) {
        setState(() {
          _aiInsight = "Firebase Error [${e.code}]: ${e.message}\nDetails: ${e.details}";
        });
      }
    } catch (e) {
      debugPrint("Firebase Function Error: $e");
      if (mounted && requestId == _aiRequestId) {
        setState(() {
          _aiInsight = "Co-Pilot offline. Error: $e";
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

  Widget _buildRecentSearches(ThemeData theme, bool isDark) {
    if (!_searchFocusNode.hasFocus) {
      // Reset edit mode silently if they click away from the search bar
      _isSearchEditMode = false;
      _selectedSearches.clear();
      return const SizedBox.shrink();
    }

    if (_currentUser == null || _currentUser!.isAnonymous) {
      return const SizedBox.shrink(); 
    }

    return StreamBuilder<DocumentSnapshot>(
      key: ValueKey(_currentUser!.uid),
      stream: FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
        
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null || !data.containsKey('recent_airports')) return const SizedBox.shrink();

        List<dynamic> recents = data['recent_airports'];
        if (recents.isEmpty) return const SizedBox.shrink();

        final displayList = recents.reversed.toList();

        return Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, 4))
              ],
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header (Only shows in Edit Mode)
                if (_isSearchEditMode)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8, top: 8, bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: _selectedSearches.length == displayList.length,
                              activeColor: theme.primaryColor,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedSearches = displayList.map((e) => e.toString()).toSet();
                                  } else {
                                    _selectedSearches.clear();
                                  }
                                });
                              },
                            ),
                            Text("Select All", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isSearchEditMode = false;
                              _selectedSearches.clear();
                            });
                          },
                          child: Text("Cancel", style: TextStyle(color: theme.primaryColor)),
                        )
                      ],
                    ),
                  ),

                // Main List
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: _isSearchEditMode ? 168 : 112),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: displayList.length,
                    itemBuilder: (context, index) {
                      final icao = displayList[index].toString();
                      final isSelected = _selectedSearches.contains(icao);

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            if (_isSearchEditMode) {
                              setState(() {
                                if (isSelected) _selectedSearches.remove(icao);
                                else _selectedSearches.add(icao);
                              });
                            } else {
                              FocusManager.instance.primaryFocus?.unfocus();
                              _searchController.text = icao;
                              setState(() => _currentAirportCode = icao);
                              _fetchMetarData();
                            }
                          },
                          child: SizedBox(
                            height: 56,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  if (_isSearchEditMode)
                                    Checkbox(
                                      value: isSelected,
                                      activeColor: theme.primaryColor,
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) _selectedSearches.add(icao);
                                          else _selectedSearches.remove(icao);
                                        });
                                      },
                                    )
                                  else
                                    Icon(Icons.history, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                                  
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(icao, style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurface, fontWeight: FontWeight.w500)),
                                  ),
                                  
                                  if (!_isSearchEditMode)
                                    Icon(Icons.north_west, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Footer (Action Buttons)
                const Divider(height: 1),
                if (_isSearchEditMode)
                  InkWell(
                    onTap: _selectedSearches.isEmpty ? null : () async {
                      await Firebaseservice().removeSelectedSearches(_selectedSearches.toList());
                      setState(() {
                        _selectedSearches.clear();
                        _isSearchEditMode = false;
                      });
                    },
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      child: Text(
                        "Delete Selected (${_selectedSearches.length})", 
                        style: TextStyle(color: _selectedSearches.isEmpty ? Colors.grey : Colors.redAccent, fontWeight: FontWeight.bold)
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _isSearchEditMode = true),
                          child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            child: Text("Edit", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      Container(width: 1, height: 24, color: Colors.grey.withOpacity(0.3)),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            await Firebaseservice().clearAllAirportSearches();
                            FocusManager.instance.primaryFocus?.unfocus();
                          },
                          child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            child: const Text("Clear All", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final aviationColors = Theme.of(context).extension<AviationColors>()!;
    
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
                        
                        // Recent Searches
                        _buildRecentSearches(theme, isDark),

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
                  "${_getGreeting()}, Captain",
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
                focusNode: _searchFocusNode,
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
        // Replaced Button (New Style)
        _GlassLocateButton(
          onPressed: () => _showNearestAirportsList(context),
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
    final aviationColors = Theme.of(context).extension<AviationColors>()!;

    // 1. Flight Category
    final fltcat = _metarData!['fltcat']?.toString() ?? 'N/A';
    Color catColor = theme.colorScheme.onSurface;
    switch (fltcat) {
      case 'VFR': catColor = aviationColors.vfr ?? Colors.green; break;
      case 'MVFR': catColor = aviationColors.mvfr ?? Colors.blue; break;
      case 'IFR': catColor = aviationColors.ifr ?? Colors.red; break;
      case 'LIFR': catColor = aviationColors.lifr ?? Colors.purple; break;
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

// Re-designed Square Button
class _GlassLocateButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _GlassLocateButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // Determine Theme Brightness
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final aviationColors = Theme.of(context).extension<AviationColors>()!;

    // --- COLOR LOGIC ---
    // Dark Mode: Background = Charcoal (0xFF333333), Icon = Light Blue Accent
    // Light Mode: Background = White, Icon = Deep Blue (Colors.blue)
    final Color bgColor = aviationColors.mapButtonBg ?? (isDark ? const Color(0xFF333333) : Colors.white);
    final Color iconColor = aviationColors.mapButtonIcon ?? (isDark ? Colors.lightBlueAccent : Colors.blue);
    
    // --- SHADOW LOGIC ---
    // Subtle shadow in Light Mode to pop against map/background
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
             offset: const Offset(0, 2), // Slight downward shadow
           )
        ];

    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16), // Rounded Square
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor.withOpacity(0.9), // Slightly opaque for glass effect
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.2) : Colors.grey.withOpacity(0.1), 
                width: 1
              ),
              boxShadow: shadows,
            ),
            child: Icon(Icons.my_location, color: iconColor, size: 28),
          ),
        ),
      ),
    );
  }
}

class NearestAirportsSheet extends StatefulWidget {
  final double userLat;
  final double userLon;
  final int initialRadius;
  final ValueChanged<String> onAirportSelected;

  const NearestAirportsSheet({
    super.key,
    required this.userLat,
    required this.userLon,
    required this.initialRadius,
    required this.onAirportSelected,
  });

  @override
  State<NearestAirportsSheet> createState() => _NearestAirportsSheetState();
}

class _NearestAirportsSheetState extends State<NearestAirportsSheet> {
  late int _currentRadius;
  List<Map<String, dynamic>> _foundAirports = [];
  bool _isSearching = true;
  String? _dbContent;
  Map<String, String> _airportCategories = {};
  Timer? _categoryTimer;

  @override
  void initState() {
    super.initState();
    _currentRadius = widget.initialRadius;
    _loadDbAndSearch();
    
    // Auto-Refresh Categories every 20 minutes
    _categoryTimer = Timer.periodic(const Duration(minutes: 20), (_) {
      _fetchCategories();
    });
  }

  @override
  void dispose() {
    _categoryTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDbAndSearch() async {
    try {
      _dbContent = await rootBundle.loadString('assets/GlobalAirportDatabase.txt');
      _searchAirports();
    } catch (e) {
      debugPrint("DB Load Error: $e");
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _searchAirports() async {
    if (!mounted || _dbContent == null) return;
    setState(() => _isSearching = true);

    final params = {
      'content': _dbContent,
      'lat': widget.userLat,
      'lon': widget.userLon,
      'radius': _currentRadius.toDouble(),
    };

    try {
      final results = await compute(_calculateNearestAirports, params);
      if (mounted) {
        setState(() {
          _foundAirports = results;
          _isSearching = false;
        });
        _fetchCategories();
      }
    } catch (e) {
      debugPrint("Search Error: $e");
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _fetchCategories() async {
    if (_foundAirports.isEmpty) return;
    
    final codes = _foundAirports.map((a) => a['icao'] as String).toList();
    
    try {
      final categories = await WeatherService.getFlightCategories(codes);
      if (mounted) {
        setState(() {
          _airportCategories = categories;
        });
      }
    } catch (e) {
      debugPrint("Category Fetch Error: $e");
    }
  }

  void _updateRadius(int newRadius) {
    setState(() {
      _currentRadius = newRadius;
    });
    _searchAirports();
  }

  Color _getCategoryColor(String? cat, AviationColors colors) {
    if (cat == null) return Colors.grey;
    switch (cat.toUpperCase()) {
      case 'VFR': return colors.vfr ?? Colors.green;
      case 'MVFR': return colors.mvfr ?? Colors.blue;
      case 'IFR': return colors.ifr ?? Colors.red;
      case 'LIFR': return colors.lifr ?? Colors.purple;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final aviationColors = Theme.of(context).extension<AviationColors>()!;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
      ),
      child: Column(
        children: [
           // Handle
           Center(
             child: Container(
               width: 40, height: 4, 
               margin: const EdgeInsets.symmetric(vertical: 12), 
               decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), borderRadius: BorderRadius.circular(2))
             )
           ),
           
           // Header
           Padding(
             padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
             child: Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 Row(
                   children: [
                     Icon(Icons.radar, color: theme.primaryColor),
                     const SizedBox(width: 8),
                     Text("Nearby Airports", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                   ],
                 ),
                 // Custom Dropdown Button
                 PopupMenuButton<int>(
                    initialValue: _currentRadius,
                    offset: const Offset(0, 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    color: aviationColors.distanceMenuBg ?? (isDark ? const Color(0xFF2C2C2C) : Colors.white),
                    onSelected: _updateRadius,
                    itemBuilder: (context) => [10, 25, 50, 100].map((r) => PopupMenuItem(
                      value: r,
                      child: Text("$r nm", style: TextStyle(fontWeight: FontWeight.bold, color: aviationColors.distanceMenuText ?? theme.colorScheme.onSurface)),
                    )).toList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Text("$_currentRadius nm", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 4),
                          Icon(Icons.keyboard_arrow_down, color: theme.primaryColor, size: 16),
                        ],
                      ),
                    ),
                 ),
               ],
             ),
           ),
           const Divider(),
           
           // List Content
           Expanded(
              child: _isSearching 
                ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                : _foundAirports.isEmpty 
                  ? Center(child: Text("No airports found within $_currentRadius nm.", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _foundAirports.length,
                      itemBuilder: (context, index) {
                         final apt = _foundAirports[index];
                         final double dist = apt['distance'];
                         final cat = _airportCategories[apt['icao']];
                         
                         return InkWell(
                            onTap: () => widget.onAirportSelected(apt['icao']),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              child: Row(
                                children: [
                                  // Distance
                                  SizedBox(
                                    width: 60,
                                    child: Text(
                                      "${dist.toStringAsFixed(1)} nm",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: theme.primaryColor,
                                      ),
                                    ),
                                  ),
                                  // Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              apt['icao'],
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: theme.colorScheme.onSurface,
                                              ),
                                            ),
                                            if (cat != null) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: _getCategoryColor(cat, aviationColors).withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: _getCategoryColor(cat, aviationColors), width: 1),
                                                ),
                                                child: Text(
                                                  cat,
                                                  style: TextStyle(
                                                    color: _getCategoryColor(cat, aviationColors),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ]
                                          ],
                                        ),
                                        Text(
                                          apt['name'],
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.chevron_right, color: theme.colorScheme.onSurface.withOpacity(0.3), size: 18),
                                ],
                              ),
                            ),
                         );
                      },
                  )
           )
        ],
      ),
    );
  }
}

// --- Top Level Isolate Function for compute() ---
List<Map<String, dynamic>> _calculateNearestAirports(Map<String, dynamic> params) {
  final String fileContent = params['content'];
  final double userLat = params['lat'];
  final double userLon = params['lon'];
  final double radiusNm = params['radius'];
  final double radiusMeters = radiusNm * 1852.0;

  final List<String> lines = const LineSplitter().convert(fileContent);
  final List<Map<String, dynamic>> results = [];

  for (String line in lines) {
    if (line.trim().isEmpty) continue;
    final parts = line.split(':');
    if (parts.length < 14) continue;

    String name = parts[2].trim();
    String nameUpper = name.toUpperCase();
    if (nameUpper.contains("HELIPORT") || nameUpper.contains("HELIPAD") || nameUpper.contains("HELI ")) continue;
    if (nameUpper.contains("SEAPLANE") || nameUpper.contains(" SPB ") || nameUpper.contains("FLOATPLANE")) continue;
    if (nameUpper.contains("STATION") || nameUpper.contains("TRAIN")) continue;

    int latDeg = int.tryParse(parts[5]) ?? 0;
    int latMin = int.tryParse(parts[6]) ?? 0;
    int latSec = int.tryParse(parts[7]) ?? 0;
    String latDir = parts[8].toUpperCase();

    int lonDeg = int.tryParse(parts[9]) ?? 0;
    int lonMin = int.tryParse(parts[10]) ?? 0;
    int lonSec = int.tryParse(parts[11]) ?? 0;
    String lonDir = parts[12].toUpperCase();

    double lat = latDeg + (latMin / 60.0) + (latSec / 3600.0);
    if (latDir == 'S') lat = -lat;

    double lon = lonDeg + (lonMin / 60.0) + (lonSec / 3600.0);
    if (lonDir == 'W') lon = -lon;

    if (lat == 0.0 && lon == 0.0) continue;

    // Simple bounding box check (optimization)
    // 1 deg lat ~= 60nm. 
    if ((lat - userLat).abs() > (radiusNm / 30.0)) continue; 
    if ((lon - userLon).abs() > (radiusNm / 30.0)) continue; 

    double distMeters = _haversineDistanceTop(userLat, userLon, lat, lon);
    if (distMeters <= radiusMeters) {
      String icao = parts[0];
      if (icao == 'N/A') icao = parts[1];
      if (icao == 'N/A' || icao.isEmpty) continue;

      results.add({
        'icao': icao,
        'name': name,
        'distance': distMeters / 1852.0, 
      });
    }
  }

  results.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
  return results;
}

double _haversineDistanceTop(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    const c = math.cos;
    final a = 0.5 - c((lat2 - lat1) * p)/2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p))/2;
    return 12742 * math.asin(math.sqrt(a)) * 1000;
}