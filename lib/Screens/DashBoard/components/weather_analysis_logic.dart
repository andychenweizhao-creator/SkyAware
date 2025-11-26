import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../../../Service/WeatherEngine.dart'; // For WeatherPoint, LegWx
import 'Risk_Assesments.dart' hide LegWx;

class WeatherAnalysisLogic {
  static Map<String, dynamic> buildVfrAnalysisForPoint(
      LegWx wx, {
        double? referenceAltitudeFt,
        bool usePlannedAlt = false,
      }) {
    final double? clouds = wx.cloudBaseFt;
    final double? tops = wx.cloudTopFt; // Assuming LegWx has this or we estimate it
    final double? vis = wx.visibilitySm;
    final int? windDir = wx.windDirDeg;
    final double? windSpeed = wx.windSpeedKt;
    final double? precip = wx.precipPct;
    final int wxCode = wx.weatherCode;

    String category = 'UNKNOWN';
    String suitability = 'Insufficient data to evaluate.';
    final List<String> reasons = [];
    final List<String> hazards = [];

    // --- BASE VFR CHECK (Surface / General Conditions) ---
    // We determine the general "Category" (VFR, MVFR, IFR, LIFR) based on surface metar rules
    // But we override the "Risk" flag later if we are safely above it.
    if (clouds != null || vis != null) {
      final double cloudsSafe = clouds ?? 15000;
      final double visSafe = vis ?? 10.0;

      if (cloudsSafe < 500 || visSafe < 1.0) {
        category = 'LIFR';
      } else if (cloudsSafe < 1000 || visSafe < 3.0) {
        category = 'IFR';
      } else if (cloudsSafe < 3000 || visSafe < 5.0) {
        category = 'MVFR';
      } else {
        category = 'VFR';
      }
    }

    // --- ALTITUDE SPECIFIC FILTER ---
    // User requested: "only display the risk weather on the current altitude"
    if (referenceAltitudeFt != null) {
      // 1. CLOUD CLEARANCE CHECK
      if (clouds != null) {
        final double base = clouds;
        final double top = tops ?? (base + 3000); // Fallback thickness if unknown
        
        final double prohibitedBottom = base - 500.0;
        final double prohibitedTop = top + 1000.0;

        bool isClear = true;

        if (referenceAltitudeFt >= prohibitedBottom && referenceAltitudeFt <= prohibitedTop) {
           isClear = false;
           // If we are actually inside/near clouds at OUR altitude, we flag it.
           if (referenceAltitudeFt >= base && referenceAltitudeFt <= top) {
             hazards.add("Flight Level ${referenceAltitudeFt.round()} ft is INSIDE clouds.");
           } else if (referenceAltitudeFt < base) {
             hazards.add("Violates 500ft cloud separation (Base: ${base.round()} ft).");
           } else {
             hazards.add("Violates 1000ft cloud separation (Top: ${top.round()} ft).");
           }
        } 
        
        // If we are clear of clouds at our altitude, we can potentially downgrade the Surface Category warning
        // e.g., It might be IFR at the airport (OVC008), but if we are at 8000ft (VFR-on-top), it's fine enroute.
        if (isClear && (category == 'IFR' || category == 'LIFR' || category == 'MVFR')) {
           // We append a note but don't treat it as a "Hazard" for this point if we are VFR on Top
           // effectively 'masking' the surface risk.
           // However, visibility limits still apply generally unless we have altitude-specific visibility.
        }
      }

      // 2. VISIBILITY (Assuming surface visibility applies unless we have loft data)
      if (vis != null && vis < 3.0) {
        // Visibility is hard to escape unless above a layer, but let's assume it's a risk.
        hazards.add("Low Visibility (${vis.toStringAsFixed(1)} SM) at flight path.");
      }

    } else {
      // No altitude provided? Fallback to standard surface analysis
       if (category != 'VFR') {
         // Add generic surface warnings if we don't know altitude
         if (category == 'LIFR' || category == 'IFR') {
            hazards.add("Low Ceilings/Visibility reported ($category).");
         }
       }
    }


    // --- UNIVERSAL HAZARDS (Independent of Altitude or severe enough to matter) ---
    if (precip != null && precip >= 60) {
       hazards.add('High chance of precipitation (${precip.toStringAsFixed(0)}%).');
    }

    if (windSpeed != null && windSpeed >= 30) {
       hazards.add('Strong winds (${windSpeed.toStringAsFixed(0)} kt).');
    }

    if ([95, 96, 99].contains(wxCode)) {
      hazards.add('Thunderstorm activity reported.');
    } else if ([66, 67].contains(wxCode)) {
      hazards.add('Freezing Rain/Ice Pellets reported.');
    }

    // Final Suitability Text
    if (hazards.isEmpty) {
      suitability = "Suitable for VFR at ${referenceAltitudeFt?.round() ?? 'current'} ft.";
    } else {
      suitability = "Risks detected at ${referenceAltitudeFt?.round() ?? 'current'} ft.";
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

  static List<WeatherPoint> mergeWeatherPointsAdaptive(
      List<WeatherPoint> list, {
        required double baseMergeKm,
        required bool isPreflight,
      }) {
    if (list.length < 2) return list;
    final Distance distance = const Distance();

    bool similarWx(LegWx a, LegWx b) {
      final ca = buildVfrAnalysisForPoint(a);
      final cb = buildVfrAnalysisForPoint(b);
      if (ca['category'] != cb['category']) return false;

      final ac = ca['clouds'];
      final bc = cb['clouds'];
      if (ac != null && bc != null) {
        if ((isPreflight && (ac - bc).abs() > 400) ||
            (!isPreflight && (ac - bc).abs() > 800)) return false;
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
      return WeatherPoint(LatLng(lat, lon), c.first.weather, levels: c.first.levels);
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
}
