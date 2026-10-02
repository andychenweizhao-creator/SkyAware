import 'package:flutter/material.dart';

class WeatherColors {
  static LinearGradient getGradient(String? condition, {bool isNight = false}) {
    if (condition == null) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2C3E50), Color(0xFF000000)],
      );
    }

    final c = condition.toLowerCase();

    if (isNight) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF200122), Color(0xFF6f0000), Color(0xFF000000)], // Deep Purple/Red/Black
      );
    }

    if (c.contains('clear') || c.contains('sunny')) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF29B2DD), Color(0xFF33AADD), Color(0xFF2DC8EA)], // Azure to Cyan
      );
    } else if (c.contains('cloud') || c.contains('overcast')) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF63747C), Color(0xFF3B4852)], // Blue-Grey
      );
    } else if (c.contains('rain') || c.contains('drizzle')) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3C4B58), Color(0xFF252E38)], // Desaturated Slate Blue
      );
    } else if (c.contains('snow')) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF8FAABA), Color(0xFF68829E)], // Cool Grey/Blue
      );
    } else {
      // Default
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF203A43), Color(0xFF2C5364)],
      );
    }
  }
}
