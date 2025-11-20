import 'dart:async';
import 'dart:convert';
import "../Service/WeatherEngine.dart";
import 'package:latlong2/latlong.dart';
import '../../../Service/weather_service.dart';
import 'package:http/http.dart' as http;

class TerrainSample {
  final LatLng position;
  final double elevationFt;

  TerrainSample(this.position, this.elevationFt);
}

class RouteTerrainSummary {
  final List<TerrainSample> samples;
  final double maxElevationFt;
  final double recommendedAltitudeFt;

  RouteTerrainSummary({
    required this.samples,
    required this.maxElevationFt,
    required this.recommendedAltitudeFt,
  });
}

class TerrainEngine {
  // Use same 2 km spacing as WeatherEngine
  static const double _spacingKm = 2.0;

  // Highest safety tier C: keep at least 2500 ft above terrain
  static const double _safetyMarginFt = 2500.0;

  /// Fetch SRTM 30m terrain profile along the route and
  /// compute an automatic recommended cruise altitude.
  static Future<RouteTerrainSummary> fetchRouteTerrain(
      List<LatLng> path,
      ) async {
    if (path.length < 2) {
      return RouteTerrainSummary(
        samples: const [],
        maxElevationFt: 0,
        recommendedAltitudeFt: _safetyMarginFt,
      );
    }

    // Reuse WeatherEngine's sampling, but fetch elevations in batches
    final samplesLatLng = WeatherEngine._sampleRoute(path, spacingKm: _spacingKm);

    final List<TerrainSample> out = [];
    double maxElevFt = 0;

    // Batch size for OpenTopoData multi-location requests
    const int batchSize = 50;
    for (int i = 0; i < samplesLatLng.length; i += batchSize) {
      final int end = (i + batchSize > samplesLatLng.length)
          ? samplesLatLng.length
          : i + batchSize;
      final batch = samplesLatLng.sublist(i, end);
      final elevs = await _fetchElevationsFtBatch(batch);

      for (int j = 0; j < batch.length; j++) {
        final elevFt = (j < elevs.length) ? elevs[j] : null;
        if (elevFt == null) continue;

        final p = batch[j];
        out.add(TerrainSample(p, elevFt));
        if (elevFt > maxElevFt) {
          maxElevFt = elevFt;
        }
      }
    }

    final recommendedAltFt = maxElevFt + _safetyMarginFt;

    return RouteTerrainSummary(
      samples: out,
      maxElevationFt: maxElevFt,
      recommendedAltitudeFt: recommendedAltFt,
    );
  }

  /// Call SRTM NASA 30m DEM via OpenTopoData API.
  /// Dataset: `srtm30m`
  static Future<double?> _fetchElevationFt(LatLng p) async {
    final uri = Uri.https(
      'api.opentopodata.org',
      '/v1/srtm30m',
      {
        'locations': '${p.latitude},${p.longitude}',
      },
    );

    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;

      final json = jsonDecode(res.body);
      if (json is! Map<String, dynamic>) return null;

      final results = json['results'];
      if (results is! List || results.isEmpty) return null;

      final first = results.first;
      if (first is! Map<String, dynamic>) return null;

      final elevMeters = first['elevation'];
      if (elevMeters is! num) return null;

      // meters -> feet
      return elevMeters.toDouble() * 3.28084;
    } catch (_) {
      return null;
    }
  }

  static Future<List<double?>> _fetchElevationsFtBatch(
      List<LatLng> points,
      ) async {
    if (points.isEmpty) return [];

    final locations = points
        .map((p) => '${p.latitude},${p.longitude}')
        .join('|');

    final uri = Uri.https(
      'api.opentopodata.org',
      '/v1/srtm30m',
      {
        'locations': locations,
      },
    );

    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        // On error, return nulls for all points so caller can skip them.
        return List<double?>.filled(points.length, null);
      }

      final json = jsonDecode(res.body);
      if (json is! Map<String, dynamic>) {
        return List<double?>.filled(points.length, null);
      }

      final results = json['results'];
      if (results is! List || results.isEmpty) {
        return List<double?>.filled(points.length, null);
      }

      final List<double?> out = [];
      for (final r in results) {
        if (r is! Map<String, dynamic>) {
          out.add(null);
          continue;
        }
        final elevMeters = r['elevation'];
        if (elevMeters is! num) {
          out.add(null);
          continue;
        }
        out.add(elevMeters.toDouble() * 3.28084);
      }

      // If API returned fewer results than requested, pad with nulls
      while (out.length < points.length) {
        out.add(null);
      }
      return out;
    } catch (_) {
      return List<double?>.filled(points.length, null);
    }
  }
}