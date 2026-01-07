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
import 'components/altitude_speed_box.dart';
import 'components/weather_analysis_box.dart';
import 'components/departure_time_box.dart';
import 'components/flight_plan_box.dart';
import '../../components/Maps/inflightview.dart';
import '../../components/Maps/PreflightView.dart';

class DashBoard extends StatefulWidget {
  const DashBoard({super.key});

  @override
  State<DashBoard> createState() => _DashBoardState();
}

class _DashBoardState extends State<DashBoard> with TickerProviderStateMixin {
  // Pre-flight Map State
  late Preflightview preflightview;

  bool _isInFlight = false;


  //

  // In-flight Map State
  late inflightview Inflight;
  late MapController _mapController ;
 // Toggle between Dashboard (Pre) and Map (In)


  // Advanced Weather State

  dynamic _selectedFeature;

  @override
  void initState() {
    super.initState();

    // Pre-flight Map State Setup
    preflightview = Preflightview(_isInFlight);
    //In-flight Map State Setup
    Inflight = inflightview();
    //Map variable Setup
    _mapController = MapController();
  }


    @override
    void dispose() {
      super.dispose();
    }







    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A1A2F),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: _isInFlight ? Inflight : _buildPreFlightView(),
        ),
      );
    }


    // --------------------------------------------------------------------------
    // PRE-FLIGHT VIEW (Dashboard)
    // --------------------------------------------------------------------------


    // --------------------------------------------------------------------------
    // IN-FLIGHT VIEW (Map)
    // --------------------------------------------------------------------------

    // Wind / Temp Visualization Layer


    Widget _buildWeatherControls() {
      if (!_showWinds && !_showTemps && !_showPrecip)
        return const SizedBox.shrink();

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
                      Text("Alt: ${_selectedAltitude.round()} ft",
                          style: const TextStyle(color: Colors.white)),
                      Expanded(
                        child: Slider(
                          value: _selectedAltitude,
                          min: 3000,
                          max: 39000,
                          divisions: 12,
                          activeColor: const Color(0xFFE040FB),
                          label: "${_selectedAltitude.round()} ft",
                          onChanged: (v) =>
                              setState(() => _selectedAltitude = v),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(
                          Icons.schedule, color: Colors.white70, size: 20),
                      const SizedBox(width: 8),
                      Text("Forecast: +${_forecastHour.round()}h",
                          style: const TextStyle(color: Colors.white)),
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
        subtitle =
        "${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(
            4)}";
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
          _buildInfoRow("Wind",
              "${wx.windDirDeg.round()}° @ ${wx.windSpeedKt.round()} kt"),
          _buildInfoRow("Temp", "${wx.temperatureC.toStringAsFixed(1)} °C"),
          _buildInfoRow("Precip",
              wx.precip ? (wx.temperatureC < 0 ? "Snow" : "Rain") : "None"),
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
                  BoxShadow(color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 10)),
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
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: Colors.white, size: 32),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                            Text(subtitle, style: const TextStyle(
                                color: Colors.cyanAccent, fontSize: 12)),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () =>
                              setState(() => _selectedFeature = null),
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

    Widget _buildInfoRow(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5))),
            Text(value, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w500)),
          ],
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
              heroTag: "center_map",
              mini: true,
              backgroundColor: const Color(0xFF1C2C54),
              child: const Icon(Icons.my_location, color: Colors.white),
              onPressed: () => _mapController.move(_aircraftPosition, 10),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: "zoom_in",
              mini: true,
              backgroundColor: const Color(0xFF1C2C54),
              child: const Icon(Icons.add, color: Colors.white),
              onPressed: () =>
                  _mapController.move(_mapController.camera.center,
                      _mapController.camera.zoom + 1),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: "zoom_out",
              mini: true,
              backgroundColor: const Color(0xFF1C2C54),
              child: const Icon(Icons.remove, color: Colors.white),
              onPressed: () =>
                  _mapController.move(_mapController.camera.center,
                      _mapController.camera.zoom - 1),
            ),
          ],
        ),
      );
    }
  }
}

