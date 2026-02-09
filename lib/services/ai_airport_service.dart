import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class AiAirportService {
  static const Duration _geminiTimeout = Duration(seconds: 40);

  /// Searches for airports strictly within the provided bounding box coordinates.
  static Future<List<Map<String, dynamic>>> searchAirportsInBounds(
      double north, double south, double east, double west, GenerativeModel model) async {
    
    // 1. "Jailbreak" Simulator Prompt with Bounding Box
    final prompt = """
      ACT AS A FLIGHT SIMULATOR DATABASE.
      Task: List 5 to 12 aviation airports located strictly within this rectangular region:
      - North Lat: $north
      - South Lat: $south
      - East Lon: $east
      - West Lon: $west
      
      CRITICAL INSTRUCTIONS:
      - ONLY list airports geometrically inside these bounds.
      - If the area is remote (e.g. ocean, desert) and contains no airports, return an empty list `[]`. Do not hallucinate.
      - For each found airport, estimate a safety risk color for a general aviation pilot (Green=#00FF00, Yellow=#FFFF00, Red=#FF0000).
      - Return RAW JSON ONLY. No markdown, no chat.
      
      JSON FORMAT:
      [{"id": "ICAO", "site": "Airport Name", "lat": 0.0, "lon": 0.0, "risk_color": "#00FF00"}]
      """;

    final content = [Content.text(prompt)];
    
    try {
      final response = await model.generateContent(content).timeout(_geminiTimeout);

      if (response.text != null) {
        return _parseAiResponse(response.text!, null, null); // No reference point for dist calculation
      }
      return [];
    } catch (e) {
      debugPrint("AI Bounds Search Failed: $e");
      return [];
    }
  }

  /// RESTORED: Searches for nearby airports using a center point and radius.
  /// Required for HomePage and InFlightView.
  static Future<List<Map<String, dynamic>>> searchNearbyAirports(
      double lat, double lon, int radius, GenerativeModel model) async {
    
    final prompt = """
      ACT AS A FLIGHT SIMULATOR DATABASE.
      List 5 to 10 aviation airports near Latitude: $lat, Longitude: $lon. Radius: $radius NM.
      
      CRITICAL INSTRUCTIONS:
      - If NO airports are found within this radius, you MUST expand the search range and return the nearest major airports. DO NOT RETURN AN EMPTY LIST.
      - For each, estimate a safety risk color for a general aviation pilot based on general terrain/difficulty (Green=#00FF00, Yellow=#FFFF00, Red=#FF0000).
      - Return RAW JSON ONLY. No markdown, no chat.
      
      JSON FORMAT:
      [{"id": "ICAO", "site": "Airport Name", "lat": 0.0, "lon": 0.0, "risk_color": "#00FF00"}]
      """;

    final content = [Content.text(prompt)];
    
    try {
      final response = await model.generateContent(content).timeout(_geminiTimeout);

      if (response.text != null) {
        return _parseAiResponse(response.text!, lat, lon);
      }
      return [];
    } catch (e) {
      debugPrint("AI Radius Search Failed: $e");
      return [];
    }
  }

  static List<Map<String, dynamic>> _parseAiResponse(String rawText, double? refLat, double? refLon) {
    try {
      String jsonString = rawText;
      // Aggressive String Cleaning
      jsonString = jsonString.replaceAll('```json', '').replaceAll('```', '');
      
      final startIndex = jsonString.indexOf('[');
      final endIndex = jsonString.lastIndexOf(']');
      
      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        jsonString = jsonString.substring(startIndex, endIndex + 1);
      } else {
        debugPrint("No JSON list found in response");
        return [];
      }

      final List<dynamic> results = json.decode(jsonString);
      List<Map<String, dynamic>> airports = [];

      for (var result in results) {
        double stationLat = (result['lat'] as num).toDouble();
        double stationLon = (result['lon'] as num).toDouble();

        double distanceMeters = 0.0;
        if (refLat != null && refLon != null) {
          distanceMeters = Geolocator.distanceBetween(refLat, refLon, stationLat, stationLon);
        }

        String name = result['site'] ?? 'Unknown Station';
        String id = result['id'] ?? '???';
        String color = result['risk_color'] ?? '#00FF00';

        airports.add({
          'data': {
            'properties': {
              'id': id,
              'site': name,
              'risk_color': color,
            },
            'geometry': {
              'coordinates': [stationLon, stationLat]
            }
          },
          'distance': distanceMeters,
        });
      }

      // Sort by distance if calculated
      if (refLat != null) {
        airports.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
      }
      
      return airports;
    } catch (e) {
      debugPrint("Parsing Error: $e");
      return [];
    }
  }
}
