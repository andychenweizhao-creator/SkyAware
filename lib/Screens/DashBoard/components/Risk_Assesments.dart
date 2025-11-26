import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';


class LegWx {
  final int weatherCode;
  final double? cloudBaseFt;
  final double? cloudTopMinFt;
  final double? cloudTopFt; // 最顶层最大云顶高度（兼容原逻辑）
  final double? visibilitySm;
  final int? windDirDeg;
  final double? windSpeedKt;
  final double? precipPct;
  final bool convective;

  LegWx({
    required this.weatherCode,
    this.cloudBaseFt,
    this.cloudTopMinFt,
    this.cloudTopFt,
    this.visibilitySm,
    this.windDirDeg,
    this.windSpeedKt,
    this.precipPct,
    this.convective = false,
  });

  LegWx copyWith({
    int? weatherCode,
    double? cloudBaseFt,
    double? cloudTopMinFt,
    double? cloudTopFt,
    double? visibilitySm,
    int? windDirDeg,
    double? windSpeedKt,
    double? precipPct,
    bool? convective,
  }) {
    return LegWx(
      weatherCode: weatherCode ?? this.weatherCode,
      cloudBaseFt: cloudBaseFt ?? this.cloudBaseFt,
      cloudTopMinFt: cloudTopMinFt ?? this.cloudTopMinFt,
      cloudTopFt: cloudTopFt ?? this.cloudTopFt,
      visibilitySm: visibilitySm ?? this.visibilitySm,
      windDirDeg: windDirDeg ?? this.windDirDeg,
      windSpeedKt: windSpeedKt ?? this.windSpeedKt,
      precipPct: precipPct ?? this.precipPct,
      convective: convective ?? this.convective,
    );
  }

  factory LegWx.empty() {
    return LegWx(weatherCode: 0);
  }
}

/// Service wrapper for aviationweather.gov API
class AviationWeatherService {
  static const String _host = 'aviationweather.gov';
  static const String _basePath = '/api/data';

  /// Generic GET -> JSON helper
  static Future<dynamic> _getJson(
    String endpoint,
    Map<String, String> query,
  ) async {
    final uri = Uri.https(_host, '$_basePath/$endpoint', query);

    // Debug log for you to see in console
    // ignore: avoid_print
    print('🌐 AviationWeather GET: $uri');

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception(
        'AviationWeather error ${res.statusCode}: ${res.body}',
      );
    }
    return jsonDecode(res.body);
  }

  /// METAR for specific ICAO
  static Future<dynamic> fetchMetar(String icao) async {
    return _getJson('metar', {
      'ids': icao,
      'format': 'json',
    });
  }

  /// TAF for specific ICAO
  static Future<dynamic> fetchTaf(String icao) async {
    return _getJson('taf', {
      'ids': icao,
      'format': 'json',
    });
  }

  /// International SIGMET / AIRMET (hazard areas)
  static Future<dynamic> fetchSigmet() async {
    return _getJson('isigmet', {
      'format': 'json',
      'states': 'all', // Ensure we get data for a wide area
    });
  }

  /// Winds/temperature aloft (region all)
  static Future<dynamic> fetchWindTemp() async {
    return _getJson('windtemp', {
      'region': 'all',
      'format': 'json',
    });
  }
}

/// Risk information for a single leg between two waypoints
class LegRisk {
  final LatLng from;
  final LatLng to;

  /// Thunderstorm / convective risk (0–1)
  final double thunderstormRisk;

  /// Icing risk (0–1)
  final double icingRisk;

  /// Turbulence risk (0–1)
  final double turbulenceRisk;

  /// IFR / low-visibility / ceiling risk (0–1)
  final double ifrRisk;

  final int? cloudBaseFt;
  final int? windDirDeg;
  final int? windSpeedKt;
  final double? visibilitySm;

  const LegRisk({
    required this.from,
    required this.to,
    this.thunderstormRisk = 0,
    this.icingRisk = 0,
    this.turbulenceRisk = 0,
    this.ifrRisk = 0,
    this.cloudBaseFt,
    this.windDirDeg,
    this.windSpeedKt,
    this.visibilitySm,
  });

  /// Simple average of all components -> 0 (safe) to 1 (high risk)
  double get total =>
      (thunderstormRisk + icingRisk + turbulenceRisk + ifrRisk) / 4.0;

  /// A descriptive summary of the primary weather risks for this leg.
  String get weatherText {
    final significantRisks = <String>[];
    if (thunderstormRisk > 0.6) significantRisks.add('TSRA'); // Thunderstorm/Rain
    if (icingRisk > 0.6) significantRisks.add('ICING');
    if (turbulenceRisk > 0.6) significantRisks.add('TURB');
    if (ifrRisk > 0.6) significantRisks.add('IFR');

    if (significantRisks.isEmpty) {
      if (total > 0.4) return 'MOD RISK';
      if (total > 0.2) return 'LOW RISK';
      return 'VFR';
    }

    return significantRisks.join(' / ');
  }
}

