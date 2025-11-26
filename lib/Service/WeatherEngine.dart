import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class SuitabilityResult {
  final bool isSuitable;
  final List<String> warnings;

  const SuitabilityResult({
    required this.isSuitable,
    required this.warnings,
  });

  @override
  String toString() => isSuitable ? "Suitable" : "Unsuitable: ${warnings.join(', ')}";
}

class FlightLevelWx {
  final int levelFt;
  final double windDirDeg;
  final double windSpeedKt;
  final double temperatureC;
  final double visibilitySm;
  final bool precip;
  final double cloudBaseFt;
  final double cloudTopFt;
  final double icingRisk;
  final double turbulenceRisk;

  const FlightLevelWx({
    required this.levelFt,
    required this.windDirDeg,
    required this.windSpeedKt,
    required this.temperatureC,
    required this.visibilitySm,
    required this.precip,
    required this.cloudBaseFt,
    required this.cloudTopFt,
    required this.icingRisk,
    required this.turbulenceRisk,
  });
}

class WeatherPoint {
  final LatLng position;
  final LegWx weather;
  final List<FlightLevelWx> levels;
  final String stationId;

  const WeatherPoint(this.position, this.weather, {required this.levels, this.stationId = "Unknown"});

  SuitabilityResult evaluateSuitability(double altitudeFt) {
    final warnings = <String>[];

    // 1. Cloud Clearance Check
    if (weather.cloudBaseFt != null) {
      final base = weather.cloudBaseFt!;
      final top = weather.cloudTopFt ?? (base + 4000.0); // Estimate thickness for METAR

      final prohibitedBottom = base - 500.0;
      final prohibitedTop = top + 1000.0;

      if (altitudeFt > prohibitedBottom && altitudeFt < prohibitedTop) {
        if (altitudeFt >= base && altitudeFt <= top) {
           warnings.add("Inside Cloud Layer (${base.round()}-${top.round()} ft)");
        } else if (altitudeFt < base) {
           warnings.add("Violates 500ft cloud separation (Base: ${base.round()} ft)");
        } else {
           warnings.add("Violates 1000ft cloud separation (Top: ${top.round()} ft)");
        }
      }
    }

    // 2. Visibility
    if (weather.visibilitySm != null && weather.visibilitySm! < 3.0) {
      warnings.add("Visibility below 3 SM (${weather.visibilitySm!.toStringAsFixed(1)} SM)");
    }

    // 3. Convective
    if (weather.convective) {
      warnings.add("Thunderstorms Reported");
    }

    // 4. Freezing Precip
    if (weather.weatherCode == 66 || weather.weatherCode == 67) {
       warnings.add("Freezing Precipitation");
    }

    return SuitabilityResult(
      isSuitable: warnings.isEmpty,
      warnings: warnings,
    );
  }
}

class LegWx {
  final int weatherCode;
  final double? cloudBaseFt;
  final double? cloudTopMinFt;
  final double? cloudTopFt;
  final double? visibilitySm;
  final int? windDirDeg;
  final double? windSpeedKt;
  final double? precipPct;
  final bool convective;

  const LegWx({
    required this.weatherCode,
    required this.cloudBaseFt,
    this.cloudTopMinFt,
    this.cloudTopFt,
    required this.visibilitySm,
    required this.windDirDeg,
    required this.windSpeedKt,
    required this.precipPct,
    required this.convective,
  });
}

class WeatherEngine {
  static const double _spacingKm = 40.0; // Increased for METAR density
  static const String _awcBaseUrl = "https://aviationweather.gov/api/data/metar";
  static final Distance _dist = const Distance();

  static Future<List<WeatherPoint>> fetchRouteWeather(
    List<LatLng> path, {
    double? referenceAltitudeFt,
  }) async {
    if (path.length < 2) return [];

    // Sample every 40km since METAR stations aren't super dense
    final samples = sampleRoute(path, spacingKm: _spacingKm);
    
    final List<LatLng> targetPoints = samples.length > 12 
        ? [samples.first, ...samples.skip(1).take(10), samples.last]
        : samples;

    final List<WeatherPoint> results = [];
    
    for (final p in targetPoints) {
      try {
        final wp = await _fetchAviationWeatherDotGov(p);
        if (wp != null) {
          results.add(wp);
        }
      } catch (e) {
        print('Error fetching AWC weather for point $p: $e');
      }
    }

    return results;
  }

