// import 'dart:async';
// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'package:latlong2/latlong.dart';
//
// import 'WeatherEngine.dart';
//
// class TerrainSample {
//   final LatLng position;
//   final double elevationFt;
//
//   TerrainSample(this.position, this.elevationFt);
// }
//
// class RouteTerrainSummary {
//   final List<TerrainSample> samples;
//   final double maxElevationFt;
//   final double recommendedAltitudeFt;
//
//   RouteTerrainSummary({
//     required this.samples,
//     required this.maxElevationFt,
//     required this.recommendedAltitudeFt,
//   });
// }
//
// class TerrainEngine {
//   static const double _spacingKm = 2.0;
//   static const double _safetyMarginFt = 2500.0;
//
//   static Future<RouteTerrainSummary> fetchRouteTerrain(List<LatLng> path) async {
//     if (path.length < 2) {
//       return RouteTerrainSummary(
//         samples: const [],
//         maxElevationFt: 0,
//         recommendedAltitudeFt: _safetyMarginFt,
//       );
//     }
//
//     final samplesLatLng = WeatherEngine.sampleRoute(path, spacingKm: _spacingKm);
//     final List<TerrainSample> out = [];
//     double maxElevFt = 0;
//
//     const int batchSize = 50;
//     for (int i = 0; i < samplesLatLng.length; i += batchSize) {
//       final int end = (i + batchSize > samplesLatLng.length)
//           ? samplesLatLng.length
//           : i + batchSize;
//       final batch = samplesLatLng.sublist(i, end);
//       final elevs = await _fetchElevationsFtBatch(batch);
//
//       for (int j = 0; j < batch.length; j++) {
//         final elevFt = (j < elevs.length) ? elevs[j] : null;
//         if (elevFt == null) continue;
//
//         final p = batch[j];
//         out.add(TerrainSample(p, elevFt));
//         if (elevFt > maxElevFt) {
//           maxElevFt = elevFt;
//         }
//       }
//     }
//
//     final recommendedAltFt = maxElevFt + _safetyMarginFt;
//
//     return RouteTerrainSummary(
//       samples: out,
//       maxElevationFt: maxElevFt,
//       recommendedAltitudeFt: recommendedAltFt,
//     );
//   }
//
//   static Future<List<double?>> _fetchElevationsFtBatch(List<LatLng> points) async {
//     if (points.isEmpty) return [];
//
//     final locations = points.map((p) => '${p.latitude},${p.longitude}').join('|');
//     final uri = Uri.https('api.opentopodata.org', '/v1/srtm30m', {'locations': locations});
//
//     try {
//       final res = await http.get(uri);
//       if (res.statusCode != 200) {
//         return List<double?>.filled(points.length, null);
//       }
//
//       final json = jsonDecode(res.body);
//       if (json is! Map<String, dynamic>) {
//         return List<double?>.filled(points.length, null);
//       }
//
//       final results = json['results'];
//       if (results is! List || results.isEmpty) {
//         return List<double?>.filled(points.length, null);
//       }
//
//       final List<double?> out = [];
//       for (final r in results) {
//         if (r is! Map<String, dynamic>) {
//           out.add(null);
//           continue;
//         }
//         final elevMeters = r['elevation'];
//         if (elevMeters is! num) {
//           out.add(null);
//           continue;
//         }
//         out.add(elevMeters.toDouble() * 3.28084);
//       }
//
//       while (out.length < points.length) {
//         out.add(null);
//       }
//       return out;
//     } catch (_) {
//       return List<double?>.filled(points.length, null);
//     }
//   }
// }