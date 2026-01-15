import 'dart:ui';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../UI/AppAnimations.dart';

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
  String _errorMessage = '';

  String _currentAirportCode = "";
  late final TextEditingController _searchController;

  // Gemini AI
  GenerativeModel? _model;
  String _aiInsight = "";
  int? _aiSafetyScore;
  int _aiRequestId = 0; // To handle out-of-order responses

  // API Key for Gemini
  final String _apiKey = "AIzaSyBMO9xldoTR76KPYp6IKKTlUj-rThkCi84";

  static const Duration _geminiTimeout = Duration(seconds: 25);
  static const Duration _geminiRetryDelay = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();

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
    _searchController.dispose();
    super.dispose();
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

  Color _getScoreColor(int score) {
    if (score >= 90) return Colors.greenAccent;
    if (score >= 75) return Colors.lightGreenAccent;
    if (score >= 60) return Colors.yellowAccent;
    if (score >= 40) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  Map<String, dynamic> _getFallbackSafetyScore() {
    if (_metarData == null) return {'score': 0, 'color': Colors.grey};
    final cat = _metarData!['fltcat'] ?? 'VFR';
    switch (cat) {
      case 'VFR': return {'score': 95, 'color': Colors.greenAccent};
      case 'MVFR': return {'score': 75, 'color': Colors.yellowAccent};
      case 'IFR': return {'score': 50, 'color': Colors.orangeAccent};
      case 'LIFR': return {'score': 30, 'color': Colors.redAccent};
      default: return {'score': 0, 'color': Colors.grey};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A2F),
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
                color: const Color(0xFF0A84FF).withOpacity(0.15),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0A84FF).withOpacity(0.2),
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
                        _buildHeader(),
                        const SizedBox(height: 20),
                        // Search Bar
                        _buildAirportBar(),
                      ],
                    ),
                  ),
                ),

                // Content Area
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : !_hasSearched
                          ? _buildColdStartPlaceholder()
                          : _errorMessage.isNotEmpty
                              ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.redAccent, fontSize: 16)))
                              : RefreshIndicator(
                                  onRefresh: _fetchMetarData,
                                  color: Colors.white,
                                  backgroundColor: const Color(0xFF0A1A2F),
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    physics: const BouncingScrollPhysics(),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 1. Sun Phase
                                        StaggeredEntrance(index: 1, child: _buildSunPhaseWidget()),
                                        const SizedBox(height: 32),

                                        // 2. Safety Gauge
                                        StaggeredEntrance(index: 2, child: Center(child: _buildSafetyGauge())),
                                        const SizedBox(height: 32),

                                        // 3. Metrics Grid
                                        StaggeredEntrance(index: 3, child: _buildMetricsGrid()),
                                        const SizedBox(height: 24),

                                        // 4. Runway
                                        StaggeredEntrance(index: 4, child: _buildRunwayWidget()),
                                        const SizedBox(height: 24),

                                        // 5. AI Insight
                                        StaggeredEntrance(index: 5, child: _buildAiInsightCard()),
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

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Good Morning, Captain",
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withOpacity(0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Ready for departure?",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildAirportBar() {
    return SpringButton(
      child: _buildGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
          cursorColor: Colors.greenAccent,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: "Enter ICAO (e.g. KSFO)",
            hintStyle: TextStyle(color: Colors.white38),
            icon: Icon(Icons.location_on, color: Colors.greenAccent),
            suffixIcon: Icon(Icons.search, color: Colors.white),
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
    );
  }

  Widget _buildColdStartPlaceholder() {
    return StaggeredEntrance(
      index: 1,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 80, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              "Enter ICAO code to view intelligence",
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSunPhaseWidget() {
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

    String formatTime(DateTime dt) => "${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')} Z";

    // Animate Expansion
    return SpringButton(
      child: _buildGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Sunrise ${formatTime(sunrise)}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                Text(timeText, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                Text("Sunset ${formatTime(sunset)}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
                    color: Colors.white.withOpacity(0.1),
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

  Widget _buildSafetyGauge() {
    int score;
    Color color;

    if (_aiSafetyScore != null) {
      score = _aiSafetyScore!;
      color = _getScoreColor(score);
    } else {
      final fallback = _getFallbackSafetyScore();
      score = fallback['score'] as int;
      color = fallback['color'] as Color;
    }

    return SpringButton(
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: CircularProgressIndicator(
                value: 1.0,
                strokeWidth: 15,
                color: Colors.white.withOpacity(0.05),
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
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.0,
                  )
                ),
                Text(
                  _aiSafetyScore != null ? "AI SAFETY SCORE" : "EST. SCORE",
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
        ),
      ),
    );
  }

  Widget _buildMetricsGrid() {
    if (_metarData == null) return const SizedBox.shrink();

    // 1. Flight Category
    final fltcat = _metarData!['fltcat']?.toString() ?? 'N/A';
    Color catColor = Colors.white;
    switch (fltcat) {
      case 'VFR': catColor = Colors.greenAccent; break;
      case 'MVFR': catColor = Colors.blueAccent; break;
      case 'IFR': catColor = Colors.redAccent; break;
      case 'LIFR': catColor = Colors.purpleAccent; break;
      default: catColor = Colors.grey;
    }

    // 2. Altimeter
    final altimMb = _metarData!['altim'];
    String altimDisplay = "29.92 inHg";
    if (altimMb is num) {
      altimDisplay = "${(altimMb * 0.02953).toStringAsFixed(2)} inHg";
    }

    // 3. Temp / Dewp
    final temp = _metarData!['temp']?.toString() ?? '0';
    final dewp = _metarData!['dewp']?.toString() ?? '0';
    Color tempColor = Colors.white;
    try {
      final t = double.parse(temp);
      final d = double.parse(dewp);
      if ((t - d).abs() < 3) tempColor = Colors.orangeAccent;
    } catch (_) {}

    // 4. Wind
    dynamic rawDir = _metarData!['wdir'];
    dynamic rawSpd = _metarData!['wspd'];
    String windDirDisplay = rawDir is num ? "${rawDir.toString().padLeft(3, '0')}°" : "VRB";
    String windSpdDisplay = rawSpd?.toString() ?? "0";
    final windDisplay = "$windDirDisplay @ ${windSpdDisplay}kt";

    // 5. Sky
    String skyCond = "SKC";
    if (_metarData!.containsKey('clouds')) {
      final List<dynamic> clouds = _metarData!['clouds'] ?? [];
      if (clouds.isNotEmpty) {
        final layer = clouds[0];
        skyCond = "${layer['cover']} ${layer['base'] ?? ''}".trim();
      }
    } else {
       final cover = _metarData!['cover']?.toString() ?? 'SKC';
       final ceil = _metarData!['ceil'];
       final ceilStr = ceil != null ? (ceil as num).toInt().toString() : '';
       skyCond = "$cover $ceilStr".trim();
    }
    
    // 6. Vis / Wx
    final vis = _metarData!['visib']?.toString() ?? '10+';
    final wx = _metarData!['wx']?.toString() ?? '';

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.4,
      children: [
        _buildMetricCard("FLIGHT CAT", fltcat, icon: Icons.flight, color: catColor, isPill: true),
        _buildMetricCard("ALTIMETER", altimDisplay, icon: Icons.speed),
        _buildMetricCard("TEMP / DEWP", "$temp°C / $dewp°C", icon: Icons.thermostat, color: tempColor),
        _buildMetricCard("WIND", windDisplay, icon: Icons.air),
        _buildMetricCard("SKY COND", skyCond, icon: Icons.cloud),
        _buildMetricCard("VIS / WX", "$vis SM $wx".trim(), icon: Icons.visibility),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, {
    IconData? icon,
    Color color = Colors.white,
    bool isPill = false,
  }) {
    return SpringButton(
      child: _buildGlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.bold)),
                if (icon != null) Icon(icon, color: Colors.white.withOpacity(0.4), size: 16),
              ],
            ),
            if (isPill)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.5)),
                ),
                child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
              )
            else
              Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildRunwayWidget() {
    if (_metarData == null) return const SizedBox.shrink();
    
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

    final runwayNum = (runwayHeading / 10).toInt();
    final runwayNumOpp = runwayNum > 18 ? runwayNum - 18 : runwayNum + 18;
    final arrowRotation = (windDir - runwayHeading + 180) * (math.pi / 180.0);

    return SpringButton(
      child: _buildGlassCard(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
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
                  Text("IDEAL RUNWAY ${runwayNum.toString().padLeft(2,'0')}", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  // We simplified this for brevity as logic was preserved
                  Text("Wind ${windDir.toStringAsFixed(0)}@${windSpd.toStringAsFixed(0)}kt", style: const TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildAiInsightCard() {
    return SpringButton(
      child: _buildGlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 20),
                const SizedBox(width: 12),
                const Text("Co-Pilot Insight", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 12),
            Text(_aiInsight, style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8), height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, EdgeInsets padding = EdgeInsets.zero}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
          ),
          child: child,
        ),
      ),
    );
  }
}
