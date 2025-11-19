import 'dart:async';
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;


class MetarData {
  final double? visibilitySm;
  final double? cloudBaseFt;

  const MetarData({this.visibilitySm, this.cloudBaseFt});
}

class _Airport {
  final String icao;
  final double lat;
  final double lon;
  const _Airport(this.icao, this.lat, this.lon);
}

class MetarService {
  static const String _host = 'aviationweather.gov';
  static const String _basePath = '/api/data';
  static final Map<String, MetarData> _cache = {};

  static Future<MetarData?> fetchNearestMetar(LatLng p) async {
    // ---- GLOBAL METAR MODE ----
    // Query aviationweather.gov for nearest METAR station globally
    final stationUri = Uri.https(
      _host,
      '$_basePath/stations',
      {
        'format': 'json',
        'lat': p.latitude.toString(),
        'lon': p.longitude.toString(),
        'radius': '150', // km radius for nearest search
      },
    );

    final stationRes = await http.get(stationUri);
    if (stationRes.statusCode != 200) return null;

    final stationJson = jsonDecode(stationRes.body);
    if (stationJson is! List || stationJson.isEmpty) return null;

    // Pick nearest station by haversine
    double bestDist = double.infinity;
    String? bestIcao;
    for (final s in stationJson) {
      if (s is! Map<String, dynamic>) continue;
      final icao = s['icaoId'] ?? s['stationId'];
      final lat = s['latitude'];
      final lon = s['longitude'];
      if (icao == null || lat == null || lon == null) continue;

      final d = Distance().as(
        LengthUnit.Kilometer,
        p,
        LatLng(lat.toDouble(), lon.toDouble()),
      );

      if (d < bestDist) {
        bestDist = d;
        bestIcao = icao.toString();
      }
    }

    if (bestIcao == null) return null;

    // Use caching
    if (_cache.containsKey(bestIcao)) {
      return _cache[bestIcao];
    }
    final station = bestIcao;

    // ---- GLOBAL METAR PARSER ----
    final metarUri = Uri.https(
      _host,
      '$_basePath/metar',
      {'format': 'json', 'ids': station},
    );

    final metarRes = await http.get(metarUri);
    if (metarRes.statusCode != 200) return null;

    final metarJson = jsonDecode(metarRes.body);
    if (metarJson is! List || metarJson.isEmpty) return null;

    final obs = metarJson.first;
    if (obs is! Map<String, dynamic>) return null;

    // Visibility (SM)
    double? visibilitySm;
    final visField = obs['visibility'];
    if (visField is num) {
      visibilitySm = visField.toDouble();
    } else if (visField is String) {
      visibilitySm = double.tryParse(visField);
    }

    // Cloud base from clouds[]
    double? cloudBaseFt;
    if (obs['clouds'] is List) {
      for (final c in obs['clouds']) {
        if (c is Map && c['base'] != null) {
          final base = c['base'];
          if (base is num) {
            cloudBaseFt = base * 100.0;
            break;
          } else {
            final parsed = double.tryParse(base.toString());
            if (parsed != null) {
              cloudBaseFt = parsed * 100.0;
              break;
            }
          }
        }
      }
    }

    // Raw METAR fallback ceiling
    final raw = obs['rawOb'] ?? obs['raw_text'] ?? obs['raw'] ?? '';
    if (raw is String) {
      final parsed = _parseCeilingFromMetar(raw);
      cloudBaseFt ??= parsed;
    }

    final data = MetarData(
      visibilitySm: visibilitySm,
      cloudBaseFt: cloudBaseFt,
    );
    _cache[station] = data;
    return data;
  }

  // Parse ceiling (cloud base) from raw METAR string.
  // Ceiling = lowest VV / OVC / BKN layer, height = XXX * 100 ft.
  static double? _parseCeilingFromMetar(String raw) {
    // Example token: BKN070, OVC008, VV002, etc.
    final reg = RegExp(r'(VV|OVC|BKN)(\d{3})');
    final matches = reg.allMatches(raw);
    if (matches.isEmpty) return null;

    double? best;
    for (final m in matches) {
      final code = m.group(1);
      final hStr = m.group(2);
      if (hStr == null) continue;
      final h = int.tryParse(hStr);
      if (h == null) continue;

      final ft = h * 100.0;
      if (best == null || ft < best) {
        best = ft;
      }
    }
    return best;
  }
}