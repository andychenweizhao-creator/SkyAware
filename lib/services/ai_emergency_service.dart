import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:latlong2/latlong.dart'; 
import 'airport_database_service.dart';

class AiEmergencyService {
  static const Duration _timeout = Duration(seconds: 60); // Increased timeout to 60s for AI/Cloud Function cold starts

  /// Analyzes the situation and selects the best airport from the provided candidates.
  static Future<Map<String, dynamic>> calculateEmergencyRoute({
    required double lat,
    required double lon,
    required double alt,
    required double heading,
    required String aircraftType,
    required String emergencyType,
    required List<Airport> candidates,
  }) async {
    
    // 1. Build Candidate List String (Top 5 Only)
    final Distance distanceCalc = const Distance();
    final LatLng currentPos = LatLng(lat, lon);
    
    // Calculate distance and sort
    final sortedCandidates = List<Airport>.from(candidates);
    // Note: This sorting assumes we have distances calculated or we rely on the input being roughly sorted.
    // To be precise, we can recalculate or assume the database service returned them sorted.
    // Assuming 'candidates' might be a larger list or we want to ensure we take only the top 5 nearest.
    // Since we don't have a mutable property on Airport for distance easily here without wrapping,
    // and assuming the calling service (AirportDatabaseService) returns them sorted by distance:
    final topCandidates = sortedCandidates.take(5).toList();

    final StringBuffer candidateBuffer = StringBuffer();
    for (int i = 0; i < topCandidates.length; i++) {
      final airport = topCandidates[i];
      final double dist = distanceCalc.as(LengthUnit.Meter, currentPos, LatLng(airport.lat, airport.lon)) / 1852.0;
      candidateBuffer.writeln('${i + 1}. ${airport.ident} (${airport.name}) - ${dist.toStringAsFixed(1)}nm, Elev ${airport.elevation}ft');
    }

    // 2. Enhanced Prompt for "Useful & Detailed" Response
    final prompt = """
ACT AS A CHIEF FLIGHT INSTRUCTOR.
CRITICAL SITUATION: $emergencyType.
AIRCRAFT: $aircraftType.
CURRENT STATE: Alt ${alt.toInt()}ft, Hdg ${heading.toInt()}°.

CANDIDATES:
${candidateBuffer.toString()}

TASK:
1. Select the ABSOLUTE SAFEST airport. Consider distance vs altitude (Glide Ratio).
2. Generate a SPECIFIC, ACTIONABLE checklist for $aircraftType.

REQUIREMENTS FOR JSON OUTPUT:
- "reason_for_selection": Provide a solid tactical reason (e.g., "Longest runway within glide range," or "Headwind approach available"). DO NOT be vague.
- "phase_1_immediate": List specific memory items. INCLUDE SPEEDS if known for $aircraftType (e.g., "Pitch for 68 kts").
- "phase_2_approach": Include avionics settings (Squawk 7700, Radio 121.5) and cabin prep.

RETURN JSON ONLY:
{
  "selected_airport_id": "ICAO",
  "reason_for_selection": "Detailed reason here...",
  "coordinates": { "lat": 0.0, "lon": 0.0 },
  "action_plan": {
    "phase_1_immediate": ["Step 1", "Step 2", "Step 3 (with speeds)"],
    "phase_2_approach": ["Step 1", "Step 2", "Step 3"]
  }
}
""";

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
        'askGemini',
        options: HttpsCallableOptions(timeout: _timeout),
      );
      final response = await callable.call(<String, dynamic>{
        'prompt': prompt,
        'isEmergency': true,
      }).timeout(_timeout);

      // Support both possible return keys based on backend configuration
      final responseData = response.data;
      final responseText = responseData['result'] ?? responseData['response'];

      if (responseText == null) {
        throw Exception("AI returned empty response");
      }

      final result = _cleanAndParseJson(responseText.toString());
      
      // Safety Fallback & Coordinate Fix
      final selectedId = result['selected_airport_id']?.toString().toUpperCase();
      if (selectedId != null) {
        final match = candidates.firstWhere(
          (a) => a.ident == selectedId, 
          orElse: () => candidates.first // Fallback to first if ID not found
        );
        // Overwrite coordinates to ensure accuracy from local DB
        result['coordinates'] = {
          "lat": match.lat,
          "lon": match.lon
        };
        // Ensure ID matches the found one (in case fallback was used)
        result['selected_airport_id'] = match.ident; 
      } else {
         // If AI didn't return an ID, use the first candidate
         final fallback = candidates.first;
         result['selected_airport_id'] = fallback.ident;
         result['coordinates'] = { "lat": fallback.lat, "lon": fallback.lon };
      }
      
      return result;

    } catch (e) {
      debugPrint("Emergency Service AI Error/Timeout: $e");
      // Fallback Result
      if (candidates.isNotEmpty) {
        final fallback = candidates.first; // Nearest
        return {
          "selected_airport_id": fallback.ident,
          "reason_for_selection": "AI Unavailable. Nearest airport selected.",
          "coordinates": { "lat": fallback.lat, "lon": fallback.lon },
          "action_plan": {
            "phase_1_immediate": ["Fly Aircraft", "Check Checklists"],
            "phase_2_approach": ["Land ASAP"]
          }
        };
      }
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