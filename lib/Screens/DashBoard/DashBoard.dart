
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../Service/WeatherEngine.dart';

import '../../components/Maps/inflightview.dart';
import '../../components/Maps/PreflightView.dart';

class DashBoard extends StatefulWidget {
  const DashBoard({super.key});

  @override
  State<DashBoard> createState() => _DashBoardState();
}

class _DashBoardState extends State<DashBoard> {
  // Pre-flight Map State
  late Preflightview preflightview;

  bool _isInFlight = false;


  //

  // In-flight Map State
  late inflightview Inflight;
  late MapController _mapController= MapController();
  // ;
  // ;
  // ;
 // Toggle between Dashboard (Pre) and Map (In)


  // Advanced Weather State

  dynamic _selectedFeature;

  @override
  void initState() {
    super.initState();

    // Pre-flight Map State Setup
    preflightview = Preflightview(_isInFlight);
    //In-flight Map State Setup
    Inflight = inflightview(_isInFlight,_mapController);
    //Map variable Setup
    // _mapController = MapController();
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
          child: _isInFlight ? Inflight : preflightview,
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
