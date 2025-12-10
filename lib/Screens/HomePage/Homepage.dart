import 'package:flutter/material.dart';
import 'package:skyaware/Service/metar_service.dart';
import 'dart:ui';
import '../../Service/WeatherEngine.dart';
import '../Login/login_page.dart';
class HomePage extends StatefulWidget
{
  @override
  State<HomePage> createState(){
    return _Homepage();

  }
}
class _Homepage extends State<HomePage>
{
  TextEditingController airportController = TextEditingController();
  bool isloading = false;
  List<Map<String, dynamic>> riskFactors = [];
  List<String> positiveFactors = [];

  List<Map<String, dynamic>> decodedData = [];

  double safetyScore = 0.0;
  String safetyLabel = "READY";
  String flightCategory = "";

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





  Widget background = Container
    (
    decoration: const BoxDecoration
      (
      gradient: LinearGradient
        (
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6), Color(0xFF7D2AE8)],
      ),
    ),
  );

  Widget title = Row(
      children: [
        Container(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    ).
                    createShader(const Rect.fromLTWH(0, 0, 300, 80)),
                  shadows: const [Shadow(color: Colors.black45, blurRadius: 18, offset: Offset(0, 6))],
                ),
              ),
              Text(
                "Aviation Intelligence System",
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2
                ),
              )
            ],
          ),
        ),
        Container(
          margin: EdgeInsets.only(top: 24),
          child: Icon(
            Icons.flight,
            color: Colors.white,
            size: 60,
          ),
        )
      ]
  );

  Widget box(){
    Widget box_header = Text(
        "Airport Safety Check",
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: 0.5
      ),
    );

    Widget airport_code = SizedBox(
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
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.white30),
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.white70),
            borderRadius: BorderRadius.circular(12)
          ),
        )
      )
    );



    Widget Safety_Button = ElevatedButton(
      child: Text(
        isloading ? "Loading..." : "Check",
        style: const TextStyle(fontSize: 16)
      ),
      onPressed: isloading ? null : () async {
        setState(() {
          isloading = true;
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

        setState(() => isloading = false);
      }
    );

    return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          child: Container(
              margin: const EdgeInsets.only(left: 30,right: 30),
              constraints: const BoxConstraints(maxWidth: 460),
              // padding: const EdgeInsets.symmetric(vertical: 30),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient:  LinearGradient(
                  colors: [Colors.white.withOpacity(0.18), Colors.white.withOpacity(0.05)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.4),
                boxShadow: [
                  BoxShadow(
                      color: Colors.white.withOpacity(0.25),
                      blurRadius: 25,
                      spreadRadius: -5,
                      offset: const Offset(-4,-4)
                  ),
                  BoxShadow(
                      color: Colors.black.withOpacity(0.45),
                      blurRadius: 30,
                      offset: const Offset(6, 10)
                  ),
                ],
              ),
              child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                box_header,
                const SizedBox(height: 20),
                airport_code,
                const SizedBox(height: 12),
                Safety_Button,

              ],
            ),
          ),
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        ),
    );
  }



  @override
  Widget build(BuildContext context)
  {
    return Scaffold
      (
      // extendBodyBehindAppBar: true,
      // appBar: AppBar(
      //   title: Text("SkyAware"),
      //   backgroundColor: Colors.transparent,
      //   elevation: 0,
      //   flexibleSpace:
      //   Container
      //     (
      //     decoration: const BoxDecoration
      //       (
      //       gradient: LinearGradient
      //         (
      //         begin: Alignment.topLeft,
      //         end: Alignment.bottomRight,
      //         colors: [Color(0xFF0A84FF),Color(0xFF0A84FF)],
      //       ),
      //     ),
      //   ),
      // ),
      body: Stack
        (
        children:
        [
          background,
          Container(
            margin: const EdgeInsets.only(top: 40),
            child: Expanded(
              child: SingleChildScrollView(
                child:Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                        margin: const EdgeInsets.only(left: 20),
                        child: title
                    ),
                    const SizedBox(height: 30),
                    Container(
                      margin: const EdgeInsets.only(right: 40),
                      child: const Text(
                        "Flight Safety Index",
                        style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(right: 40, top: 0),
                      child: const Text(
                        "Real‑Time VFR Risk Model",
                        style: TextStyle(fontSize: 19, color: Color(0xFFB8C4D4), fontWeight: FontWeight.w400, letterSpacing: 0.2),
                      ),
                    ),
                    const SizedBox(height: 10),
                     box(),
                     const SizedBox(height: 30),
                     ElevatedButton(
                       style: ElevatedButton.styleFrom(
                         backgroundColor: Colors.white.withOpacity(0.1),
                         foregroundColor: Colors.white,
                         elevation: 0,
                         side: const BorderSide(color: Colors.white38),
                       ),
                       onPressed: () {
                         Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginPage()));
                       },
                       child: const Text("Access Restricted Area (Login)"),
                     ),
                     const SizedBox(height: 50),
                  ]
                )
             )
            )
          )
        ]
      )
    );
  }
}