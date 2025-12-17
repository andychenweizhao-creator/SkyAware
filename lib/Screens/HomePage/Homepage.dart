import 'package:flutter/material.dart';
import 'package:skyaware/Service/metar_service.dart';
import 'dart:ui';
import '../../Service/WeatherEngine.dart';
import '../Login/login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _Homepage();
}

class _Homepage extends State<HomePage> {
  final TextEditingController airportController = TextEditingController();
  bool isloading = false;
  List<Map<String, dynamic>> riskFactors = [];
  List<String> positiveFactors = [];
  List<Map<String, dynamic>> decodedData = [];

  double safetyScore = 0.0;
  String safetyLabel = ""; // Start empty
  String flightCategory = "";

  final MetarJsonService _metarService = MetarJsonService();

  void _analyzeSafety(Map<String, dynamic> data) {
    final risks = <Map<String, dynamic>>[];
    final positives = <String>[];
    final decoded = <Map<String, dynamic>>[]; // Fixed type to dynamic

    double score = 10.0;
    String cat = "VFR";

    // --- DECODED FIELDS ---
    String raw = data['rawOb'] ?? "";
    String name = data['name'] ?? "";
    String icao = data['icaoId'] ?? "";
    String time = data['reportTime'] ?? "";

    decoded.add({"label": "METAR for", "value": "$icao ($name)"});
    decoded.add({"label": "Observed at", "value": time});

    // --- TEMP/DEW ---
    dynamic tempObj = data['temp'];
    dynamic dewpObj = data['dewp'];
    double? temp = (tempObj is num) ? tempObj.toDouble() : null;
    double? dewp = (dewpObj is num) ? dewpObj.toDouble() : null;

    if (temp != null) {
      double f = (temp * 9/5) + 32;
      decoded.add({"label": "Temperature", "value": "${temp}°C (${f.toStringAsFixed(0)}°F)"});
    }

    if (temp != null && dewp != null) {
      double fDew = (dewp * 9/5) + 32;
      double spread = temp - dewp;
      double rh = 100 - (5 * spread);
      if (rh > 100) rh = 100;

      decoded.add({"label": "Dewpoint", "value": "${dewp}°C (${fDew.toStringAsFixed(0)}°F)\nRH: ${rh.toStringAsFixed(0)}%"});

      if (spread <= 2.0) {
        score -= 2.0;
        risks.add({'msg': "High Fog Risk (Spread ≤ 2°C)", 'color': Colors.orange});
      } else {
        positives.add("Temp/Dew Spread Good");
      }
    }

    // --- ALTIMETER ---
    dynamic altObj = data['altim'];
    if (altObj is num) {
      double alt = altObj.toDouble(); // hPa
      double inHg = alt * 0.02953;
      decoded.add({"label": "Pressure", "value": "${inHg.toStringAsFixed(2)} inHg (${alt.round()} hPa)"});

      if (inHg < 29.80) risks.add({'msg': "Low Pressure (${inHg.toStringAsFixed(2)} inHg)", 'color': Colors.orangeAccent});
    }

    // --- WIND ---
    dynamic wspd = data['wspd'];
    dynamic wgst = data['wgst'];
    dynamic wdir = data['wdir'];
    double wind = (wspd is num) ? wspd.toDouble() : 0.0;
    double gust = (wgst is num) ? wgst.toDouble() : 0.0;
    String dir = (wdir is num) ? "${wdir}°" : "VRB";

    double mph = wind * 1.15078;
    String windStr = "$dir @ ${wind.round()} kt (${mph.toStringAsFixed(1)} mph)";
    if (gust > 0) windStr += "\nGusts ${gust.round()} kt";

    decoded.add({"label": "Winds", "value": windStr});

    if (wind > 30 || gust > 35) {
      score -= 5.0;
      risks.add({'msg': "Severe Winds", 'color': Colors.redAccent});
    } else if (wind > 20 || gust > 25) {
      score -= 3.0;
      risks.add({'msg': "Strong Winds", 'color': Colors.orangeAccent});
    } else {
      positives.add("Winds Manageable");
    }

    // --- VISIBILITY ---
    dynamic visObj = data['visib'];
    double? vis;
    if (visObj is num) vis = visObj.toDouble();
    else if (visObj is String) vis = double.tryParse(visObj.replaceAll('+', ''));

    if (vis != null) {
      decoded.add({"label": "Visibility", "value": "$vis SM"});

      if (vis < 1.0) {
        score -= 6.0;
        cat = "LIFR";
        risks.add({'msg': "Extreme Low Visibility ($vis SM)", 'color': Colors.red});
      } else if (vis < 3.0) {
        score -= 4.0;
        if (cat != "LIFR") cat = "IFR";
        risks.add({'msg': "IFR Visibility ($vis SM)", 'color': Colors.redAccent});
      } else if (vis <= 5.0) {
        score -= 2.0;
        if (cat == "VFR") cat = "MVFR";
        risks.add({'msg': "Marginal Visibility ($vis SM)", 'color': Colors.orange});
      } else {
        positives.add("Visibility Good");
      }
    }

    // --- CLOUDS ---
    double? ceiling;
    final clouds = data['clouds'];
    String cloudStr = "";
    if (clouds is List && clouds.isNotEmpty) {
      List<String> layers = [];
      for (var c in clouds) {
        final cover = c['cover']; 
        final base = c['base'];   
        String desc = cover.toString();
        if (base != null) {
          String ft = base.toString();
          layers.add("$desc $ft");
        }
        if ((cover == 'BKN' || cover == 'OVC') && base is num) {
          if (ceiling == null || base < ceiling) ceiling = base.toDouble();
        }
      }
      cloudStr = layers.join(", ");
    } else {
      cloudStr = "Sky Clear";
    }
    decoded.add({"label": "Clouds", "value": cloudStr});

    if (ceiling != null) {
      decoded.add({"label": "Ceiling", "value": "${ceiling.round()} ft"});

      if (ceiling < 500) {
        score -= 6.0;
        cat = "LIFR";
        risks.add({'msg': "LIFR Ceiling (${ceiling.round()} ft)", 'color': Colors.red});
      } else if (ceiling < 1000) {
        score -= 4.0;
        if (cat != "LIFR") cat = "IFR";
        risks.add({'msg': "IFR Ceiling (${ceiling.round()} ft)", 'color': Colors.redAccent});
      } else if (ceiling < 3000) {
        score -= 2.0;
        if (cat == "VFR") cat = "MVFR";
        risks.add({'msg': "MVFR Ceiling (${ceiling.round()} ft)", 'color': Colors.orange});
      } else {
        positives.add("Ceiling VFR");
      }
    }

    score = score.clamp(0.0, 10.0);
    String label;
    if (score >= 8.0) label = "SAFE";
    else if (score >= 5.0) label = "CAUTION";
    else label = "DANGER";

    setState(() {
      safetyScore = score / 10.0;
      safetyLabel = label;
      flightCategory = cat;
      riskFactors = risks;
      positiveFactors = positives;
      decodedData = decoded;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A2F),
      body: Stack(
        children: [
          // Global Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0A1A2F), Color(0xFF1C2C54), Color(0xFF0A1A2F)],
              ),
            ),
          ),
          // Orbs
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0A84FF).withOpacity(0.1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0A84FF).withOpacity(0.2),
                    blurRadius: 80.0,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 32),
                  _buildSearchBox(),
                  const SizedBox(height: 32),
                  if (safetyLabel.isNotEmpty) ...[
                     _buildResultCard(),
                     const SizedBox(height: 24),
                  ],
                  _buildLoginLink(),
                  const SizedBox(height: 100), // Bottom padding for nav bar
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Icon(Icons.flight_takeoff, color: Colors.white, size: 48),
        const SizedBox(height: 16),
        const Text(
          "SkyAware",
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -1.0,
          ),
        ),
        Text(
          "Aviation Intelligence System",
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBox() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              const Text(
                "Airport Safety Check",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: airportController,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black.withOpacity(0.2),
                  hintText: "Enter ICAO (e.g. KJFK)",
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isloading ? null : _handleSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A84FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: isloading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                        )
                      : const Text("Analyze Conditions", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSearch() async {
    setState(() {
      isloading = true;
      safetyLabel = ""; // Reset
    });

    final icao = airportController.text.trim().toUpperCase();
    if (icao.isEmpty) {
        setState(() => isloading = false);
        return;
    }
    
    final data = await _metarService.getMetarData(icao);

    if (data != null) {
      _analyzeSafety(data);
    } else {
      setState(() {
        safetyLabel = "NOT FOUND";
        safetyScore = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Airport not found or no data available")));
    }

    setState(() => isloading = false);
  }

  Widget _buildResultCard() {
    Color statusColor = Colors.grey;
    if (safetyLabel == "SAFE") statusColor = Colors.greenAccent;
    else if (safetyLabel == "CAUTION") statusColor = Colors.orangeAccent;
    else if (safetyLabel == "DANGER") statusColor = Colors.redAccent;
    else if (safetyLabel == "NOT FOUND") statusColor = Colors.grey;

    if (safetyLabel == "NOT FOUND") return const SizedBox.shrink();

    return Column(
      children: [
        // Score Circle
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: statusColor, width: 4),
            color: statusColor.withOpacity(0.1),
            boxShadow: [
               BoxShadow(color: statusColor.withOpacity(0.2), blurRadius: 20, spreadRadius: 5),
            ]
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                (safetyScore * 10).toStringAsFixed(1),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                safetyLabel,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "Flight Category: $flightCategory",
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 24),
        
        // Decoded Data Grid
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Conditions", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white10),
              ...decodedData.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item['label'], style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                    const SizedBox(width: 8),
                    Flexible(
                        child: Text(item['value'], 
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.right,
                    )),
                  ],
                ),
              )).toList(),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Risks
        if (riskFactors.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Risk Factors", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...riskFactors.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r['msg'], style: const TextStyle(color: Colors.white70, fontSize: 13))),
                    ],
                  ),
                )).toList(),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLoginLink() {
    return TextButton(
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginPage()));
      },
      child: Text(
        "Login for Flight Planning",
        style: TextStyle(color: Colors.white.withOpacity(0.5)),
      ),
    );
  }
}