// ----------------------------------------------------------------------------
// PAINTERS
// ----------------------------------------------------------------------------
//FIXME:Move this class to its own file
class WeatherOverlayPainter extends CustomPainter {
  final List<WeatherPoint> data;
  final double altitude;
  final int timeOffset;
  final double animationValue;
  final MapController mapController;
  final bool showWind;
  final bool showTemp;
  final bool showPrecip;

  WeatherOverlayPainter({
    required this.data,
    required this.altitude,
    required this.timeOffset,
    required this.animationValue,
    required this.mapController,
    required this.showWind,
    required this.showTemp,
    required this.showPrecip,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final windPaint = Paint()..strokeCap = StrokeCap.round;
    final tempPaint = Paint()..style = PaintingStyle.fill;
    final precipPaint = Paint()..strokeWidth = 2.0..strokeCap = StrokeCap.round;

    for (var wp in data) {
      final point = mapController.camera.latLngToScreenPoint(wp.position);
      final screenPos = Offset(point.x, point.y);
      
      // Optimization: Skip if far off screen
      if (screenPos.dx < -50 || screenPos.dx > size.width + 50 || 
          screenPos.dy < -50 || screenPos.dy > size.height + 50) continue;

      final wx = wp.getConditions(altitude, timeOffset);

      // Draw Temperature Blob
      if (showTemp) {
         double t = wx.temperatureC;
         Color tColor;
         if (t < -20) tColor = Colors.purpleAccent;
         else if (t < 0) tColor = Colors.blueAccent;
         else if (t < 15) tColor = Colors.greenAccent;
         else if (t < 30) tColor = Colors.orangeAccent;
         else tColor = Colors.redAccent;

         // Pulsing effect using animationValue
         double pulse = 30 + (math.sin(animationValue * math.pi * 2) * 5);

         tempPaint.color = tColor.withOpacity(0.3);
         canvas.drawCircle(screenPos, pulse, tempPaint);
      }

      // Draw Wind Particle
      if (showWind) {
        double speed = wx.windSpeedKt;
        double dir = wx.windDirDeg;

        Color wColor = Colors.cyanAccent;
        if (speed > 30) wColor = Colors.yellowAccent;
        if (speed > 50) wColor = Colors.orangeAccent;
        if (speed > 70) wColor = Colors.redAccent;

        windPaint.color = wColor.withOpacity(0.8);
        windPaint.strokeWidth = 2.0;

        // Animated Position
        double rad = (dir - 90) * (math.pi / 180.0);
        double dist = (speed / 2.0) * animationValue; 
        
        // Simple flow visualization: Arrow moves away from point
        double dx = math.cos(rad) * dist;
        double dy = math.sin(rad) * dist;

        // Draw 'tail' fading out
        canvas.drawLine(screenPos, screenPos + Offset(dx, dy), windPaint);
        // Draw head
        canvas.drawCircle(screenPos + Offset(dx, dy), 2, windPaint);
      }
      
      // Draw Precipitation (Rain/Snow)
      if (showPrecip && wx.precip) {
         bool isSnow = wx.temperatureC < 0;
         precipPaint.color = isSnow ? Colors.white : Colors.blueAccent;
         
         // Animate falling down
         double fallDist = 20 * animationValue;
         // Draw multiple particles around the point
         for(int i=0; i<3; i++) {
             double offsetX = (i - 1) * 10.0; 
             double offsetY = fallDist + (i * 5.0) % 20;
             
             if (isSnow) {
                 // Snowflake (dot)
                 canvas.drawCircle(screenPos + Offset(offsetX, offsetY), 2, precipPaint);
             } else {
                 // Raindrop (line)
                 canvas.drawLine(
                   screenPos + Offset(offsetX, offsetY), 
                   screenPos + Offset(offsetX, offsetY + 5), 
                   precipPaint
                 );
             }
         }
      }
    }
  }

  @override
  bool shouldRepaint(covariant WeatherOverlayPainter old) {
    return old.animationValue != animationValue || 
           old.altitude != altitude || 
           old.timeOffset != timeOffset ||
           old.showWind != showWind ||
           old.showTemp != showTemp ||
           old.showPrecip != showPrecip;
  }
}