  static List<LatLng> sampleRoute(List<LatLng> path,
      {required double spacingKm}) {
    final List<LatLng> out = [];
    if (path.length < 2) return out;

    double totalMeters = 0;
    for (int i = 0; i < path.length - 1; i++) {
      totalMeters += _dist.as(LengthUnit.Meter, path[i], path[i + 1]);
    }

    double stepMeters = spacingKm * 1000.0;
    if (totalMeters > 300000) stepMeters *= 1.5;

    for (int i = 0; i < path.length - 1; i++) {
      final a = path[i];
      final b = path[i + 1];

      final segLen = _dist.as(LengthUnit.Meter, a, b);
      if (segLen <= 0) continue;

      int steps = (segLen / stepMeters).floor();
      if (steps < 1) steps = 1;

      for (int s = 0; s <= steps; s++) {
        if (i > 0 && s == 0) continue;

        final t = ((s * stepMeters) / segLen).clamp(0.0, 1.0);
        final lat = a.latitude + (b.latitude - a.latitude) * t;
        final lon = a.longitude + (b.longitude - a.longitude) * t;

        out.add(LatLng(lat, lon));
      }
    }
    return out;
  }

  static Future<WeatherPoint?> _fetchAviationWeatherDotGov(LatLng p) async {
    final lat = p.latitude.toStringAsFixed(4);
    final lon = p.longitude.toStringAsFixed(4);
    
    // Search radius 40 miles
    final uri = Uri.parse(
      '$_awcBaseUrl?lat=$lat&lon=$lon&distance=40&format=json'
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) return null;

    final List<dynamic> data = json.decode(response.body);
    if (data.isEmpty) return null;

    final station = data[0];
    final String stationId = station['icaoId'] ?? "Unknown";

    final dynamic temp = station['temp'];
    final dynamic wdir = station['wdir'];
    final dynamic wspd = station['wspd'];
    final dynamic vis = station['visib'];
    final dynamic clouds = station['clouds'];

    double? baseFt;
    if (clouds != null && clouds is List) {
      for (final c in clouds) {
        final cover = c['cover'];
        final base = c['base'];
        if ((cover == 'BKN' || cover == 'OVC') && base is num) {
           if (baseFt == null || base < baseFt) baseFt = base.toDouble();
        }
      }
    }

    double visSm = (vis is num) ? vis.toDouble() : 10.0;
    double windKts = (wspd is num) ? wspd.toDouble() : 0.0;
    int windDeg = (wdir is num) ? wdir.toInt() : 0;

    String wxStr = (station['wxString'] as String? ?? "").toUpperCase();
    bool isConvective = wxStr.contains("TS");
    bool isPrecip = wxStr.contains("RA") || wxStr.contains("SN") || wxStr.contains("FZ");
    
    int code = 0;
    if (isConvective) code = 95;
    else if (wxStr.contains("FZ")) code = 66;
    else if (wxStr.contains("SN")) code = 71;
    else if (wxStr.contains("RA")) code = 61;
    else if (baseFt != null && baseFt < 1000) code = 3; // Low clouds fallback

    final legWx = LegWx(
      weatherCode: code,
      cloudBaseFt: baseFt,
      cloudTopFt: null, // METAR has no tops
      visibilitySm: visSm,
      windDirDeg: windDeg,
      windSpeedKt: windKts,
      precipPct: isPrecip ? 100.0 : 0.0,
      convective: isConvective,
    );

    // Create dummy levels since we only have surface
    final levels = <FlightLevelWx>[]; 
    // (Implementation omitted for brevity as we rely on surface METAR mostly for this mode)

    return WeatherPoint(p, legWx, levels: levels, stationId: stationId);
  }
}
