import 'package:flutter/cupertino.dart';

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../Screens/DashBoard/components/altitude_speed_box.dart';
import '../../Screens/DashBoard/components/weather_analysis_box.dart';
import '../../Screens/DashBoard/components/departure_time_box.dart';
import '../../Screens/DashBoard/components/flight_plan_box.dart';

import '../../Animations/PreFlightAnimation.dart';



class Preflightview extends StatefulWidget {
  bool _isInFlight;
  Preflightview(this._isInFlight, {super.key});

  @override

  State<Preflightview> createState() => _PreflightviewState();
}

class _PreflightviewState extends State<Preflightview> with TickerProviderStateMixin {
  late PreFlightAnimation _preFlightAnimation;
  void initState() {
    super.initState();
    _preFlightAnimation = PreFlightAnimation(vsync: this);
    _preFlightAnimation.start();
  }



  @override
  Widget build(BuildContext context) {
    return _buildPreFlightView();
  }
  Widget _buildPreFlightView() {
    return Stack(
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
                BoxShadow(color: const Color(0xFF0A84FF).withOpacity(0.2), blurRadius: 100, spreadRadius: 20),
              ],
            ),
          ),
        ),

        SafeArea(
          child: FadeTransition(
            opacity: _preFlightAnimation.fadeAnimation,
            child: SlideTransition(
              position: _preFlightAnimation.slideAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Live Monitor", style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white)),
                        ElevatedButton.icon(
                          onPressed: () => setState(() => widget._isInFlight = true),
                          icon: const Icon(Icons.flight_takeoff),
                          label: const Text("FLY MAP"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE040FB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        )
                      ],
                    ),
                    const Text(
                      "Real-Time Parameter Tracking",
                      style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w400, letterSpacing: 0.2),
                    ),
                    const SizedBox(height: 30),
                    Center(child: AltitudeSpeedBox()),
                    const SizedBox(height: 20),
                    Center(child: WeatherAnalysisBox()),

                    Padding(
                      padding: const EdgeInsets.only(top: 40.0, bottom: 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.flight_takeoff, color: Color(0xFF0A84FF), size: 30),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  "Pre-Flight Planning",
                                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, height: 1.1, color: Colors.white),
                                ),
                                SizedBox(height: 8),
                                Text("3-Hour Weather & Risk Forecast", style: TextStyle(color: Colors.white70, fontSize: 16)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    DepartureTimeBox(),
                    const SizedBox(height: 20),
                    FlightPlanBox(),
                    const SizedBox(height: 20),
                    //FIXME: Relook at the code below
                    // Center(
                    //   child: OutlinedButton.icon(
                    //     onPressed: _importFlightPlan,
                    //     icon: const Icon(Icons.upload_file),
                    //     label: const Text("Import Flight Plan (.fpl)"),
                    //     style: OutlinedButton.styleFrom(
                    //         foregroundColor: Colors.white54,
                    //         side: const BorderSide(color: Colors.white24)
                    //     ),
                    //   ),
                    // ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),
        )
      ],
    );
  }
}
