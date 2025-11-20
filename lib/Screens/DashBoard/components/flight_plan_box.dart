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

class FlightPlanBox extends StatefulWidget {
  const FlightPlanBox({super.key});

  @override
  _FlightPlanBoxState createState() => _FlightPlanBoxState();
}

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

  // -------------------------
  //   VFR ANALYSIS HELPER
  // -------------------------


  // -------------------------
  //      MAIN UI
  // -------------------------




// =======================================
//        SMALL WEATHER BUBBLE
// =======================================

  // -------------------------
  //   VFR ANALYSIS HELPER
  // -------------------------


// =======================================
//      ALTITUDE WEATHER PROFILE
// =======================================

