import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:percent_indicator/percent_indicator.dart';
import '../../Service/metar_service.dart';
import '../../Service/openai_service.dart';
import 'dart:math' as math;

class HomePage_1 extends StatefulWidget {
  const HomePage_1({super.key, required this.title});
  State<HomePage_1> createState() => _MyHomePageState();

  final String title;
}

class _MyHomePageState extends State<HomePage_1> {
  TextEditingController airportController = TextEditingController();
  double safetyScore = 0.0;
  String safetyLabel = "READY";
  String flightCategory = "";
  
  List<Map<String, dynamic>> riskFactors = []; 
  List<String> positiveFactors = [];
  
  // Structured Data for "Decoded" View
  List<Map<String, String>> decodedData = [];

  bool isLoading = false;

  final MetarJsonService _metarService = MetarJsonService();

  void _analyzeSafety(Map<String, dynamic> data) {
    final risks = <Map<String, dynamic>>[];
    final positives = <String>[];
    final decoded = <Map<String, String>>[];
    
    double score = 10.0;
    String cat = "VFR";

    // --- DECODED FIELDS ---
    String raw = data['rawOb'] ?? "";
    String name = data['name'] ?? "";
    String icao = data['icaoId'] ?? "";
    String time = data['reportTime'] ?? "";
    
    decoded.add({"label": "METAR for:", "value": "$icao ($name)"});
    decoded.add({"label": "Text:", "value": raw});
    decoded.add({"label": "Conditions at:", "value": time});

    // --- TEMP/DEW ---
    dynamic tempObj = data['temp'];
    dynamic dewpObj = data['dewp'];
    double? temp = (tempObj is num) ? tempObj.toDouble() : null;
    double? dewp = (dewpObj is num) ? dewpObj.toDouble() : null;

    if (temp != null) {
       double f = (temp * 9/5) + 32;
       decoded.add({"label": "Temperature:", "value": "${temp}°C (${f.toStringAsFixed(0)}°F)"});
    }
    
    if (temp != null && dewp != null) {
      double fDew = (dewp * 9/5) + 32;
      double spread = temp - dewp;
      double rh = 100 - (5 * spread);
      if (rh > 100) rh = 100;
      
      decoded.add({"label": "Dewpoint:", "value": "${dewp}°C (${fDew.toStringAsFixed(0)}°F) (RH = ${rh.toStringAsFixed(0)}%)"});

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
        decoded.add({"label": "Pressure (altimeter):", "value": "${inHg.toStringAsFixed(2)} inHg (${alt.round()} hPa)"});
        
        if (inHg < 29.80) risks.add({'msg': "Low Pressure (${inHg.toStringAsFixed(2)} inHg)", 'color': Colors.orangeAccent});
    }

    // --- WIND ---
    dynamic wspd = data['wspd'];
    dynamic wgst = data['wgst'];
    dynamic wdir = data['wdir'];
    double wind = (wspd is num) ? wspd.toDouble() : 0.0;
    double gust = (wgst is num) ? wgst.toDouble() : 0.0;
    String dir = (wdir is num) ? "${wdir}°" : "VRB";
    
    // Convert to MPH for display style matching
    double mph = wind * 1.15078;
    
    String windStr = "from the $dir at ${wind.round()} kt (${(wind*0.514).toStringAsFixed(1)} m/s, ${mph.toStringAsFixed(1)} mph)";
    if (gust > 0) windStr += " Gusting ${gust.round()} kt";
    
    decoded.add({"label": "Winds:", "value": windStr});

    if (wind > 30 || gust > 35) {
      score -= 5.0;
      risks.add({'msg': "Severe Winds ($dir @ ${wind.round()}G${gust.round()}kt)", 'color': Colors.redAccent});
    } else if (wind > 20 || gust > 25) {
      score -= 3.0;
      risks.add({'msg': "Strong Winds ($dir @ ${wind.round()}G${gust.round()}kt)", 'color': Colors.orangeAccent});
    } else {
      positives.add("Winds Manageable");
    }

    // --- VISIBILITY ---
    dynamic visObj = data['visib'];
    double? vis;
    if (visObj is num) vis = visObj.toDouble();
    else if (visObj is String) vis = double.tryParse(visObj.replaceAll('+', ''));

    if (vis != null) {
        double km = vis * 1.60934;
        decoded.add({"label": "Visibility:", "value": "$vis+ mi ($km+ km)"}); // mimicking "10+ mi" style
        
        if (vis < 1.0) {
            score -= 6.0;
            cat = "LIFR";
            risks.add({'msg': "Extreme Low Visibility ($vis SM)", 'color': Colors.red});
        } else if (vis < 3.0) {
            score -= 4.0;
            if (cat != "LIFR") cat = "IFR";
            risks.add({'msg': "Visibility < VFR Minimums ($vis SM)", 'color': Colors.redAccent});
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
        final cover = c['cover']; // SCT, BKN
        final base = c['base'];   // 2200
        
        // Convert cover code to full text if desired, e.g. SCT -> scattered clouds
        String desc = cover.toString().toLowerCase();
        if (desc == 'sct') desc = "scattered clouds";
        if (desc == 'bkn') desc = "broken clouds";
        if (desc == 'ovc') desc = "overcast";
        if (desc == 'few') desc = "few clouds";
        
        if (base != null) {
            // Format: "scattered clouds at 2,200 ft"
            // Add commas to number
            // base is typically int
            String ft = base.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
            layers.add("$desc at $ft ft");
        }
        
        // Ceiling logic
        if ((cover == 'BKN' || cover == 'OVC') && base is num) {
          if (ceiling == null || base < ceiling) ceiling = base.toDouble();
        }
      }
      cloudStr = layers.join(", ");
    } else {
      cloudStr = "sky clear";
    }
    decoded.add({"label": "Clouds:", "value": cloudStr});

    if (ceiling != null) {
      String cFt = ceiling.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
      decoded.add({"label": "Ceiling:", "value": "$cFt ft"});
      
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
    } else {
      // If clear, maybe dont show Ceiling line? Or show "none"?
      // Screenshot doesn't show "Ceiling" if none, but shows "Ceiling: 7,000 ft" if exists.
      // Let's skip adding it if null.
    }

    // --- WEATHER ---
    String wxString = (data['wxString'] ?? "").toString();
    // Decode codes? e.g. -RA -> light rain
    // Simple map for common ones
    String wxDecoded = wxString;
    if (wxString.contains("-RA")) wxDecoded = "light rain";
    else if (wxString.contains("+RA")) wxDecoded = "heavy rain";
    else if (wxString.contains("RA")) wxDecoded = "rain";
    else if (wxString.contains("TS")) wxDecoded = "thunderstorm";
    
    if (wxDecoded.isNotEmpty) {
        decoded.add({"label": "Weather:", "value": wxDecoded});
        
        if (wxString.contains("TS")) {
            score -= 8.0;
            risks.add({'msg': "Thunderstorms Reported", 'color': Colors.red});
        } else if (wxString.contains("FZ") || wxString.contains("SN")) {
            score -= 6.0;
            risks.add({'msg': "Winter Precip Detected", 'color': Colors.red});
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

  Color _getCategoryColor(String cat) {
    switch (cat) {
      case 'LIFR': return Colors.purpleAccent;
      case 'IFR': return Colors.redAccent;
      case 'MVFR': return Colors.blueAccent;
      case 'VFR': return Colors.greenAccent;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6), Color(0xFF7D2AE8)],
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 40, left: 10),
            child: Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          "SkyAware",
                          style: TextStyle(
                            fontSize: 60,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.5,
                            foreground: Paint()
                              ..shader = const LinearGradient(
                                colors: [Color(0xFF66D1FF), Color(0xFF00FFA3)],
                              ).createShader(const Rect.fromLTWH(0, 0, 300, 80)),
                            shadows: const [Shadow(color: Colors.black45, blurRadius: 18, offset: Offset(0, 6))],
                          ),
                        ),

                      ],
                    ),
                    const Text(
                      "Aviation Intelligence System",
                      style: TextStyle(color: Colors.white70, fontSize: 24, fontWeight: FontWeight.w400, letterSpacing: 0.2),
                    ),
                    Container(
                      margin: const EdgeInsets.only(left: 64, top: 20),
                      child: const Text(
                        "Flight Safety Index",
                        style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(left: 70, top: 0),
                      child: const Text(
                        "Real‑Time VFR Risk Model",
                        style: TextStyle(fontSize: 19, color: Color(0xFFB8C4D4), fontWeight: FontWeight.w400, letterSpacing: 0.2),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            margin: const EdgeInsets.only(top: 30),
                            constraints: const BoxConstraints(maxWidth: 460),
                            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: LinearGradient(
                                colors: [Colors.white.withOpacity(0.18), Colors.white.withOpacity(0.05)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.4),
                              boxShadow: [
                                BoxShadow(color: Colors.white.withOpacity(0.25), blurRadius: 25, spreadRadius: -5, offset: const Offset(-4, -4)),
                                BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 30, offset: const Offset(6, 10)),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  "Airport Safety Check",
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5),
                                ),
                                const SizedBox(height: 18),
                                SizedBox(
                                  width: 240,
                                  child: TextField(
                                    controller: airportController,
                                    style: const TextStyle(color: Colors.white),
                                    textAlign: TextAlign.center,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.08),
                                      labelText: "Enter ICAO Code",
                                      labelStyle: const TextStyle(color: Colors.white70),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white30), borderRadius: BorderRadius.circular(12)),
                                      focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white70), borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white.withOpacity(0.12),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white30)),
                                  ),
                                  onPressed: isLoading ? null : () async {
                                    setState(() {
                                      isLoading = true;
                                      riskFactors = [];
                                      positiveFactors = [];
                                      decodedData = [];
                                      safetyScore = 0;
                                      safetyLabel = "ANALYZING";
                                      flightCategory = "";
                                    });

                                    final icao = airportController.text.trim().toUpperCase();
                                    final data = await _metarService.getMetarData(icao);

                                    if (data != null) {
                                      _analyzeSafety(data);
                                    } else {
                                      setState(() {
                                        safetyLabel = "NOT FOUND";
                                        safetyScore = 0;
                                      });
                                    }

                                    setState(() => isLoading = false);
                                  },
                                  child: Text(isLoading ? "Scanning..." : "Analyze Safety", style: const TextStyle(fontSize: 16)),
                                ),
                                const SizedBox(height: 30),
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    TweenAnimationBuilder<double>(
                                      tween: Tween<double>(begin: 0, end: safetyScore),
                                      duration: const Duration(milliseconds: 1500),
                                      curve: Curves.easeInOutCubic,
                                      builder: (context, value, _) {
                                        return CircularPercentIndicator(
                                          radius: 120,
                                          lineWidth: 36,
                                          percent: value,
                                          progressColor: value >= 0.8 ? Colors.greenAccent : value >= 0.5 ? Colors.orangeAccent : Colors.redAccent,
                                          backgroundColor: Colors.white24,
                                          circularStrokeCap: CircularStrokeCap.round,
                                          center: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text((value * 10).toStringAsFixed(1), style: const TextStyle(fontSize: 42, color: Colors.white, fontWeight: FontWeight.bold)),
                                              Text(safetyLabel, style: const TextStyle(fontSize: 18, color: Colors.white70)),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    if (flightCategory.isNotEmpty)
                                      Positioned(
                                        bottom: 30,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _getCategoryColor(flightCategory).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: _getCategoryColor(flightCategory).withOpacity(0.8)),
                                          ),
                                          child: Text(flightCategory, style: TextStyle(color: _getCategoryColor(flightCategory), fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                  ],
                                ),

                                // --- DECODED METAR TABLE ---
                                if (decodedData.isNotEmpty) ...[
                                  const SizedBox(height: 20),
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // TITLE with timestamp
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text("METAR DECODED", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                            // Placeholder timestamp or use data
                                            // Text("UTC", style: TextStyle(color: Colors.white54, fontSize: 10)),
                                          ],
                                        ),
                                        const SizedBox(height: 12),

                                        // Key-Value Rows
                                        ...decodedData.map((item) {
                                          final label = item['label']!;
                                          final value = item['value']!;
                                          final isRaw = label == "Text:";

                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 6.0),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                  width: 120,
                                                  child: Text(
                                                    label,
                                                    style: const TextStyle(
                                                      color: Color(0xFF7F9EFF), // Light periwinkle/blue for labels
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Container(
                                                    padding: isRaw ? const EdgeInsets.all(4) : EdgeInsets.zero,
                                                    decoration: isRaw ? BoxDecoration(color: Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(4)) : null,
                                                    child: Text(
                                                      value,
                                                      style: TextStyle(
                                                        color: isRaw ? Colors.white : Colors.white.withOpacity(0.9),
                                                        fontSize: 13,
                                                        fontFamily: isRaw ? 'Monospace' : null,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),

                                        const Divider(color: Colors.white12, height: 24),

                                        // RISKS & POSITIVES
                                        if (riskFactors.isNotEmpty) ...[
                                          const Text("⚠️ RISK FACTORS", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                          const SizedBox(height: 8),
                                          ...riskFactors.map((r) => Padding(
                                            padding: const EdgeInsets.only(bottom: 4.0),
                                            child: Row(
                                              children: [
                                                Icon(Icons.warning_amber_rounded, color: r['color'], size: 16),
                                                const SizedBox(width: 8),
                                                Expanded(child: Text(r['msg'], style: const TextStyle(color: Colors.white, fontSize: 13))),
                                              ],
                                            ),
                                          )),
                                          const SizedBox(height: 12),
                                        ],

                                        if (positiveFactors.isNotEmpty) ...[
                                          const Text("✅ FAVORABLE CONDITIONS", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                          const SizedBox(height: 8),
                                          ...positiveFactors.map((p) => Padding(
                                            padding: const EdgeInsets.only(bottom: 4.0),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 16),
                                                const SizedBox(width: 8),
                                                Expanded(child: Text(p, style: const TextStyle(color: Colors.white, fontSize: 13))),
                                              ],
                                            ),
                                          )),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
