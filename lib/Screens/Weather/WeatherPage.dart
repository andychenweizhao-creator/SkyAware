import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/AltitudeWeatherService.dart';
import '../../UI/AppAnimations.dart';
import '../../UI/WeatherColors.dart';

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final AltitudeWeatherService _weatherService = AltitudeWeatherService();
  WeatherData? _weatherData;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadWeatherData();
  }

  Future<void> _loadWeatherData() async {
    try {
      final data = await _weatherService.getCurrentWeather();

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
      extendBody: true, // Forces body to flow behind the navigation bar
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
                      // Add padding at bottom so content isn't covered by floating nav
                      padding: const EdgeInsets.only(bottom: 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),
                          
                          // Header (Location)
                          StaggeredEntrance(index: 0, child: _buildHeader()),

                          const SizedBox(height: 10),

                          // Main Weather Section
                          StaggeredEntrance(index: 1, child: _buildMainSection()),

                          const SizedBox(height: 40),

                          // Glass Details Grid
                          _buildDetailsGrid(),
                        ],
                      ),
                    ),
        ),
      ),
      // Removed bottomNavigationBar to avoid duplication with the global NavigationBar
    );
  }

  Widget _buildHeader() {
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
                    ? "Lat: ${_weatherData!.latitude.toStringAsFixed(2)}  Lon: ${_weatherData!.longitude.toStringAsFixed(2)}  Alt: ${_weatherData!.altitudeFt.toStringAsFixed(0)}ft"
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
    return Column(
      children: [
        // VFR/IFR Pill Tag
        if (_weatherData?.flightCategory != null)
          SpringButton(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: _getCategoryColor(_weatherData!.flightCategory!).withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
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

        // Main Icon
        Icon(
          _getConditionIcon(_weatherData?.condition),
          color: Colors.white, 
          size: 80,
        ),
        
        // Temperature (Thin, Huge)
        _weatherData != null 
          ? AnimatedCounter(
              value: _weatherData!.temperature,
              suffix: "°",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 100,
                fontWeight: FontWeight.w200, // Very thin
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

        // Condition Text
        Text(
          _weatherData?.condition ?? "--",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w400,
          ),
        ),

        // High / Low / Interpolated Label
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
            value: _weatherData?.densityAltitude != null
                ? "${_weatherData!.densityAltitude!.toStringAsFixed(0)} ft"
                : "--",
            icon: Icons.compress,
            isAlert: (_weatherData?.densityAltitude ?? 0) > (_weatherData?.altitudeFt ?? 0) + 2000,
          ),
          _buildStaggeredTile(
            index: 3,
            title: "DEWPOINT",
            value: _weatherData?.dewpoint != null
                ? "${_weatherData!.dewpoint!.toStringAsFixed(1)}°"
                : "--",
            icon: Icons.water_drop_outlined,
            subtitle: _weatherData != null && _weatherData!.dewpoint != null
                ? "Spread: ${(_weatherData!.temperature - _weatherData!.dewpoint!).toStringAsFixed(1)}°"
                : null,
          ),
          _buildStaggeredTile(
            index: 4,
            title: "VISIBILITY",
            value: _weatherData?.visibility != null
                ? "${_weatherData!.visibility} SM"
                : "--",
            icon: Icons.visibility_outlined,
          ),
          _buildStaggeredTile(
            index: 5,
            title: "CEILING",
            value: _weatherData?.ceiling ?? "--",
            icon: Icons.cloud_outlined,
          ),
           _buildStaggeredTile(
             index: 6,
            title: "WIND",
            value: _weatherData != null
                ? "${_weatherData!.windSpeed.toStringAsFixed(0)} kt"
                : "--",
            icon: Icons.air,
            subtitle: _weatherData != null ? "Dir: ${_weatherData!.windDirection.toStringAsFixed(0)}°" : null,
          ),
           _buildStaggeredTile(
             index: 7,
            title: "PRESSURE",
            value: _weatherData?.pressure != null
                ? "${_weatherData!.pressure!.toStringAsFixed(2)} inHg"
                : "--",
            icon: Icons.speed,
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
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row
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
                  
                  // Main Value
                  Text(
                    value,
                    style: TextStyle(
                      color: isAlert ? Colors.redAccent : Colors.white,
                      fontSize: 24,
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
