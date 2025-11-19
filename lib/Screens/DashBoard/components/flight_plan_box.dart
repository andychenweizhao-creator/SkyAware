// ========================
//  flight_plan_box.dart
//  WEATHER PROFILE + DETAIL BUBBLES
// ========================

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
import 'Risk_Assesments.dart' hide LegWx;

import 'package:http/http.dart' as http;
import "../../../components/WeatherIconResolver.dart";
import "../../../models/metar_airport.dart";




// =========================
//     WEATHER ENGINE
//  ForeFlight‑Grade 2 km Grid
// =========================

// --- METAR & Nearest Airport helpers ---







class WeatherEngine {
  static const double _spacingKm = 5.0;

  static const Map<String, String> _baseHeaders = {
    'Accept': 'application/geo+json',
    'User-Agent': 'SkyAware/1.0 (your-email@example.com)',
  };

  static final Distance _dist = const Distance();

  static Future<List<WeatherPoint>> fetchRouteWeather(
      List<LatLng> path) async {
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

  static List<LatLng> _sampleRoute(List<LatLng> path,
      {required double spacingKm}) {
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

// =========================
//     TERRAIN ENGINE
//  SRTM NASA 30 m DEM (auto +2500 ft)
// =========================



extension FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

class FlightPlanBox extends StatefulWidget {
  const FlightPlanBox({super.key});

  @override
  State<FlightPlanBox> createState() => _FlightPlanBoxState();
}

enum FlightMode { auto, preflight, inflight }

class _FlightPlanBoxState extends State<FlightPlanBox> {
  static _FlightPlanBoxState? instance;
  FlightMode _flightMode = FlightMode.auto;
  bool _isRefreshingWeather = false;
  List<LatLng> _flightPath = [];
  List<String> _waypointNames = [];
  final MapController _mapController = MapController();
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  LatLng? _departureAirport;
  LatLng? _arrivalAirport;
  String _mapStyle = 'osm';

  final Map<String, String> _tileSources = {
    'osm': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'terrain': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    'satellite':
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    'wunderground': 'webview',
  };

  List<LegRisk> _legRisks = [];
  List<WeatherPoint> _weatherPoints = [];
  WeatherPoint? _hoverWeather;
  // Terrain profile (SRTM 30m) and auto altitude suggestion
  List<TerrainSample> _terrainSamples = [];
  double? _maxTerrainFt;
  double? _recommendedAltitudeFt;
  // User-provided planned cruise altitude (ft), used in preflight for terrain checks
  double? _plannedAltitudeFt;


  @override
  void initState() {
    super.initState();
    _FlightPlanBoxState.instance = this;
    _initLocationStream();
  }

  Future<void> _initLocationStream() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    _positionStream =
        Geolocator.getPositionStream().listen((Position position) {
          if (mounted) {
            setState(() => _currentPosition = position);
          }
        });
  }
  double? _getReferenceAltitudeFt() {
    // AUTO MODE
    if (_flightMode == FlightMode.auto) {
      final double airspeed = _currentPosition?.speed ?? 0;

      if (airspeed < 10) {
        // Preflight auto detection — ensure value exists to prevent null altitude → no weather risk shown
        return _plannedAltitudeFt ?? _recommendedAltitudeFt ?? 15000;
      } else {
        if (_currentPosition?.altitude != null) {
          return _currentPosition!.altitude * 3.28084;
        }
        // fallback if GPS altitude unavailable
        return _recommendedAltitudeFt ?? 15000;
      }
    }

    // FORCE PREFLIGHT
    if (_flightMode == FlightMode.preflight) {
      return _plannedAltitudeFt ?? _recommendedAltitudeFt ?? 15000;
    }

    // FORCE IN-FLIGHT WITH GPS
    if (_currentPosition?.altitude != null) {
      return _currentPosition!.altitude * 3.28084;
    }

    // Final fallback ensures weather risks still appear
    return _recommendedAltitudeFt ?? 15000;
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  // -------------------------
  //   Upload & Parse .fpl
  // -------------------------
  Future<void> _uploadAndParseFpl() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
      allowCompression: false,
    );

    if (result == null) return;

    final filePath = result.files.single.path!;
    final lower = filePath.toLowerCase();

    if (!(lower.endsWith('.fpl') ||
        lower.endsWith('.xml') ||
        lower.endsWith('.pln') ||
        lower.endsWith('.fms') ||
        lower.endsWith('.txt'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid file type.')),
      );
      return;
    }

    Uint8List? bytes = result.files.single.bytes;
    if (bytes == null && result.files.single.path != null) {
      bytes = await File(result.files.single.path!).readAsBytes();
    }
    if (bytes == null) return;

    final content = utf8.decode(bytes);
    List<LatLng> path = [];
    List<String> names = [];

    bool parsedAsXml = false;

    try {
      final cleaned = content.replaceAll(RegExp('xmlns="[^"]*"'), '');
      final document = xml.XmlDocument.parse(cleaned);

      // Garmin waypoint lookup
      final Map<String, LatLng> waypointLookup = {};
      for (final wp in document.findAllElements('waypoint')) {
        final id = wp.findElements('identifier').firstOrNull?.innerText;
        final latStr = wp.findElements('lat').firstOrNull?.innerText;
        final lonStr = wp.findElements('lon').firstOrNull?.innerText;
        if (id != null && latStr != null && lonStr != null) {
          final lat = double.tryParse(latStr);
          final lon = double.tryParse(lonStr);
          if (lat != null && lon != null) {
            waypointLookup[id] = LatLng(lat, lon);
          }
        }
      }

      // Garmin route points
      final routePoints = document.findAllElements('route-point');
      if (routePoints.isNotEmpty) {
        parsedAsXml = true;
        for (final rp in routePoints) {
          final id =
              rp.findElements('waypoint-identifier').firstOrNull?.innerText;
          if (id != null && waypointLookup.containsKey(id)) {
            path.add(waypointLookup[id]!);
            names.add(id);
          }
        }
      }

      // SimBrief / generic waypoint parsing
      final waypoints = document.findAllElements('waypoint', namespace: '*');
      final fixes = document.findAllElements('fix', namespace: '*');

      if (waypoints.isNotEmpty && !parsedAsXml) {
        parsedAsXml = true;
        for (final wp in waypoints) {
          String? latString =
              wp.findElements('lat', namespace: '*').firstOrNull?.innerText;
          String? lonString =
              wp.findElements('lon', namespace: '*').firstOrNull?.innerText;

          latString ??= wp.getAttribute('lat');
          lonString ??= wp.getAttribute('lon');

          if (latString != null && lonString != null) {
            final lat = double.tryParse(latString);
            final lon = double.tryParse(lonString);
            if (lat != null && lon != null) {
              path.add(LatLng(lat, lon));
              names.add(wp.getAttribute('id') ??
                  wp.getAttribute('name') ??
                  'WP${names.length + 1}');
            }
          }
        }
      }

      if (fixes.isNotEmpty && !parsedAsXml) {
        parsedAsXml = true;
        for (final fix in fixes) {
          final latStr = fix.findElements('lat').firstOrNull?.innerText;
          final lonStr = fix.findElements('lon').firstOrNull?.innerText;
          if (latStr != null && lonStr != null) {
            final lat = double.tryParse(latStr);
            final lon = double.tryParse(lonStr);
            if (lat != null && lon != null) {
              path.add(LatLng(lat, lon));
              names.add(fix.getAttribute('id') ??
                  fix.getAttribute('name') ??
                  'WP${names.length + 1}');
            }
          }
        }
      }

      // ForeFlight-style <leg>
      final legs = document.findAllElements('leg');
      if (legs.isNotEmpty && !parsedAsXml) {
        parsedAsXml = true;
        for (final leg in legs) {
          final latStr = leg.getAttribute('lat');
          final lonStr = leg.getAttribute('lon');
          if (latStr != null && lonStr != null) {
            final lat = double.tryParse(latStr);
            final lon = double.tryParse(lonStr);
            if (lat != null && lon != null) {
              path.add(LatLng(lat, lon));
              names.add(leg.getAttribute('id') ??
                  leg.getAttribute('name') ??
                  'WP${names.length + 1}');
            }
          }
        }
      }
    } catch (_) {}

    // Fallback text parsing
    if (!parsedAsXml) {
      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 3 &&
            ['AIRP', 'ADEP', 'ADES', 'WAYP', 'FIX', 'NDB', 'VOR', 'GPS']
                .contains(parts[0].toUpperCase())) {
          final lat = double.tryParse(parts[parts.length - 2]);
          final lon = double.tryParse(parts[parts.length - 1]);
          if (lat != null && lon != null) {
            path.add(LatLng(lat, lon));
            names.add('WP${names.length + 1}');
          }
        } else {
          final ll = trimmed.split(',');
          if (ll.length == 2) {
            final lat = double.tryParse(ll[0]);
            final lon = double.tryParse(ll[1]);
            if (lat != null && lon != null) {
              path.add(LatLng(lat, lon));
              names.add('WP${names.length + 1}');
            }
          }
        }
      }
    }

    setState(() {
      _flightPath = path;
      _waypointNames = names;
      _departureAirport = path.isNotEmpty ? path.first : null;
      _arrivalAirport = path.length > 1 ? path.last : null;
      _weatherPoints = []; // Clear previous weather points
      _terrainSamples = [];
      _maxTerrainFt = null;
      _recommendedAltitudeFt = null;
    });

    // Fetch high-resolution weather and terrain for the route in parallel
    final weatherFuture = WeatherEngine.fetchRouteWeather(path);
    final terrainFuture = TerrainEngine.fetchRouteTerrain(path);

    final weatherPoints = await weatherFuture;
    final terrainSummary = await terrainFuture;

    setState(() {
      _weatherPoints = weatherPoints;
      _terrainSamples = terrainSummary.samples;
      _maxTerrainFt = terrainSummary.maxElevationFt;
      _recommendedAltitudeFt = terrainSummary.recommendedAltitudeFt;
    });

    // Disabled OpenAI-dependent risk engine and route risk analysis.
    _legRisks = [];
    // Commented out all OpenAI/risk engine code below:
    // final riskFuture = RiskEngine.analyzeRoute(...);
    // await riskFuture;
    // setState(() { _legRisks = ... });

    // Fit map
    if (_flightPath.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(_flightPath);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50),
        ),
      );
    }
  }

  // -------------------------
  //   VFR ANALYSIS HELPER
  // -------------------------
  Map<String, dynamic> _buildVfrAnalysisForPoint(LegWx wx) {
    final double? clouds = wx.cloudBaseFt;
    final double? vis = wx.visibilitySm;
    final int? windDir = wx.windDirDeg;
    final double? windSpeed = wx.windSpeedKt;
    final double? precip = wx.precipPct;
    final int wxCode = wx.weatherCode;

    String category = 'UNKNOWN';
    String suitability = 'Insufficient data to evaluate.';
    final List<String> reasons = [];
    final List<String> hazards = [];

    if (clouds != null || vis != null) {
      final double? c = clouds;
      final double? v = vis;

      // If cloudBase is missing, assume very high (>10000 ft)
      final double cloudsSafe = c ?? 15000;

      // If visibility is missing, assume very good (>= 10 SM)
      final double visSafe = v ?? 10.0;

      // FAA 常用的 LIFR / IFR / MVFR / VFR 分级：
      // LIFR: ceiling < 500 ft 或 vis < 1 SM
      // IFR:  500–<1000 ft 或 vis 1–<3 SM
      // MVFR: 1000–<3000 ft 或 vis 3–<5 SM
      // VFR:  ceiling >= 3000 ft 且 vis >= 5 SM
      if (cloudsSafe < 500 || visSafe < 1.0) {
        category = 'LIFR';
        suitability = 'Highly unsuitable for VFR (IFR required).';
        if (cloudsSafe < 500) {
          reasons.add('Ceiling ${cloudsSafe.toStringAsFixed(0)} ft < 500 ft LIFR threshold.');
        }
        if (visSafe < 1.0) {
          reasons.add('Visibility ${visSafe.toStringAsFixed(1)} SM < 1 SM LIFR threshold.');
        }
      } else if (cloudsSafe < 1000 || visSafe < 3.0) {
        category = 'IFR';
        suitability = 'Not suitable for VFR (IFR recommended).';
        if (cloudsSafe < 1000) {
          reasons.add('Ceiling ${cloudsSafe.toStringAsFixed(0)} ft < 1000 ft IFR threshold.');
        }
        if (visSafe < 3.0) {
          reasons.add('Visibility ${visSafe.toStringAsFixed(1)} SM < 3 SM IFR/VFR boundary.');
        }
      } else if (cloudsSafe < 3000 || visSafe < 5.0) {
        category = 'MVFR';
        suitability = 'Marginal VFR (flyable but requires great caution).';
        if (cloudsSafe < 3000) {
          reasons.add('Ceiling ${cloudsSafe.toStringAsFixed(0)} ft is between 1000–3000 ft (MVFR).');
        }
        if (visSafe < 5.0) {
          reasons.add('Visibility ${visSafe.toStringAsFixed(1)} SM is between 3–5 SM (MVFR).');
        }
      } else {
        category = 'VFR';
        suitability = 'Suitable for VFR flight.';
        reasons.add('Ceiling ≥ 3000 ft and visibility ≥ 5 SM meet typical VFR criteria.');
      }

      // Additional hazard factors based on precip, wind, and weather code.
      if (precip != null) {
        if (precip >= 70) {
          hazards.add('High precipitation probability (${precip.toStringAsFixed(0)}%), visibility very likely reduced.');
        } else if (precip >= 40) {
          hazards.add('Moderate to high precipitation probability (${precip.toStringAsFixed(0)}%), visibility may be reduced.');
        } else if (precip >= 20) {
          hazards.add('Some chance of precipitation (${precip.toStringAsFixed(0)}%), monitor actual conditions.');
        }
      }

      if (windSpeed != null) {
        if (windSpeed >= 35) {
          hazards.add('Strong winds (${windSpeed.toStringAsFixed(0)} kt) may cause significant turbulence and crosswind risk.');
        } else if (windSpeed >= 25) {
          hazards.add('Elevated winds (${windSpeed.toStringAsFixed(0)} kt); use caution for takeoff, landing, and low-level flight.');
        }
      }

      if ([95, 96, 99].contains(wxCode)) {
        hazards.add('Thunderstorms / strong convection (weather code $wxCode); VFR is strongly discouraged.');
      } else if ([61, 63, 65].contains(wxCode)) {
        hazards.add('Moderate to heavy rain (weather code $wxCode) significantly reduces surface and in-flight visibility.');
      } else if ([71, 73, 75].contains(wxCode)) {
        hazards.add('Snow (weather code $wxCode) may reduce visibility and cause accumulation.');
      } else if ([66, 67].contains(wxCode)) {
        hazards.add('Freezing rain or ice pellets (weather code $wxCode) imply icing risk.');
      } else if ([51, 53, 55].contains(wxCode)) {
        hazards.add('Drizzle / light rain (weather code $wxCode) may reduce visibility.');
      }

      // === Altitude-based cloud clearance hazard (Preflight / In-flight unified) ===
      final double? refAltFt = _getReferenceAltitudeFt();
      if (refAltFt != null && clouds != null) {
        final double clearanceToBase = clouds - refAltFt;
        final bool usePlannedAlt = _flightMode == FlightMode.preflight ||
            (_flightMode == FlightMode.auto && (_currentPosition?.speed ?? 0) < 10);
        final String altSourceText =
        usePlannedAlt ? "Planned altitude" : "Current altitude";

        if (clearanceToBase < 0) {
          hazards.add(
              '$altSourceText is above the cloud base (IMC), which is not legal for VFR flight.');
        } else if (clearanceToBase < 500) {
          hazards.add(
              '$altSourceText is only ${clearanceToBase.toStringAsFixed(0)} ft below the ceiling, not meeting the recommended 500 ft VFR clearance.');
        }
      }
    }

    return {
      'clouds': clouds,
      'vis': vis,
      'windDir': windDir,
      'windSpeed': windSpeed,
      'category': category,
      'suitability': suitability,
      'reason': reasons.join('\n• '),
      'precip': precip,
      'hazards': hazards,
    };
  }

  // ===============================
  // Weather Merge (80km Adaptive)
  // ===============================
  List<WeatherPoint> _mergeWeatherPointsAdaptive(List<WeatherPoint> list) {
    if (list.length < 2) return list;

    double baseMergeKm = (_flightMode == FlightMode.preflight) ? 80.0 : 50.0;
    final Distance distance = const Distance();

    bool similarWx(LegWx a, LegWx b) {
      final ca = _buildVfrAnalysisForPoint(a);
      final cb = _buildVfrAnalysisForPoint(b);

      if (ca['category'] != cb['category']) return false;

      final ac = ca['clouds'];
      final bc = cb['clouds'];
      if (ac != null && bc != null) {
        if ((_flightMode == FlightMode.preflight && (ac - bc).abs() > 400) ||
            (_flightMode != FlightMode.preflight && (ac - bc).abs() > 800)) {
          return false;
        }
      }

      final av = ca['vis'];
      final bv = cb['vis'];
      if (av != null && bv != null) {
        if ((_flightMode == FlightMode.preflight && (av - bv).abs() > 1.2) ||
            (_flightMode != FlightMode.preflight && (av - bv).abs() > 2.5)) {
          return false;
        }
      }

      final ap = ca['precip'];
      final bp = cb['precip'];
      if (ap != null && bp != null) {
        if ((_flightMode == FlightMode.preflight && (ap - bp).abs() > 15) ||
            (_flightMode != FlightMode.preflight && (ap - bp).abs() > 30)) {
          return false;
        }
      }

      return true;
    }

    WeatherPoint buildWeightedCenter(List<WeatherPoint> c) {
      if (c.length == 1) return c.first;

      double totalDist = 0;
      List<double> weights = [0];

      for (int i = 1; i < c.length; i++) {
        final d = distance.as(LengthUnit.Kilometer, c[i - 1].position, c[i].position);
        totalDist += d;
        weights.add(totalDist);
      }

      final double sumWeights = weights.reduce((a, b) => a + b);
      double lat = 0, lon = 0;

      for (int i = 0; i < c.length; i++) {
        final w = weights[i] / sumWeights;
        lat += c[i].position.latitude * w;
        lon += c[i].position.longitude * w;
      }

      // --- Compute averaged weather values for merged cluster ---
      double? avgCloudBase;
      double? avgVis;
      int? avgWindDir;
      double? avgWindSpeed;
      double? avgPrecip;

      // simple accumulator
      double sumCloud = 0, countCloud = 0;
      double sumVis = 0, countVis = 0;
      double sumDirX = 0, sumDirY = 0, countDir = 0;
      double sumWind = 0, countWind = 0;
      double sumPrecip = 0, countPrecip = 0;

      for (final wp in c) {
        final wx = wp.weather;

        if (wx.cloudBaseFt != null) {
          sumCloud += wx.cloudBaseFt!;
          countCloud++;
        }
        if (wx.visibilitySm != null) {
          sumVis += wx.visibilitySm!;
          countVis++;
        }
        if (wx.windDirDeg != null && wx.windDirDeg! >= 0) {
          final rad = wx.windDirDeg! * 3.1415926535 / 180.0;
          sumDirX += Math.cos(rad);
          sumDirY += Math.sin(rad);
          countDir++;
        }
        if (wx.windSpeedKt != null) {
          sumWind += wx.windSpeedKt!;
          countWind++;
        }
        if (wx.precipPct != null) {
          sumPrecip += wx.precipPct!;
          countPrecip++;
        }
      }

      avgCloudBase = countCloud > 0 ? sumCloud / countCloud : null;
      avgVis = countVis > 0 ? sumVis / countVis : null;
      avgWindSpeed = countWind > 0 ? sumWind / countWind : null;
      avgPrecip = countPrecip > 0 ? sumPrecip / countPrecip : null;

      if (countDir > 0) {
        final meanDirRad = Math.atan2(sumDirY / countDir, sumDirX / countDir);
        final deg = (meanDirRad * 180.0 / 3.1415926535);
        avgWindDir = ((deg % 360) + 360).toInt() % 360;
      }

      // build new averaged wx object
      final baseWx = c.first.weather;
      final newWx = LegWx(
        weatherCode: baseWx.weatherCode,
        cloudBaseFt: avgCloudBase,
        visibilitySm: avgVis,
        windDirDeg: avgWindDir,
        windSpeedKt: avgWindSpeed,
        precipPct: avgPrecip,
        convective: baseWx.convective,
      );

      return WeatherPoint(LatLng(lat, lon), newWx);
    }

    List<WeatherPoint> result = [];
    List<WeatherPoint> cluster = [list.first];

    for (int i = 1; i < list.length; i++) {
      final prev = cluster.last;
      final curr = list[i];
      final d = distance.as(LengthUnit.Kilometer, prev.position, curr.position);

      if (d <= baseMergeKm && similarWx(prev.weather, curr.weather)) {
        cluster.add(curr);
      } else {
        result.add(buildWeightedCenter(cluster));
        cluster = [curr];
      }
    }

    result.add(buildWeightedCenter(cluster));
    return result;
  }

  Widget _buildHoverWeatherBubble(LegWx wx) {
    final wxData = _buildVfrAnalysisForPoint(wx);
    final double? clouds = wxData['clouds'] as double?;
    final double? vis = wxData['vis'] as double?;
    final int? windDir = wxData['windDir'] as int?;
    final double? windSpeed = wxData['windSpeed'] as double?;
    final String category = wxData['category'] as String;
    final double? precip = wxData['precip'] as double?;
    final List<dynamic> hazards = wxData['hazards'] as List<dynamic>;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF111820).withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ['MVFR','IFR','LIFR'].contains(category)
              ? Colors.orangeAccent
              : Colors.greenAccent,
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('VFR 分类: $category',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('☁ 云底: ${clouds != null ? '${clouds.toStringAsFixed(0)} ft' : '—'}'),
            Text('👀 能见度: ${vis != null ? '${vis.toStringAsFixed(1)} SM' : '—'}'),
            Text('💨 风向风速: ${windDir != null && windSpeed != null ? '$windDir° / ${windSpeed.toStringAsFixed(0)} kt' : '—'}'),
            Text('🌧 降水概率: ${precip != null ? '${precip.toStringAsFixed(0)} %' : '—'}'),
          ],
        ),
      ),
    );
  }

  // -------------------------
  //      MAIN UI
  // -------------------------
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2C3E50),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // HEADER BAR
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Flight Plan",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.fullscreen, color: Colors.white),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FullscreenMap(
                        flightPath: _flightPath,
                        waypointNames: _waypointNames,
                        departureAirport: _departureAirport,
                        arrivalAirport: _arrivalAirport,
                        currentPosition: _currentPosition,
                        tileSources: _tileSources,
                        mapStyle: _mapStyle,
                        legRisks: _legRisks,
                        weatherPoints: _weatherPoints,
                        terrainSamples: _terrainSamples,
                        recommendedAltitudeFt: _recommendedAltitudeFt,
                        plannedAltitudeFt: _plannedAltitudeFt,
                      ),
                    ),
                  );
                },
              ),
              TextButton(
                onPressed: _uploadAndParseFpl,
                child: const Text(
                  "Upload .fpl",
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),

          // 🔹 ForeFlight 风格航路天气剖面条
          if (_legRisks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
              child: RouteWeatherProfile(
                legRisks: _legRisks,
                waypointNames: _waypointNames,
              ),
            ),

          // Altitude Weather Profile
          if (_legRisks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6.0, bottom: 12.0),
              child: AltitudeWeatherProfile(
                legRisks: _legRisks,
                waypointNames: _waypointNames,
              ),
            ),

          // Terrain auto altitude suggestion (SRTM 30m DEM, +2500 ft margin)
          if (_maxTerrainFt != null && _recommendedAltitudeFt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 10.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2A35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orangeAccent.withOpacity(0.7), width: 0.8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.terrain, color: Colors.orangeAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Terrain Profile • SRTM NASA 30m (AUTO +2500 ft)',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Max terrain along route: ${_maxTerrainFt!.toStringAsFixed(0)} ft   '
                                'Recommended cruise altitude: ${_recommendedAltitudeFt!.toStringAsFixed(0)} ft',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Planned Altitude Input (preflight only)
          if ((_currentPosition?.speed ?? 0) < 10)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: TextField(
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Planned Cruise Altitude (ft)",
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: const Color(0xFF1E2A35),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) {
                  final val = double.tryParse(v);
                  if (val != null) {
                    setState(() => _plannedAltitudeFt = val);
                  }
                },
              ),
            ),

          // --- FLIGHT MODE BUTTONS (Position 3) ---
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // AUTO
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _flightMode == FlightMode.auto
                          ? Colors.blueAccent
                          : const Color(0xFF1E2A35),
                    ),
                    onPressed: () {
                      setState(() => _flightMode = FlightMode.auto);
                    },
                    child: const Text("AUTO"),
                  ),
                ),
            
                // PRE-FLIGHT
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _flightMode == FlightMode.preflight
                          ? Colors.blueAccent
                          : const Color(0xFF1E2A35),
                    ),
                    onPressed: () {
                      setState(() => _flightMode = FlightMode.preflight);
                    },
                    child: const Text("PRE-FLIGHT"),
                  ),
                ),
            
                // IN-FLIGHT
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _flightMode == FlightMode.inflight
                          ? Colors.blueAccent
                          : const Color(0xFF1E2A35),
                    ),
                    onPressed: () {
                      setState(() => _flightMode = FlightMode.inflight);
                    },
                    child: const Text("IN-FLIGHT"),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // MAP TYPE DROPDOWN
          DropdownButton<String>(
            value: _mapStyle,
            dropdownColor: const Color(0xFF2C3E50),
            style: const TextStyle(color: Colors.white),
            onChanged: (value) => setState(() => _mapStyle = value!),
            items: _tileSources.keys
                .map(
                  (s) => DropdownMenuItem(
                value: s,
                child: Text(
                  s == 'wunderground'
                      ? 'WUNDERGROUND'
                      : s.toUpperCase(),
                ),
              ),
            )
                .toList(),
          ),

          // ===== FLIGHT MODE SELECTION REMOVED =====

          const SizedBox(height: 15),

          // ------------- MAIN MAP PREVIEW -------------
          SizedBox(
            height: 250,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _flightPath.isNotEmpty
                        ? _flightPath.first
                        : const LatLng(37.96, -112.32),
                    initialZoom: _flightPath.isNotEmpty ? 12.0 : 5.0,
                    interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.all),
                  ),
                  children: [
                    // Selected basemap / weather layer
                    TileLayer(
                      urlTemplate: _tileSources[_mapStyle]!,
                      tileProvider: NetworkTileProvider(),
                    ),
                    // RISK COLORED SEGMENTS
                    if (_legRisks.isNotEmpty)
                      PolylineLayer(
                        polylines: List.generate(_legRisks.length, (i) {
                          final r = _legRisks[i].total;
                          Color c;
                          if (r > 0.7) {
                            c = Colors.redAccent;
                          } else if (r > 0.4) {
                            c = Colors.orangeAccent;
                          } else {
                            c = Colors.greenAccent;
                          }
                          return Polyline(
                            points: [_legRisks[i].from, _legRisks[i].to],
                            strokeWidth: 6,
                            color: c.withOpacity(0.85),
                          );
                        }),
                      ),
                    // MAIN ROUTE
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _flightPath,
                          strokeWidth: 3,
                          color: Colors.amberAccent,
                        ),
                      ],
                    ),
                    // WHITE SEGMENT LINES
                    PolylineLayer(
                      polylines: _flightPath.length > 1
                          ? List.generate(_flightPath.length - 1, (i) {
                        return Polyline(
                          points: [
                            _flightPath[i],
                            _flightPath[i + 1],
                          ],
                          strokeWidth: 1.5,
                          color: Colors.white70,
                        );
                      })
                          : [],
                    ),
                    // MARKERS
                    if (_hoverWeather != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            width: 260,
                            height: 110,
                            point: _hoverWeather!.position,
                            child: _buildHoverWeatherBubble(_hoverWeather!.weather),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        // INTERMEDIATE WAYPOINT LABELS
                        if (_flightPath.length > 2)
                          for (int i = 1; i < _flightPath.length - 1; i++) ...[
                            Marker(
                              width: 12,
                              height: 12,
                              point: _flightPath[i],
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.amberAccent,
                                ),
                              ),
                            ),
                            Marker(
                              width: 80,
                              height: 30,
                              point: _flightPath[i],
                              child: Text(
                                _waypointNames.length > i
                                    ? _waypointNames[i]
                                    : 'WP$i',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        // In preflight mode: ALWAYS show raw weather hover zones
                        if (_weatherPoints.isNotEmpty)
                          ..._weatherPoints.map((wp) {
                            return Marker(
                              width: 30,
                              height: 30,
                              point: wp.position,
                              child: MouseRegion(
                                onEnter: (_) => setState(() => _hoverWeather = wp),
                                onExit: (_) => setState(() => _hoverWeather = null),
                                child: const SizedBox(width: 30, height: 30),
                              ),
                            );
                          }),
                        // HIGH-RESOLUTION WEATHER (hover-enabled):
                        // - Risky segments (MVFR/IFR/LIFR or hazards) show icons
                        // - Pure VFR/no-hazard segments use invisible hover zones to show tooltip
                        if (_weatherPoints.isNotEmpty)
                          ...(() {
                            final mergedWx = _mergeWeatherPointsAdaptive(_weatherPoints);
                            return [
                              for (final weatherPoint in mergedWx)
                                Marker(
                                  width: 44,
                                  height: 46,
                                  point: weatherPoint.position,
                                  child: Builder(
                                    builder: (context) {
                                      final wxData = _buildVfrAnalysisForPoint(weatherPoint.weather);
                                      final String category = wxData['category'] as String;
                                      final List<dynamic> hazards = wxData['hazards'] as List<dynamic>;
                                      bool isRisk = ['MVFR', 'IFR', 'LIFR'].contains(category) || hazards.isNotEmpty;

                                      // Unified widget for all mergedWx markers:
                                      return GestureDetector(
                                        onTap: () {
                                          showDialog(
                                            context: context,
                                            builder: (_) => AlertDialog(
                                              backgroundColor: const Color(0xFF1E2A35),
                                              title: const Text(
                                                "Enroute Weather",
                                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                              ),
                                              content: _buildHoverWeatherBubble(weatherPoint.weather),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(context),
                                                  child: const Text("OK", style: TextStyle(color: Colors.lightBlueAccent)),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              WeatherIconResolver.getIcon(weatherPoint.weather.weatherCode),
                                              size: 26,
                                              color: isRisk ? Colors.orangeAccent : Colors.white70,
                                            ),
                                            const SizedBox(height: 1),
                                            Builder(builder: (context) {
                                              final wxData = _buildVfrAnalysisForPoint(weatherPoint.weather);
                                              final double? clouds = wxData['clouds'] as double?;
                                              final double? vis = wxData['vis'] as double?;
                                              final double? precip = wxData['precip'] as double?;

                                              // --- Weather condition short text ---
                                              final int wxCode = weatherPoint.weather.weatherCode;
                                              String cond = "";
                                              if ([95, 96, 99].contains(wxCode)) {
                                                cond = "TS";
                                              } else if ([61, 63, 65].contains(wxCode)) {
                                                cond = "Rain";
                                              } else if ([51, 53, 55].contains(wxCode)) {
                                                cond = "Drizzle";
                                              } else if ([71, 73, 75].contains(wxCode)) {
                                                cond = "Snow";
                                              } else if ([66, 67].contains(wxCode)) {
                                                cond = "FZRA";
                                              } else if ([45, 48].contains(wxCode)) {
                                                cond = "Fog";
                                              } else if (wxCode == 0) {
                                                cond = "Clear";
                                              }

                                              // 如果天气代码没有给出明显现象，但降水概率很高，则用 precip 来判断是否“在下雨/下雪”
                                              if (cond.isEmpty && precip != null && precip >= 60) {
                                                if ([71, 73, 75].contains(wxCode)) {
                                                  cond = "Snow";
                                                } else {
                                                  cond = "Rain";
                                                }
                                              }

                                              String label = "";
                                              if (cond.isNotEmpty) label += cond;
                                              if (clouds != null) {
                                                if (label.isNotEmpty) label += " ";
                                                label += "${clouds.toStringAsFixed(0)}ft";
                                              }
                                              if (vis != null) {
                                                if (label.isNotEmpty) label += " ";
                                                label += "${vis.toStringAsFixed(1)}SM";
                                              }

                                              return SizedBox(
                                                width: 50,
                                                child: Text(
                                                  label,
                                                  textAlign: TextAlign.center,
                                                  softWrap: true,
                                                  overflow: TextOverflow.fade,
                                                  maxLines: 2,
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 8.0,
                                                    fontWeight: FontWeight.w600,
                                                    height: 1.1,
                                                  ),
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ];
                          })(),
                        // TERRAIN RISK MARKERS (FAA VFR logic)
                        if (_terrainSamples.isNotEmpty)
                          ..._terrainSamples.where((t) {
                            double? clearance;
                            double elevation = t.elevationFt;

                            // 统一用 helper 获取参考高度（preflight: 输入；in-flight: GPS）
                            double? referenceAltitude = _getReferenceAltitudeFt();
                            if (referenceAltitude == null) return false;

                            clearance = referenceAltitude - elevation;




                            // VFR strict logic: Only mark hazardous terrain
                            // FAA: 1000ft clearance general, 2000ft mountainous
                            bool isMountainous = elevation > 4000; // Simplified terrain classification
                            double required = isMountainous ? 2000 : 1000;

                            return clearance < required;
                          }).map((t) {
                            double elevation = t.elevationFt;
                            double? referenceAltitude = _getReferenceAltitudeFt();

                            double clearance = (referenceAltitude ?? 0) - elevation;

                            Color c;
                            IconData icon;

                            if (clearance < 500) {
                              c = Colors.redAccent;
                              icon = Icons.warning_rounded;
                            } else {
                              c = Colors.orangeAccent;
                              icon = Icons.report_problem_rounded;
                            }

                            return Marker(
                              width: 34,
                              height: 34,
                              point: t.position,
                              child: GestureDetector(
                                onTap: () => _showTerrainPopup(t),
                                child: Icon(icon, color: c, size: 30),
                              ),
                            );
                          }),
                        // DEPARTURE
                        if (_departureAirport != null)
                          Marker(
                            width: 80,
                            height: 80,
                            point: _departureAirport!,
                            child: const Icon(
                              Icons.flight_takeoff,
                              color: Colors.greenAccent,
                              size: 36,
                            ),
                          ),
                        // ARRIVAL
                        if (_arrivalAirport != null)
                          Marker(
                            width: 80,
                            height: 80,
                            point: _arrivalAirport!,
                            child: const Icon(
                              Icons.flight_land,
                              color: Colors.redAccent,
                              size: 36,
                            ),
                          ),
                        // CURRENT POSITION
                        if (_currentPosition != null)
                          Marker(
                            width: 80,
                            height: 80,
                            point: LatLng(
                                _currentPosition!.latitude, _currentPosition!.longitude),
                            child: const Icon(
                              Icons.airplanemode_active,
                              color: Colors.lightBlueAccent,
                              size: 36,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                // REFRESH WEATHER BUTTON
                Positioned(
                  right: 15,
                  bottom: 60,
                  child: FloatingActionButton(
                    heroTag: "refresh_weather",
                    mini: true,
                    backgroundColor: Colors.orangeAccent,
                    onPressed: () async {
                      if (_flightPath.isNotEmpty && !_isRefreshingWeather) {
                        setState(() => _isRefreshingWeather = true);

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Refreshing Weather…"),
                            duration: Duration(seconds: 1),
                          ),
                        );

                        final weatherPoints = await WeatherEngine.fetchRouteWeather(_flightPath);

                        setState(() {
                          _weatherPoints = weatherPoints;
                          _isRefreshingWeather = false;
                          // Commented out OpenAI or risk engine update:
                          // _legRisks = await RiskEngine.analyzeWeather(...);
                          // _legRisks = await RiskEngine.analyzeRoute(...);
                          // _legRisks = ...;
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Weather Updated"),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    child: const Icon(Icons.refresh, color: Colors.white),
                  ),
                ),
                if (_isRefreshingWeather)
                  const Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(color: Colors.orangeAccent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TERRAIN POPUP FUNCTION
  void _showTerrainPopup(TerrainSample t) {
    // Determine reference altitude (planned or actual) and clearance
    double? referenceAltitude = _getReferenceAltitudeFt();
    double elevation = t.elevationFt;
    double? clearance = referenceAltitude != null ? referenceAltitude - elevation : null;
    String risk;
    bool isMountainous = elevation > 4000;
    double required = isMountainous ? 2000 : 1000;
    if (clearance != null) {
      if (clearance < 500) {
        risk = "⚠️ EXTREME TERRAIN RISK (<500 ft)";
      } else if (clearance < required) {
        risk = "🟠 BELOW VFR CLEARANCE (${required.toStringAsFixed(0)} ft required)";
      } else {
        risk = "🟢 VFR SAFE TERRAIN";
      }
    } else {
      risk = "UNKNOWN (No altitude reference)";
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A35),
        title: const Text(
          "Terrain Profile Point",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🌍 Lat: ${t.position.latitude.toStringAsFixed(4)}',
                style: const TextStyle(color: Colors.white70)),
            Text('🌍 Lon: ${t.position.longitude.toStringAsFixed(4)}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('🗻 Elevation: ${t.elevationFt.toStringAsFixed(0)} ft',
                style: const TextStyle(color: Colors.white70)),
            if (referenceAltitude != null)
              Text('✈ Reference Alt: ${referenceAltitude.toStringAsFixed(0)} ft',
                  style: const TextStyle(color: Colors.white70)),
            if (clearance != null)
              Text('📉 Clearance: ${clearance.toStringAsFixed(0)} ft',
                  style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(risk, style: const TextStyle(color: Colors.orangeAccent)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK",
                style: TextStyle(color: Colors.lightBlueAccent)),
          ),
        ],
      ),
    );
  }
}

// MINI TERRAIN PROFILE CHART (ForeFlight Style)
class _TerrainProfilePainter extends CustomPainter {
  final List<TerrainSample> samples;
  final double recommendedAltitude;

  _TerrainProfilePainter(this.samples, this.recommendedAltitude);

  @override
  void paint(Canvas canvas, Size size) {
    final paintTerrain = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final paintAltitude = Paint()
      ..color = Colors.lightBlueAccent
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    if (samples.isEmpty) return;

    final maxElev = samples.map((e) => e.elevationFt).reduce((a, b) => a > b ? a : b);
    final scale = size.height / (recommendedAltitude * 1.2);

    final ui.Path terrainPath = ui.Path();
    for (int i = 0; i < samples.length; i++) {
      final x = (i / (samples.length - 1)) * size.width;
      final y = size.height - (samples[i].elevationFt * scale);
      if (i == 0) {
        terrainPath.moveTo(x, y);
      } else {
        terrainPath.lineTo(x, y);
      }
    }

    final recommendedY = size.height - (recommendedAltitude * scale);

    canvas.drawPath(terrainPath, paintTerrain);
    canvas.drawLine(Offset(0, recommendedY), Offset(size.width, recommendedY), paintAltitude);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// =======================================
//      WEATHER PROFILE (TOP BAR)
// =======================================

class RouteWeatherProfile extends StatelessWidget {
  final List<LegRisk> legRisks;
  final List<String> waypointNames;

  const RouteWeatherProfile({
    super.key,
    required this.legRisks,
    required this.waypointNames,
  });

  Color _colorFor(double r) {
    if (r > 0.7) return Colors.redAccent;
    if (r > 0.4) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  String _level(double r) {
    if (r > 0.7) return 'HIGH';
    if (r > 0.4) return 'MED';
    return 'LOW';
  }

  String _categoryFor(LegRisk r) {
    final double? clouds = r.cloudBaseFt?.toDouble();
    final double? vis = r.visibilitySm?.toDouble();

    // If cloudBase is missing, assume very high (>10000 ft)
    final double cloudsSafe = clouds ?? 15000;

    // If visibility is missing, assume very good (>= 10 SM)
    final double visSafe = vis ?? 10.0;

    if (cloudsSafe < 500 || visSafe < 1.0) {
      return 'LIFR';
    } else if (cloudsSafe < 1000 || visSafe < 3.0) {
      return 'IFR';
    } else if (cloudsSafe < 3000 || visSafe < 5.0) {
      return 'MVFR';
    } else {
      return 'VFR';
    }
  }

  Color _colorForCategory(String category) {
    switch (category) {
      case 'LIFR':
        return Colors.purpleAccent;
      case 'IFR':
        return Colors.redAccent;
      case 'MVFR':
        return Colors.blueAccent;
      case 'VFR':
        return Colors.greenAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (legRisks.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF1E2A35),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.cloud, color: Colors.white70, size: 18),
          const SizedBox(width: 6),
          const Text(
            'Route Weather',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: List.generate(legRisks.length, (i) {
                final r = legRisks[i].total;
                final category = _categoryFor(legRisks[i]);
                final color = _colorForCategory(category);
                final startName =
                i < waypointNames.length ? waypointNames[i] : 'WP${i + 1}';
                final endName = (i + 1) < waypointNames.length
                    ? waypointNames[i + 1]
                    : 'WP${i + 2}';
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '$startName → $endName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 9,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          category,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// =======================================
//        SMALL WEATHER BUBBLE
// =======================================

class _WeatherBubble extends StatelessWidget {
  final int index;
  final LegRisk risk;

  const _WeatherBubble({
    required this.index,
    required this.risk,
  });

  Color _colorFor(double r) {
    if (r > 0.7) return Colors.redAccent;
    if (r > 0.4) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  String _level(double r) {
    if (r > 0.7) return 'HIGH';
    if (r > 0.4) return 'MED';
    return 'LOW';
  }

  @override
  Widget build(BuildContext context) {
    final level = _level(risk.total);
    final color = _colorFor(risk.total);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF111820).withOpacity(0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题：Leg + 风险等级
            Row(
              children: [
                Icon(
                  Icons.cloud,
                  size: 12,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  'LEG ${index + 1} • $level',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 具体天气内容（多行）
            Text(
              risk.weatherText,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// =======================================
//           FULLSCREEN MAP
// =======================================

class FullscreenMap extends StatefulWidget {
  final List<LatLng> flightPath;
  final List<String> waypointNames;
  final LatLng? departureAirport;
  final LatLng? arrivalAirport;
  final Position? currentPosition;
  final Map<String, String> tileSources;
  final String mapStyle;
  final List<LegRisk> legRisks;
  final List<WeatherPoint> weatherPoints;
  final List<TerrainSample> terrainSamples;
  final double? recommendedAltitudeFt;
  final double? plannedAltitudeFt;


  const FullscreenMap({
    super.key,
    required this.flightPath,
    required this.waypointNames,
    required this.departureAirport,
    required this.arrivalAirport,
    required this.currentPosition,
    required this.tileSources,
    required this.mapStyle,
    required this.legRisks,
    required this.weatherPoints,
    required this.terrainSamples,
    required this.recommendedAltitudeFt,
    this.plannedAltitudeFt,
  });

  @override
  State<FullscreenMap> createState() => _FullscreenMapState();
}

class _FullscreenMapState extends State<FullscreenMap> {
  late String _currentMapStyle = 'osm';
  late MapController _fullscreenController = MapController();
  late WebViewController _webController;

  // Added fields for terrain profile
  List<TerrainSample> _terrainSamples = [];
  double? _recommendedAltitudeFt;

  @override
  void initState() {
    super.initState();
    _currentMapStyle = widget.mapStyle;
    _fullscreenController = MapController();
    if (widget.mapStyle == 'wunderground') {
      _webController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse("https://www.wunderground.com"));
    }
    // Pass values from widget (dynamic for compatibility)
    _terrainSamples = widget.terrainSamples;
    _recommendedAltitudeFt = widget.recommendedAltitudeFt;
  }

  // TERRAIN POPUP FUNCTION (copy)
  void _showTerrainPopup(TerrainSample t) {
    final elevation = t.elevationFt;
    final airspeed = widget.currentPosition?.speed ?? 0;

    double? referenceAltitude;
    if (airspeed < 10) {
      referenceAltitude = widget.plannedAltitudeFt;
    } else {
      referenceAltitude = widget.currentPosition?.altitude != null
          ? widget.currentPosition!.altitude * 3.28084
          : null;
    }

    final clearance = referenceAltitude != null ? referenceAltitude - elevation : null;
    final bool isMountainous = elevation > 4000;
    final double required = isMountainous ? 2000 : 1000;

    String risk;
    if (clearance != null) {
      if (clearance < 500) {
        risk = "⚠️ EXTREME TERRAIN RISK (<500 ft)";
      } else if (clearance < required) {
        risk = "🟠 BELOW VFR CLEARANCE (${required.toStringAsFixed(0)} ft required)";
      } else {
        risk = "🟢 VFR SAFE TERRAIN";
      }
    } else {
      risk = "UNKNOWN (No altitude reference)";
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A35),
        title: const Text("Terrain Profile Point",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🌍 Lat: ${t.position.latitude.toStringAsFixed(4)}',
                style: const TextStyle(color: Colors.white70)),
            Text('🌍 Lon: ${t.position.longitude.toStringAsFixed(4)}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('🗻 Elevation: ${t.elevationFt.toStringAsFixed(0)} ft',
                style: const TextStyle(color: Colors.white70)),
            if (referenceAltitude != null)
              Text('✈ Reference Alt: ${referenceAltitude.toStringAsFixed(0)} ft',
                  style: const TextStyle(color: Colors.white70)),
            if (clearance != null)
              Text('📉 Clearance: ${clearance.toStringAsFixed(0)} ft',
                  style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(risk, style: const TextStyle(color: Colors.orangeAccent)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK",
                style: TextStyle(color: Colors.lightBlueAccent)),
          ),
        ],
      ),
    );
  }

  // -------------------------
  //   VFR ANALYSIS HELPER
  // -------------------------
  Map<String, dynamic> _buildVfrAnalysisForPoint(LegWx wx) {
    final double? clouds = wx.cloudBaseFt;
    final double? vis = wx.visibilitySm;
    final int? windDir = wx.windDirDeg;
    final double? windSpeed = wx.windSpeedKt;
    final double? precip = wx.precipPct;
    final int wxCode = wx.weatherCode;

    String category = 'UNKNOWN';
    String suitability = '数据不足，无法评估';
    final List<String> reasons = [];
    final List<String> hazards = [];

    if (clouds != null || vis != null) {
      final double? c = clouds;
      final double? v = vis;

      // If cloudBase is missing, assume very high (>10000 ft)
      final double cloudsSafe = c ?? 15000;

      // If visibility is missing, assume very good (>= 10 SM)
      final double visSafe = v ?? 10.0;

      if (cloudsSafe < 500 || visSafe < 1.0) {
        category = 'LIFR';
        suitability = '极不适合 VFR（需要 IFR）';
        if (cloudsSafe < 500) {
          reasons.add('云底 ${cloudsSafe.toStringAsFixed(0)} ft < 500 ft LIFR 标准。');
        }
        if (visSafe < 1.0) {
          reasons.add('能见度 ${visSafe.toStringAsFixed(1)} SM < 1 SM LIFR 标准。');
        }
      } else if (cloudsSafe < 1000 || visSafe < 3.0) {
        category = 'IFR';
        suitability = '不适合 VFR（建议 IFR）';
        if (cloudsSafe < 1000) {
          reasons.add('云底 ${cloudsSafe.toStringAsFixed(0)} ft < 1000 ft IFR 标准。');
        }
        if (visSafe < 3.0) {
          reasons.add('能见度 ${visSafe.toStringAsFixed(1)} SM < 3 SM IFR/VFR 分界线。');
        }
      } else if (cloudsSafe < 3000 || visSafe < 5.0) {
        category = 'MVFR';
        suitability = '边缘 VFR（可飞但需非常谨慎）';
        if (cloudsSafe < 3000) {
          reasons.add('云底 ${cloudsSafe.toStringAsFixed(0)} ft 在 1000–3000 ft 之间，为 MVFR。');
        }
        if (visSafe < 5.0) {
          reasons.add('能见度 ${visSafe.toStringAsFixed(1)} SM 在 3–5 SM 之间，为 MVFR。');
        }
      } else {
        category = 'VFR';
        suitability = '适合 VFR 飞行。';
        reasons.add('云底 ≥ 3000 ft 且能见度 ≥ 5 SM，满足典型 VFR 标准。');
      }

      // Additional hazard factors based on precip, wind, and weather code.
      if (precip != null) {
        if (precip >= 70) {
          hazards.add('降水概率很高（${precip.toStringAsFixed(0)}%），很可能导致能见度明显下降。');
        } else if (precip >= 40) {
          hazards.add('有较大降水概率（${precip.toStringAsFixed(0)}%），能见度可能下降。');
        } else if (precip >= 20) {
          hazards.add('存在降水可能（${precip.toStringAsFixed(0)}%），需要关注实际天气。');
        }
      }

      if (windSpeed != null) {
        if (windSpeed >= 35) {
          hazards.add('风速很大（${windSpeed.toStringAsFixed(0)} kt），可能产生明显颠簸和侧风风险。');
        } else if (windSpeed >= 25) {
          hazards.add('风速偏大（${windSpeed.toStringAsFixed(0)} kt），起降与低空飞行需注意。');
        }
      }

      if ([95, 96, 99].contains(wxCode)) {
        hazards.add('存在雷暴/强对流（雷暴信号代码 $wxCode），强烈不建议 VFR。');
      } else if ([61, 63, 65].contains(wxCode)) {
        hazards.add('中到大雨（天气代码 $wxCode），地面与空中能见度明显降低。');
      } else if ([71, 73, 75].contains(wxCode)) {
        hazards.add('降雪（天气代码 $wxCode），可能导致能见度下降与积雪。');
      } else if ([66, 67].contains(wxCode)) {
        hazards.add('可能存在冻雨或雨夹雪（天气代码 $wxCode），有结冰风险。');
      } else if ([51, 53, 55].contains(wxCode)) {
        hazards.add('毛毛雨/小雨（天气代码 $wxCode），能见度可能变差。');
      }
    }

    return {
      'clouds': clouds,
      'vis': vis,
      'windDir': windDir,
      'windSpeed': windSpeed,
      'category': category,
      'suitability': suitability,
      'reason': reasons.join('\n• '),
      'precip': precip,
      'hazards': hazards,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2C3E50),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C3E50),
        title: const Text("Fullscreen Map"),
      ),
      body: Stack(
        children: [
          if (_currentMapStyle == 'wunderground')
            WebViewWidget(controller: _webController)
          else
            FlutterMap(
              mapController: _fullscreenController,
              options: MapOptions(
                initialCenter: widget.flightPath.isNotEmpty
                    ? widget.flightPath.first
                    : const LatLng(37.96, -112.32),
                initialZoom: 8,
                interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                TileLayer(
                  urlTemplate: widget.tileSources[_currentMapStyle]!,
                  tileProvider: NetworkTileProvider(),
                ),
                // RISK COLORED SEGMENTS
                if (widget.legRisks.isNotEmpty)
                  PolylineLayer(
                    polylines: List.generate(widget.legRisks.length, (i) {
                      final r = widget.legRisks[i].total;
                      Color c;
                      if (r > 0.7) {
                        c = Colors.redAccent;
                      } else if (r > 0.4) {
                        c = Colors.orangeAccent;
                      } else {
                        c = Colors.greenAccent;
                      }
                      return Polyline(
                        points: [
                          widget.legRisks[i].from,
                          widget.legRisks[i].to,
                        ],
                        strokeWidth: 7,
                        color: c.withOpacity(0.9),
                      );
                    }),
                  ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: widget.flightPath,
                      strokeWidth: 3,
                      color: Colors.amberAccent,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (widget.weatherPoints.isNotEmpty)
                      for (final weatherPoint in widget.weatherPoints.where((wp) {
                        final wxData = _buildVfrAnalysisForPoint(wp.weather);
                        final String category = wxData['category'] as String;
                        final List<dynamic> hazards = wxData['hazards'] as List<dynamic>;
                        if (['MVFR', 'IFR', 'LIFR'].contains(category)) return true;
                        if (hazards.isNotEmpty) return true;
                        return false;
                      })) ...[
                        Marker(
                          width: 45,
                          height: 45,
                          point: weatherPoint.position,
                          child: GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  backgroundColor: const Color(0xFF1E2A35),
                                  title: const Text(
                                    "Enroute Weather",
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  content: Builder(
                                    builder: (context) {
                                      final wxData = _buildVfrAnalysisForPoint(weatherPoint.weather);
                                      final clouds = wxData['clouds'] as double?;
                                      final vis = wxData['vis'] as double?;
                                      final int? windDir = wxData['windDir'] as int?;
                                      final double? windSpeed = wxData['windSpeed'] as double?;
                                      final String category = wxData['category'] as String;
                                      final String suitability = wxData['suitability'] as String;
                                      final String reason = wxData['reason'] as String;
                                      final double? precip = wxData['precip'] as double?;
                                      final List<dynamic> hazards = wxData['hazards'] as List<dynamic>;

                                      return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'VFR 分类: $category',
                                            style: const TextStyle(
                                              color: Colors.orangeAccent,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '☁ 云底: '
                                                '${clouds != null ? clouds.toStringAsFixed(0) + ' ft' : '—'}',
                                            style: const TextStyle(color: Colors.white70),
                                          ),
                                          Text(
                                            '👀 能见度: '
                                                '${vis != null ? vis.toStringAsFixed(1) + ' SM' : '—'}',
                                            style: const TextStyle(color: Colors.white70),
                                          ),
                                          Text(
                                            '💨 风向风速: '
                                                '${windDir != null && windSpeed != null ? '$windDir° / ${windSpeed.toStringAsFixed(0)} kt' : '—'}',
                                            style: const TextStyle(color: Colors.white70),
                                          ),
                                          Text(
                                            '🌧 降水概率: '
                                                '${precip != null ? precip.toStringAsFixed(0) + ' %' : '—'}',
                                            style: const TextStyle(color: Colors.white70),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '是否适合 VFR：$suitability',
                                            style: const TextStyle(color: Colors.lightBlueAccent),
                                          ),
                                          if (reason.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            const Text(
                                              '原因说明：',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              '• $reason',
                                              style: const TextStyle(color: Colors.white70),
                                            ),
                                          ],
                                          if (hazards.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            const Text(
                                              '天气因素：',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            ...hazards.map(
                                                  (h) => Text(
                                                '• $h',
                                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text(
                                        "OK",
                                        style: TextStyle(color: Colors.lightBlueAccent),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Icon(
                              WeatherIconResolver.getIcon(weatherPoint.weather.weatherCode),
                              size: 32,
                              color: WeatherIconResolver.getColor(weatherPoint.weather.weatherCode),
                            ),
                          ),
                        ),
                      ],
                    // TERRAIN RISK MARKERS
                    if (_terrainSamples.isNotEmpty)
                      ..._terrainSamples.where((t) {
                        final elevation = t.elevationFt;
                        final airspeed = widget.currentPosition?.speed ?? 0;
                        double? referenceAltitude;

                        if (airspeed < 10) {
                          if (widget.plannedAltitudeFt == null) return false;
                          referenceAltitude = widget.plannedAltitudeFt;
                        } else {
                          if (widget.currentPosition?.altitude == null) return false;
                          referenceAltitude = widget.currentPosition!.altitude * 3.28084;
                        }

                        final clearance = referenceAltitude! - elevation;
                        final bool isMountainous = elevation > 4000;
                        final double required = isMountainous ? 2000 : 1000;
                        return clearance < required;
                      }).map((t) {
                        final elevation = t.elevationFt;
                        final airspeed = widget.currentPosition?.speed ?? 0;
                        double? referenceAltitude;

                        if (airspeed < 10) {
                          referenceAltitude = widget.plannedAltitudeFt;
                        } else {
                          referenceAltitude = widget.currentPosition?.altitude != null
                              ? widget.currentPosition!.altitude * 3.28084
                              : null;
                        }

                        final clearance = (referenceAltitude ?? 0) - elevation;
                        Color c;
                        IconData icon;
                        if (clearance < 500) {
                          c = Colors.redAccent;
                          icon = Icons.warning_rounded;
                        } else {
                          c = Colors.orangeAccent;
                          icon = Icons.report_problem_rounded;
                        }

                        return Marker(
                          width: 38,
                          height: 38,
                          point: t.position,
                          child: GestureDetector(
                            onTap: () => _showTerrainPopup(t),
                            child: Icon(icon, color: c, size: 26),
                          ),
                        );
                      }),
                    // departure
                    if (widget.departureAirport != null)
                      Marker(
                        point: widget.departureAirport!,
                        width: 80,
                        height: 80,
                        child: const Icon(
                          Icons.flight_takeoff,
                          color: Colors.greenAccent,
                          size: 40,
                        ),
                      ),
                    // arrival
                    if (widget.arrivalAirport != null)
                      Marker(
                        point: widget.arrivalAirport!,
                        width: 80,
                        height: 80,
                        child: const Icon(
                          Icons.flight_land,
                          color: Colors.redAccent,
                          size: 40,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          // REFRESH WEATHER BUTTON
          Positioned(
            right: 15,
            bottom: 180,
            child: FloatingActionButton(
              heroTag: "refresh_weather_full",
              mini: true,
              backgroundColor: Colors.orangeAccent,
              onPressed: () async {
                if (widget.flightPath.isNotEmpty) {
                  final weatherPoints = await WeatherEngine.fetchRouteWeather(widget.flightPath);
                  setState(() {
                    widget.weatherPoints.clear();
                    widget.weatherPoints.addAll(weatherPoints);
                  });
                }
              },
              child: const Icon(Icons.refresh, color: Colors.white),
            ),
          ),
          // ZOOM BUTTONS
          Positioned(
            right: 15,
            bottom: 120,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: "zoom_in",
                  mini: true,
                  backgroundColor: Colors.blueGrey,
                  onPressed: () => _fullscreenController.move(
                    _fullscreenController.camera.center,
                    _fullscreenController.camera.zoom + 1,
                  ),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: "zoom_out",
                  mini: true,
                  backgroundColor: Colors.blueGrey,
                  onPressed: () => _fullscreenController.move(
                    _fullscreenController.camera.center,
                    _fullscreenController.camera.zoom - 1,
                  ),
                  child: const Icon(Icons.remove, color: Colors.white),
                ),
              ],
            ),
          ),
          // MAP STYLE SWITCHER
          Positioned(
            left: 15,
            bottom: 120,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String>(
                value: _currentMapStyle,
                dropdownColor: Colors.black87,
                underline: Container(),
                style: const TextStyle(color: Colors.white),
                onChanged: (value) =>
                    setState(() => _currentMapStyle = value!),
                items: widget.tileSources.keys
                    .map(
                      (style) => DropdownMenuItem(
                    value: style,
                    child: Text(
                      style == 'wunderground'
                          ? 'WUNDERGROUND'
                          : style.toUpperCase(),
                    ),
                  ),
                )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// =======================================
//      ALTITUDE WEATHER PROFILE
// =======================================

class AltitudeWeatherProfile extends StatelessWidget {
  final List<LegRisk> legRisks;
  final List<String> waypointNames;

  const AltitudeWeatherProfile({
    super.key,
    required this.legRisks,
    required this.waypointNames,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: Color(0xFF1A242F),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.air_rounded, color: Colors.lightBlueAccent, size: 18),
          const SizedBox(width: 6),
          const Text(
            'Altitude Profile',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: List.generate(legRisks.length, (i) {
                final fromName = i < waypointNames.length ? waypointNames[i] : 'WP${i+1}';
                final toName = (i+1) < waypointNames.length ? waypointNames[i+1] : 'WP${i+2}';

                final clouds = legRisks[i].cloudBaseFt ?? 0;
                final wind = legRisks[i].windDirDeg != null && legRisks[i].windSpeedKt != null
                    ? '${legRisks[i].windDirDeg}° / ${legRisks[i].windSpeedKt}kt'
                    : '—';
                final vis = legRisks[i].visibilitySm != null
                    ? '${legRisks[i].visibilitySm} sm'
                    : '—';

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '$fromName → $toName',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 9,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),

                          // CLOUD BASE BAR
                          Container(
                            // height: 20, // <-- REMOVED FIXED HEIGHT
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blueGrey, width: 0.8),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Clouds',
                                  style: TextStyle(
                                    color: Colors.lightBlueAccent,
                                    fontSize: 9,
                                  ),
                                ),
                                Text(
                                  clouds > 0 ? '${clouds} ft' : '—',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 2),

                          // WIND BAR
                          Container(
                            height: 16,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(6),
                              border:
                              Border.all(color: Colors.lightBlueAccent, width: 0.8),
                            ),
                            child: Center(
                              child: Text(
                                wind,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 2),

                          // VISIBILITY
                          Text(
                            'Vis $vis',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
