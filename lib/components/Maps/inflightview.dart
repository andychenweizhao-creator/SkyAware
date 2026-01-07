import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import '../../Service/WeatherEngine.dart';
import '../../Screens/DashBoard/components/altitude_speed_box.dart';
import '../../Screens/DashBoard/components/weather_analysis_box.dart';
import '../../Screens/DashBoard/components/departure_time_box.dart';
import '../../Screens/DashBoard/components/flight_plan_box.dart';

import '../../Animations/PreFlightAnimation.dart';
import '../../Animations/RadarAnimation.dart';
import '../../Animations/WindAnimation.dart';



class inflightview extends StatefulWidget{

  State <inflightview> createState(){
    return _inflightview();

  }
}
class _inflightview extends State<inflightview>with TickerProviderStateMixin{

  String _mode = 'VFR';
  bool _showRadar = true;
  bool _showWinds = false;
  bool _showTemps = false;
  bool _showPrecip = false; // New: Precipitation Overlay

  double _selectedAltitude = 3000; // New: Altitude Slider
  double _forecastHour = 0; // New: Time Slider

  LatLng _aircraftPosition = const LatLng(37.96, -112.32);
  double _heading = 45.0;

  // Data
  final List<LatLng> _route = [];
  List<WeatherPoint> _routeWeather = [];
  List<WeatherPoint> _areaWeather = []; // New: Area Weather for visualization

  Timer? _simTimer;

  late PreFlightAnimation _preFlightAnimation;
  late RadarAnimation _radarAnimation;
  late WindAnimation _windAnimation;



