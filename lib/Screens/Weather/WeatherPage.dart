import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../repositories/weather_repository.dart';
import '../../models/weather_model.dart';
import '../../services/unit_settings_service.dart';
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
  
  // Track the units the data was fetched in to allow on-the-fly conversion if settings change
  bool _fetchedAsMetric = true; 

  @override
  void initState() {
    super.initState();
    _loadWeatherData();
  }

  Future<void> _loadWeatherData() async {
    try {
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

      // 2. Reverse Geocoding
      String locName = "Unknown Location";
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          String name = place.name ?? "";
          String locality = place.locality ?? "";
          String adminArea = place.administrativeArea ?? "";

          if (locality.isNotEmpty && adminArea.isNotEmpty) {
             locName = "Near $locality, $adminArea";
          } else if (name.isNotEmpty && locality.isNotEmpty) {
             locName = "Near $name, $locality";
          } else if (locality.isNotEmpty) {
             locName = "Near $locality";
          } else {
             locName = "Lat: ${position.latitude.toStringAsFixed(1)}, Lon: ${position.longitude.toStringAsFixed(1)}";
          }
        }
      } catch (e) {
        debugPrint("Geocoding error: $e");
      }

      // 3. Get Weather
      // Determine preference at time of fetch
      final units = Provider.of<UnitSettingsProvider>(context, listen: false);
      bool useMetric = units.temperatureUnit == TemperatureUnit.celsius;
      
      final data = await _weatherRepository.getWeather(
          position.latitude, 
          position.longitude, 
          altitudeFt, 
          useMetric: useMetric
      );

      if (mounted) {
        setState(() {
          _weatherData = data;
          _fetchedAsMetric = useMetric; // Store what we fetched
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
        altDisplay = "${(_weatherData!.altitudeFt * 0.3048).toStringAsFixed(0)}m";
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
        ],
      ),
    );
  }

  Widget _buildMainSection() {
    final units = Provider.of<UnitSettingsProvider>(context);
    
    int tempVal = 0;
    String tempSuffix = "°";
    
    if (_weatherData != null) {
      double t = _weatherData!.temperature;
      bool targetMetric = units.temperatureUnit == TemperatureUnit.celsius;

      // Conversion logic if settings changed since fetch
      if (_fetchedAsMetric && !targetMetric) {
        // Fetched C, Display F
        t = (t * 9 / 5) + 32;
      } else if (!_fetchedAsMetric && targetMetric) {
        // Fetched F, Display C
        t = (t - 32) * 5 / 9;
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
      if (units.altitudeUnit == AltitudeUnit.meters) {
        densityAltDisplay = "${(_weatherData!.densityAltitude! * 0.3048).toStringAsFixed(0)} m";
      } else {
        densityAltDisplay = "${_weatherData!.densityAltitude!.toStringAsFixed(0)} ft";
      }
    }

    // Dewpoint
    String dewpointDisplay = "--";
    String spreadDisplay = "";
    if (_weatherData?.dewpoint != null && _weatherData!.dewpoint != null) {
      double d = _weatherData!.dewpoint!;
      double t = _weatherData!.temperature;
      
      bool targetMetric = units.temperatureUnit == TemperatureUnit.celsius;
      
      // Convert T and D if necessary to match target unit
      if (_fetchedAsMetric && !targetMetric) {
        d = (d * 9 / 5) + 32;
        t = (t * 9 / 5) + 32;
      } else if (!_fetchedAsMetric && targetMetric) {
        d = (d - 32) * 5 / 9;
        t = (t - 32) * 5 / 9;
      }
      
      double spread = t - d;
      
      dewpointDisplay = "${d.toStringAsFixed(1)}°";
      spreadDisplay = "Spread: ${spread.toStringAsFixed(1)}°";
    }

    // Visibility
    // Display raw string from Service
    String visDisplay = _weatherData?.visibility ?? "--";

    // Ceiling
    String ceilingDisplay = _weatherData?.ceiling ?? "--"; 

    // Wind
    String windDisplay = "--";
    if (_weatherData != null) {
       double w = _weatherData!.windSpeed;
       String unit = "kt";
       
       // Determine source unit
       // if _fetchedAsMetric: KMH. if !: MPH.
       
       if (units.distanceSpeedUnit == DistanceSpeedUnit.kilometersKph) {
         // Target: KPH
         if (!_fetchedAsMetric) w = w * 1.60934; // MPH -> KPH
         // If source KMH, do nothing.
         unit = "kph";
       } else if (units.distanceSpeedUnit == DistanceSpeedUnit.milesMph) {
         // Target: MPH
         if (_fetchedAsMetric) w = w / 1.60934; // KMH -> MPH
         unit = "mph";
       } else {
         // Target: Knots
         if (_fetchedAsMetric) w = w * 0.539957; // KMH -> Kt
         else w = w * 0.868976; // MPH -> Kt
       }
       
       windDisplay = "${w.toStringAsFixed(0)} $unit";
    }

    // Pressure
    // Display raw string from Service
    String pressureDisplay = _weatherData?.pressure ?? "--";

    // Humidity
    String humidityDisplay = "--";
    if (_weatherData?.humidity != null) {
      humidityDisplay = "${_weatherData!.humidity!.round()}%";
    }

    // Precipitation
    String precipDisplay = "--";
    if (_weatherData?.precip != null) {
       precipDisplay = _weatherData!.precip!;
    } else if (_weatherData != null) {
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
            title: "DENSITY ALT",
            value: densityAltDisplay,
            icon: Icons.compress,
            isAlert: (_weatherData?.densityAltitude ?? 0) > (_weatherData?.altitudeFt ?? 0) + 2000,
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
            title: "CEILING / PRECIP",
            value: ceilingDisplay,
            icon: Icons.cloud_outlined,
            subtitle: "Precip: $precipDisplay",
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
            title: "SUNRISE / SUNSET",
            value: sunDisplay,
            icon: Icons.wb_twilight,
            valueFontSize: 18, 
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
