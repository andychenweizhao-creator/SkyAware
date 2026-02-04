import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../repositories/weather_repository.dart';
import '../../models/weather_model.dart';
import '../../services/unit_settings_service.dart';
import '../../services/AviationWeatherCalculator.dart';
import '../../UI/AppAnimations.dart';
import '../../UI/WeatherColors.dart';

// Updated WeatherPage logic for raw data display
class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final WeatherRepository _weatherRepository = WeatherRepository();
  WeatherModel? _weatherData;
  bool _isLoading = true;
  String _errorMessage = '';
  
  // State for Surface Mode Toggle
  bool _useSurfaceMode = false;
  
  @override
  void initState() {
    super.initState();
    _loadWeatherData();
  }

  Future<void> _loadWeatherData() async {
    try {
      if (mounted && _weatherData == null) {
         setState(() => _isLoading = true);
      }
      
      // 1. Get Location
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Location permissions are denied';
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw 'Location permissions are permanently denied.';
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best
      );
      double altitudeFt = position.altitude * 3.28084;

      // 2. Get Weather (Always Metric Baseline)
      final data = await _weatherRepository.getWeather(
          position.latitude, 
          position.longitude, 
          altitudeFt, 
          forceSurface: _useSurfaceMode, 
      );

      if (mounted) {
        setState(() {
          _weatherData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load weather: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: AliveBackground(
        gradient: WeatherColors.getGradient(_weatherData?.condition),
        child: SafeArea(
          bottom: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _errorMessage.isNotEmpty
                  ? Center(
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),
                          StaggeredEntrance(index: 0, child: _buildHeader()),
                          const SizedBox(height: 10),
                          StaggeredEntrance(index: 1, child: _buildMainSection()),
                          const SizedBox(height: 40),
                          _buildDetailsGrid(),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final units = Provider.of<UnitSettingsProvider>(context);
    
    String altDisplay = "--";
    if (_weatherData != null) {
      if (units.altitudeUnit == AltitudeUnit.meters) {
        // Source is Feet (User Input stored in model)
        double altMeters = AviationMath.feetToMeters(_weatherData!.altitudeFt);
        altDisplay = "${altMeters.toStringAsFixed(0)}m";
      } else {
        altDisplay = "${_weatherData!.altitudeFt.toStringAsFixed(0)}ft";
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        children: [
          Text(
            _weatherData?.locationName ?? "--",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.gps_fixed, color: Colors.white70, size: 14),
              const SizedBox(width: 6),
              Text(
                _weatherData != null
                    ? "Lat: ${_weatherData!.latitude.toStringAsFixed(2)}  Lon: ${_weatherData!.longitude.toStringAsFixed(2)}  Alt: $altDisplay"
                    : "Locating...",
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Mode Switch Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _useSurfaceMode ? "Surface Mode" : "Altitude Mode",
                style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Switch(
                value: !_useSurfaceMode, // True if Altitude, False if Surface
                onChanged: (val) {
                  setState(() {
                    _useSurfaceMode = !val;
                    _isLoading = true; // Show loading while fetching
                  });
                  _loadWeatherData();
                },
                activeColor: Colors.blueAccent,
                activeTrackColor: Colors.blueAccent.withOpacity(0.4),
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.grey.withOpacity(0.4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainSection() {
    final units = Provider.of<UnitSettingsProvider>(context);
    
    int tempVal = 0;
    String tempSuffix = "°";
    
    if (_weatherData != null) {
      double t = _weatherData!.temperature; // Source Metric (C)
      
      if (units.temperatureUnit == TemperatureUnit.fahrenheit) {
        t = AviationMath.celsiusToFahrenheit(t);
      }
      
      tempVal = t.round();
    }

    return Column(
      children: [
        if (_weatherData?.flightCategory != null)
          SpringButton(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: _getCategoryColor(_weatherData!.flightCategory!).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Text(
                _weatherData!.flightCategory!,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),

        Icon(
          _getConditionIcon(_weatherData?.condition),
          color: Colors.white, 
          size: 80,
        ),
        
        _weatherData != null 
          ? AnimatedCounter(
              value: tempVal,
              suffix: tempSuffix,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 100,
                fontWeight: FontWeight.w200,
                height: 1.0,
              ),
            )
          : const Text(
              "--",
              style: TextStyle(
                color: Colors.white,
                fontSize: 100,
                fontWeight: FontWeight.w200,
                height: 1.0,
              ),
            ),

        Text(
          _weatherData?.condition ?? "--",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w400,
          ),
        ),

        const SizedBox(height: 5),
        Text(
          _weatherData?.isInterpolated == true
              ? "Interpolated Aloft Data"
              : "Surface Data",
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsGrid() {
    final units = Provider.of<UnitSettingsProvider>(context);

    // Density Altitude
    String densityAltDisplay = "--";
    if (_weatherData?.densityAltitude != null) {
      double daMeters = _weatherData!.densityAltitude!; // Source Metric (m)
      
      if (units.altitudeUnit == AltitudeUnit.meters) {
         densityAltDisplay = "${daMeters.toStringAsFixed(0)} m";
      } else {
         double daFt = AviationMath.metersToFeet(daMeters);
         densityAltDisplay = "${daFt.toStringAsFixed(0)} ft";
      }
    }

    // Dewpoint
    String dewpointDisplay = "--";
    String spreadDisplay = "";
    if (_weatherData?.dewpoint != null && _weatherData!.dewpoint != null) {
      double d = _weatherData!.dewpoint!; // Source C
      double t = _weatherData!.temperature; // Source C
      
      if (units.temperatureUnit == TemperatureUnit.fahrenheit) {
        d = AviationMath.celsiusToFahrenheit(d);
        t = AviationMath.celsiusToFahrenheit(t);
      }
      
      double spread = t - d;
      
      dewpointDisplay = "${d.toStringAsFixed(1)}°";
      spreadDisplay = "Spread: ${spread.toStringAsFixed(1)}°";
    }

    // Visibility
    String visDisplay = "--";
    if (_weatherData?.visibility != null) {
      double visMeters = _weatherData!.visibility!; // Source m
      
      if (units.distanceSpeedUnit == DistanceSpeedUnit.milesMph || 
          units.distanceSpeedUnit == DistanceSpeedUnit.nauticalMilesKnots) { // Typically visibility is SM in aviation
         double visSm = AviationMath.metersToMiles(visMeters);
         visDisplay = "${visSm.toStringAsFixed(1)} mi";
      } else {
         double visKm = visMeters / 1000.0;
         visDisplay = "${visKm.toStringAsFixed(1)} km";
      }
    }

    // Ceiling (Dynamic Units)
    String ceilingDisplay = "--";
    if (_weatherData?.ceilingType != null) {
        String type = _weatherData!.ceilingType!;
        
        if (type == "Unlimited") {
            ceilingDisplay = "Unlimited";
        } else if (_weatherData!.ceilingHeight != null) {
            double hMeters = _weatherData!.ceilingHeight!; // Source Meters
            String valStr = "";
            
            if (units.altitudeUnit == AltitudeUnit.meters) {
                valStr = "${hMeters.toStringAsFixed(0)} m";
            } else {
                double hFt = AviationMath.metersToFeet(hMeters);
                // Round to nearest 100ft typically? Or just integer.
                // Keeping it simple integer.
                valStr = "${hFt.toStringAsFixed(0)} ft";
            }
            
            // Format: "Overcast ~2000 ft" or "Below Aircraft (500 ft)" logic reconstruction?
            // WeatherModel stores type like "Overcast", "Broken", "Below Aircraft", "Above".
            
            if (type.contains("Below Aircraft")) {
                ceilingDisplay = "Below Aircraft \n($valStr)";
            } else if (type.contains("Above")) {
                ceilingDisplay = "$valStr \nAbove";
            } else {
                // "Overcast", "Broken"
                ceilingDisplay = "$type \n~$valStr";
            }
        } else {
            ceilingDisplay = type;
        }
    }

    // Wind
    String windDisplay = "--";
    if (_weatherData != null) {
       double w = _weatherData!.windSpeed; // Source KMH
       String unit = "kt";
       
       if (units.distanceSpeedUnit == DistanceSpeedUnit.kilometersKph) {
         unit = "kph"; // Already KMH
       } else if (units.distanceSpeedUnit == DistanceSpeedUnit.milesMph) {
         w = AviationMath.kmhToMph(w);
         unit = "mph";
       } else {
         w = AviationMath.kmhToKnots(w);
         unit = "kt";
       }
       
       windDisplay = "${w.toStringAsFixed(0)} $unit";
    }

    // Pressure
    String pressureDisplay = "--";
    if (_weatherData?.pressure != null) {
       double p = _weatherData!.pressure!; // Source hPa
       
       if (units.pressureUnit == PressureUnit.inHg) {
          p = AviationMath.hpaToInHg(p);
          pressureDisplay = "${p.toStringAsFixed(2)} inHg";
       } else {
          pressureDisplay = "${p.toStringAsFixed(2)} hPa";
       }
    }

    // Humidity
    String humidityDisplay = "--";
    if (_weatherData?.humidity != null) {
      humidityDisplay = "${_weatherData!.humidity!.round()}%";
    }

    // Precipitation
    String precipDisplay = "--";
    if (_weatherData?.precip != null) {
       double pVal = _weatherData!.precip!; // Source mm
       
       // Metric check for precip? Usually follows Distance or Temp preference? 
       // Or explicit if available. UnitSettingsProvider doesn't have explicit precip unit.
       // Usually: Metric (mm) if Temp is C or Dist is KM.
       // Let's use Temp unit as proxy for "System".
       
       if (units.temperatureUnit == TemperatureUnit.celsius) {
          precipDisplay = "${pVal.toStringAsFixed(2)} mm";
       } else {
          double pInch = AviationMath.mmToInches(pVal);
          precipDisplay = "${pInch.toStringAsFixed(2)}\"";
       }
    } else if (_weatherData != null) {
         // Fallback logic
        if (precipDisplay == "--") {
            if (_weatherData!.condition.toLowerCase().contains("rain") || 
                _weatherData!.condition.toLowerCase().contains("snow") ||
                _weatherData!.condition.toLowerCase().contains("drizzle")) {
                precipDisplay = "Active"; 
            } else {
                precipDisplay = "None";
            }
        }
    }

    // Sunrise / Sunset
    String sunDisplay = "--";
    if (_weatherData?.sunrise != null && _weatherData?.sunset != null) {
       String formatTime(DateTime dt) {
          String h = dt.hour.toString().padLeft(2, '0');
          String m = dt.minute.toString().padLeft(2, '0');
          return "$h:$m";
       }
       sunDisplay = "SR ${formatTime(_weatherData!.sunrise!)}\nSS ${formatTime(_weatherData!.sunset!)}";
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.1,
        children: [
          _buildStaggeredTile(
            index: 2,
            title: "SUNRISE / SUNSET",
            value: sunDisplay,
            icon: Icons.wb_twilight,
            valueFontSize: 18, 
          ),
          _buildStaggeredTile(
            index: 3,
            title: "DEWPOINT",
            value: dewpointDisplay,
            icon: Icons.water_drop_outlined,
            subtitle: _weatherData != null && _weatherData!.dewpoint != null
                ? spreadDisplay
                : null,
          ),
          _buildStaggeredTile(
            index: 4,
            title: "VISIBILITY",
            value: visDisplay,
            icon: Icons.visibility_outlined,
          ),
          _buildStaggeredTile(
            index: 5,
            title: "DENSITY ALT",
            value: densityAltDisplay,
            icon: Icons.compress,
            isAlert: (_weatherData?.densityAltitude ?? 0) > (_weatherData?.altitudeFt ?? 0) + 2000,
          ),
           _buildStaggeredTile(
             index: 6,
            title: "WIND",
            value: windDisplay,
            icon: Icons.air,
            subtitle: _weatherData != null ? "Dir: ${_weatherData!.windDirection.toStringAsFixed(0)}°" : null,
          ),
           _buildStaggeredTile(
             index: 7,
            title: "PRESSURE",
            value: pressureDisplay,
            icon: Icons.speed,
          ),
          _buildStaggeredTile(
            index: 8,
            title: "HUMIDITY",
            value: humidityDisplay,
            icon: Icons.percent,
          ),
          _buildStaggeredTile(
            index: 9,
            title: "CEILING / PRECIP",
            value: ceilingDisplay,
            icon: Icons.cloud_outlined,
            subtitle: "Precip: $precipDisplay",
          ),
        ],
      ),
    );
  }
  
  Widget _buildStaggeredTile({
    required int index,
    required String title,
    required String value,
    required IconData icon,
    String? subtitle,
    bool isAlert = false,
    double valueFontSize = 24,
  }) {
    return StaggeredEntrance(
      index: index,
      child: SpringButton(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: Colors.white70, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    value,
                    style: TextStyle(
                      color: isAlert ? Colors.redAccent : Colors.white,
                      fontSize: valueFontSize,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getConditionIcon(String? condition) {
    if (condition == null) return Icons.help_outline;
    final c = condition.toLowerCase();
    if (c.contains('clear')) return Icons.wb_sunny_rounded;
    if (c.contains('sunny')) return Icons.wb_sunny_rounded;
    if (c.contains('partly')) return Icons.wb_cloudy_rounded; 
    if (c.contains('cloud')) return Icons.cloud_rounded;
    if (c.contains('rain')) return Icons.water_drop_rounded;
    if (c.contains('snow')) return Icons.ac_unit_rounded;
    if (c.contains('fog') || c.contains('obscured')) return Icons.foggy;
    return Icons.wb_cloudy_rounded;
  }
  
  Color _getCategoryColor(String category) {
    switch (category) {
      case 'VFR': return Colors.green;
      case 'MVFR': return Colors.blue;
      case 'IFR': return Colors.red;
      case 'LIFR': return Colors.purple;
      default: return Colors.grey;
    }
  }
}
