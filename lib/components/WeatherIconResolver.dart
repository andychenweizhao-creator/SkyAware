import 'package:flutter/material.dart';

// WeatherIconResolver for weather icons/colors
class WeatherIconResolver {
  static IconData getIcon(int weatherCode) {
    if (weatherCode == 0) return Icons.wb_sunny;
    if ([1,2,3].contains(weatherCode)) return Icons.cloud;
    if ([51,53,55].contains(weatherCode)) return Icons.water_drop;
    if ([61,63,65].contains(weatherCode)) return Icons.umbrella;
    if ([66,67].contains(weatherCode)) return Icons.ac_unit;
    if ([71,73,75].contains(weatherCode)) return Icons.cloudy_snowing;
    if ([95].contains(weatherCode)) return Icons.thunderstorm;
    if ([96,99].contains(weatherCode)) return Icons.flash_on;
    return Icons.help_center;
  }

  static Color getColor(int weatherCode) {
    if (weatherCode == 0) return Colors.amberAccent;
    if ([1,2,3].contains(weatherCode)) return Colors.white70;
    if ([51,53,55].contains(weatherCode)) return Colors.blueAccent;
    if ([61,63,65].contains(weatherCode)) return Colors.blue;
    if ([66,67].contains(weatherCode)) return Colors.cyanAccent;
    if ([71,73,75].contains(weatherCode)) return Colors.lightBlueAccent;
    if ([95,96,99].contains(weatherCode)) return Colors.deepPurpleAccent;
    return Colors.grey;
  }
}