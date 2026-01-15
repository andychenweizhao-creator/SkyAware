import '../services/WeatherData.dart';
import 'package:flutter/material.dart';


// Placeholder for Gemini API Key - Replace with your actual key


class Weather extends StatefulWidget {
  const Weather({super.key});

  @override
  State<Weather> createState() => _WeatherState();
}

class _WeatherState extends State<Weather> with SingleTickerProviderStateMixin {

  Widget InfoBox(String text, Icon icon){

    return
      Align(
        alignment: Alignment.topCenter,
        child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
                text,
                style:TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                )
              ),
            SizedBox(width: 10),
            icon,
          ],
        ),
        ),
      );
  }
  Widget build(BuildContext context) {
    double boxWidth = 360;
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
              width: boxWidth,
              height: 240,
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
              width: boxWidth,
              height: 240,
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
          SingleChildScrollView(
            child: Center(
              child: Column(
                children: [
                  //temperature
                  Container
                    (
                    margin: EdgeInsets.only(top: 100),
                    width: boxWidth,
                    height: 240,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [
                              Colors.white30,
                              Colors.blueGrey,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    child: InfoBox("73F", Icon(Icons.thermostat, size: 45),
                  )
                  ),
                  Container
                    (
                    //wind and cloud
                    margin: EdgeInsets.only( top: 100),
                    width: boxWidth,
                    height: 240,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white30,
                          Colors.blueGrey,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: InfoBox("Cloudy/10Kt", Icon(Icons.cloud, size: 40),
                  ),
                  ),
                  Container
                    (
                    //precipitation
                    margin: EdgeInsets.only(top: 100),
                    width: boxWidth,
                    height: 240,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white30,
                          Colors.blueGrey,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  child: InfoBox("Chance of Rain",Icon(Icons.water_drop, size: 45),
                  ),
                  ),
                  SizedBox(height: 150),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  }

