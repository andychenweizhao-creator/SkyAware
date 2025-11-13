import 'dart:convert';
import 'package:http/http.dart' as http;

// A data class to hold the parsed weather details
class WeatherDetails {
  final double visibility;
  final String precipitation;
  final String cloudCeiling;

  WeatherDetails({required this.visibility, required this.precipitation, required this.cloudCeiling});
}

class WeatherService {
  // Fetches wind conditions from the weather.gov API
  Future<Map<String, dynamic>> getWindConditions(double latitude, double longitude) async {
    try {
      final obsData = await _getLatestObservation(latitude, longitude);

      // 4. Parse and convert the data
      final windSpeedMps = obsData['windSpeed']?['value'] ?? 0.0;
      final windGustMps = obsData['windGust']?['value'] ?? 0.0;
      final windDirectionDegrees = obsData['windDirection']?['value'] ?? 0.0;

      return {
        'speed': windSpeedMps * 2.23694, // m/s to mph
        'gust': windGustMps * 2.23694, // m/s to mph
        'direction': _degreesToCardinal(windDirectionDegrees),
      };
    } catch (e) {
      print('Weather API Error: $e');
      return Future.error(e.toString());
    }
  }

  // Fetches detailed weather conditions
  Future<WeatherDetails> getWeatherDetails(double latitude, double longitude) async {
    try {
      final obsData = await _getLatestObservation(latitude, longitude);

      final visibilityMeters = obsData['visibility']?['value'] ?? 0.0;
      final precipitation = _parsePrecipitation(obsData['presentWeather'] ?? []);
      final cloudCeiling = _parseCloudCeiling(obsData['cloudLayers'] ?? []);

      return WeatherDetails(
        visibility: visibilityMeters / 1609.34, // meters to miles
        precipitation: precipitation,
        cloudCeiling: cloudCeiling,
      );
    } catch (e) {
      print('Weather API Error: $e');
      return Future.error(e.toString());
    }
  }

  // Helper to get the latest observation data from the API
  Future<Map<String, dynamic>> _getLatestObservation(double latitude, double longitude) async {
    // 1. Get the forecast grid URL for the given coordinates
    final pointsUrl = Uri.parse('https://api.weather.gov/points/$latitude,$longitude');
    final pointsResponse = await http.get(pointsUrl, headers: {'User-Agent': '(SkyAware, sky.aware@email.com)'});
    if (pointsResponse.statusCode != 200) throw Exception('Failed to get grid. Status: ${pointsResponse.statusCode}');

    final pointsData = jsonDecode(pointsResponse.body);
    final stationUrl = pointsData['properties']?['observationStations'];
    if (stationUrl == null) throw Exception('No stations found.');

    // 2. Get the list of nearby stations
    final stationsResponse = await http.get(Uri.parse(stationUrl), headers: {'User-Agent': '(SkyAware, sky.aware@email.com)'});
    if (stationsResponse.statusCode != 200) throw Exception('Failed to get stations. Status: ${stationsResponse.statusCode}');

    final stationsData = jsonDecode(stationsResponse.body);
    final latestObservationsUrl = stationsData['features'][0]?['id'] + '/observations/latest';

    // 3. Get the latest observation from the first station
    final obsResponse = await http.get(Uri.parse(latestObservationsUrl), headers: {'User-Agent': '(SkyAware, sky.aware@email.com)'});
    if (obsResponse.statusCode != 200) throw Exception('Failed to get observations. Status: ${obsResponse.statusCode}');

    return jsonDecode(obsResponse.body)['properties'];
  }

  String _parsePrecipitation(List<dynamic> presentWeather) {
    if (presentWeather.isEmpty) return "None";
    // Return the first precipitation type found
    return presentWeather[0]?['weather'] ?? "None";
  }

  String _parseCloudCeiling(List<dynamic> cloudLayers) {
    for (var layer in cloudLayers) {
      final amount = layer['amount'];
      if (amount == 'BKN' || amount == 'OVC') {
        final elevation = layer['base']?['value'] ?? 0;
        return "${(elevation * 3.28084).toStringAsFixed(0)} ft";
      }
    }
    return "Clear";
  }

  String _degreesToCardinal(num degrees) {
    const List<String> directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'N'];
    return directions[(degrees % 360) ~/ 45];
  }
}
