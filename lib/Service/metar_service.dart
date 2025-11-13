import 'dart:convert';
import 'package:http/http.dart' as http;

class MetarJsonService {
  Future<String> getMetar(String icao) async {
    final code = icao.trim().toUpperCase();

    final url = Uri.parse(
      "https://aviationweather.gov/api/data/metar?ids=$code&format=json",
    );

    print("🌐 Fetching METAR for $code ...");

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        try {
          final List<dynamic> data = jsonDecode(response.body);
          if (data.isNotEmpty && data[0]["rawOb"] != null) {
            final raw = data[0]["rawOb"];
            print("✅ METAR: $raw");
            return raw;
          } else {
            return "No METAR data found for $code";
          }
        } catch (e) {
          print("⚠️ Parse error: $e");
          return "Error parsing METAR data";
        }
      } else {
        print("❌ HTTP error: ${response.statusCode}");
        return "Error fetching METAR: ${response.statusCode}";
      }
    } catch (e) {
      print("❌ Network error: $e");
      return "Network error fetching METAR";
    }
  }
}