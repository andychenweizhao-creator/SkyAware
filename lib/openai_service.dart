import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenAIService {
  static const String apiKey = "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"; // Replace with your actual API key

  Future<String> analyzeSafety(String metarText) async {
    final uri = Uri.parse("https://api.openai.com/v1/chat/completions");

    try {
      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $apiKey",
        },
        body: json.encode({
          "model": "gpt-4.1-mini",
          "messages": [
            {
              "role": "system",
              "content": "You are an aviation weather safety assistant. Analyze METAR and provide a 1-10 safety score only."
            },
            {
              "role": "user",
              "content": "METAR: $metarText"
            }
          ],
          "max_tokens": 30
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data["choices"][0]["message"]["content"];
      } else {
        return "AI error: ${response.statusCode}";
      }
    } catch (e) {
      return "Network error: $e";
    }
  }
}