/// --- Geometry helpers for risk analysis ---
class _GeometryUtils {
  /// Calculate the midpoint of a line segment.
  static LatLng midpoint(LatLng p1, LatLng p2) {
    return LatLng(
        (p1.latitude + p2.latitude) / 2, (p1.longitude + p2.longitude) / 2);
  }

  /// Check if a point is inside a polygon using the ray-casting algorithm.
  static bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.isEmpty) return false;
    int crossings = 0;
    for (int i = 0; i < polygon.length; i++) {
      final LatLng a = polygon[i];
      final LatLng b = polygon[(i + 1) % polygon.length];

      if (a.longitude == b.longitude && a.longitude == point.longitude) {
        if (point.latitude >= min(a.latitude, b.latitude) &&
            point.latitude <= max(a.latitude, b.latitude)) {
          return true; // On a vertical edge.
        }
      }

      if ((point.latitude > a.latitude && point.latitude <= b.latitude) ||
          (point.latitude > b.latitude && point.latitude <= a.latitude)) {
        // Calculate the x-coordinate of the intersection of the ray with the edge.
        final double vt =
            (point.latitude - a.latitude) / (b.latitude - a.latitude);
        final double intersectLon =
            a.longitude + vt * (b.longitude - a.longitude);
        if (point.longitude < intersectLon) {
          crossings++;
        }
      }
    }
    return (crossings % 2) == 1; // True if odd number of crossings.
  }
}

/// Route risk engine: given a flight path + dep/arr ICAO, compute risk per leg.
class RouteRiskEngine {
  /// Analyze the whole route and return a LegRisk list (length = path.length-1)
  static Future<List<LegRisk>> analyzeRoute({
    required List<LatLng> path,
    required String departureIcao,
    required String arrivalIcao,
  }) async {
    if (path.length < 2) return [];

    try {
      // Fetch all relevant weather data in parallel.
      final results = await Future.wait([
        AviationWeatherService.fetchMetar(departureIcao),
        AviationWeatherService.fetchMetar(arrivalIcao),
        AviationWeatherService.fetchSigmet(),
      ]);

      final depMetar = results[0];
      final arrMetar = results[1];
      final List<dynamic> sigmets = results[2] as List<dynamic>;

      final List<LegRisk> legs = [];
      for (int i = 0; i < path.length - 1; i++) {
        final from = path[i];
        final to = path[i + 1];
        final legMidpoint = _GeometryUtils.midpoint(from, to);

        // Default risks
        double thunderstormRisk = 0.05;
        double icingRisk = 0.1;
        double turbulenceRisk = 0.2; // Baseline turbulence is common

        // Check if leg's midpoint falls within any SIGMET polygons
        for (final sigmet in sigmets) {
          if (sigmet is! Map ||
              sigmet['points'] == null ||
              sigmet['points'] is! List) continue;

          final List<LatLng> polygon = (sigmet['points'] as List)
              .map((p) => LatLng(
                    (p['lat'] as num).toDouble(),
                    (p['lon'] as num).toDouble(),
                  ))
              .toList();

          if (_GeometryUtils.isPointInPolygon(legMidpoint, polygon)) {
            final hazard =
                sigmet['hazard']?['type']?.toString().toUpperCase() ?? '';
            switch (hazard) {
              case 'TS':
              case 'TSGR':
              case 'CONV': // Convective activity
                thunderstormRisk = max(thunderstormRisk, 0.9);
                break;
              case 'ICE':
              case 'FZRA': // Freezing Rain
                icingRisk = max(icingRisk, 0.9);
                break;
              case 'TURB':
                turbulenceRisk = max(turbulenceRisk, 0.8);
                break;
            }
          }
        }

        // IFR risk is still best estimated from TAFs/METARs.
        // This simplified version uses the same value for all legs.
        final ifr = _ifrRiskFromMetar(depMetar, arrMetar);

        legs.add(
          LegRisk(
            from: from,
            to: to,
            thunderstormRisk: thunderstormRisk,
            icingRisk: icingRisk,
            turbulenceRisk: turbulenceRisk,
            ifrRisk: ifr,
          ),
        );
      }

      return legs;
    } catch (e) {
      // ignore: avoid_print
      print('❌ RouteRiskEngine.analyzeRoute error: $e');
      return [];
    }
  }

  // This rule remains simple, based on terminal forecasts, as it's for visibility.
  static double _ifrRiskFromMetar(dynamic dep, dynamic arr) {
    final txt = (dep ?? '').toString() + (arr ?? '').toString();
    final upper = txt.toUpperCase();

    // Very rough rules: for demo purposes only
    if (upper.contains('VV') || upper.contains('FG') || upper.contains('<')) {
      return 0.9; // Vertical visibility / Fog / Low viz
    }
    if (upper.contains('OVC') || upper.contains('BKN')) {
      return 0.6; // Overcast / Broken clouds
    }
    if (upper.contains('BR') || upper.contains('HZ')) {
      return 0.4; // Mist / Haze
    }

    return 0.1; // Default VFR is safer
  }
} //
