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
import 'dart:math' as math;


import '../../../Service/weather_service.dart';
import 'Risk_Assesments.dart' hide LegWx;

import 'package:http/http.dart' as http;
import "../../../components/WeatherIconResolver.dart";
import "../../../models/metar_airport.dart";
import "../../../Service/TerrianEngines.dart";
import '../../../Service/WeatherEngine.dart';

class FlightPlanBox extends StatefulWidget {
  const FlightPlanBox({super.key});

  @override
  _FlightPlanBoxState createState() => _FlightPlanBoxState();
}

enum FlightMode { auto, preflight, inflight }

class _FlightPlanBoxState extends State<FlightPlanBox> {
  // =========================
  //     STATE VARIABLES
  // =========================
  List<LatLng> _flightPath = [];
  List<String> _waypointNames = [];
  LatLng? _departureAirport;
  LatLng? _arrivalAirport;
  Position? _currentPosition;
  final MapController _mapController = MapController();
  String _mapStyle = 'osm';
  FlightMode _flightMode = FlightMode.auto;
  StreamSubscription<Position>? _positionStream;

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
  List<TerrainSample> _terrainSamples = [];
  double? _maxTerrainFt;
  double? _recommendedAltitudeFt;
  double? _plannedAltitudeFt;
  bool _isRefreshingWeather = false;

  @override
  void initState() {
    super.initState();
    _initLocationStream();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
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
      _weatherPoints = [];
      _terrainSamples = [];
      _maxTerrainFt = null;
      _recommendedAltitudeFt = null;
    });

    final weatherFuture = WeatherEngine.fetchRouteWeather(path, referenceAltitudeFt: _getReferenceAltitudeFt());
    final terrainFuture = TerrainEngine.fetchRouteTerrain(path);

    final weatherPoints = await weatherFuture;
    final terrainSummary = await terrainFuture;

    setState(() {
      _weatherPoints = weatherPoints;
      _terrainSamples = terrainSummary.samples;
      _maxTerrainFt = terrainSummary.maxElevationFt;
      _recommendedAltitudeFt = terrainSummary.recommendedAltitudeFt;
    });

    _legRisks = [];

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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _flightPath.isNotEmpty ? _flightPath.first : LatLng(51.5, -0.09),
              initialZoom: 9.2,
            ),
            children: [
              TileLayer(
                urlTemplate: _tileSources[_mapStyle],
                userAgentPackageName: 'com.example.app',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _flightPath,
                    strokeWidth: 4.0,
                    color: Colors.blue,
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton(
            onPressed: _uploadAndParseFpl,
            child: Text('Upload Flight Plan'),
          ),
        ),
      ],
    );
  }
}
