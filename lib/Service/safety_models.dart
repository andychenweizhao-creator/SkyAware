import 'dart:convert';
import 'package:http/http.dart' as http;

class MetarService {
  Future<String> fetchByIcao(String icao) async {
    final url = Uri.parse('https://aviationweather.gov/api/data/metar?ids=$icao&format=json');
    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Failed to load METAR for $icao');
    }

    final jsonMap = jsonDecode(response.body);
    print('DEBUG METAR JSON: $jsonMap');

    // aviationweather.gov returns a map with a "data" list
    if (jsonMap is Map<String, dynamic>) {
      final dataList = jsonMap['data'];
      if (dataList is List && dataList.isNotEmpty) {
        final first = dataList[0];
        if (first is Map<String, dynamic>) {
          final rawText = first['raw_text'];
          if (rawText is String && rawText.isNotEmpty) {
            print("✅ FAA METAR fetched for $icao: $rawText");
            return rawText;
          }
        }
      }
    }

    print("⚠️ No METAR data found for $icao");
    return "";
  }
}