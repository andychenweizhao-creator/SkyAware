import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';

// Placeholder for Gemini API Key - Replace with your actual key
const String _kGeminiApiKey = 'AIzaSyB_nwHRCKO9RgAgOXTPfeL5o_UbL3GW3X4';

class Weather extends StatefulWidget {
  const Weather({super.key});

  @override
  State<Weather> createState() => _WeatherState();
}

class _WeatherState extends State<Weather> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Hazard Data State
  List<dynamic> _fetchedData = [];
  bool _isLoading = false;
  bool _is204 = false;
  String? _error;
  final TextEditingController _levelController = TextEditingController();

  // AI State
  String? _aiSummary;
  bool _isAiLoading = false;
  late final GenerativeModel _model;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad));

    _controller.forward();

    // Initialize Gemini Model
    // Using 'gemini-3-pro-preview' as requested
    _model = GenerativeModel(
      model: 'gemini-3-pro-preview',
      apiKey: _kGeminiApiKey,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _levelController.dispose();
    super.dispose();
  }

  Future<void> _fetchHazardData(String type) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _fetchedData = [];
      _is204 = false;
      _aiSummary = null; // Reset AI summary
      _isAiLoading = false;
    });

    // Get level from input, default to 200 if empty
    String level = _levelController.text.trim();
    if (level.isEmpty) {
      level = "200";
    }

    // Determine URL based on button type
    Uri uri;
    switch (type) {
      case 'conv':
        // SIGMET for Convection with Level
        uri = Uri.parse('https://aviationweather.gov/api/data/airsigmet?format=json&types=sigmet&hazard=conv');
        break;
      case 'ice':
        // G-AIRMET for Icing with Level
        uri = Uri.parse('https://aviationweather.gov/api/data/gairmet?format=json&hazard=ice');
        break;
      case 'turb':
        // Determine whether to use turb-lo or turb-hi based on altitude
        int val = int.tryParse(level) ?? 0;

        // Heuristic: If input is likely a Flight Level (e.g., 200), convert to feet (20000).
        // If the user entered feet directly (e.g., 20000), use as is.
        // Threshold: 1000. If < 1000, assume FL.
        int altitudeFeet = (val < 1000) ? val * 100 : val;

        // Check condition: >= 18000 ft is High Level
        if (altitudeFeet >= 18000) {
           uri = Uri.parse('https://aviationweather.gov/api/data/gairmet?product=tango&format=json&hazard=turb-hi&fore=3&level=$level');
        } else {
           uri = Uri.parse('https://aviationweather.gov/api/data/gairmet?product=tango&format=json&hazard=turb-lo&fore=3&level=$level');
        }
        break;
      case 'mtn_obs':
        // Mountain Obscuration
        uri = Uri.parse('https://aviationweather.gov/api/data/gairmet?format=json&hazard=mtn_obs&fore=3&level=$level');
        break;
      case 'ifr':
        // IFR
        uri = Uri.parse('https://aviationweather.gov/api/data/gairmet?format=json&hazard=ifr&fore=3&level=$level');
        break;
      case 'llws':
        // Low Level Wind Shear
        uri = Uri.parse('https://aviationweather.gov/api/data/gairmet?product=tango&format=json&hazard=llws&fore=3&level=$level');
        break;
      case 'sfc_wind':
        // Surface Wind
        uri = Uri.parse('https://aviationweather.gov/api/data/gairmet?product=tango&format=json&hazard=sfc_wind&fore=3&level=$level');
        break;
      case 'tcf':
        // TCF (Traffic Flow Management Convective Forecast) - Raw Format
        uri = Uri.parse('https://aviationweather.gov/api/data/tcf?format=raw');
        break;
      default:
        // Fallback
        uri = Uri.parse('https://aviationweather.gov/api/data/airsigmet?format=json&level=$level');
    }

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        dynamic data;
        try {
          // Try to parse as JSON
          data = json.decode(response.body);
          // Ensure it's a list for UI compatibility
          if (data is! List) {
            data = [data];
          }
        } catch (e) {
          // If JSON decoding fails, treat as raw text
          data = [{"raw_text": response.body}];
        }

        if (mounted) {
          setState(() {
            _fetchedData = data as List<dynamic>;
            _isLoading = false;
          });

          // Trigger AI Analysis if data exists
          if (_fetchedData.isNotEmpty && _kGeminiApiKey != 'YOUR_GEMINI_API_KEY_HERE') {
            _analyzeWithGemini(_fetchedData);
          } else if (_kGeminiApiKey == 'YOUR_GEMINI_API_KEY_HERE') {
             setState(() {
               _aiSummary = "Gemini API Key missing. Please update source code.";
             });
          }
        }
      } else if (response.statusCode == 204) {
        if (mounted) {
          setState(() {
            _fetchedData = [];
            _is204 = true;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load data: ${response.statusCode}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Network error: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _analyzeWithGemini(List<dynamic> data) async {
    setState(() {
      _isAiLoading = true;
    });

    try {
      // Limit data size if necessary to avoid token limits, take first 5 items if list is huge
      final subset = data.length > 5 ? data.sublist(0, 5) : data;
      final jsonString = json.encode(subset);

      final prompt = "You are an aviation weather expert. I will provide raw JSON data containing SIGMETs, G-AIRMETs, or TCF forecasts. Your job is to parse the coordinates and abbreviations and output a concise summary. Specifically: Identify the geographic locations (convert lat/long polygons to nearby US States or major cities) and specify the Altitudes (Ceiling/Floor) and Severity. Format it for a pilot to read quickly. Here is the data: $jsonString";

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      if (mounted) {
        setState(() {
          _aiSummary = response.text;
          _isAiLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiSummary = "AI Analysis Failed: $e";
          _isAiLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A2F),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Live Weather Data', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
           // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0A1A2F), Color(0xFF1C2C54), Color(0xFF0A1A2F)],
              ),
            ),
          ),
          // Decorative Orbs
           Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0A84FF).withOpacity(0.15),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0A84FF).withOpacity(0.2),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
           Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7D2AE8).withOpacity(0.15),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7D2AE8).withOpacity(0.2),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      _buildHazardSection(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHazardSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Multi-Hazard Inspector (AWC Mix)",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          // Level Input
          TextField(
            controller: _levelController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Flight Level (e.g. 200)',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              filled: true,
              fillColor: Colors.black.withOpacity(0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          // Action Buttons using Wrap
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              _buildHazardButton("Conv (SIGMET)", "conv", Colors.redAccent),
              _buildHazardButton("Ice (G-AIRMET)", "ice", Colors.cyanAccent),
              _buildHazardButton("Turb (G-AIRMET)", "turb", Colors.orangeAccent),
              _buildHazardButton("Mtn Obs", "mtn_obs", Colors.brown),
              _buildHazardButton("IFR", "ifr", Colors.purpleAccent),
              _buildHazardButton("LLWS", "llws", Colors.yellowAccent),
              _buildHazardButton("surf-wind", "sfc_wind", Colors.tealAccent),
              _buildHazardButton("TCF", "tcf", Colors.indigoAccent),
            ],
          ),
          const SizedBox(height: 10),

          // AI Summary Section
          if (_isAiLoading || _aiSummary != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.indigoAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigoAccent.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text("🤖 AI Summary (Gemini)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_isAiLoading)
                    const Center(child: LinearProgressIndicator())
                  else
                    Text(
                      _aiSummary ?? "",
                      style: const TextStyle(color: Colors.white70),
                    ),
                ],
              ),
            ),
          ],

          // Results Area
          Container(
            height: 300,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : SingleChildScrollView(
                        child: SelectableText(
                          _is204
                              ? "No active hazards found at this level (Status 204)."
                              : _fetchedData.isEmpty
                                  ? "Enter level and select a hazard to fetch data."
                                  : const JsonEncoder.withIndent('  ').convert(_fetchedData),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'Courier',
                            fontSize: 12,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHazardButton(String label, String type, Color color) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 100),
      child: ElevatedButton(
        onPressed: () => _fetchHazardData(type),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.2),
          foregroundColor: color,
          side: BorderSide(color: color),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
