import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:skyaware/Service/weather_service.dart';
import 'dart:ui' as ui;
import '../../models/metar_airport.dart';
import '../../Service/TerrianEngines.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  _MapViewState createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _mapController = MapController();
  List<LatLng> _flightPath = [];
  String _mapStyle = 'osm';
  final Map<String, String> _tileSources = {
    'osm': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'terrain': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    'satellite':
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  };
  List<LegRisk> _legRisks = [];
  WeatherPoint? _hoverWeather;
  List<WeatherPoint> _weatherPoints = [];
  List<TerrainSample> _terrainSamples = [];
  dynamic _departureAirport;
  dynamic _arrivalAirport;
  dynamic _currentPosition;
  List<String> _waypointNames = [];
  bool _isRefreshingWeather = false;
  double? _plannedAltitudeFt;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 15),
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
                  if (_legRisks.isNotEmpty)
                    PolylineLayer(
                      polylines: List.generate(_legRisks.length, (i) {
                        final r = 0.5; //_legRisks[i].total;
                        Color c;
                        if (r > 0.7) {
                          c = Colors.redAccent;
                        } else if (r > 0.4) {
                          c = Colors.orangeAccent;
                        } else {
                          c = Colors.greenAccent;
                        }
                        return Polyline(
                          points: [], // [_legRisks[i].from, _legRisks[i].to],
                          strokeWidth: 6,
                          color: c.withOpacity(0.85),
                        );
                      }),
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
                          _buildHoverWeatherBubble(_hoverWeather!.weather),
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
                                    final wxData = _buildVfrAnalysisForPoint(
                                        weatherPoint.weather);
                                    final String category =
                                    wxData['category'] as String;
                                    final List<dynamic> hazards =
                                    wxData['hazards'] as List<dynamic>;
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
                                                weatherPoint.weather),
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
                                            final wxData =
                                            _buildVfrAnalysisForPoint(
                                                weatherPoint.weather);
                                            final double? clouds =
                                            wxData['clouds'] as double?;
                                            final double? vis =
                                            wxData['vis'] as double?;
                                            final double? precip =
                                            wxData['precip'] as double?;

                                            final int wxCode = weatherPoint
                                                .weather.weatherCode;
                                            String cond = "";
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
                                            if (vis != null) {
                                              if (label.isNotEmpty) {
                                                label += " ";
                                              }
                                              label +=
                                              "${vis.toStringAsFixed(1)}SM";
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

                      final weatherPoints =
                      await WeatherEngine.fetchRouteWeather(_flightPath);

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

  _buildHoverWeatherBubble(weather) {
    return Container();
  }

  _mergeWeatherPointsAdaptive(List<WeatherPoint> weatherPoints) {
    return [];
  }

  _buildVfrAnalysisForPoint(weather) {
    return {};
  }

  double? _getReferenceAltitudeFt() {
    return _plannedAltitudeFt;
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
    final double? clouds = 0.0; //r.cloudBaseFt?.toDouble();
    final double? vis = 0.0; //r.visibilitySm?.toDouble();

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
                final r = 0.5; // legRisks[i].total;
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