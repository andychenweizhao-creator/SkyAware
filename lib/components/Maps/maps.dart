import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:skyaware/Service/weather_service.dart';

import '../../models/metar_airport.dart';
import '../../Service/TerrianEngines.dart';

class Maps extends StatefulWidget {
  const Maps({super.key});

  @override
  _MapsState createState() => _MapsState();
}

class _MapsState extends State<Maps> {
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

  _getReferenceAltitudeFt() {}

  _showTerrainPopup(TerrainSample t) {}
}