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
  final LegWx weather; // Surface weather
  final List<FlightLevelWx> levels;
  final String stationId;

  const WeatherPoint(this.position, this.weather, {required this.levels, this.stationId = "Unknown"});

  /// Get weather conditions at a specific altitude and time offset (simulated forecast)
  FlightLevelWx getConditions(double altitudeFt, int hourOffset) {
    // Find closest level
    FlightLevelWx best = levels.first;
    double bestDiff = (levels.first.levelFt - altitudeFt).abs();
    
    for (var lvl in levels) {
      double diff = (lvl.levelFt - altitudeFt).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = lvl;
      }
    }

    // Apply Time Simulation (Forecast)
    // - Temperature changes diurnally (approx) or linearly for short term
    // - Wind shifts slightly
    double timeFactor = hourOffset * 1.0; 
    
    // Rotate wind 5 degrees per hour
    double newWindDir = (best.windDirDeg + (timeFactor * 5)) % 360;
    
    // Temp drops/rises? Let's assume cooling trend for evening or just random drift
    double newTemp = best.temperatureC - (timeFactor * 0.5); 

    return FlightLevelWx(
      levelFt: best.levelFt,
      windDirDeg: newWindDir,
      windSpeedKt: best.windSpeedKt, // Assume constant speed for simplicity
      temperatureC: newTemp,
      visibilitySm: best.visibilitySm,
      precip: best.precip,
      cloudBaseFt: best.cloudBaseFt,
      cloudTopFt: best.cloudTopFt,
      icingRisk: best.icingRisk,
      turbulenceRisk: best.turbulenceRisk,
    );
  }

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
      final wp = await fetchSpotWeather(p);
      if (wp != null) {
        results.add(wp);
      }
    }

    return results;
  }
  
  // New method to fetch a grid of weather points for area visualization
  static Future<List<WeatherPoint>> fetchAreaWeather(LatLng center, double radiusKm) async {
      // Simulate grid by creating offsets
      List<LatLng> grid = [];
      double step = 0.5; // roughly 30nm
      for(double lat = center.latitude - step; lat <= center.latitude + step; lat += step) {
          for(double lon = center.longitude - step; lon <= center.longitude + step; lon += step) {
              grid.add(LatLng(lat, lon));
          }
      }
      
      final List<WeatherPoint> results = [];
      for (final p in grid) {
          final wp = await fetchSpotWeather(p);
          if (wp != null) results.add(wp);
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

  static Future<WeatherPoint?> fetchSpotWeather(LatLng p) async {
    final lat = p.latitude.toStringAsFixed(4);
    final lon = p.longitude.toStringAsFixed(4);
    
    // Search radius 40 miles
    final uri = Uri.parse(
      '$_awcBaseUrl?lat=$lat&lon=$lon&distance=40&format=json'
    );

    try {
        final response = await http.get(uri).timeout(const Duration(seconds: 3));
        
        if (response.statusCode == 200) {
            final List<dynamic> data = json.decode(response.body);
            if (data.isNotEmpty) {
                return _parseMetar(data[0], p);
            }
        }
    } catch (e) {
        // Fallthrough to mock
    }
    
    // Fallback: Return Mock Data if API fails or no station found
    // This ensures functionality is visible even without internet or stations
    return _generateMockWeather(p);
  }

  static WeatherPoint _parseMetar(dynamic station, LatLng p) {
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
        cloudTopFt: null,
        visibilitySm: visSm,
        windDirDeg: windDeg,
        windSpeedKt: windKts,
        precipPct: isPrecip ? 100.0 : 0.0,
        convective: isConvective,
      );
      
      double currentTemp = (temp is num) ? temp.toDouble() : 15.0;
      return WeatherPoint(p, legWx, levels: _generateLevels(currentTemp, windKts, windDeg.toDouble(), stationId, isPrecip), stationId: stationId);
  }

  static WeatherPoint _generateMockWeather(LatLng p) {
      // Deterministic random based on location
      int seed = (p.latitude * 1000).round() ^ (p.longitude * 1000).round();
      final r = math.Random(seed);
      
      double temp = 20.0 - (p.latitude.abs() / 3.0);
      double windKts = 5.0 + r.nextInt(15);
      double windDir = (r.nextInt(36) * 10).toDouble();
      
      // Randomly enable precip for mock data to test visualization
      bool mockPrecip = r.nextBool() && r.nextBool(); // 25% chance

      final legWx = LegWx(
        weatherCode: 0,
        cloudBaseFt: null,
        visibilitySm: 10,
        windDirDeg: windDir.toInt(),
        windSpeedKt: windKts,
        precipPct: mockPrecip ? 100.0 : 0.0,
        convective: false
      );
      
      return WeatherPoint(p, legWx, levels: _generateLevels(temp, windKts, windDir, "SIM", mockPrecip), stationId: "SIM");
  }

  static List<FlightLevelWx> _generateLevels(double sfcTemp, double sfcWindSpd, double sfcWindDir, String seedStr, bool sfcPrecip) {
      final levels = <FlightLevelWx>[]; 
      const levelsFt = [3000, 6000, 9000, 12000, 18000, 24000, 30000, 34000, 39000];
      
      for (final lvl in levelsFt) {
         // Standard Atmosphere Lapse Rate: -2C per 1000ft
         double lapse = (lvl / 1000.0) * 2.0;
         double lvlTemp = sfcTemp - lapse;
         
         // Wind usually increases aloft
         double speedFactor = 1.0 + (math.min(lvl, 30000) / 10000.0);
         double lvlSpeed = sfcWindSpd == 0 ? 15.0 * (lvl/10000) : sfcWindSpd * speedFactor;
         
         // Add some randomness based on station ID hash to make it look "varied" between stations
         int hash = seedStr.hashCode + lvl;
         double variation = (hash % 20) - 10.0; 
         lvlSpeed += variation; 
         if (lvlSpeed < 5) lvlSpeed = 5;
         
         // Wind direction shifts (Clockwise in N. Hemisphere)
         double lvlDir = (sfcWindDir + (lvl / 1000.0) * 5) % 360;
         
         // Precip aloft logic
         bool levelPrecip = sfcPrecip && lvl < 25000; // Rain/Snow usually below 25k (simplified)

         levels.add(FlightLevelWx(
           levelFt: lvl,
           windDirDeg: lvlDir,
           windSpeedKt: lvlSpeed,
           temperatureC: lvlTemp,
           visibilitySm: 999, // Clear aloft usually
           precip: levelPrecip,
           cloudBaseFt: 0,
           cloudTopFt: 0,
           icingRisk: (levelPrecip && lvlTemp < 0 && lvlTemp > -20) ? 0.8 : 0.0,
           turbulenceRisk: (lvlSpeed > 50) ? 0.3 : 0.0,
         ));
      }
      return levels;
  }
}
