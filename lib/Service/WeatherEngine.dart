import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xml/xml.dart' as xml;
import 'dart:ui' as ui;
import 'dart:math' as Math;


import '../../../Service/weather_service.dart';


import 'package:http/http.dart' as http;
import "../../../components/WeatherIconResolver.dart";
import "../../../models/metar_airport.dart";
import "../Screens/DashBoard/components/flight_plan_box.dart";


class WeatherEngine {
  static const double _spacingKm = 5.0;

  static const Map<String, String> _baseHeaders = {
    'Accept': 'application/geo+json',
    'User-Agent': 'SkyAware/1.0 (your-email@example.com)',
  };


  static final Distance _dist = const Distance();

  static Future<List<WeatherPoint>> fetchRouteWeather(List<LatLng> path) async {
    if (path.length < 2) return [];

    // Sample the route every _spacingKm, with adaptive density
    final samples = _sampleRoute(path, spacingKm: _spacingKm);

    // For each sample point, call the high‑fidelity _fetchPointWeather()
    final futures = samples.map((p) async {
      try {
        final wx = await _fetchPointWeather(p);
        if (wx == null) return null;
        return WeatherPoint(p, wx);
      } catch (_) {
        return null;
      }
    }).toList();

    final results = await Future.wait(futures);
    return results.whereType<WeatherPoint>().toList();
  }

