import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../location_service.dart';

class AltitudeSpeedBox extends StatefulWidget {
  @override
  _AltitudeSpeedBoxState createState() => _AltitudeSpeedBoxState();
}

class _AltitudeSpeedBoxState extends State<AltitudeSpeedBox> {
  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _positionSubscription = _locationService.getPositionStream().listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
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
          child: _currentPosition == null
              ? Center(child: CircularProgressIndicator(color: Colors.white))
              : Row(
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
                                  text: (_currentPosition!.altitude * 3.28084).toStringAsFixed(0),
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
                                  text: (_currentPosition!.speed * 2.23694).toStringAsFixed(0),
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
                ),
        ),
      ),
    );
  }
}
