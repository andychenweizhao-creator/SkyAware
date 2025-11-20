
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart' as xml;


import '../../../Service/weather_service.dart';


class LegRisk {}
class TerrainSample {
  final LatLng position;
  final double elevationFt;

  TerrainSample(this.position, this.elevationFt);
}
class TerrainSummary {
  final List<TerrainSample> samples;
  final double maxElevationFt;
  final double recommendedAltitudeFt;

  TerrainSummary({
    required this.samples,
    required this.maxElevationFt,
    required this.recommendedAltitudeFt,
  });
}

class TerrainEngine {
  static Future<TerrainSummary> fetchRouteTerrain(List<LatLng> path) async {
    // Dummy implementation
    return TerrainSummary(
      samples: [],
      maxElevationFt: 0,
      recommendedAltitudeFt: 0,
    );
  }
}



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

  @override
  Widget build(BuildContext context) {
    return Container(); // Placeholder
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
    );

    if (result == null) return;

    final file = result.files.single;
    final lower = file.path!.toLowerCase();

    if (!(lower.endsWith('.fpl') ||
        lower.endsWith('.xml') ||
        lower.endsWith('.pln') ||
        lower.endsWith('.fms') ||
        lower.endsWith('.txt'))) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid file type.')),
        );
      }
      return;
    }

    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
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
}
