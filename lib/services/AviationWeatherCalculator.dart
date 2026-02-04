import 'dart:math';
import 'package:sunrise_sunset_calc/sunrise_sunset_calc.dart';
import 'AdvancedAviationPhysics.dart';

class AviationWeatherCalculator {
  /// Finds the nearest station from a list of airports/stations.
  /// [stations] must contain maps with 'lat', 'lon', and optionally 'icao'.
  static Map<String, dynamic>? findNearestStation({
    required double userLat,
    required double userLon,
    required List<Map<String, dynamic>> stations,
  }) {
    if (stations.isEmpty) return null;

    Map<String, dynamic>? nearest;
    double minKm = double.infinity;

    for (var s in stations) {
      if (s['lat'] != null && s['lon'] != null) {
        double dist = AviationMath.haversineDistance(
          userLat,
          userLon,
          (s['lat'] as num).toDouble(),
          (s['lon'] as num).toDouble(),
        );
        if (dist < minKm) {
          minKm = dist;
          nearest = s;
        }
      }
    }
    return nearest;
  }
}

class AviationMath {
  /// Calculates Density Altitude using the FAA standard formula.
  /// DA = PA + [120 * (OAT - ISA)]
  static double calculateDensityAltitude({
    required double altimeterInHg,
    required double stationElevationFt,
    required double tempC,
  }) {
    double pa = calculatePressureAltitude(
      altimeterInHg: altimeterInHg,
      stationElevationFt: stationElevationFt,
    );
    // Standard Temperature (ISA) = 15 - (2 * (Station_Elevation_ft / 1000))
    double isaTemp = 15 - (2 * (stationElevationFt / 1000));

    return pa + (120 * (tempC - isaTemp));
  }

  /// Calculates Pressure Altitude.
  /// PA = (29.92 - Altimeter_inHg) * 1000 + Station_Elevation_ft
  static double calculatePressureAltitude({
    required double altimeterInHg,
    required double stationElevationFt,
  }) {
    return (29.92 - altimeterInHg) * 1000 + stationElevationFt;
  }

  /// Calculates Relative Humidity using the Magnus-Tetens approximation.
  /// Deprecated: Use AdvancedAviationPhysics.calculateRelativeHumidity instead for higher precision.
  static double calculateRelativeHumidity({
    required double tempC,
    required double dewpointC,
  }) {
    // RH = 100 * (exp((17.625 * Td) / (243.04 + Td)) / exp((17.625 * T) / (243.04 + T)))
    double numer = exp((17.625 * dewpointC) / (243.04 + dewpointC));
    double denom = exp((17.625 * tempC) / (243.04 + tempC));
    return 100 * (numer / denom);
  }

  /// Calculates local sunrise and sunset times using sunrise_sunset_calc.
  /// Returns formatted HH:mm strings.
  static Map<String, String> calculateLocalSunriseSunset({
    required double lat,
    required double lon,
    required DateTime date,
  }) {
    final result = calculateRawSunriseSunset(lat: lat, lon: lon, date: date);

    return {
      'sunrise': _formatTime(result.sunrise),
      'sunset': _formatTime(result.sunset),
    };
  }
  
  /// Returns raw SunriseSunsetResult objects.
  static SunriseSunsetResult calculateRawSunriseSunset({
    required double lat,
    required double lon,
    required DateTime date,
  }) {
    return getSunriseSunset(
      lat,
      lon,
      date.timeZoneOffset,
      date,
    );
  }

  static String _formatTime(DateTime dt) {
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  /// Haversine formula to calculate distance between two coordinates in km.
  static double haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // Radius of the earth in km
    double dLat = _degToRad(lat2 - lat1);
    double dLon = _degToRad(lon2 - lon1);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _degToRad(double deg) => deg * (pi / 180);
}
