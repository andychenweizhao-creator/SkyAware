// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'package:latlong2/latlong.dart';
//
// // A data class for the weather data
// class Weather {
//   final double windSpeed;
//   final double windGust;
//   final String windDirection;
//   final double visibility;
//   final double precipitation;
//   final String cloudCover;
//
//   Weather({
//     required this.windSpeed,
//     required this.windGust,
//     required this.windDirection,
//     required this.visibility,
//     required this.precipitation,
//     required this.cloudCover,
//   });
// }
//
// class WeatherService {
//   static const _apiKey = "b6f7e96abf1c4433976164508251311";
//
//   Future<Weather> getWeather(double latitude, double longitude) async {
//     final url = Uri.parse(
//         'https://api.weatherapi.com/v1/current.json?key=$_apiKey&q=$latitude,$longitude');
//
//     try {
//       final response = await http.get(url);
//
//       if (response.statusCode != 200) {
//         throw Exception('Failed to load weather data. Status: ${response.statusCode}, Body: ${response.body}');
//       }
//
//       final data = jsonDecode(response.body);
//       final current = data['current'];
//       if (current == null) {
//         throw Exception('No current weather data available.');
//       }
//
//       return Weather(
//         windSpeed: (current['wind_mph'] as num?)?.toDouble() ?? 0.0,
//         windGust: (current['gust_mph'] as num?)?.toDouble() ?? 0.0,
//         windDirection: _degreesToCardinal((current['wind_degree'] as num?)?.toDouble() ?? 0.0),
//         visibility: (current['vis_miles'] as num?)?.toDouble() ?? 0.0,
//         precipitation: (current['precip_in'] as num?)?.toDouble() ?? 0.0,
//         cloudCover: "${((current['cloud'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}%",
//       );
//     } catch (e) {
//       print("Failed to fetch WeatherAPI.com weather: $e");
//       return Future.error(e);
//     }
//   }
//
//   // Converts degrees to a cardinal direction
//   String _degreesToCardinal(num degrees) {
//     const List<String> directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'N'];
//     return directions[((degrees % 360) / 45).round()];
//   }
// }
// class LegWx {
//   final int weatherCode;
//   final double? cloudBaseFt;
//   final double? visibilitySm;
//   final int? windDirDeg;
//   final double? windSpeedKt;
//   final double? precipPct;
//   final bool convective;
//
//   const LegWx({
//     required this.weatherCode,
//     required this.cloudBaseFt,
//     required this.visibilitySm,
//     required this.windDirDeg,
//     required this.windSpeedKt,
//     required this.precipPct,
//     required this.convective,
//   });
// }
//
// class WeatherPoint {
//   final LatLng position;
//   final LegWx weather;
//
//   const WeatherPoint(this.position, this.weather);
// }
