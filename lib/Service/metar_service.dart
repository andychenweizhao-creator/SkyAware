// import 'dart:convert';
// import 'package:http/http.dart' as http;
//
// class MetarJsonService {
//   Future<String> getMetar(String icao) async {
//     final data = await getMetarData(icao);
//     if (data != null && data.containsKey('rawOb')) {
//       return data['rawOb'];
//     }
//     return "No METAR data found for $icao";
//   }
//
//   Future<Map<String, dynamic>?> getMetarData(String icao) async {
//     final code = icao.trim().toUpperCase();
//     final url = Uri.parse(
//       "https://aviationweather.gov/api/data/metar?ids=$code&format=json",
//     );
//
//     try {
//       final response = await http.get(url);
//       if (response.statusCode == 200) {
//         final List<dynamic> list = jsonDecode(response.body);
//         if (list.isNotEmpty) {
//           return list[0] as Map<String, dynamic>;
//         }
//       }
//     } catch (e) {
//       print("Error fetching METAR JSON: $e");
//     }
//     return null;
//   }
//
//   Future<String?> getTaf(String icao) async {
//     final code = icao.trim().toUpperCase();
//     // TAF endpoint
//     final url = Uri.parse(
//       "https://aviationweather.gov/api/data/taf?ids=$code&format=json",
//     );
//
//     try {
//       final response = await http.get(url);
//       if (response.statusCode == 200) {
//         final List<dynamic> list = jsonDecode(response.body);
//         if (list.isNotEmpty) {
//           return list[0]['rawTAF'] ?? list[0]['rawOb']; // sometimes labeled differently
//         }
//       }
//     } catch (e) {
//       print("Error fetching TAF: $e");
//     }
//     return null;
//   }
// }
