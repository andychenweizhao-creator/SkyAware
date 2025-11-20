import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../components/WeatherIconResolver.dart';
import '../models/metar_airport.dart';

class VFRAnalysisHelper extends StatefulWidget {
  final List<LatLng> flightPath;
  final Map<String, String> tileSources;
  final List<dynamic> legRisks;
  final List<dynamic> weatherPoints;

  const VFRAnalysisHelper({
    super.key,
    required this.flightPath,
    required this.tileSources,
    required this.legRisks,
    required this.weatherPoints,
  });

  @override
  _VFRAnalysisHelperState createState() => _VFRAnalysisHelperState();
}

class _VFRAnalysisHelperState extends State<VFRAnalysisHelper> {
  String _currentMapStyle = 'osm';
  late WebViewController _webController;
  final MapController _fullscreenController = MapController();

  @override
  void initState() {
    super.initState();
    _webController = WebViewController();
  }

  Map<String, dynamic> _buildVfrAnalysisForPoint(LegWx wx) {
    final double? clouds = wx.cloudBaseFt;
    final double? vis = wx.visibilitySm;
    final int? windDir = wx.windDirDeg;
    final double? windSpeed = wx.windSpeedKt;
    final double? precip = wx.precipPct;
    final int wxCode = wx.weatherCode;

    String category = 'UNKNOWN';
    String suitability = '数据不足，无法评估';
    final List<String> reasons = [];
    final List<String> hazards = [];

    if (clouds != null || vis != null) {
      final double? c = clouds;
      final double? v = vis;

      // If cloudBase is missing, assume very high (>10000 ft)
      final double cloudsSafe = c ?? 15000;

      // If visibility is missing, assume very good (>= 10 SM)
      final double visSafe = v ?? 10.0;

      if (cloudsSafe < 500 || visSafe < 1.0) {
        category = 'LIFR';
        suitability = '极不适合 VFR（需要 IFR）';
        if (cloudsSafe < 500) {
          reasons.add('云底 ${cloudsSafe.toStringAsFixed(0)} ft < 500 ft LIFR 标准。');
        }
        if (visSafe < 1.0) {
          reasons.add('能见度 ${visSafe.toStringAsFixed(1)} SM < 1 SM LIFR 标准。');
        }
      } else if (cloudsSafe < 1000 || visSafe < 3.0) {
        category = 'IFR';
        suitability = '不适合 VFR（建议 IFR）';
        if (cloudsSafe < 1000) {
          reasons.add('云底 ${cloudsSafe.toStringAsFixed(0)} ft < 1000 ft IFR 标准。');
        }
        if (visSafe < 3.0) {
          reasons.add('能见度 ${visSafe.toStringAsFixed(1)} SM < 3 SM IFR/VFR 分界线。');
        }
      } else if (cloudsSafe < 3000 || visSafe < 5.0) {
        category = 'MVFR';
        suitability = '边缘 VFR（可飞但需非常谨慎）';
        if (cloudsSafe < 3000) {
          reasons.add('云底 ${cloudsSafe.toStringAsFixed(0)} ft 在 1000–3000 ft 之间，为 MVFR。');
        }
        if (visSafe < 5.0) {
          reasons.add('能见度 ${visSafe.toStringAsFixed(1)} SM 在 3–5 SM 之间，为 MVFR。');
        }
      } else {
        category = 'VFR';
        suitability = '适合 VFR 飞行。';
        reasons.add('云底 ≥ 3000 ft 且能见度 ≥ 5 SM，满足典型 VFR 标准。');
      }

      // Additional hazard factors based on precip, wind, and weather code.
      if (precip != null) {
        if (precip >= 70) {
          hazards.add('降水概率很高（${precip.toStringAsFixed(0)}%），很可能导致能见度明显下降。');
        } else if (precip >= 40) {
          hazards.add('有较大降水概率（${precip.toStringAsFixed(0)}%），能见度可能下降。');
        } else if (precip >= 20) {
          hazards.add('存在降水可能（${precip.toStringAsFixed(0)}%），需要关注实际天气。');
        }
      }

      if (windSpeed != null) {
        if (windSpeed >= 35) {
          hazards.add('风速很大（${windSpeed.toStringAsFixed(0)} kt），可能产生明显颠簸和侧风风险。');
        } else if (windSpeed >= 25) {
          hazards.add('风速偏大（${windSpeed.toStringAsFixed(0)} kt），起降与低空飞行需注意。');
        }
      }

      if ([95, 96, 99].contains(wxCode)) {
        hazards.add('存在雷暴/强对流（雷暴信号代码 $wxCode），强烈不建议 VFR。');
      } else if ([61, 63, 65].contains(wxCode)) {
        hazards.add('中到大雨（天气代码 $wxCode），地面与空中能见度明显降低。');
      } else if ([71, 73, 75].contains(wxCode)) {
        hazards.add('降雪（天气代码 $wxCode），可能导致能见度下降与积雪。');
      } else if ([66, 67].contains(wxCode)) {
        hazards.add('可能存在冻雨或雨夹雪（天气代码 $wxCode），有结冰风险。');
      } else if ([51, 53, 55].contains(wxCode)) {
        hazards.add('毛毛雨/小雨（天气代码 $wxCode），能见度可能变差。');
      }
    }

    return {
      'clouds': clouds,
      'vis': vis,
      'windDir': windDir,
      'windSpeed': windSpeed,
      'category': category,
      'suitability': suitability,
      'reason': reasons.join('\n• '),
      'precip': precip,
      'hazards': hazards,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFF2C3E50),
        appBar: AppBar(
          backgroundColor: const Color(0xFF2C3E50),
          title: const Text("Fullscreen Map"),
        ),
        body: Stack(children: [
          if (_currentMapStyle == 'wunderground')
            WebViewWidget(controller: _webController)
          else
            FlutterMap(
              mapController: _fullscreenController,
              options: MapOptions(
                initialCenter: widget.flightPath.isNotEmpty
                    ? widget.flightPath.first
                    : const LatLng(37.96, -112.32),
                initialZoom: 8,
                interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                TileLayer(
                  urlTemplate: widget.tileSources[_currentMapStyle]!,
                  tileProvider: NetworkTileProvider(),
                ),
                // RISK COLORED SEGMENTS
                if (widget.legRisks.isNotEmpty)
                  PolylineLayer(
                    polylines: List.generate(widget.legRisks.length, (i) {
                      final r = widget.legRisks[i].total;
                      Color c;
                      if (r > 0.7) {
                        c = Colors.redAccent;
                      } else if (r > 0.4) {
                        c = Colors.orangeAccent;
                      } else {
                        c = Colors.greenAccent;
                      }
                      return Polyline(
                        points: [
                          widget.legRisks[i].from,
                          widget.legRisks[i].to,
                        ],
                        strokeWidth: 7,
                        color: c.withOpacity(0.9),
                      );
                    }),
                  ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: widget.flightPath,
                      strokeWidth: 3,
                      color: Colors.amberAccent,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (widget.weatherPoints.isNotEmpty)
                      for (final weatherPoint in widget.weatherPoints.where((wp) {
                        final wxData = _buildVfrAnalysisForPoint(wp.weather);
                        final String category = wxData['category'] as String;
                        final List<dynamic> hazards =
                        wxData['hazards'] as List<dynamic>;
                        if (['MVFR', 'IFR', 'LIFR'].contains(category)) {
                          return true;
                        }
                        if (hazards.isNotEmpty) return true;
                        return false;
                      })) ...[
                        Marker(
                          width: 45,
                          height: 45,
                          point: weatherPoint.position,
                          child: GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  backgroundColor: const Color(0xFF1E2A35),
                                  title: const Text(
                                    "Enroute Weather",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  content: Builder(
                                    builder: (context) {
                                      final wxData = _buildVfrAnalysisForPoint(
                                          weatherPoint.weather);
                                      final clouds =
                                      wxData['clouds'] as double?;
                                      final vis = wxData['vis'] as double?;
                                      final int? windDir =
                                      wxData['windDir'] as int?;
                                      final double? windSpeed =
                                      wxData['windSpeed'] as double?;
                                      final String category =
                                      wxData['category'] as String;
                                      final String suitability =
                                      wxData['suitability'] as String;
                                      final String reason =
                                      wxData['reason'] as String;
                                      final double? precip =
                                      wxData['precip'] as double?;
                                      final List<dynamic> hazards =
                                      wxData['hazards'] as List<dynamic>;

                                      return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'VFR 分类: $category',
                                            style: const TextStyle(
                                              color: Colors.orangeAccent,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '☁ 云底: '
                                                '${clouds != null ? '${clouds.toStringAsFixed(0)} ft' : '—'}',
                                            style: const TextStyle(
                                                color: Colors.white70),
                                          ),
                                          Text(
                                            '👀 能见度: '
                                                '${vis != null ? '${vis.toStringAsFixed(1)} SM' : '—'}',
                                            style: const TextStyle(
                                                color: Colors.white70),
                                          ),
                                          Text(
                                            '💨 风向风速: '
                                                '${windDir != null && windSpeed != null ? '$windDir° / ${windSpeed.toStringAsFixed(0)} kt' : '—'}',
                                            style: const TextStyle(
                                                color: Colors.white70),
                                          ),
                                          Text(
                                            '🌧 降水概率: '
                                                '${precip != null ? '${precip.toStringAsFixed(0)} %' : '—'}',
                                            style: const TextStyle(
                                                color: Colors.white70),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '是否适合 VFR：$suitability',
                                            style: const TextStyle(
                                                color: Colors.lightBlueAccent),
                                          ),
                                          if (reason.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            const Text(
                                              '原因说明：',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              '• $reason',
                                              style: const TextStyle(
                                                  color: Colors.white70),
                                            ),
                                          ],
                                          if (hazards.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            const Text(
                                              '天气因素：',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            ...hazards.map(
                                                  (h) => Text(
                                                '• $h',
                                                style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 11),
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context),
                                      child: const Text(
                                        "OK",
                                        style: TextStyle(
                                            color: Colors.lightBlueAccent),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Icon(
                              WeatherIconResolver.getIcon(
                                  weatherPoint.weather.weatherCode),
                              size: 32,
                              color: WeatherIconResolver.getColor(
                                  weatherPoint.weather.weatherCode),
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                ],
              ),
            )]));
  }
}

class LegWx {
  final double? cloudBaseFt;
  final double? visibilitySm;
  final int? windDirDeg;
  final double? windSpeedKt;
  final double? precipPct;
  final int weatherCode;

  LegWx({
    this.cloudBaseFt,
    this.visibilitySm,
    this.windDirDeg,
    this.windSpeedKt,
    this.precipPct,
    required this.weatherCode,
  });
}