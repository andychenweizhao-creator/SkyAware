import 'dart:convert';
import 'package:http/http.dart' as http;
import '../weather_service.dart';

class OpenAIService {
  // TODO: Replace with your actual API key using a secure method like flutter_dotenv
  // DO NOT hardcode your secret key here.
  static const String _apiKey = "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";

  Future<String> analyzeSafety(String metarText) async {
    final uri = Uri.parse("https://api.openai.com/v1/chat/completions");

    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer $_apiKey",
    };

    try {
      final response = await http.post(
        uri,
        headers: headers,
        body: json.encode({
          "model": "gpt-4.1-mini",
          "messages": [
            {"role": "system", "content": "You are an aviation weather safety assistant. Analyze METAR and provide a 1-10 safety score only."},
            {"role": "user", "content": "METAR: $metarText"}
          ],
          "max_tokens": 10,
          "temperature": 0.1,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data["choices"][0]["message"]["content"].trim();
      } else {
        print("OpenAI Error (analyzeSafety): ${response.statusCode} ${response.body}");
        return "ERROR";
      }
    } catch (e) {
      print("OpenAI Error: $e");
      return "ERROR";
    }
  }

  Future<String> analyzeWeather(Weather weather) async {
    final uri = Uri.parse("https://api.openai.com/v1/chat/completions");

    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer $_apiKey",
    };

    final weatherDescription = "Analyze the following weather conditions for a VFR flight: "
        "Wind: ${weather.windSpeed.toStringAsFixed(0)} mph, direction ${weather.windDirection}. "
        "Gusts: ${weather.windGust.toStringAsFixed(0)} mph. "
        "Visibility: ${weather.visibility.toStringAsFixed(1)} miles. "
        "Precipitation: ${weather.precipitation.toStringAsFixed(2)} inches. "
        "Cloud Cover: ${weather.cloudCover}."
        "Based on these conditions, provide a safety score from 1 (very dangerous) to 10 (optimal). Respond with only the number.";

    try {
      final response = await http.post(
        uri,
        headers: headers,
        body: json.encode({
          "model": "gpt-3.5-turbo",
          "messages": [
            {"role": "system", "content": "You are an aviation weather assistant. Respond with only a number from 1 to 10."},
            {"role": "user", "content": weatherDescription}
          ],
          "max_tokens": 4, // A score is only a few characters
          "temperature": 0.1,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data["choices"][0]["message"]["content"].trim();
      } else {
        print("OpenAI Error (analyzeWeather): ${response.statusCode} ${response.body}");
        return "ERROR";
      }
    } catch (e) {
      print("OpenAI Error: $e");
      return "ERROR";
    }
  }
}
