import 'package:flutter/material.dart';
import 'components/altitude_speed_box.dart';
import 'components/weather_analysis_box.dart';
import 'components/departure_time_box.dart';
import 'components/flight_plan_box.dart';


class DashBoard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Stack(
          children: [
            Container(
              margin: EdgeInsets.only(top: 60,left: 30, right: 30),
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
                                  fontWeight: FontWeight.bold
                              )
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
                          SizedBox(height: 20),
                          Center(child: AltitudeSpeedBox()),
                          SizedBox(height: 20),
                          Center(child: WeatherAnalysisBox()),
                          Padding(
                            padding: const EdgeInsets.only(top: 40.0),
                            child: Row(
                              children: [
                                Icon(Icons.flight_takeoff, color: Colors.lightBlueAccent, size: 45),
                                SizedBox(width: 15),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Pre-Flight\nPlanning",
                                      style: TextStyle(
                                        fontSize: 38,
                                        fontWeight: FontWeight.bold,
                                        height: 1.2,
                                      ),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      "3-Hour Weather & Risk Forecast",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                          DepartureTimeBox(),
                          SizedBox(height: 20),
                           FlightPlanBox(),
                          SizedBox(height: 40), // Add some padding at the bottom
                        ],
                      ),
                    )
                  )
                ],
              ),
            )
          ],
        )
    );
  }
}
