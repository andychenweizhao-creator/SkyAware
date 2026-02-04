import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/weather_model.dart';
import 'AviationWeatherCalculator.dart';

class OpenMeteoService {
  static const String _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  /// Fetches weather data matching the user's specific URL requirements.
  /// Dynamically replaces location, elevation, timezone, and units.
  Future<WeatherModel> getWeather({
    required double lat,
    required double lon,
    required double altitudeFt,
    required bool useMetric,
  }) async {
    try {
      // 1. Elevation Calculation (ft -> meters)
      int elevationMeters = (altitudeFt * 0.3048).round();

      // 2. Dynamic Units Construction
      String unitParams;
      if (useMetric) {
        unitParams = '&temperature_unit=celsius&wind_speed_unit=kmh&precipitation_unit=mm';
      } else {
        unitParams = '&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch';
      }

      // 3. URL Construction
      // current: Requested fields
      String currentFields = 'temperature_2m,relative_humidity_2m,dew_point_2m,precipitation,rain,showers,snowfall,wind_speed_10m,wind_direction_10m,wind_gusts_10m,cloud_cover,pressure_msl,surface_pressure,visibility,weather_code';

      // Removing models=hrrr as it caused 400 Bad Request
      String params =
          'latitude=$lat&longitude=$lon&elevation=$elevationMeters'
          '&current=$currentFields'
          '$unitParams'
          '&timezone=auto';

      // Dynamic URL Construction
      Uri uri = Uri.parse('$_baseUrl?$params');

      var response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current'];
        final currentUnits = data['current_units'];

        // --- Data Mapping & Display Formatting ---

        // Temperature (Raw value)
        double temp = (current['temperature_2m'] as num).toDouble();
        
        // Dewpoint (Raw value)
        double dewpoint = (current['dew_point_2m'] as num).toDouble();
        
        // Humidity (Raw value)
        double humidity = (current['relative_humidity_2m'] as num).toDouble();
        
        // Wind (Raw value)
        double windSpeed = (current['wind_speed_10m'] as num).toDouble();
        double windDir = (current['wind_direction_10m'] as num).toDouble();

        // Pressure (UI) - Display Altimeter Setting
        // API returns pressure_msl in hPa (default) unless unit specified.
        // We did not specify pressure_unit, so it is hPa.
        double rawPressureHpa = (current['pressure_msl'] as num).toDouble();
        String pressureString;
        if (useMetric) {
          // Format as hPa
          pressureString = "${rawPressureHpa.toStringAsFixed(2)} hPa";
        } else {
          // Convert to inHg for Imperial display
          double pressureInHg = rawPressureHpa * 0.02953;
          pressureString = "${pressureInHg.toStringAsFixed(2)} inHg";
        }

        // Visibility (UI)
        // API returns meters.
        double visMeters = (current['visibility'] as num).toDouble();
        String visibilityString;
        if (useMetric) {
          double visKm = visMeters / 1000;
          visibilityString = "${visKm.toStringAsFixed(1)} km";
        } else {
          double visMiles = visMeters * 0.000621371;
          visibilityString = "${visMiles.toStringAsFixed(1)} mi";
        }

        // Cloud Cover (UI)
        String ceiling = "${current['cloud_cover']}%";

        // Precipitation (UI)
        double precipVal = (current['precipitation'] as num).toDouble();
        String precipUnit = currentUnits['precipitation'] ?? (useMetric ? 'mm' : 'inch');
        String precipString = "${precipVal.toStringAsFixed(2)} $precipUnit";

        // Weather Code
        int code = (current['weather_code'] as num).toInt();
        String condition = _mapWmoCode(code);


        // --- Density Altitude Calculation ---
        // Requirement: Use surface_pressure + temperature_2m + elevation. NOT MSL.
        // Formula: DA = PressureAltitude + 120 * (TempC - ISATemp)
        
        // 1. Get Surface Pressure (hPa)
        double surfacePressureHpa = (current['surface_pressure'] as num).toDouble();
        
        // 2. Calculate Pressure Altitude from Station Pressure (ft)
        // PA = 145442.16 * (1 - (hPa / 1013.25) ^ 0.190263)
        double pressureAltitude = 145442.16 * (1 - pow((surfacePressureHpa / 1013.25), 0.190263));

        // 3. Get Temp in Celsius (if units are Fahrenheit, convert locally for formula)
        double tempC = useMetric ? temp : (temp - 32) * 5 / 9;

        // 4. ISA Temp at Pressure Altitude
        double isaTemp = 15 - (2 * (pressureAltitude / 1000));

        // 5. Final DA
        double densityAltitude = pressureAltitude + (120 * (tempC - isaTemp));


        // --- Sunrise/Sunset ---
        final sunTimes = AviationMath.calculateRawSunriseSunset(
          lat: lat,
          lon: lon,
          date: DateTime.now(),
        );

        return WeatherModel(
          temperature: temp,
          windSpeed: windSpeed,
          windDirection: windDir,
          pressure: pressureString,
          humidity: humidity,
          dewpoint: dewpoint,
          condition: condition,
          visibility: visibilityString,
          flightCategory: null,
          ceiling: ceiling,
          densityAltitude: densityAltitude,
          stationId: "GPS (Open-Meteo)",
          altitudeFt: altitudeFt,
          latitude: lat,
          longitude: lon,
          locationName: "Local Forecast",
          isInterpolated: true,
          precip: precipString,
          sunrise: sunTimes.sunrise,
          sunset: sunTimes.sunset,
        );

      } else {
        throw Exception('Failed to load weather data: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching Open-Meteo data: $e');
    }
  }

  String _mapWmoCode(int code) {
    // WMO Weather interpretation codes (WW)
    switch (code) {
      case 0: return 'Clear sky';
      case 1: return 'Mainly clear';
      case 2: return 'Partly cloudy';
      case 3: return 'Overcast';
      case 45: return 'Fog';
      case 48: return 'Depositing rime fog';
      case 51: return 'Light Drizzle';
      case 53: return 'Moderate Drizzle';
      case 55: return 'Dense Drizzle';
      case 61: return 'Slight Rain';
      case 63: return 'Moderate Rain';
      case 65: return 'Heavy Rain';
      case 71: return 'Slight Snow';
      case 73: return 'Moderate Snow';
      case 75: return 'Heavy Snow';
      case 77: return 'Snow grains';
      case 80: return 'Slight Rain Showers';
      case 81: return 'Moderate Rain Showers';
      case 82: return 'Violent Rain Showers';
      case 85: return 'Slight Snow Showers';
      case 86: return 'Heavy Snow Showers';
      case 95: return 'Thunderstorm';
      case 96: return 'Thunderstorm with Hail';
      case 99: return 'Thunderstorm with Hail';
      default: return 'Unknown ($code)';
    }
  }
}
