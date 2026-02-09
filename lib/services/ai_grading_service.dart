import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';
import 'airport_database_service.dart';

class AiGradingService {
  static const Duration _timeout = Duration(seconds: 40);

  /// Analyzes a list of airports and returns a map of ICAO -> Risk Details.
  static Future<Map<String, Map<String, String>>> gradeAirports(
      List<Airport> airports, GenerativeModel model) async {
    
    if (airports.isEmpty) return {};

    // 1. Prepare concise list for prompt to save tokens
    final airportList = airports.map((a) => "${a.ident} (${a.elevation}ft)").join(", ");

    final prompt = """
      ACT AS A FLIGHT INSTRUCTOR.
      Analyze these airports for General Aviation VFR landing risk based on Elevation (Density Altitude risk) and general knowledge (Terrain/Runway).
      Airports: $airportList.
      
      Return RAW JSON ONLY. No markdown. Format:
      {
        "KLAX": {"color": "#FF0000", "reason": "Busy Airspace"},
        "KSEZ": {"color": "#FFFF00", "reason": "High Terrain/Turbulence"},
        "L70": {"color": "#00FF00", "reason": "Standard VFR"}
      }
      Use Green (#00FF00) for Low Risk, Yellow (#FFFF00) for Moderate, Red (#FF0000) for High.
      """;

    try {
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content).timeout(_timeout);

      if (response.text != null) {
        String jsonString = response.text!;
        jsonString = jsonString.replaceAll('```json', '').replaceAll('```', '');
        
        final startIndex = jsonString.indexOf('{');
        final endIndex = jsonString.lastIndexOf('}');
        
        if (startIndex != -1 && endIndex != -1) {
          jsonString = jsonString.substring(startIndex, endIndex + 1);
          
          final Map<String, dynamic> rawData = json.decode(jsonString);
          final Map<String, Map<String, String>> grades = {};
          
          rawData.forEach((key, value) {
            grades[key] = {
              'color': value['color']?.toString() ?? '#808080',
              'reason': value['reason']?.toString() ?? 'No info',
            };
          });
          return grades;
        }
      }
    } catch (e) {
      debugPrint("AI Grading Failed: $e");
    }
    return {};
  }
}
