// ========================
//  main_ui.dart
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


import '../Screens/DashBoard/components/Risk_Assesments.dart' hide LegWx;
import '../Service/WeatherEngine.dart';

import 'package:http/http.dart' as http;
import "./WeatherIconResolver.dart";
import "../models/metar_airport.dart";
import "../Service/terrain_engine.dart";

class MainUi extends StatefulWidget {
  const MainUi({super.key});

  @override
  _MainUiState createState() => _MainUiState();
}

class _MainUiState extends State<MainUi> {
  List<LatLng> _flightPath = [];
  List<String> _waypointNames = [];
  LatLng? _departureAirport;
  LatLng? _arrivalAirport;
  Position? _currentPosition;
  final MapController _mapController = MapController();
  String _mapStyle = 'osm';
  FlightMode _flightMode = FlightMode.auto;

  final Map<String, String> _tileSources = {
    'osm': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'terrain': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    'satellite':
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    'wunderground': 'webview',
  };

  List<LegRisk> _legRisks = [];
  List<WeatherPoint> _weatherPoints = [];
  List<TerrainSample> _terrainSamples = [];
  double? _maxTerrainFt;
  double? _recommendedAltitudeFt;
  double? _plannedAltitudeFt;

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
              // Navigator.push(
              //   context,
              //   MaterialPageRoute(
              //     builder: (context) => FullscreenMap(
              //       flightPath: _flightPath,
              //       waypointNames: _waypointNames,
              //       departureAirport: _departureAirport,
              //       arrivalAirport: _arrivalAirport,
              //       currentPosition: _currentPosition,
              //       tileSources: _tileSources,
              //       mapStyle: _mapStyle,
              //       legRisks: _legRisks,
              //       weatherPoints: _weatherPoints,
              //       terrainSamples: _terrainSamples,
              //       recommendedAltitudeFt: _recommendedAltitudeFt,
              //       plannedAltitudeFt: _plannedAltitudeFt,
              //     ),
              //   ),
              // );
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
    // child: RouteWeatherProfile(
    //   legRisks: _legRisks,
    //   waypointNames: _waypointNames,
    // ),
  ),

  // Altitude Weather Profile
  if (_legRisks.isNotEmpty)
  Padding(
  padding: const EdgeInsets.only(top: 6.0, bottom: 12.0),
  // child: AltitudeWeatherProfile(
  // legRisks: _legRisks,
  // waypointNames: _waypointNames,
  // ),
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
  border: Border.all(color: Colors.orangeAccent.withAlpha(178), width: 0.8),
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
        ],
      ),
  );
}

void _uploadAndParseFpl() {}
}

enum FlightMode { auto, preflight, inflight }