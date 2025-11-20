import 'dart:convert';
import 'package:http/http.dart' as http;

class AviationWeatherService {
  static const String _baseUrl =
      'https://aviationweather.gov/api/data/metar?ids=KLAX&format=json';

  static Future<Map<String, dynamic>?> fetchMetar() async {
    try {
      final response = await http.get(Uri.parse(_baseUrl));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        if (data.isNotEmpty) {
          return data.first;
        } else {
          print("✅ 请求成功但数据为空");
          return null;
        }
      } else {
        print("❌ 请求失败 Status code: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("❌ 请求异常: $e");
      return null;
    }
  }
}