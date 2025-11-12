import 'package:flutter/material.dart';
import 'SecondPage.dart';
import 'ThirdPage.dart';
import 'FourthPage.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'dart:ui';
import 'metar_service.dart';
import 'openai_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Color(0xFF0A1A2F),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int currentIndex = 0;
  String metarData = "";
  TextEditingController airportController = TextEditingController();
  double safetyScore = 0.75;
  String safetyLabel = "SAFE";

  final MetarJsonService _metarService = MetarJsonService();
  final OpenAIService _openAIService = OpenAIService();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A84FF), // vivid macOS blue
                  Color(0xFF5E5CE6), // purple/indigo
                  Color(0xFF7D2AE8), // bright purple
                ],
              ),
            ),
          ),
          Container(
            margin: EdgeInsets.only(top: 40, left: 10),
            child: Row(
              children: [
                Expanded(
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
                            ..shader = LinearGradient(
                              colors: [
                                Color(0xFF66D1FF),
                                Color(0xFF00FFA3),
                              ],
                            ).createShader(Rect.fromLTWH(0, 0, 300, 80)),
                          shadows: [
                            Shadow(color: Colors.black45, blurRadius: 18, offset: Offset(0, 6)),
                          ],
                        ),
                      ),
                      Text(
                        "Aviation Intelligence System",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Container(
                        margin: EdgeInsets.only(left: 64, top: 20),
                        child: Text(
                          "Flight Safety Index",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      Container(
                        margin: EdgeInsets.only(left: 70, top: 0),
                        child: Text(
                          "Real‑Time VFR Risk Model",
                          style: TextStyle(
                            fontSize: 19,
                            color: Color(0xFFB8C4D4),
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              margin: EdgeInsets.only(top: 30),
                              constraints: BoxConstraints(maxWidth: 460),
                              height: 500,
                              padding: EdgeInsets.symmetric(
                                  vertical: 30, horizontal: 30),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.18),
                                    Colors.white.withOpacity(0.05),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.35),
                                  width: 1.4,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.25),
                                    blurRadius: 25,
                                    spreadRadius: -5,
                                    offset: Offset(-4, -4),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.45),
                                    blurRadius: 30,
                                    offset: Offset(6, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "Airport Safety Check",
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  SizedBox(height: 18),
                                  SizedBox(
                                    width: 240,
                                    child: TextField(
                                      controller: airportController,
                                      style: TextStyle(color: Colors.white),
                                      textAlign: TextAlign.center,
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(
                                            0.08),
                                        labelText: "Enter ICAO Code",
                                        labelStyle: TextStyle(
                                            color: Colors.white70),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius
                                              .circular(
                                              12),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                              color: Colors.white30),
                                          borderRadius: BorderRadius
                                              .circular(
                                              12),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                              color: Colors.white70),
                                          borderRadius: BorderRadius
                                              .circular(
                                              12),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white
                                          .withOpacity(
                                          0.12),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 26, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            12),
                                        side: BorderSide(
                                            color: Colors.white30),
                                      ),
                                    ),
                                    onPressed: () async {
                                      final icao = airportController.text
                                          .trim().toUpperCase();
                                      final metar = await _metarService
                                          .getMetar(icao);

                                      setState(() {
                                        metarData = metar;
                                      });

                                      if (metar.isNotEmpty &&
                                          !metar.startsWith("Error") &&
                                          !metar.startsWith("No METAR")) {
                                        final scoreText = await _openAIService
                                            .analyzeSafety(metar);

                                        setState(() {
                                          final firstNumber = RegExp(
                                              r"\d+(\.\d+)?").firstMatch(
                                              scoreText);
                                          if (firstNumber != null) {
                                            final score = double.parse(
                                                firstNumber.group(0)!);
                                            safetyScore = 
                                                (score / 10).clamp(
                                                    0.0, 1.0);
                                            safetyLabel =
                                            score >= 7 ? "SAFE" : score >= 4
                                                ? "MODERATE"
                                                : "DANGER";
                                          } else {
                                            safetyLabel = "ERROR";
                                          }
                                        });
                                      } else {
                                        setState(() {
                                          safetyLabel = "ERROR";
                                          safetyScore = 0;
                                        });
                                      }
                                    },
                                    child: Text("Analyze Safety",
                                        style: TextStyle(fontSize: 16)),
                                  ),
                                  SizedBox(height: 30),
                                  TweenAnimationBuilder<double>(
                                    tween: Tween<double>(
                                        begin: 0, end: safetyScore),
                                    duration: Duration(milliseconds: 1500),
                                    curve: Curves.easeInOutCubic,
                                    builder: (context, value, _) {
                                      return CircularPercentIndicator(
                                        radius: 120,
                                        lineWidth: 36,
                                        percent: value,
                                        progressColor: value >= 0.7
                                            ? Colors.greenAccent
                                            : value >= 0.4
                                            ? Colors.orangeAccent
                                            : Colors.redAccent,
                                        backgroundColor: Colors.white24,
                                        circularStrokeCap: CircularStrokeCap
                                            .round,
                                        center: Column(
                                          mainAxisAlignment: MainAxisAlignment
                                              .center,
                                          children: [
                                            Text(
                                              (value * 10).toStringAsFixed(
                                                  1),
                                              style: TextStyle(
                                                fontSize: 42,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              safetyLabel,
                                              style: TextStyle(
                                                fontSize: 18,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  child: Padding(
                    padding: EdgeInsets.only(right: 35, bottom: 780),
                    child: Icon(
                      Icons.flight,
                      size: 60,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Container(
          height: 70,
          margin: EdgeInsets.symmetric(horizontal: 40),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white30, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() => currentIndex = 0);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => MyHomePage(title: 'Flutter Demo Home Page')),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.house, color: currentIndex == 0 ? Colors.white : Colors.white70),
                    Text("Home", style: TextStyle(
                        color: currentIndex == 0 ? Colors.white : Colors.white70, fontSize: 12
                    )),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => currentIndex = 1);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => SecondPage()),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.dashboard, color: currentIndex == 1 ? Colors.white : Colors.white70),
                    Text("Dashboard", style: TextStyle(
                        color: currentIndex == 1 ? Colors.white : Colors.white70, fontSize: 12
                    )),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => currentIndex = 2);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => ThirdPage()),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud, color: currentIndex == 2 ? Colors.white : Colors.white70),
                    Text("Weather", style: TextStyle(
                        color: currentIndex == 2 ? Colors.white : Colors.white70, fontSize: 12
                    )),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => currentIndex = 3);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => FourthPage()),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.settings, color: currentIndex == 3 ? Colors.white : Colors.white70),
                    Text("Settings", style: TextStyle(
                        color: currentIndex == 3 ? Colors.white : Colors.white70, fontSize: 12
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
