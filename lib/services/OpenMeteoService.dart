import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/weather_model.dart';
import 'AviationWeatherCalculator.dart';

class OpenMeteoService {
  static const String _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  /// Fetches weather data using the user's requirements.
  /// Includes dynamic timezone and raw output debugging.
  Future<WeatherModel> getWeather({
    required double lat,
    required double lon,
    required double altitudeFt,
    required bool useMetric,
    String timezone = 'America/Los_Angeles', // Dynamic Parameter
  }) async {
    try {
      // 1. Elevation Calculation (ft -> meters)
      int elevationMeters = (altitudeFt * 0.3048).round();

      // 2. Dynamic Units
      String unitParams;
      if (useMetric) {
        unitParams = '&temperature_unit=celsius&wind_speed_unit=kmh&precipitation_unit=mm';
      } else {
        unitParams = '&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch';
      }

      // 3. API Construction
      // hourly: dew_point_2m, visibility, cloud_cover_low, cloud_cover_mid, cloud_cover_high
      String hourlyFields = 'dew_point_2m,visibility,cloud_cover_low,cloud_cover_mid,cloud_cover_high';
      
      // current: relative_humidity_2m,precipitation,rain,showers,snowfall,temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,cloud_cover,pressure_msl,surface_pressure
      String currentFields = 'relative_humidity_2m,precipitation,rain,showers,snowfall,temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,cloud_cover,pressure_msl,surface_pressure';

      String params =
          'latitude=$lat&longitude=$lon&elevation=$elevationMeters'
          '&hourly=$hourlyFields'
          '&current=$currentFields'
          '$unitParams'
          '&timezone=$timezone'; // Dynamic Parameter

      Uri uri = Uri.parse('$_baseUrl?$params');
      print('OpenMeteo Request: $uri');

      // --- Reverse Geocoding (Nominatim) ---
      String locationName = "Local Forecast";
      try {
        final geoUri = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=10&addressdetails=1');
        // User-Agent is required by Nominatim
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
             } else {
               locationName = "Local Forecast";
             }
          }
        }
      } catch (e) {
        print("Nominatim geocoding error: $e");
        // Fallback to "Local Forecast" is already set
      }

      var response = await http.get(uri);

      // Raw Output (Requirement)
      print('OpenMeteo Raw Response: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current'];
        final currentUnits = data['current_units'];
        final hourly = data['hourly'];
        final hourlyUnits = data['hourly_units'];

        // --- Data Mapping (Handling Missing Fields Safely) ---

        // Temperature
        double temp = (current['temperature_2m'] as num).toDouble();
        
        // Humidity
        double humidity = (current['relative_humidity_2m'] as num).toDouble();
        
        // Wind
        double windSpeed = (current['wind_speed_10m'] as num).toDouble();
        double windDir = (current['wind_direction_10m'] as num).toDouble();
        double windGusts = (current['wind_gusts_10m'] as num).toDouble();

        // Pressure (UI) - MSL
        double rawPressureHpa = (current['pressure_msl'] as num).toDouble();
        String pressureString;
        
        if (useMetric) {
           pressureString = "${rawPressureHpa.toStringAsFixed(2)} hPa";
        } else {
           double pressureVal = rawPressureHpa;
           if (pressureVal > 800) {
             pressureVal *= 0.02953;
           }
           pressureString = "${pressureVal.toStringAsFixed(2)} inHg";
        }

        // Precipitation
        double precipVal = (current['precipitation'] as num).toDouble();
        String precipUnit = currentUnits['precipitation'] ?? (useMetric ? 'mm' : 'inch');
        String precipString = "${precipVal.toStringAsFixed(2)} $precipUnit";

        // Weather Code - NOT requested, default to Unknown
        String condition = "Unknown";

        // --- Linear Interpolation Logic ---
        // 1. Find indices
        int index1 = -1;
        int index2 = -1;
        double weight = 0.0;
        
        try {
           String currentTimeStr = current['time']; 
           DateTime currentDt = DateTime.parse(currentTimeStr);
           
           if (hourly != null && hourly['time'] != null) {
              List<dynamic> times = hourly['time'];
              // Construct string for current hour matching Open-Meteo format YYYY-MM-DDTHH:00
              String hourStr1 = "${currentDt.toIso8601String().substring(0, 13)}:00";
              index1 = times.indexOf(hourStr1);
              
              if (index1 != -1) {
                // Determine next index
                if (index1 + 1 < times.length) {
                   index2 = index1 + 1;
                } else {
                   // Fallback to last available (boundary safety)
                   index2 = index1; 
                }
                
                // Calculate weight (minutes / 60)
                weight = currentDt.minute / 60.0;
              }
           }
        } catch (e) {
           print("Error finding interpolation indices: $e");
        }

        // Helper for interpolation
        double interpolate(double v1, double v2, double w) {
          return v1 + (v2 - v1) * w;
        }

        // --- Dewpoint (Interpolated) ---
        double? dewpoint;
        if (index1 != -1 && hourly != null && hourly['dew_point_2m'] != null) {
           List<dynamic> dewList = hourly['dew_point_2m'];
           if (index1 < dewList.length) {
              double d1 = (dewList[index1] as num).toDouble();
              double d2 = (index2 < dewList.length) ? (dewList[index2] as num).toDouble() : d1;
              dewpoint = interpolate(d1, d2, weight);
           }
        }

        // --- Visibility (Interpolated & Converted) ---
        String? visibilityString = "N/A";
        double visMilesForCategory = 10;
        
        if (index1 != -1 && hourly != null && hourly['visibility'] != null) {
           List<dynamic> visList = hourly['visibility'];
           if (index1 < visList.length) {
              double v1 = (visList[index1] as num).toDouble();
              double v2 = (index2 < visList.length) ? (visList[index2] as num).toDouble() : v1;
              
              // 1. Interpolate Raw Value
              double visVal = interpolate(v1, v2, weight);
              
              // 2. Unit Logic
              String visUnit = 'm'; 
              if (hourlyUnits != null && hourlyUnits['visibility'] != null) {
                visUnit = hourlyUnits['visibility'].toString();
              }
              
              // Calculate visMiles for Category Logic
              if (visUnit == 'ft') {
                  visMilesForCategory = visVal / 5280;
              } else {
                  // assume 'm'
                  visMilesForCategory = visVal * 0.000621371;
              }

              if (useMetric) {
                // Convert to KM
                double visKm;
                if (visUnit == 'ft') {
                  visKm = visVal * 0.0003048;
                } else {
                  visKm = visVal / 1000;
                }
                visibilityString = "${visKm.toStringAsFixed(1)} km";
              } else {
                // Display in Miles
                visibilityString = "${visMilesForCategory.toStringAsFixed(1)} mi";
              }
           }
        }

        // Ceiling / Sky Condition Calculation
        String ceilingString = "Unknown";
        double ceilingFeetForCategory = 100000; 
        
        try {
          double totalCover = (current['cloud_cover'] as num).toDouble();
          
          // Sky Condition string logic
          String skyCondition;
          if (totalCover < 10) {
            skyCondition = "SKC (Clear)";
          } else if (totalCover < 30) {
            skyCondition = "FEW (Few)";
          } else if (totalCover < 60) {
            skyCondition = "SCT (Scattered)";
          } else if (totalCover < 90) {
            skyCondition = "BKN (Broken)";
          } else {
            skyCondition = "OVC (Overcast)";
          }

          // Ceiling Height Logic
          String heightStr = "";
          if (totalCover >= 60) { // Ceiling represents BKN or OVC
             if (index1 != -1 && hourly != null) {
               double low = 0;
               double mid = 0;
               double high = 0;
               
               if (hourly['cloud_cover_low'] != null) {
                 low = (hourly['cloud_cover_low'][index1] as num).toDouble();
               }
               if (hourly['cloud_cover_mid'] != null) {
                 mid = (hourly['cloud_cover_mid'][index1] as num).toDouble();
               }
               if (hourly['cloud_cover_high'] != null) {
                 high = (hourly['cloud_cover_high'][index1] as num).toDouble();
               }
               
               if (low > 50) {
                 heightStr = "~2,000 ft";
                 ceilingFeetForCategory = 2000;
               } else if (mid > 50) {
                 heightStr = "~8,000 ft";
                 ceilingFeetForCategory = 8000;
               } else {
                 heightStr = "~20,000 ft";
                 ceilingFeetForCategory = 20000;
               }
             }
          } else {
             ceilingFeetForCategory = 100000;
          }
          
          if (heightStr.isNotEmpty) {
             ceilingString = "$skyCondition $heightStr";
          } else {
             ceilingString = skyCondition;
          }
          
        } catch (e) {
          print("Error calculating ceiling: $e");
          ceilingString = "${current['cloud_cover']}%"; 
        }
        
        // --- Flight Category Logic ---
        String flightCategory = "VFR";
        if (visMilesForCategory < 1 || ceilingFeetForCategory < 500) {
           flightCategory = "LIFR";
        } else if (visMilesForCategory < 3 || ceilingFeetForCategory < 1000) {
           flightCategory = "IFR";
        } else if (visMilesForCategory <= 5 || ceilingFeetForCategory <= 3000) {
           flightCategory = "MVFR";
        } else {
           flightCategory = "VFR";
        }
        
        if (windGusts > 25) {
           flightCategory += " (DANGER)";
        }

        // --- Density Altitude Calculation ---
        // 1. Altimeter Conversion: Convert rawPressureHpa to Altimeter Setting in inHg
        double altimeterInHg = rawPressureHpa * 0.02953; 
        
        // 2. Refined Pressure Altitude (PA)
        double pressureAltitudeFt = (29.92 - altimeterInHg) * 1000 + altitudeFt;
        
        // 3. Get Temp in Celsius
        double tempC = useMetric ? temp : (temp - 32) * 5 / 9;
        
        // 4. ISA Temp
        double isaTempC = 15 - (1.98 * pressureAltitudeFt / 1000);
        
        // 5. Precise DA Formula
        double densityAltitudeFt = pressureAltitudeFt + (118.8 * (tempC - isaTempC));
        
        // 6. Unit-Specific Output
        double finalDensityAltitude;
        if (useMetric) {
           finalDensityAltitude = densityAltitudeFt * 0.3048; // Convert to Meters
        } else {
           finalDensityAltitude = densityAltitudeFt; // Keep in Feet
        }

        // --- Sunrise/Sunset ---
        final sunTimes = AviationMath.calculateRawSunriseSunset(
          lat: lat,
          lon: lon,
          date: DateTime.now(),
        );

        return WeatherModel(
          temperature: temp,
          windSpeed: windSpeed,
          windDirection: windDir,
          pressure: pressureString,
          humidity: humidity,
          dewpoint: dewpoint,
          condition: condition,
          visibility: visibilityString,
          flightCategory: flightCategory,
          ceiling: ceilingString,
          densityAltitude: finalDensityAltitude,
          stationId: "GPS (Open-Meteo)",
          altitudeFt: altitudeFt,
          latitude: lat,
          longitude: lon,
          locationName: locationName, // Mapped to the new Nominatim result
          isInterpolated: true,
          precip: precipString,
          sunrise: sunTimes.sunrise,
          sunset: sunTimes.sunset,
        );

      } else {
        throw Exception('Failed to load weather data: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching Open-Meteo data: $e');
    }
  }
}