  static List<LatLng> _sampleRoute(List<LatLng> path, {required double spacingKm}) {
    final List<LatLng> out = [];
    if (path.length < 2) return out;

    // Compute total route length to adapt sampling density.
    double totalMeters = 0;
    for (int i = 0; i < path.length - 1; i++) {
      totalMeters += _dist.as(LengthUnit.Meter, path[i], path[i + 1]);
    }

    double stepMeters = spacingKm * 1000.0;

    // Balanced 模式：
    // - < 150 km: 保持原 spacingKm（例如 5 km）
    // - 150–300 km: 间距约 1.5x
    // - 300–600 km: 间距约 2x
    // - > 600 km: 间距约 3x（超长航路自动降采样）
    if (totalMeters > 600000) {
      stepMeters *= 3.0;
    } else if (totalMeters > 300000) {
      stepMeters *= 2.0;
    } else if (totalMeters > 150000) {
      stepMeters *= 1.5;
    }

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

  static Future<LegWx?> _fetchPointWeather(LatLng p) async {
    const double rainThreshold = 50.0; // B 阈值 50%

    final pointsUri = Uri.https(
      'api.weather.gov',
      '/points/${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}',
    );

    final pointsRes = await http.get(pointsUri, headers: _baseHeaders);
    if (pointsRes.statusCode != 200) return null;

    final pointsJson = jsonDecode(pointsRes.body);
    final props = pointsJson['properties'] as Map<String, dynamic>?;
    if (props == null) return null;

    // Data source priority: forecastHourly → forecastGridData → forecast
    final gridUrl =
    props['forecastHourly'] ??
    props['forecastGridData'] ??
    props['forecast'];

    if (gridUrl == null) return null;

    final gridRes = await http.get(Uri.parse(gridUrl), headers: _baseHeaders);
    if (gridRes.statusCode != 200) return null;

    final gridJson = jsonDecode(gridRes.body);
    final gridProps = gridJson['properties'] as Map<String, dynamic>?;
    if (gridProps == null) return null;

    // Hourly fallback source
    final List<dynamic>? hourly = gridProps['periods'] as List<dynamic>?;

    // STEP 1 — ADD HOURLY WIND + VISIBILITY AUTO DECODE BLOCK
    Map<String, dynamic>? firstHour =
    (hourly != null && hourly.isNotEmpty && hourly.first is Map)
    ? hourly.first as Map<String, dynamic>
        : null;

    String _hf(String key) =>
    firstHour?[key]?.toString().toLowerCase() ?? "";
    String _joinForecastText() =>
    (_hf("shortForecast") + " " + _hf("detailedForecast")).trim();
    final String _wxText = _joinForecastText();

    // Attach nearest METAR fallback
    final metar = await MetarService.fetchNearestMetar(p);

    // ----- Cloud Base (ft) -----
    double? cloudBaseFt = metar?.cloudBaseFt ??
    _extractFirst(gridProps['ceilingHeight'],
    convert: (v, u) => v * 3.28084);

    // ----- Visibility (SM) -----
    double? visibilitySm = metar?.visibilitySm ??
    _extractFirst(gridProps['visibility'],
    convert: (v, u) => v / 1609.34);

    if (cloudBaseFt == null && gridProps['cloudLayers'] != null) {
      final layers = gridProps['cloudLayers']['values'];
      if (layers is List && layers.isNotEmpty) {
        final first = layers.first;
        if (first is Map && first['base'] != null) {
          final raw = first['base']['value'];
          if (raw is num) cloudBaseFt = raw * 3.28084;
        }
      }
    }

    //FIXME: fix indents starting here
  // ---- CLOUD BASE FALLBACK FROM HOURLY TEXT ----
  if (cloudBaseFt == null && firstHour != null) {
  final txt = _wxText;

  // patterns like "ceilings at 1200 ft", "overcast 600 feet", "ceiling 800ft"
  final RegExp cb1 = RegExp(
  r'(ceiling|ceilings?|overcast|broken|bkn|clouds?)\s*(at|near|around)?\s*(\d{2,5})\s*(ft|feet)',
  caseSensitive: false);
  final Match? m1 = cb1.firstMatch(txt);
  if (m1 != null) {
  final double? v = double.tryParse(m1.group(3)!);
  if (v != null) cloudBaseFt = v;
  }

  // patterns like "cloud base 1500 ft"
  if (cloudBaseFt == null) {
  final RegExp cbBase = RegExp(r'(cloud\s*base)\s*(at|near|around)?\s*(\d{2,5})\s*(ft|feet)', caseSensitive: false);
  final Match? mBase = cbBase.firstMatch(txt);
  if (mBase != null) {
  final double? v = double.tryParse(mBase.group(3)!);
  if (v != null) cloudBaseFt = v;
  }
  }

  // patterns like "scattered clouds at 3000ft" or "sct 030"
  if (cloudBaseFt == null) {
  final RegExp cbScattered = RegExp(r'(sct|scattered|few)\s*(clouds?)?\s*(at)?\s*(\d{2,5})\s*(ft|feet)?', caseSensitive: false);
  final Match? mSc = cbScattered.firstMatch(txt);
  if (mSc != null) {
  final double? v = double.tryParse(mSc.group(4)!);
  if (v != null) cloudBaseFt = v;
  }
  }

  // METAR-like patterns: "OVC008", "BKN020", "VV002", "SCT030"
  if (cloudBaseFt == null) {
  final RegExp cb2 = RegExp(r'(OVC|BKN|VV|SCT|FEW)(\d{3})', caseSensitive: false);
  final Match? m2 = cb2.firstMatch(txt.toUpperCase());
  if (m2 != null) {
  final int? h = int.tryParse(m2.group(2)!);
  if (h != null) cloudBaseFt = h * 100.0;
  }
  }

  // If still no cloud base, infer from cloud layer terms
  if (cloudBaseFt == null) {
  if (txt.contains('low clouds')) cloudBaseFt = 800;
  else if (txt.contains('mid level clouds') || txt.contains('mid-level clouds')) cloudBaseFt = 6000;
  else if (txt.contains('high clouds')) cloudBaseFt = 12000;
  }
  // ---- FINAL HARD FAILSAFE FOR CLOUD BASE ----
  // If still null, derive from weather + visibility
  if (cloudBaseFt == null) {
  final hasRain = txt.contains("rain") || txt.contains("shower");
  final hasSnow = txt.contains("snow");
  final hasFog  = txt.contains("fog") || txt.contains("mist") || txt.contains("haze");
  final vis = visibilitySm ?? 6.0;

  if (hasFog) {
  cloudBaseFt = 400; // near-surface fog
  } else if (hasSnow) {
  cloudBaseFt = 1200;
  } else if (hasRain) {
  if (vis < 2.0) cloudBaseFt = 1000;
  else if (vis < 5.0) cloudBaseFt = 1800;
  else cloudBaseFt = 2500;
  } else {
  // Clear or no ceiling info → assume VFR high ceiling
  if (vis >= 8.0) cloudBaseFt = 15000;
  else cloudBaseFt = 12000;
  }
  }
  }

  // STEP 3 — REPLACE VISIBILITY BLOCK
  if (visibilitySm == null && firstHour != null) {
  final txt = _wxText;

  RegExp mile = RegExp(r'visibility\s*(\d+(\.\d+)?)\s*mile');
  Match? m1 = mile.firstMatch(txt);
  if (m1 != null) visibilitySm = double.tryParse(m1.group(1)!);

  RegExp km = RegExp(r'visibility\s*(\d+(\.\d+)?)\s*km');
  Match? m2 = km.firstMatch(txt);
  if (visibilitySm == null && m2 != null) {
  double? v = double.tryParse(m2.group(1)!);
  if (v != null) visibilitySm = v / 1.609;
  }

  RegExp meter = RegExp(r'visibility\s*(\d+(\.\d+)?)\s*m');
  Match? m3 = meter.firstMatch(txt);
  if (visibilitySm == null && m3 != null) {
  double? v = double.tryParse(m3.group(1)!);
  if (v != null) visibilitySm = v / 1609.34;
  }

  if (visibilitySm == null) {
  if (txt.contains("dense fog")) visibilitySm = 0.25;
  else if (txt.contains("fog") || txt.contains("mist")) visibilitySm = 1.0;
  else if (txt.contains("haze")) visibilitySm = 4.0;
  else if (txt.contains("snow")) visibilitySm = 2.0;
  else if (txt.contains("rain") || txt.contains("shower")) visibilitySm = 3.0;
  else visibilitySm = 6.0;
  }
  }

  if (visibilitySm == null && gridProps['weather'] != null) {
  final codeFallback = _extractWx(gridProps['weather']);
  if ([45].contains(codeFallback)) visibilitySm = 0.5;
  else if ([61, 63, 65].contains(codeFallback)) visibilitySm = 3.0;
  else if ([71, 73, 75].contains(codeFallback)) visibilitySm = 2.0;
  else if ([95, 96, 99].contains(codeFallback)) visibilitySm = 1.0;
  }

  // ----- Precip Probability % -----
  double? precipPct = _extractFirst(
  gridProps['probabilityOfPrecipitation'],
  convert: (v, u) => v.toDouble(),
  );

  if (precipPct == null && firstHour != null) {
  final p = firstHour['probabilityOfPrecipitation'];
  if (p is Map && p['value'] != null) {
  final pv = p['value'];
  if (pv is num) precipPct = pv.toDouble();
  }
  }

  // STEP 2 — REPLACE WIND BLOCK
  int? windDirDeg = _extractFirst(
  gridProps['windDirection'],
  convert: (v, u) => v.toDouble(),
  )?.round();

  double? windSpeedKt = _extractFirst(
  gridProps['windSpeed'],
  convert: (v, u) {
  if (u is String && u.contains('km_h')) return v / 1.852;
  if (u is String && u.contains('m_s')) return v * 1.94384;
  return v;
  },
  );

  /// AUTO WIND PARSER (B MODE + G1 gust enabled)
  if (firstHour != null) {
  String wS = _hf("windSpeed");
  String wD = _hf("windDirection");

  // Define full wind direction map including intercardinal 16-point
  final Map<String, int> dirs = {
  "n": 360, "north": 360,
  "nne": 22, "northnortheast": 22, "north-northeast": 22,
  "ne": 45, "northeast": 45,
  "ene": 67, "eastnortheast": 67, "east-northeast": 67,
  "e": 90, "east": 90,
  "ese": 112, "eastsoutheast": 112, "east-southeast": 112,
  "se": 135, "southeast": 135,
  "sse": 157, "southsoutheast": 157, "south-southeast": 157,
  "s": 180, "south": 180,
  "ssw": 202, "southsouthwest": 202, "south-southwest": 202,
  "sw": 225, "southwest": 225,
  "wsw": 247, "westsouthwest": 247, "west-southwest": 247,
  "w": 270, "west": 270,
  "wnw": 292, "westnorthwest": 292, "west-northwest": 292,
  "nw": 315, "northwest": 315,
  "nnw": 337, "northnorthwest": 337, "north-northwest": 337,
  };

  double? gustKt;

  // calm / light wind special cases
  if (wS.contains("calm")) {
  windSpeedKt ??= 0;
  } else if (wS.contains("light") && windSpeedKt == null) {
  windSpeedKt = 3.0;
  }

  // mph ranges: "10 to 20 mph" or "15 mph"
  final RegExp mphR = RegExp(r'(\d+)(?:\s*to\s*(\d+))?\s*mph');
  final Match? mM = mphR.firstMatch(wS);
  if (mM != null) {
  final double? a = double.tryParse(mM.group(1)!);
  final double? b = mM.group(2) != null ? double.tryParse(mM.group(2)!) : null;
  final double? v = (a != null && b != null) ? (a + b) / 2 : a;
  if (v != null) {
  windSpeedKt ??= v * 0.868976; // mph -> kt
  }
  }

  // m/s
  final RegExp msR = RegExp(r'(\d+(\.\d+)?)\s*m/s');
  final Match? msM = msR.firstMatch(wS);
  if (msM != null) {
  final double? v = double.tryParse(msM.group(1)!);
  if (v != null) {
  windSpeedKt ??= v * 1.94384; // m/s -> kt
  }
  }

  // km/h
  final RegExp kmhR = RegExp(r'(\d+(\.\d+)?)\s*km/h');
  final Match? khM = kmhR.firstMatch(wS);
  if (khM != null) {
  final double? v = double.tryParse(khM.group(1)!);
  if (v != null) {
  windSpeedKt ??= v / 1.852; // km/h -> kt
  }
  }

  // gusts: "gusts to 35 mph"
  final RegExp gustR = RegExp(r'gust(?:ing)?\s*(?:to)?\s*(\d+)', caseSensitive: false);
  final Match? gM = gustR.firstMatch(wS);
  if (gM != null) {
  final double? gv = double.tryParse(gM.group(1)!);
  if (gv != null) {
  gustKt = gv * 0.868976; // mph -> kt
  }
  }

  // If we have gusts and steady wind, keep steady in kt and let UI show gust separately if desired
  if (gustKt != null && windSpeedKt != null) {
  // Keep steady windSpeedKt as the mean/steady value in kt.
  // You can render gust in UI from both values instead of encoding "G" into a number.
  }

  // ---- WIND DIRECTION ----
  if (wD.isNotEmpty) {
  final String rawDir = wD.replaceAll('-', '').replaceAll(' ', '');
  final String key = rawDir.toLowerCase();

  // Try direct lookup first
  if (dirs.containsKey(key)) {
  windDirDeg ??= dirs[key];
  } else {
  // Fallback: search for any known token inside the string
  for (final entry in dirs.entries) {
  if (key.contains(entry.key)) {
  windDirDeg ??= entry.value;
  break;
  }
  }
  }

  // variable wind direction
  if (key.contains('vrb') || key.contains('variable')) {
  windDirDeg ??= -1; // mark as variable wind; UI can show "VRB"
  }
  }
  }

  // ----- Weather code -----
  int weatherCode = _extractWx(gridProps['weather']);

  // New rain rule: if precip >= 50% OR weather text indicates rain/shower
  if (weatherCode == 0 && precipPct != null && precipPct >= rainThreshold) {
  weatherCode = 61; // normalize to Rain
  }

  // === ALTITUDE-BASED WEATHER SELECTION (NEW) ===
  // Use the same reference altitude used by VFR logic
  final double? refAltFt = _FlightPlanBoxState.instance?._getReferenceAltitudeFt();

  // If user altitude is ABOVE cloud base → convert weather into IMC layer
  if (refAltFt != null && cloudBaseFt != null) {
  if (refAltFt > cloudBaseFt) {
  // User flying inside/above clouds → visibility must drop, classify as IMC
  visibilitySm = Math.max(0.5, (visibilitySm ?? 3.0) * 0.5);

  // Force weather phenomenon to "cloud / IMC"
  if (weatherCode == 0 || weatherCode == 3) {
  weatherCode = 3; // CLOUD / OVC
  }
  } else {
  // If flying well BELOW cloud base → visibility slightly improves
  if (visibilitySm != null) {
  visibilitySm = Math.min(visibilitySm * 1.1, 10.0);
  }
  }
  }

  final convective = [95, 96, 99].contains(weatherCode);

  return LegWx(
  weatherCode: weatherCode,
  cloudBaseFt: cloudBaseFt,
  visibilitySm: visibilitySm,
  windDirDeg: windDirDeg,
  windSpeedKt: windSpeedKt,
  precipPct: precipPct,
  convective: convective,
  );
  }

  static double? _extractFirst(dynamic field,
  {required double Function(double v, String? u) convert}) {
  if (field == null || field is! Map<String, dynamic>) return null;

  final unit = field['uom'] as String?;
  final List<dynamic>? values = field['values'];
  if (values == null || values.isEmpty) return null;

  final first = values.first;
  if (first is! Map<String, dynamic>) return null;

  final raw = first['value'];
  if (raw == null) return null;

  final double? v =
  (raw is num) ? raw.toDouble() : double.tryParse(raw.toString());
  if (v == null) return null;

  return convert(v, unit);
  }

  static int _extractWx(dynamic field) {
  if (field == null || field is! Map<String, dynamic>) return 0;
  final values = field['values'];
  if (values == null || values.isEmpty) return 0;

  final wx = values.first;
  if (wx is! Map<String, dynamic>) return 0;

  final list = wx['value'];
  if (list is! List || list.isEmpty) return 0;

  final first = list.first;
  if (first is! Map<String, dynamic>) return 0;

  final w = (first['weather'] as String?)?.toLowerCase() ?? '';

  if (w.contains('thunder')) return 95;
  if (w.contains('snow')) return 71;
  if (w.contains('freezing') || w.contains('ice')) return 66;
  if (w.contains('rain') || w.contains('shower')) return 61;
  if (w.contains('drizzle')) return 51;
  if (w.contains('fog')) return 45;
  if (w.contains('cloud')) return 3;
  return 0;
  }
}