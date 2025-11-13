import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:geolocator/geolocator.dart';
import '../../Service/location_service.dart';
import '../../Service/wind_conditions_box.dart';
import '../../Service/weather_details_box.dart';

class DashBoard extends StatefulWidget {
  @override
  _DashBoardState createState() => _DashBoardState();
}

class _DashBoardState extends State<DashBoard> {
  final LocationService _locationService = LocationService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            margin: EdgeInsets.only(top: 60, left: 30, right: 30),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Live Monitor",
                          style: TextStyle(
                            fontSize: 50,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "Real-Time Parameter Tracking",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(height: 5),
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                margin: EdgeInsets.only(top: 30),
                                constraints: BoxConstraints(maxWidth: 1000),
                                height: 200,
                                padding: EdgeInsets.symmetric(
                                  vertical: 20,
                                  horizontal: 30,
                                ),
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
                                child: StreamBuilder<Position>(
                                  stream: _locationService.getPositionStream(),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) {
                                      return Center(child: Text('Error: ${snapshot.error}'));
                                    }

                                    if (!snapshot.hasData) {
                                      return Center(child: CircularProgressIndicator());
                                    }

                                    final position = snapshot.data!;
                                    return Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // Left column
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                "ALTITUDE",
                                                style: TextStyle(
                                                  fontSize: 30,
                                                  color: Colors.white70,
                                                  letterSpacing: 0.8,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              SizedBox(height: 8),
                                              RichText(
                                                text: TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: (position.altitude * 3.28084).toStringAsFixed(0),
                                                      style: TextStyle(
                                                        fontSize: 44,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFF66D1FF),
                                                      ),
                                                    ),
                                                    TextSpan(
                                                      text: " ft",
                                                      style: TextStyle(
                                                        fontSize: 28,
                                                        fontWeight: FontWeight.w600,
                                                        color: Color(0xFF66D1FF),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                "Above Sea Level",
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.white54,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Right column
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                "GROUND SPEED",
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.white70,
                                                  letterSpacing: 0.8,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              SizedBox(height: 8),
                                              RichText(
                                                text: TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: (position.speed * 2.23694).toStringAsFixed(0),
                                                      style: TextStyle(
                                                        fontSize: 44,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFF6CFF8C),
                                                      ),
                                                    ),
                                                    TextSpan(
                                                      text: " mph",
                                                      style: TextStyle(
                                                        fontSize: 28,
                                                        fontWeight: FontWeight.w600,
                                                        color: Color(0xFF6CFF8C),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                "GPS Tracking",
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.white54,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 20),
                        Center(child: WindConditionsBox()),
                        SizedBox(height: 20),
                        Center(child: WeatherDetailsBox()),
                        SizedBox(height: 20),
                      ],
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
}
