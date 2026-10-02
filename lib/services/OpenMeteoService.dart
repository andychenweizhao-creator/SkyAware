import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/weather_model.dart';
import 'AviationWeatherCalculator.dart';

class OpenMeteoService {
  static const String _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  /// Fetches weather data. Always returns Metric units (Celsius, KMH, hPa, Meters).
  /// Conversions should happen in the UI.
  Future<WeatherModel> getWeather({
    required double lat,
    required double lon,
    required double altitudeFt, // User's GPS Altitude
    bool forceSurface = false, // Allow forcing surface mode
    String timezone = 'auto', // Default to auto to get correct local offset
  }) async {
    try {
      // 1. Dynamic Units - Always Metric
      String unitParams = '&temperature_unit=celsius&wind_speed_unit=kmh&precipitation_unit=mm';

      // 2. API Construction
      // Removed &daily=sunrise,sunset as we calculate locally
      String hourlyFields = 'dew_point_2m,visibility,cloud_cover_low,cloud_cover_mid,cloud_cover_high';
      String currentFields = 'relative_humidity_2m,precipitation,rain,showers,snowfall,temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,cloud_cover,pressure_msl,surface_pressure,weather_code,is_day';

      String params =
          'latitude=$lat&longitude=$lon'
          '&hourly=$hourlyFields'
          '&current=$currentFields'
          '$unitParams'
          '&timezone=$timezone';

      Uri uri = Uri.parse('$_baseUrl?$params');
      print('OpenMeteo Request: $uri');

      // --- Reverse Geocoding ---
      String locationName = "Local Forecast";
      try {
        final geoUri = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=10&addressdetails=1');
        final geoResponse = await http.get(geoUri, headers: {'User-Agent': 'SkyAwareApp'});
        
        if (geoResponse.statusCode == 200) {
          final geoData = json.decode(geoResponse.body);
          final address = geoData['address'];
          if (address != null) {
             String city = address['city'] ?? 
                            address['suburb'] ?? 
                            address['town'] ?? 
                            address['village'] ?? 
                            address['county'] ?? 
                            "";
             String state = address['state'] ?? "";
             
             if (city.isNotEmpty && state.isNotEmpty) {
               locationName = "$city, $state";
             } else if (city.isNotEmpty) {
               locationName = city;
             } else if (state.isNotEmpty) {
               locationName = state;
             }
          }
        }
      } catch (e) {
        print("Nominatim geocoding error: $e");
      }

      var response = await http.get(uri);
      print('OpenMeteo Raw Response: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current'];
        final hourly = data['hourly'];
        
        // Get UTC Offset
        int utcOffsetSeconds = (data['utc_offset_seconds'] as num?)?.toInt() ?? 0;
        
        // Elevation Handling
        double surfaceElevM = (data['elevation'] as num).toDouble();
        double surfaceElevFt = AviationMath.metersToFeet(surfaceElevM);
        double aglFt = altitudeFt - surfaceElevFt;
        
        // Mode Detection: Active if > 100ft AGL AND not forced to surface
        bool isAltitudeMode = !forceSurface && (aglFt > 100);

        // --- Data Extraction (Surface Baseline - ALWAYS METRIC) ---

        double tempC = (current['temperature_2m'] as num).toDouble();
        double humidity = (current['relative_humidity_2m'] as num).toDouble();
        double windSpeedKmh = (current['wind_speed_10m'] as num).toDouble(); 
        double windDir = (current['wind_direction_10m'] as num).toDouble();
        double windGustsKmh = (current['wind_gusts_10m'] as num).toDouble(); 
        
        double rawPressureHpa = (current['pressure_msl'] as num).toDouble(); // Altimeter (QNH)
        double surfacePressureHpa = (current['surface_pressure'] as num).toDouble(); // QFE

        double precipValMm = (current['precipitation'] as num).toDouble();
        
        // --- Time & Interpolation ---
        int index1 = -1;
        int index2 = -1;
        double weight = 0.0;
        
        try {
           String currentTimeStr = current['time']; 
           DateTime currentDt = DateTime.parse(currentTimeStr); 
           // Note: Since timezone=auto, currentDt is essentially the local time at the location
           // but without offset info in string, parse() treats it as local device time or unstated.
           // However, hourly times also follow the same timezone, so string matching works fine.
           
           if (hourly != null && hourly['time'] != null) {
              List<dynamic> times = hourly['time'];
              String hourStr1 = "${currentDt.toIso8601String().substring(0, 13)}:00";
              index1 = times.indexOf(hourStr1);
              
              if (index1 != -1) {
                if (index1 + 1 < times.length) {
                   index2 = index1 + 1;
                } else {
                   index2 = index1; 
                }
                weight = currentDt.minute / 60.0;
              }
           }
        } catch (e) {
           print("Error finding interpolation indices: $e");
        }

        double interpolate(double v1, double v2, double w) => v1 + (v2 - v1) * w;

        // Dewpoint (Surface - Metric)
        double dewpointC = 0.0;
        if (index1 != -1 && hourly != null && hourly['dew_point_2m'] != null) {
           List<dynamic> dewList = hourly['dew_point_2m'];
           if (index1 < dewList.length) {
              double d1 = (dewList[index1] as num).toDouble();
              double d2 = (index2 < dewList.length) ? (dewList[index2] as num).toDouble() : d1;
              dewpointC = interpolate(d1, d2, weight); 
           }
        }

        // Visibility (Surface - Metric Meters)
        double visRawMeters = 0.0;
        
        if (index1 != -1 && hourly != null && hourly['visibility'] != null) {
           List<dynamic> visList = hourly['visibility'];
           if (index1 < visList.length) {
              double v1 = (visList[index1] as num).toDouble();
              double v2 = (index2 < visList.length) ? (visList[index2] as num).toDouble() : v1;
              visRawMeters = interpolate(v1, v2, weight);
           }
        }

        // Ceiling (Surface)
        double totalCover = (current['cloud_cover'] as num).toDouble();
        double estimatedCeilingAglFt = 100000;
        String ceilingType = "Unknown";

        if (totalCover < 50) {
            ceilingType = "Unlimited";
        } else {
             // Estimate Height
             if (index1 != -1 && hourly != null) {
               double low = 0, mid = 0, high = 0;
               if (hourly['cloud_cover_low'] != null) low = (hourly['cloud_cover_low'][index1] as num).toDouble();
               if (hourly['cloud_cover_mid'] != null) mid = (hourly['cloud_cover_mid'][index1] as num).toDouble();
               if (hourly['cloud_cover_high'] != null) high = (hourly['cloud_cover_high'][index1] as num).toDouble();
               
               if (low > 50) estimatedCeilingAglFt = 2000;
               else if (mid > 50) estimatedCeilingAglFt = 8000;
               else estimatedCeilingAglFt = 20000;
             }
             
             ceilingType = totalCover > 90 ? "Overcast" : "Broken";
        }

        // --- MODE CALCULATIONS (Physics in Metric) ---
        
        double finalTempC = tempC;
        double finalDewpointC = dewpointC;
        double finalPressureHpa = rawPressureHpa; 
        double finalWindSpeedKmh = windSpeedKmh;
        double finalVisMeters = visRawMeters;
        
        double? finalCeilingHeightMeters;
        String finalCeilingType = ceilingType;
        
        double daPA_ft = 0;

        // Altimeter in inHg (needed for PA calc in Feet)
        double altimeterInHg = AviationMath.hpaToInHg(rawPressureHpa);

        if (isAltitudeMode) {
           // 1. Temperature Lapse Rate (1.98 C per 1000ft)
           finalTempC = tempC - (1.98 * (aglFt / 1000));

           // 2. Dewpoint Lapse Rate (0.278 C per 1000ft)
           finalDewpointC = dewpointC - (0.278 * (aglFt / 1000));

           // 3. Pressure at Altitude
           // P = P0 * (1 - 2.25577e-5 * h)^5.25588 (h in meters)
           double aglMeters = AviationMath.feetToMeters(aglFt);
           double localPressureHpa = surfacePressureHpa * pow((1 - 2.25577e-5 * aglMeters), 5.25588);
           finalPressureHpa = localPressureHpa;

           // 4. Wind Gradient (Power Law)
           // V = V0 * (h/10)^0.143 (h in meters)
           // Ensure h >= 10m
           double hForWind = max(aglMeters, 10.0);
           finalWindSpeedKmh = windSpeedKmh * pow((hForWind / 10.0), 0.143);

           // 5. Visibility (Cloud Layer LCL)
           // LCL(ft) approx 400 * (T_surf - Td_surf)
           double lclFt = 400 * (tempC - dewpointC);
           if (totalCover > 50 && aglFt >= lclFt) {
              // In cloud
              finalVisMeters = 100; // ~0.1 km
           }
           
           // 6. Ceiling Relative to Aircraft
           if (estimatedCeilingAglFt < 100000) {
              double relCeiling = estimatedCeilingAglFt - aglFt;
              if (relCeiling < 0) {
                 finalCeilingType = "Below Aircraft";
                 // Store absolute difference in meters
                 finalCeilingHeightMeters = AviationMath.feetToMeters(relCeiling.abs());
              } else {
                 finalCeilingType = "Above";
                 finalCeilingHeightMeters = AviationMath.feetToMeters(relCeiling);
              }
           } else {
              // Unlimited
              finalCeilingType = "Unlimited";
              finalCeilingHeightMeters = null;
           }

           // PA at Altitude
           // PA = PA_surf + (alt - elev)
           double paSurf = (29.92 - altimeterInHg) * 1000 + surfaceElevFt;
           daPA_ft = paSurf + aglFt;

        } else {
           // Surface Mode
           finalTempC = tempC;
           finalDewpointC = dewpointC;
           finalPressureHpa = rawPressureHpa; 
           
           if (estimatedCeilingAglFt < 100000) {
               finalCeilingHeightMeters = AviationMath.feetToMeters(estimatedCeilingAglFt);
           } else {
               finalCeilingType = "Unlimited";
               finalCeilingHeightMeters = null;
           }
           
           // PA Surface
           daPA_ft = (29.92 - altimeterInHg) * 1000 + surfaceElevFt;
        }

        // --- Final Formatting & Conversions ---
        // DA Calculation
        double isaTempAtAltC = 15 - (1.98 * daPA_ft / 1000);
        double daFt = daPA_ft + (118.8 * (finalTempC - isaTempAtAltC));
        double daMeters = AviationMath.feetToMeters(daFt);

        // Flight Category Logic (Needs Miles)
        double visMiles = AviationMath.metersToMiles(finalVisMeters);
        
        // Ceiling for Category (Must be in Feet, AGL)
        double ceilingFeetForCategory = 100000;
        if (isAltitudeMode) {
           ceilingFeetForCategory = estimatedCeilingAglFt;
        } else {
           ceilingFeetForCategory = estimatedCeilingAglFt;
        }
        
        String flightCategory = "VFR";
        if (visMiles < 1 || ceilingFeetForCategory < 500) {
           flightCategory = "LIFR";
        } else if (visMiles < 3 || ceilingFeetForCategory < 1000) {
           flightCategory = "IFR";
        } else if (visMiles <= 5 || ceilingFeetForCategory <= 3000) {
           flightCategory = "MVFR";
        } else {
           flightCategory = "VFR";
        }
        
        // Safety Warning
        double windSpeedKts = AviationMath.kmhToKnots(finalWindSpeedKmh);
        double windGustsKts = AviationMath.kmhToKnots(windGustsKmh);
        if (windSpeedKts > 20 || windGustsKts > 25) {
           flightCategory += " (DANGER)";
        }

        // --- Sunrise/Sunset (LOCAL CALCULATION - NO API DEPENDENCY) ---
        // Uses AviationWeatherCalculator (sunrise_sunset_calc)
        // We use UTC date to calculate UTC sunrise/sunset
        final sunTimes = AviationMath.calculateRawSunriseSunset(
          lat: lat,
          lon: lon,
          date: DateTime.now().toUtc(), 
        );

        // --- Dynamic Background Engine ---
        DateTime now = DateTime.now();
        // Use 'is_day' from API for primary day/night switch as it handles complex twilight better
        // than simple sunrise/sunset times, but we can fallback if needed.
        bool isDay = (current['is_day'] as num) == 1; 
        
        String timePhase = isDay ? "day" : "night";
        
        // Proximity Check for Sunrise/Sunset Background Visuals
        if (sunTimes.sunrise != null && sunTimes.sunset != null) {
          // Compare against UTC now since sunrise/sunset are UTC
          DateTime nowUtc = now.toUtc();
          DateTime sr = sunTimes.sunrise!; // UTC
          DateTime ss = sunTimes.sunset!; // UTC
          DateTime srStart = sr.subtract(Duration(minutes: 30));
          DateTime srEnd = sr.add(Duration(minutes: 30));
          DateTime ssStart = ss.subtract(Duration(minutes: 30));
          DateTime ssEnd = ss.add(Duration(minutes: 30));

          if (nowUtc.isAfter(srStart) && nowUtc.isBefore(srEnd)) {
            timePhase = "sunrise";
          } else if (nowUtc.isAfter(ssStart) && nowUtc.isBefore(ssEnd)) {
            timePhase = "sunset";
          }
        }

        // Weather Phenomenon
        int weatherCode = (current['weather_code'] as num?)?.toInt() ?? 0;
        double rainVal = (current['rain'] as num?)?.toDouble() ?? 0.0;
        double showersVal = (current['showers'] as num?)?.toDouble() ?? 0.0;
        double snowfallVal = (current['snowfall'] as num?)?.toDouble() ?? 0.0;
        
        bool isThunderstorm = (weatherCode == 95 || weatherCode == 96 || weatherCode == 99);
        if (!isThunderstorm && (rainVal > 0 || showersVal > 0) && windGustsKts > 35) {
           isThunderstorm = true;
        }

        String weatherStr = "clear";
        if (isThunderstorm) {
          weatherStr = "thunderstorm";
        } else if (snowfallVal > 0) {
          weatherStr = snowfallVal > 0.5 ? "snow_heavy" : "snow_light"; 
        } else if (rainVal > 0 || showersVal > 0) {
          double totalRain = rainVal + showersVal;
          weatherStr = totalRain > 2.0 ? "rain_heavy" : "rain_light"; 
        } else {
           if (totalCover <= 15) {
             weatherStr = "clear";
           } else if (totalCover <= 50) {
             weatherStr = "partly_cloudy";
           } else if (totalCover <= 85) {
             weatherStr = "cloudy";
           } else {
             weatherStr = "overcast";
           }
        }

        if (visMiles < 1.0 && humidity > 90) {
           weatherStr += "_foggy";
        }

        String backgroundState = "${timePhase}_$weatherStr";
        if (isAltitudeMode && ceilingFeetForCategory < 100000 && aglFt > ceilingFeetForCategory) {
           backgroundState = "above_clouds";
        }
        
        double cloudOpacity = (totalCover / 100.0).clamp(0.0, 1.0);
        String conditionText = weatherStr.replaceAll('_', ' ').toUpperCase(); 

        return WeatherModel(
          temperature: finalTempC, // Metric (C)
          windSpeed: finalWindSpeedKmh, // Metric (KPH)
          windDirection: windDir,
          pressure: finalPressureHpa, // Metric (hPa)
          humidity: humidity,
          dewpoint: finalDewpointC, // Metric (C)
          condition: conditionText,
          visibility: finalVisMeters, // Metric (Meters)
          flightCategory: flightCategory,
          ceilingHeight: finalCeilingHeightMeters,
          ceilingType: finalCeilingType,
          densityAltitude: daMeters, // Metric (Meters)
          stationId: isAltitudeMode ? "GPS (Alt Mode)" : "GPS (Surface)",
          altitudeFt: altitudeFt,
          latitude: lat,
          longitude: lon,
          locationName: locationName,
          isInterpolated: true,
          precip: precipValMm, // Metric (mm)
          sunrise: sunTimes.sunrise, // UTC
          sunset: sunTimes.sunset, // UTC
          backgroundState: backgroundState,
          isDay: isDay,
          cloudOpacity: cloudOpacity,
          utcOffsetSeconds: utcOffsetSeconds,
        );

      } else {
        throw Exception('Failed to load weather data: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching Open-Meteo data: $e');
    }
  }
}
