import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:latlong2/latlong.dart'; // For distance calc inside service if needed
import 'airport_database_service.dart';

class AiEmergencyService {
  static const Duration _timeout = Duration(seconds: 45);

  /// Analyzes the situation and selects the best airport from the provided candidates.
  static Future<Map<String, dynamic>> calculateEmergencyRoute({
    required double lat,
    required double lon,
    required double alt,
    required double heading,
    required String aircraftType,
    required String emergencyType,
    required List<Airport> candidates,
    required GenerativeModel model,
  }) async {
    
    // 1. Build Candidate List String
    final Distance distanceCalc = const Distance();
    final LatLng currentPos = LatLng(lat, lon);
    
    final StringBuffer candidateBuffer = StringBuffer();
    for (int i = 0; i < candidates.length; i++) {
      final airport = candidates[i];
      // Fixed: Convert Meters to Nautical Miles (1 NM = 1852m) since latlong2 might not have NauticalMile
      final double dist = distanceCalc.as(LengthUnit.Meter, currentPos, LatLng(airport.lat, airport.lon)) / 1852.0;
      // Format: 1. KLAX (Los Angeles Intl) - 5nm away, Elev 125ft
      candidateBuffer.writeln('${i + 1}. ${airport.ident} (${airport.name}) - ${dist.toStringAsFixed(1)}nm away, Elev ${airport.elevation}ft');
    }

    // 2. Construct Prompt
    final prompt = """
ACT AS A FLIGHT SAFETY COMPUTER.
CRITICAL EMERGENCY DECLARED: $emergencyType
AIRCRAFT STATE: Type: $aircraftType, Alt: ${alt.toStringAsFixed(0)}ft, Heading: ${heading.toStringAsFixed(0)}°.

CANDIDATE AIRPORTS (Sorted by Distance):
${candidateBuffer.toString()}

TASK: Analyze these candidates using your internal aviation knowledge (Runway length, Terrain, Approach).
- IF Engine Failure: Prioritize Glide Range (Distance vs Altitude).
- IF Fire: Prioritize nearest paved runway.
- IF Medical: Prioritize large airports (Class B/C) with medical facilities.

CRITICAL SAFETY CONSTRAINT: 
You are guiding a FIXED-WING aircraft. 
DO NOT select Heliports, Seaplane Bases, or Train Stations even if they are in the candidate list.
ONLY select valid airports with a RUNWAY.
If the nearest option is a Heliport, SKIP IT and pick the next best Airport.

RETURN RAW JSON ONLY (No markdown, no backticks):
{
  "selected_airport_id": "ICAO_CODE",
  "reason_for_selection": "Brief reason why this is safer than others.",
  "coordinates": { "lat": 0.0, "lon": 0.0 },
  "action_plan": {
    "phase_1_immediate": [
      "Pitch for Best Glide (76 kts)",
      "Fuel Selector - SWITCH TANK",
      "Fuel Pump - ON",
      "Mixture - RICH"
    ],
    "phase_2_approach": [
      "Squawk 7700",
      "Declare Mayday on 121.5",
      "Seatbelts - SECURE"
    ]
  }
}
""";

    try {
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content).timeout(_timeout);

      if (response.text == null) {
        throw Exception("AI returned empty response");
      }

      final result = _cleanAndParseJson(response.text!);
      
      // Safety Fallback: If AI hallucinates coordinates, use the ones from our database if ID matches
      final selectedId = result['selected_airport_id']?.toString().toUpperCase();
      if (selectedId != null) {
        final match = candidates.firstWhere((a) => a.ident == selectedId, orElse: () => candidates.first);
        // Overwrite coordinates to ensure accuracy from local DB
        result['coordinates'] = {
          "lat": match.lat,
          "lon": match.lon
        };
      }
      
      return result;

    } catch (e) {
      debugPrint("Emergency Service AI Error: $e");
      throw Exception("Failed to calculate emergency plan: $e");
    }
  }

  static Map<String, dynamic> _cleanAndParseJson(String rawText) {
    String cleanText = rawText;
    cleanText = cleanText.replaceAll('```json', '').replaceAll('```', '');
    
    final startIndex = cleanText.indexOf('{');
    final endIndex = cleanText.lastIndexOf('}');

    if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
      cleanText = cleanText.substring(startIndex, endIndex + 1);
    } else {
      throw const FormatException("No JSON object found in AI response");
    }

    try {
      return json.decode(cleanText) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException("Invalid JSON format: $e");
    }
  }
}
