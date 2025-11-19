import 'package:flutter/material.dart';
import '../DashBoard/components/wind_conditions_box.dart';
import '../DashBoard/components/weather_details_box.dart';

class Weather extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Live Weather Data'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Center(child: WindConditionsBox()),
            SizedBox(height: 20),
            Center(child: WeatherDetailsBox()),
          ],
        ),
      ),
    );
  }
}
