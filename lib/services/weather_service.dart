import 'dart:convert';
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
// Removed the google_generative_ai import!

class WeatherService {
  static const Duration _geminiTimeout = Duration(seconds: 25);
  static const Duration _geminiRetryDelay = Duration(milliseconds: 600);

  /// Fetches METAR data for a specific ICAO code from aviationweather.gov
  static Future<Map<String, dynamic>> fetchMetar(String icao) async {
    final normalizedIcao = icao.trim().toUpperCase();
    final uri = Uri.https(
      'aviationweather.gov',
      '/api/data/metar',
      {
        'ids': normalizedIcao,
        'format': 'geojson',
        'hours': '2',
      },
    );

    try {
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'SkyAware/1.0',
          'Accept': 'application/geo+json, application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;

        if (features.isNotEmpty) {
          final feature = features[0];
          // Return the 'properties' map which contains the METAR data
          // We also attach geometry for location if needed later
          final properties = feature['properties'] as Map<String, dynamic>;
          if (feature['geometry'] != null && feature['geometry']['coordinates'] != null) {
            properties['geometry'] = feature['geometry'];
          }
          return properties;
        } else {
          throw Exception('Airport $icao not found.');
        }
      } else {
        throw Exception('Failed to fetch data (${response.statusCode}).');
      }
    } catch (e) {
      throw Exception('Connection Error: $e');
    }
  }

  /// Fetches flight categories (VFR, IFR, etc) for a batch of airport ICAO codes.
  /// Returns a map { 'KLAX': 'VFR', ... }
  static Future<Map<String, String>> getFlightCategories(List<String> icaoCodes) async {
    final validCodes = icaoCodes
        .map((code) => code.trim().toUpperCase())
        .where((code) => code.isNotEmpty)
        .toList();

    if (validCodes.isEmpty) return {};

    final ids = validCodes.join(',');
    final uri = Uri.https(
      'aviationweather.gov',
      '/api/data/metar',
      {
        'ids': ids,
        'format': 'geojson',
        'hours': '2',
      },
    );

    try {
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'SkyAware/1.0',
          'Accept': 'application/geo+json, application/json',
        },
      ).timeout(const Duration(seconds: 12));
      final Map<String, String> results = {};

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;

        for (var feature in features) {
          final props = feature['properties'] as Map<String, dynamic>;
          final id = props['id'] as String?; // AviationWeather API returns 'id' for the ICAO code
          final fltcat = props['fltcat'] as String?;

          if (id != null && fltcat != null) {
            results[id] = fltcat;
          }
        }
      }
      return results;
    } catch (e) {
      // Note: Consider replacing print with debugPrint in production
      print("WeatherService Error: $e");
      return {};
    }
  }

  /// Sends METAR data to Gemini AI to generate a safety score and summary.
  static Future<Map<String, dynamic>> analyzeSafety(
      Map<String, dynamic> metarData, HttpsCallable model) async {

    // Deduction System Prompt
    final prompt = """
      Act as a Chief Pilot. Analyze this METAR data: ${json.encode(metarData)}.
      Calculate a 'Safety Score' (0-100) for a General Aviation pilot.
      Start with 100. Deduct points: 
      - Ceiling < 3000ft (-20 pts)
      - Visibility < 3SM (-20 pts)
      - Wind > 15kt (-10 pts)
      - Rain/Snow present (-15 pts)

      Return a specific integer (e.g., 84, 65). DO NOT return 0 or 100 unless conditions are extreme.

      Return ONLY valid JSON: {"score": <int>, "summary": "<string, max 30 words>"}
      """;

    try {
      HttpsCallableResult response;
      // Package the prompt into the map expected by your Node.js backend
      final requestData = <String, dynamic>{'prompt': prompt};

      try {
        // Call the Firebase Function instead of the local SDK
        response = await model.call(requestData).timeout(_geminiTimeout);
      } on TimeoutException {
        await Future.delayed(_geminiRetryDelay);
        response = await model.call(requestData).timeout(_geminiTimeout);
      }

      // Extract the text using the 'result' key we defined in the index.js file
      final String? text = (response.data['result'] ?? response.data['response']) as String?;

      if (text == null) {
        throw Exception("AI returned empty response");
      }

      // Robust Regex Parsing to extract JSON object
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);

      if (jsonMatch != null) {
        final jsonString = jsonMatch.group(0)!;
        try {
          return json.decode(jsonString) as Map<String, dynamic>;
        } catch (e) {
          // Fallback if strict JSON parsing fails but regex found something resembling JSON
          throw Exception("JSON Parse Error: $e");
        }
      } else {
        // Fallback structure if no JSON found
        return {
          "score": null,
          "summary": text.replaceAll(RegExp(r'\*'), '').trim() // Simple cleanup
        };
      }
    } catch (e) {
      throw Exception("Firebase Function Error: $e");
    }
  }
}