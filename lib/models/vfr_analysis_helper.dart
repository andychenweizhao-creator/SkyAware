// ========================
//  vfr_analysis_helper.dart
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


import 'package:http/http.dart' as http;
import "../../../components/WeatherIconResolver.dart";
import "../../../models/metar_airport.dart";
import "../../../Service/TerrianEngines.dart";

enum FlightMode { auto, preflight, inflight }

class VFRAnalysisHelper {
  final FlightMode _flightMode;
  final Position? _currentPosition;
  final double? _plannedAltitudeFt;
  final double? _recommendedAltitudeFt;

  VFRAnalysisHelper({
    required FlightMode flightMode,
    required Position? currentPosition,
    required double? plannedAltitudeFt,
    required double? recommendedAltitudeFt,
  })  : _flightMode = flightMode,
        _currentPosition = currentPosition,
        _plannedAltitudeFt = plannedAltitudeFt,
        _recommendedAltitudeFt = recommendedAltitudeFt;

  Map<String, dynamic> _buildVfrAnalysisForPoint(LegWx wx) {
    final double? clouds = wx.cloudBaseFt;
    final double? vis = wx.visibilitySm;
    final int? windDir = wx.windDirDeg;
    final double? windSpeed = wx.windSpeedKt;
    final double? precip = wx.precipPct;
    final int wxCode = wx.weatherCode;

    String category = 'UNKNOWN';
    String suitability = 'Insufficient data to evaluate.';
    final List<String> reasons = [];
    final List<String> hazards = [];

    if (clouds != null || vis != null) {
      final double? c = clouds;
      final double? v = vis;

      // If cloudBase is missing, assume very high (>10000 ft)
      final double cloudsSafe = c ?? 15000;

      // If visibility is missing, assume very good (>= 10 SM)
      final double visSafe = v ?? 10.0;

      // FAA 常用的 LIFR / IFR / MVFR / VFR 分级：
      // LIFR: ceiling < 500 ft 或 vis < 1 SM
      // IFR:  500–<1000 ft 或 vis 1–<3 SM
      // MVFR: 1000–<3000 ft 或 vis 3–<5 SM
      // VFR:  ceiling >= 3000 ft 且 vis >= 5 SM
      if (cloudsSafe < 500 || visSafe < 1.0) {
        category = 'LIFR';
        suitability = 'Highly unsuitable for VFR (IFR required).';
        if (cloudsSafe < 500) {
          reasons.add('Ceiling ${cloudsSafe.toStringAsFixed(0)} ft < 500 ft LIFR threshold.');
        }
        if (visSafe < 1.0) {
          reasons.add('Visibility ${visSafe.toStringAsFixed(1)} SM < 1 SM LIFR threshold.');
        }
      } else if (cloudsSafe < 1000 || visSafe < 3.0) {
        category = 'IFR';
        suitability = 'Not suitable for VFR (IFR recommended).';
        if (cloudsSafe < 1000) {
          reasons.add('Ceiling ${cloudsSafe.toStringAsFixed(0)} ft < 1000 ft IFR threshold.');
        }
        if (visSafe < 3.0) {
          reasons.add('Visibility ${visSafe.toStringAsFixed(1)} SM < 3 SM IFR/VFR boundary.');
        }
      } else if (cloudsSafe < 3000 || visSafe < 5.0) {
        category = 'MVFR';
        suitability = 'Marginal VFR (flyable but requires great caution).';
        if (cloudsSafe < 3000) {
          reasons.add('Ceiling ${cloudsSafe.toStringAsFixed(0)} ft is between 1000–3000 ft (MVFR).');
        }
        if (visSafe < 5.0) {
          reasons.add('Visibility ${visSafe.toStringAsFixed(1)} SM is between 3–5 SM (MVFR).');
        }
      } else {
        category = 'VFR';
        suitability = 'Suitable for VFR flight.';
        reasons.add('Ceiling ≥ 3000 ft and visibility ≥ 5 SM meet typical VFR criteria.');
      }

      // Additional hazard factors based on precip, wind, and weather code.
      if (precip != null) {
        if (precip >= 70) {
          hazards.add('High precipitation probability (${precip.toStringAsFixed(0)}%), visibility very likely reduced.');
        } else if (precip >= 40) {
          hazards.add('Moderate to high precipitation probability (${precip.toStringAsFixed(0)}%), visibility may be reduced.');
        } else if (precip >= 20) {
          hazards.add('Some chance of precipitation (${precip.toStringAsFixed(0)}%), monitor actual conditions.');
        }
      }

      if (windSpeed != null) {
        if (windSpeed >= 35) {
          hazards.add('Strong winds (${windSpeed.toStringAsFixed(0)} kt) may cause significant turbulence and crosswind risk.');
        } else if (windSpeed >= 25) {
          hazards.add('Elevated winds (${windSpeed.toStringAsFixed(0)} kt); use caution for takeoff, landing, and low-level flight.');
        }
      }

      if ([95, 96, 99].contains(wxCode)) {
        hazards.add('Thunderstorms / strong convection (weather code $wxCode); VFR is strongly discouraged.');
      } else if ([61, 63, 65].contains(wxCode)) {
        hazards.add('Moderate to heavy rain (weather code $wxCode) significantly reduces surface and in-flight visibility.');
      } else if ([71, 73, 75].contains(wxCode)) {
        hazards.add('Snow (weather code $wxCode) may reduce visibility and cause accumulation.');
      } else if ([66, 67].contains(wxCode)) {
        hazards.add('Freezing rain or ice pellets (weather code $wxCode) imply icing risk.');
      } else if ([51, 53, 55].contains(wxCode)) {
        hazards.add('Drizzle / light rain (weather code $wxCode) may reduce visibility.');
      }

      // === Altitude-based cloud clearance hazard (Preflight / In-flight unified) ===
      final double? refAltFt = _getReferenceAltitudeFt();
      if (refAltFt != null && clouds != null) {
        final double clearanceToBase = clouds - refAltFt;
        final bool usePlannedAlt = _flightMode == FlightMode.preflight ||
            (_flightMode == FlightMode.auto && (_currentPosition?.speed ?? 0) < 10);
        final String altSourceText =
        usePlannedAlt ? "Planned altitude" : "Current altitude";

        if (clearanceToBase < 0) {
          hazards.add(
              '$altSourceText is above the cloud base (IMC), which is not legal for VFR flight.');
        } else if (clearanceToBase < 500) {
          hazards.add(
              '$altSourceText is only ${clearanceToBase.toStringAsFixed(0)} ft below the ceiling, not meeting the recommended 500 ft VFR clearance.');
        }
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

  // ===============================
  // Weather Merge (80km Adaptive)
  // ===============================
  List<WeatherPoint> _mergeWeatherPointsAdaptive(List<WeatherPoint> list) {
    if (list.length < 2) return list;

    double baseMergeKm = (_flightMode == FlightMode.preflight) ? 80.0 : 50.0;
    final Distance distance = const Distance();

    bool similarWx(LegWx a, LegWx b) {
      final ca = _buildVfrAnalysisForPoint(a);
      final cb = _buildVfrAnalysisForPoint(b);

      if (ca['category'] != cb['category']) return false;

      final ac = ca['clouds'];
      final bc = cb['clouds'];
      if (ac != null && bc != null) {
        if ((_flightMode == FlightMode.preflight && (ac - bc).abs() > 400) ||
            (_flightMode != FlightMode.preflight && (ac - bc).abs() > 800)) {
          return false;
        }
      }

      final av = ca['vis'];
      final bv = cb['vis'];
      if (av != null && bv != null) {
        if ((_flightMode == FlightMode.preflight && (av - bv).abs() > 1.2) ||
            (_flightMode != FlightMode.preflight && (av - bv).abs() > 2.5)) {
          return false;
        }
      }

      final ap = ca['precip'];
      final bp = cb['precip'];
      if (ap != null && bp != null) {
        if ((_flightMode == FlightMode.preflight && (ap - bp).abs() > 15) ||
            (_flightMode != FlightMode.preflight && (ap - bp).abs() > 30)) {
          return false;
        }
      }

      return true;
    }

    WeatherPoint buildWeightedCenter(List<WeatherPoint> c) {
      if (c.length == 1) return c.first;

      double totalDist = 0;
      List<double> weights = [0];

      for (int i = 1; i < c.length; i++) {
        final d = distance.as(LengthUnit.Kilometer, c[i - 1].position, c[i].position);
        totalDist += d;
        weights.add(totalDist);
      }

      final double sumWeights = weights.reduce((a, b) => a + b);
      double lat = 0, lon = 0;

      for (int i = 0; i < c.length; i++) {
        final w = weights[i] / sumWeights;
        lat += c[i].position.latitude * w;
        lon += c[i].position.longitude * w;
      }

      // --- Compute averaged weather values for merged cluster ---
      double? avgCloudBase;
      double? avgVis;
      int? avgWindDir;
      double? avgWindSpeed;
      double? avgPrecip;

      // simple accumulator
      double sumCloud = 0, countCloud = 0;
      double sumVis = 0, countVis = 0;
      double sumDirX = 0, sumDirY = 0, countDir = 0;
      double sumWind = 0, countWind = 0;
      double sumPrecip = 0, countPrecip = 0;

      for (final wp in c) {
        final wx = wp.weather;

        if (wx.cloudBaseFt != null) {
          sumCloud += wx.cloudBaseFt!;
          countCloud++;
        }
        if (wx.visibilitySm != null) {
          sumVis += wx.visibilitySm!;
          countVis++;
        }
        if (wx.windDirDeg != null && wx.windDirDeg! >= 0) {
          final rad = wx.windDirDeg! * 3.1415926535 / 180.0;
          sumDirX += math.cos(rad);
          sumDirY += math.sin(rad);
          countDir++;
        }
        if (wx.windSpeedKt != null) {
          sumWind += wx.windSpeedKt!;
          countWind++;
        }
        if (wx.precipPct != null) {
          sumPrecip += wx.precipPct!;
          countPrecip++;
        }
      }

      avgCloudBase = countCloud > 0 ? sumCloud / countCloud : null;
      avgVis = countVis > 0 ? sumVis / countVis : null;
      avgWindSpeed = countWind > 0 ? sumWind / countWind : null;
      avgPrecip = countPrecip > 0 ? sumPrecip / countPrecip : null;

      if (countDir > 0) {
        final meanDirRad = math.atan2(sumDirY / countDir, sumDirX / countDir);
        final deg = (meanDirRad * 180.0 / 3.1415926535);
        avgWindDir = ((deg % 360) + 360).toInt() % 360;
      }

      // build new averaged wx object
      final baseWx = c.first.weather;
      final newWx = LegWx(
        weatherCode: baseWx.weatherCode,
        cloudBaseFt: avgCloudBase,
        visibilitySm: avgVis,
        windDirDeg: avgWindDir,
        windSpeedKt: avgWindSpeed,
        precipPct: avgPrecip,
        convective: baseWx.convective,
      );

      return WeatherPoint(LatLng(lat, lon), newWx);
    }

    List<WeatherPoint> result = [];
    List<WeatherPoint> cluster = [list.first];

    for (int i = 1; i < list.length; i++) {
      final prev = cluster.last;
      final curr = list[i];
      final d = distance.as(LengthUnit.Kilometer, prev.position, curr.position);

      if (d <= baseMergeKm && similarWx(prev.weather, curr.weather)) {
        cluster.add(curr);
      } else {
        result.add(buildWeightedCenter(cluster));
        cluster = [curr];
      }
    }

    result.add(buildWeightedCenter(cluster));
    return result;
  }

  Widget _buildHoverWeatherBubble(LegWx wx) {
    final wxData = _buildVfrAnalysisForPoint(wx);
    final double? clouds = wxData['clouds'] as double?;
    final double? vis = wxData['vis'] as double?;
    final int? windDir = wxData['windDir'] as int?;
    final double? windSpeed = wxData['windSpeed'] as double?;
    final String category = wxData['category'] as String;
    final double? precip = wxData['precip'] as double?;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF111820).withAlpha((255 * 0.95).round()),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ['MVFR','IFR','LIFR'].contains(category)
              ? Colors.orangeAccent
              : Colors.greenAccent,
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('VFR 分类: $category',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('☁ 云底: ${clouds != null ? '${clouds.toStringAsFixed(0)} ft' : '—'}'),
            Text('👀 能见度: ${vis != null ? '${vis.toStringAsFixed(1)} SM' : '—'}'),
            Text('💨 风向风速: ${windDir != null && windSpeed != null ? '$windDir° / ${windSpeed.toStringAsFixed(0)} kt' : '—'}'),
            Text('🌧 降水概率: ${precip != null ? '${precip.toStringAsFixed(0)} %' : '—'}'),
          ],
        ),
      ),
    );
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
}