  void initState() {
    super.initState();
    _preFlightAnimation = PreFlightAnimation(vsync: this,)..start();
    _radarAnimation = RadarAnimation();
    _radarAnimation.start(shouldAnimate:() => mounted && _showRadar);
    _windAnimation = WindAnimation(vsync: this);
    _startSim();
    _fetchWeather();
    _fetchAreaWeather();
  }
  void dispose() {
    _preFlightAnimation.dispose();
    _windAnimation.dispose();
    _radarAnimation.dispose();
    _simTimer?.cancel();
    super.dispose();

  }
  void _startSim() {
    _simTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      setState(() {
        // Simple linear movement simulation
        double lat = _aircraftPosition.latitude + 0.0001;
        double lon = _aircraftPosition.longitude + 0.0001;
        _aircraftPosition = LatLng(lat, lon);
      });
    });
  }
  Future<void> _fetchWeather() async {
    final wx = await WeatherEngine.fetchRouteWeather(_route);
    if (mounted) {
      setState(() {
        _routeWeather = wx;
      });
    }
  }

  Future<void> _fetchAreaWeather() async {
    // Fetch a grid around aircraft
    final wx = await WeatherEngine.fetchAreaWeather(_aircraftPosition, 100);
    if (mounted) {
      setState(() {
        _areaWeather = wx;
      });
    }
  }

  Widget build(BuildContext context){
    return _buildInFlightView();
  }
  Widget _buildInFlightView() {
    return Stack(
      children: [
        _buildMap(),

        // Wind / Temp Visualization Layer
        if (_showWinds || _showTemps || _showPrecip)
          IgnorePointer(
            child: AnimatedBuilder(
                animation: _windAnimation.controller(),
                builder: (context, child) {
                  return CustomPaint(
                    size: MediaQuery.of(context).size,
                    painter: WeatherOverlayPainter(
                      data: _areaWeather.isNotEmpty ? _areaWeather : _routeWeather,
                      altitude: _selectedAltitude,
                      timeOffset: _forecastHour.toInt(),
                      animationValue: _windAnimation.getvalue(),
                      mapController: _mapController,
                      showWind: _showWinds,
                      showTemp: _showTemps,
                      showPrecip: _showPrecip,
                    ),
                  );
                }
            ),
          ),

        _buildTopBar(),
        _buildWeatherControls(),
        if (_selectedFeature != null) _buildInfoPanel(),
        _buildBottomControls(),
      ],
    );
  }
  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
          initialCenter: _aircraftPosition,
          initialZoom: 7.0,
          backgroundColor: const Color(0xFF0A1A2F),
          onTap: (_, point) => _handleMapTap(point),
          onMapEvent: (evt) {
            // In real app, re-fetch area weather on move end
            if (evt is MapEventMoveEnd) {
              // _fetchAreaWeather(); // Debounced
            }
          }
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          userAgentPackageName: 'com.skyaware.app',
          subdomains: const ['a', 'b', 'c', 'd'],
        ),

        if (_showRadar)
          TileLayer(
            urlTemplate: 'https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/${_radarFrames[_radarFrameIndex]}/{z}/{x}/{y}.png',
            tileBuilder: (context, widget, tile) => Opacity(opacity: 0.5, child: widget),
            key: ValueKey(_radarFrames[_radarFrameIndex]),
          ),

        PolylineLayer(
          polylines: [
            Polyline(
              points: _route,
              strokeWidth: 4.0,
              color: const Color(0xFFE040FB),
              isDotted: _mode == 'IFR',
            ),
          ],
        ),

        MarkerLayer(
          markers: [
            ..._route.map((p) => Marker(
              point: p, width: 40, height: 40,
              child: GestureDetector(
                onTap: () => setState(() => _selectedFeature = {'type': 'waypoint', 'pos': p}),
                child: const Icon(Icons.trip_origin, color: Colors.cyanAccent, size: 20),
              ),
            )),
            ..._routeWeather.map((wp) => Marker(
              point: wp.position, width: 30, height: 30,
              child: GestureDetector(
                onTap: () => setState(() => _selectedFeature = {'type': 'weather', 'data': wp}),
                child: Icon(Icons.cloud_circle, color: wp.weather.convective ? Colors.red : Colors.greenAccent, size: 24),
              ),
            )),
            Marker(
              point: _aircraftPosition, width: 60, height: 60,
              child: Transform.rotate(
                angle: _heading * (3.14159 / 180),
                child: const Icon(Icons.airplanemode_active, color: Colors.amber, size: 40),
              ),
            ),
          ],
        ),
      ],
    );
  }
  Future<void> _handleMapTap(LatLng point) async {
    setState(() => _selectedFeature = null);
    final wx = await WeatherEngine.fetchSpotWeather(point);
    if (mounted && wx != null) {
      setState(() {
        _selectedFeature = {'type': 'weather', 'data': wx};
      });
    }
  }
  Future<void> _packForFlight() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      // Mock file write
      // final file = File('${directory.path}/offline_weather.json');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Weather Pack Downloaded (Mock)")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Offline Pack Failed: $e")),
      );
    }
  }
  Future<void> _importFlightPlan() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['fpl', 'xml'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        final document = XmlDocument.parse(content);

        final waypoints = document.findAllElements('waypoint');
        List<LatLng> newRoute = [];

        for (var wp in waypoints) {
          final latText = wp
              .findElements('lat')
              .firstOrNull
              ?.value;
          final lonText = wp
              .findElements('lon')
              .firstOrNull
              ?.value;

          if (latText != null && lonText != null) {
            double lat = double.parse(latText);
            double lon = double.parse(lonText);
            newRoute.add(LatLng(lat, lon));
          }
        }

        if (newRoute.isNotEmpty) {
          setState(() {
            _route.clear();
            _route.addAll(newRoute);
            _aircraftPosition = newRoute.first;
            _isInFlight = true;
          });

          _fetchWeather();
          _fetchAreaWeather();
          _mapController.move(_aircraftPosition, 8.0);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
                "Flight Plan Imported: ${newRoute.length} Waypoints")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("No valid waypoints found in FPL file.")),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error importing plan: $e")),
      );
    }
  }
  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 100,
            padding: const EdgeInsets.only(top: 40, left: 20, right: 20, bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1A2F).withOpacity(0.85),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => setState(() => _isInFlight = false),
                  tooltip: "End Flight Monitor",
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Search Airport...",
                        prefixIcon: const Icon(Icons.search, color: Colors.white54),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: _importFlightPlan,
                  icon: const Icon(Icons.upload_file, color: Colors.white70),
                  tooltip: "Import Flight Plan",
                ),
                IconButton(
                  onPressed: _packForFlight,
                  icon: const Icon(Icons.download_for_offline, color: Colors.blueAccent),
                  tooltip: "Pack for Flight (Offline)",
                ),
                const SizedBox(width: 10),
                // Toggles
                IconButton(
                  onPressed: _toggleRadarPlay,
                  icon: Icon(_isRadarPlaying ? Icons.pause : Icons.play_arrow, color: Colors.greenAccent),
                ),
                IconButton(
                  onPressed: () => setState(() => _showRadar = !_showRadar),
                  icon: Icon(Icons.radar, color: _showRadar ? Colors.orangeAccent : Colors.white),
                ),
                IconButton(
                  onPressed: () => setState(() => _showWinds = !_showWinds),
                  icon: Icon(Icons.air, color: _showWinds ? Colors.cyanAccent : Colors.white),
                ),
                IconButton(
                  onPressed: () => setState(() => _showTemps = !_showTemps),
                  icon: Icon(Icons.thermostat, color: _showTemps ? Colors.redAccent : Colors.white),
                ),
                IconButton(
                  onPressed: () => setState(() => _showPrecip = !_showPrecip),
                  icon: Icon(Icons.water_drop, color: _showPrecip ? Colors.blue : Colors.white),
                  tooltip: "Show Precip Aloft",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildWeatherControls() {
    if (!_showWinds && !_showTemps && !_showPrecip) return const SizedBox.shrink();

    return Positioned(
      bottom: 20, left: 20, right: 80, // Right padding for zoom buttons
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C2C54).withOpacity(0.9),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.height, color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    Text("Alt: ${_selectedAltitude.round()} ft", style: const TextStyle(color: Colors.white)),
                    Expanded(
                      child: Slider(
                        value: _selectedAltitude,
                        min: 3000,
                        max: 39000,
                        divisions: 12,
                        activeColor: const Color(0xFFE040FB),
                        label: "${_selectedAltitude.round()} ft",
                        onChanged: (v) => setState(() => _selectedAltitude = v),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.schedule, color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    Text("Forecast: +${_forecastHour.round()}h", style: const TextStyle(color: Colors.white)),
                    Expanded(
                      child: Slider(
                        value: _forecastHour,
                        min: 0,
                        max: 12,
                        divisions: 12,
                        activeColor: Colors.blueAccent,
                        label: "+${_forecastHour.round()}h",
                        onChanged: (v) => setState(() => _forecastHour = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildInfoPanel() {
    if (_selectedFeature == null) return const SizedBox.shrink();

    String title = "Feature Info";
    String subtitle = "";
    List<Widget> content = [];
    IconData icon = Icons.place;

    if (_selectedFeature['type'] == 'waypoint') {
      LatLng pos = _selectedFeature['pos'];
      icon = Icons.local_airport;
      title = "Waypoint";
      subtitle = "${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}";
      content = [
        _buildInfoRow("Lat", "${pos.latitude.toStringAsFixed(4)}"),
        _buildInfoRow("Lon", "${pos.longitude.toStringAsFixed(4)}"),
      ];
    } else if (_selectedFeature['type'] == 'weather') {
      WeatherPoint wp = _selectedFeature['data'];
      icon = Icons.cloud;
      title = "Station: ${wp.stationId}";
      subtitle = "Altitude: ${_selectedAltitude.round()} ft Analysis";

      // Get info for selected altitude
      final wx = wp.getConditions(_selectedAltitude, _forecastHour.toInt());

      content = [
        _buildInfoRow("Wind", "${wx.windDirDeg.round()}° @ ${wx.windSpeedKt.round()} kt"),
        _buildInfoRow("Temp", "${wx.temperatureC.toStringAsFixed(1)} °C"),
        _buildInfoRow("Precip", wx.precip ? (wx.temperatureC < 0 ? "Snow" : "Rain") : "None"),
        _buildInfoRow("Icing Risk", "${(wx.icingRisk * 100).round()}%"),
        _buildInfoRow("Turbulence", "${(wx.turbulenceRisk * 100).round()}%"),
      ];
    }

    return Positioned(
      top: 120, left: 20, right: 20,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 400),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C2C54).withOpacity(0.95),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10)),
              ],
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: Colors.white, size: 32),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(subtitle, style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => setState(() => _selectedFeature = null),
                      )
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: content,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildBottomControls() {
    return Positioned(
      bottom: 120, right: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: "center_map", mini: true,
            backgroundColor: const Color(0xFF1C2C54),
            child: const Icon(Icons.my_location, color: Colors.white),
            onPressed: () => _mapController.move(_aircraftPosition, 10),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: "zoom_in", mini: true,
            backgroundColor: const Color(0xFF1C2C54),
            child: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: "zoom_out", mini: true,
            backgroundColor: const Color(0xFF1C2C54),
            child: const Icon(Icons.remove, color: Colors.white),
            onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1),
          ),
        ],
      ),
    );
  }
}
