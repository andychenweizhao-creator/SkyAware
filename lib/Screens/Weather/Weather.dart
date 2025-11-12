import 'package:flutter/material.dart';

class Weather extends StatefulWidget {
  const Weather({super.key});

  @override
  State<Weather> createState() => _WeatherState();
}

class _WeatherState extends State<Weather> {
  int currentIndex = 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0E1420),
      body: Stack(
        children: [
          Positioned(
            top: 60,
            left: 35,
            child: Text(
                "Weather Detail",
              style: TextStyle(
                color: Colors.white,
                fontSize: 45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Positioned(
            top: 1,
            left: 40,
            child: Text(
              "Real-Time & Forecast",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Colors.white70,
                letterSpacing: 0.5
              ),
            ),
          ),
        ],
      ),
    );
  }
}
