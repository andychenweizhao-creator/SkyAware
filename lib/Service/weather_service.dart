import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// AviationWeather.gov METAR API Service
class AviationWeatherService {
  static const String _host = 'aviationweather.gov';
  static const String _basePath = '/api/data';

  static Future<dynamic> _getJson(
    String endpoint,
    Map<String, String> query,
  ) async {
    final uri = Uri.https(_host, '$_basePath/$endpoint', query);
    print('🌐 AWC GET: $uri');

    final res = await http.get(uri, headers: {
      'User-Agent': 'SkyAware/1.0 (+https://aviationweather.gov)',
    });

    if (res.statusCode != 200) {
      throw Exception('AviationWeather error ${res.statusCode}: ${res.body}');
    }

    return jsonDecode(res.body);
  }

  /// Returns nearest METAR for lat/lon
  static Future<Map<String, dynamic>?> nearestMetar(
      double lat, double lon) async {
    final json = await _getJson('metar', {
      'format': 'json',
      'lat': lat.toStringAsFixed(4),
      'lon': lon.toStringAsFixed(4),
      'radius': '100',
      'hours': '1',
    });

    final list = (json is List)
        ? json
        : (json['features'] ??
            json['data'] ??
            json['metars'] ??
            json['METAR']) as List?;

    if (list == null || list.isEmpty) return null;

    final ob = list.first;
    if (ob is Map && ob.containsKey('properties')) {
      return ob['properties'] as Map<String, dynamic>;
    } else if (ob is Map) {
      return Map<String, dynamic>.from(ob);
    } else {
      return null;
    }
  }

  /// Convert METAR JSON → LegWx
  static LegWx decodeMetarToLegWx(Map<String, dynamic> metar) {
    double? cloudBaseFt;
    final clouds = metar['clouds'];
    if (clouds is List && clouds.isNotEmpty) {
      final first = clouds.first;
      if (first is Map && first['base'] != null) {
        final base = first['base'];
        if (base is num) cloudBaseFt = base.toDouble();
        if (base is String) cloudBaseFt = double.tryParse(base);
      }
    }

    double? visSm;
    final visField = metar['visibility'] ?? metar['visibility_sm'];
    if (visField is num) {
      final v = visField.toDouble();
      if (v > 50) {
        visSm = v / 1609.34;
      } else {
        visSm = v;
      }
    } else if (visField is String) {
      visSm = double.tryParse(visField);
    }

    int? windDirDeg;
    double? windSpeedKt;
    final wdir = metar['wind_dir'] ?? metar['wind_direction'];
    final wspd = metar['wind_speed_kt'] ?? metar['wind_speed'];

    if (wdir is num) windDirDeg = wdir.toInt();
    if (wdir is String) windDirDeg = int.tryParse(wdir);

    if (wspd is num) windSpeedKt = wspd.toDouble();
    if (wspd is String) windSpeedKt = double.tryParse(wspd);

    double? precipPct;

    int weatherCode = 0;
    final wxStr = metar['wxString'] ?? metar['weather'];
    if (wxStr is String && wxStr.isNotEmpty) {
      final s = wxStr.toUpperCase();
      if (s.contains('TS')) weatherCode = 95;
      else if (s.contains('SN')) weatherCode = 71;
      else if (s.contains('RA') || s.contains('SH')) weatherCode = 61;
      else if (s.contains('FG') || s.contains('BR')) weatherCode = 45;
      else weatherCode = 0;
    }

    final bool convective = weatherCode == 95 || weatherCode == 96 || weatherCode == 99;

    return LegWx(
      weatherCode: weatherCode,
      cloudBaseFt: cloudBaseFt,
      visibilitySm: visSm,
      windDirDeg: windDirDeg,
      windSpeedKt: windSpeedKt,
      precipPct: precipPct,
      convective: convective,
    );
  }
}

class WeatherPoint {
  final LatLng position;
  final LegWx weather;
  WeatherPoint(this.position, this.weather);
}

class LegWx {
  final int weatherCode;
  final double? cloudBaseFt;
  final double? visibilitySm;
  final int? windDirDeg;
  final double? windSpeedKt;
  final double? precipPct;
  final bool convective;

  LegWx({
    required this.weatherCode,
    this.cloudBaseFt,
    this.visibilitySm,
    this.windDirDeg,
    this.windSpeedKt,
    this.precipPct,
    this.convective = false,
  });

  factory LegWx.empty() {
    return LegWx(weatherCode: 0);
  }
}
