import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../../models/metar_airport.dart';
import '../../Service/terrain_engine.dart';
import '../../Service/WeatherEngine.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  _MapViewState createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  List<LatLng> _flightPath = [];
  String _mapStyle = 'osm';
  final Map<String, String> _tileSources = {
    'osm': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'terrain': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    'satellite':
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  };
  WeatherPoint? _hoverWeather;
  List<WeatherPoint> _weatherPoints = [];
  List<TerrainSample> _terrainSamples = [];
  dynamic _departureAirport;
  dynamic _arrivalAirport;
  dynamic _currentPosition;
  List<String> _waypointNames = [];
  bool _isRefreshingWeather = false;
  double _plannedAltitudeFt = 0;

  // Animation
  late AnimationController _windAnimController;

  @override
  void initState() {
    super.initState();
    _windAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _windAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.black54,
          child: Row(
            children: [
               const Icon(Icons.height, color: Colors.white70),
               const SizedBox(width: 10),
               Text(
                 "Alt: ${_plannedAltitudeFt.toInt()} ft", 
                 style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
               ),
               Expanded(
                 child: Slider(
                   value: _plannedAltitudeFt,
                   min: 0,
                   max: 40000,
                   divisions: 40,
                   activeColor: Colors.amberAccent,
                   inactiveColor: Colors.white24,
                   onChanged: (val) => setState(() => _plannedAltitudeFt = val),
                 ),
               ),
            ],
          ),
        ),
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
                  TileLayer(
                    urlTemplate: _tileSources[_mapStyle]!,
                    tileProvider: NetworkTileProvider(),
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _flightPath,
                        strokeWidth: 3,
                        color: Colors.amberAccent,
                      ),
                    ],
                  ),
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
                  if (_hoverWeather != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          width: 260,
                          height: 110,
                          point: _hoverWeather!.position,
                          child:
                          _buildHoverWeatherBubble(_hoverWeather!),
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
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
                      if (_weatherPoints.isNotEmpty)
                        ..._weatherPoints.map((wp) {
                          return Marker(
                            width: 30,
                            height: 30,
                            point: wp.position,
                            child: MouseRegion(
                              onEnter: (_) =>
                                  setState(() => _hoverWeather = wp),
                              onExit: (_) =>
                                  setState(() => _hoverWeather = null),
                              child:
                              const SizedBox(width: 30, height: 30),
                            ),
                          );
                        }),
                      if (_weatherPoints.isNotEmpty)
                        ...() {
                          final mergedWx =
                          _mergeWeatherPointsAdaptive(_weatherPoints);
                          return [
                            for (final weatherPoint in mergedWx)
                              Marker(
                                width: 44,
                                height: 46,
                                point: weatherPoint.position,
                                child: Builder(
                                  builder: (context) {
                                    dynamic wx = weatherPoint.weather;
                                    if (_plannedAltitudeFt > 0) {
                                       wx = weatherPoint.getConditions(_plannedAltitudeFt, 0);
                                    }

                                    final wxData = _buildVfrAnalysisForPoint(wx);
                                    final String category =
                                    wxData['category'] as String? ?? 'VFR';
                                    final List<dynamic> hazards =
                                    wxData['hazards'] as List<dynamic>? ?? [];
                                    bool isRisk = [
                                      'MVFR',
                                      'IFR',
                                      'LIFR'
                                    ].contains(category) ||
                                        hazards.isNotEmpty;

                                    return GestureDetector(
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            backgroundColor:
                                            const Color(0xFF1E2A35),
                                            title: const Text(
                                              "Enroute Weather",
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight:
                                                  FontWeight.bold),
                                            ),
                                            content:
                                            _buildHoverWeatherBubble(
                                                weatherPoint),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text("OK",
                                                    style: TextStyle(
                                                        color: Colors
                                                            .lightBlueAccent)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.thermostat,
                                            size: 26,
                                            color: isRisk
                                                ? Colors.orangeAccent
                                                : Colors.white70,
                                          ),
                                          const SizedBox(height: 1),
                                          Builder(builder: (context) {
                                            
                                            final double? clouds =
                                            wxData['clouds'] as double?;
                                            final double? vis =
                                            wxData['vis'] as double?;
                                            final double? precip =
                                            wxData['precip'] as double?;

                                            String cond = "";
                                            int wxCode = wxData['code'] as int? ?? 0;
                                            
                                            if ([95, 96, 99]
                                                .contains(wxCode)) {
                                              cond = "TS";
                                            } else if ([61, 63, 65]
                                                .contains(wxCode)) {
                                              cond = "Rain";
                                            } else if ([51, 53, 55]
                                                .contains(wxCode)) {
                                              cond = "Drizzle";
                                            } else if ([71, 73, 75]
                                                .contains(wxCode)) {
                                              cond = "Snow";
                                            } else if ([66, 67]
                                                .contains(wxCode)) {
                                              cond = "FZRA";
                                            } else if ([45, 48]
                                                .contains(wxCode)) {
                                              cond = "Fog";
                                            } else if (wxCode == 0) {
                                              cond = "Clear";
                                            }

                                            if (cond.isEmpty &&
                                                precip != null &&
                                                precip >= 60) {
                                              if ([71, 73, 75]
                                                  .contains(wxCode)) {
                                                cond = "Snow";
                                              } else {
                                                cond = "Rain";
                                              }
                                            }

                                            String label = "";
                                            if (cond.isNotEmpty) label += cond;
                                            if (clouds != null) {
                                              if (label.isNotEmpty) {
                                                label += " ";
                                              }
                                              label +=
                                              "${clouds.toStringAsFixed(0)}ft";
                                            }
                                            if (vis != null && vis < 10) {
                                              if (label.isNotEmpty) {
                                                label += " ";
                                              }
                                              label +=
                                              "${vis.toStringAsFixed(1)}SM";
                                            }
                                            
                                            if (_plannedAltitudeFt > 5000) {
                                                double? temp = wxData['temp'];
                                                double? wind = wxData['wind'];
                                                if (temp != null && wind != null) {
                                                   label = "${temp.toStringAsFixed(0)}C ${wind.toStringAsFixed(0)}kt";
                                                }
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
                        }(),
                      if (_terrainSamples.isNotEmpty)
                        ..._terrainSamples.where((t) {
                          double? clearance;
                          double elevation = t.elevationFt;

                          double? referenceAltitude =
                          _getReferenceAltitudeFt();
                          if (referenceAltitude == null) return false;

                          clearance = referenceAltitude - elevation;

                          bool isMountainous = elevation > 4000;
                          double required = isMountainous ? 2000 : 1000;

                          return clearance < required;
                        }).map((t) {
                          double elevation = t.elevationFt;
                          double? referenceAltitude =
                          _getReferenceAltitudeFt();

                          double clearance =
                              (referenceAltitude ?? 0) - elevation;

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
                      if (_currentPosition != null)
                        Marker(
                          width: 80,
                          height: 80,
                          point: LatLng(_currentPosition!.latitude,
                              _currentPosition!.longitude),
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
              
              // Weather Animation Overlay (Always Displayed)
              IgnorePointer(
                 child: AnimatedBuilder(
                   animation: _windAnimController,
                   builder: (context, child) {
                     return CustomPaint(
                       size: MediaQuery.of(context).size,
                       painter: WeatherOverlayPainter(
                         data: _weatherPoints,
                         altitude: _plannedAltitudeFt,
                         timeOffset: 0,
                         animationValue: _windAnimController.value,
                         mapController: _mapController,
                         showWind: true,
                         showTemp: false, // Too messy for always on? Or maybe true.
                         showPrecip: true,
                       ),
                     );
                   }
                 ),
              ),

              Positioned(
                right: 15,
                bottom: 60,
                child: FloatingActionButton(
                  heroTag: "refresh_weather",
                  mini: true,
                  backgroundColor: Colors.orangeAccent,
                  onPressed: () async {
                    if (!_isRefreshingWeather) {
                      setState(() => _isRefreshingWeather = true);

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Refreshing Weather Area…"),
                          duration: Duration(seconds: 1),
                        ),
                      );

                      final center = _mapController.camera.center;
                      final weatherPoints =
                      await WeatherEngine.fetchAreaWeather(center, 80);

                      setState(() {
                        _weatherPoints = weatherPoints;
                        _isRefreshingWeather = false;
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
                      child: CircularProgressIndicator(
                          color: Colors.orangeAccent),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHoverWeatherBubble(WeatherPoint wp) {
    dynamic wx = wp.weather;
    if (_plannedAltitudeFt > 0) wx = wp.getConditions(_plannedAltitudeFt, 0);
    
    // Simple display of wx
    String text = "Station: ${wp.stationId}";
    if (wx is FlightLevelWx) {
        text += "\nAlt: ${wx.levelFt}ft";
        text += "\nWind: ${wx.windDirDeg.toStringAsFixed(0)}° @ ${wx.windSpeedKt.toStringAsFixed(0)}kt";
        text += "\nTemp: ${wx.temperatureC.toStringAsFixed(1)}°C";
        if (wx.precip) text += "\nPrecip: Yes";
    } else if (wx is LegWx) {
        text += "\nSFC Wind: ${wx.windDirDeg}° @ ${wx.windSpeedKt}kt";
        text += "\nVis: ${wx.visibilitySm}SM";
    }
    
    return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10))
    );
  }

  List<WeatherPoint> _mergeWeatherPointsAdaptive(List<WeatherPoint> weatherPoints) {
    return weatherPoints;
  }

  Map<String, dynamic> _buildVfrAnalysisForPoint(dynamic weather) {
      if (weather is LegWx) {
         return {
           'category': (weather.visibilitySm ?? 10) < 3 ? 'IFR' : 'VFR',
           'hazards': weather.convective ? ['TS'] : [],
           'clouds': weather.cloudBaseFt,
           'vis': weather.visibilitySm,
           'precip': weather.precipPct,
           'code': weather.weatherCode,
           'temp': null,
           'wind': weather.windSpeedKt
         };
      } else if (weather is FlightLevelWx) {
         return {
           'category': 'VFR',
           'hazards': weather.turbulenceRisk > 0 ? ['TURB'] : [],
           'clouds': null,
           'vis': weather.visibilitySm,
           'precip': weather.precip ? 100.0 : 0.0,
           'code': 0,
           'temp': weather.temperatureC,
           'wind': weather.windSpeedKt
         };
      }
      return {'category': 'VFR', 'hazards': [], 'code': 0};
  }

  double? _getReferenceAltitudeFt() {
    return _plannedAltitudeFt > 0 ? _plannedAltitudeFt : null;
  }

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

      dynamic wx;
      if (altitude > 0) {
         wx = wp.getConditions(altitude, timeOffset);
      } else {
         wx = wp.weather; // Surface
      }

      // Draw Temperature Blob (Only if Aloft, as surface doesn't have uniform temp display here yet, or adapt)
      if (showTemp && wx is FlightLevelWx) {
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
        double speed = 0;
        double dir = 0;
        
        if (wx is FlightLevelWx) {
            speed = wx.windSpeedKt;
            dir = wx.windDirDeg;
        } else if (wx is LegWx) {
            speed = wx.windSpeedKt ?? 0;
            dir = (wx.windDirDeg ?? 0).toDouble();
        }

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
      bool hasPrecip = false;
      bool isSnow = false;
      
      if (wx is FlightLevelWx) {
          hasPrecip = wx.precip;
          isSnow = wx.temperatureC < 0;
      } else if (wx is LegWx) {
          hasPrecip = (wx.precipPct ?? 0) > 0;
          isSnow = wx.weatherCode == 71 || wx.weatherCode == 73 || wx.weatherCode == 75; // Simplified
      }

      if (showPrecip && hasPrecip) {
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
