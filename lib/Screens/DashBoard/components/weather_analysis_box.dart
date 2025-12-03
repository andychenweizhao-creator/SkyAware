import 'dart:async';
import 'package:flutter/material.dart';
import '../../../Service/location_service.dart';
import '../../../weather_service.dart';
import 'package:geolocator/geolocator.dart';

class WeatherAnalysisBox extends StatefulWidget {
  @override
  _WeatherAnalysisBoxState createState() => _WeatherAnalysisBoxState();
}

class _WeatherAnalysisBoxState extends State<WeatherAnalysisBox> {
  final LocationService _locationService = LocationService();
  final WeatherService _weatherService = WeatherService();

  StreamSubscription<Position>? _positionSubscription;
  Weather? _weather;
  Position? _lastPosition;

  @override
  void initState() {
    super.initState();
    _positionSubscription = _locationService.getPositionStream().listen((Position position) {
      if (!mounted) return;
      if (_lastPosition == null ||
          Geolocator.distanceBetween(
                _lastPosition!.latitude,
                _lastPosition!.longitude,
                position.latitude,
                position.longitude,
              ) >
              1000) {
        _lastPosition = position;
        _fetchWeather(position.latitude, position.longitude);
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchWeather(double latitude, double longitude) async {
    try {
      final weather = await _weatherService.getWeather(latitude, longitude);
      if (mounted) {
        setState(() => _weather = weather);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _weather = null); // Set weather to null on error
      }
      print('Failed to fetch weather: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final score = _calculateScore();
    final analysisText = _getAnalysisText(score);
    final color = _getColorForAnalysis(analysisText);
    final icon = _getIconForAnalysis(analysisText);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: Offset(0, 5))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Current Conditions", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
              SizedBox(height: 2),
              if (_weather == null)
                SizedBox(height: 28, child: Center(child: CircularProgressIndicator(color: Colors.white)))
              else
                Text(analysisText, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            ],
          ),
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }

  int _calculateScore() {
    if (_weather == null) return 0;
    final speed = _weather!.windSpeed;
    if (speed < 5) return 9;
    if (speed < 10) return 7;
    if (speed < 15) return 5;
    if (speed < 20) return 3;
    return 1;
  }

  String _getAnalysisText(int score) {
    if (_weather == null) return "LOADING...";
    if (score > 7) return "OPTIMAL";
    if (score > 4) return "MODERATE";
    return "DANGER";
  }

  Color _getColorForAnalysis(String analysis) {
    switch (analysis) {
      case "OPTIMAL":
        return Colors.green.shade600;
      case "MODERATE":
        return Colors.orange.shade600;
      case "DANGER":
        return Colors.red.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  IconData _getIconForAnalysis(String analysis) {
    switch (analysis) {
      case "OPTIMAL":
        return Icons.check_circle_outline;
      case "MODERATE":
        return Icons.warning_amber_outlined;
      case "DANGER":
        return Icons.dangerous_outlined;
      default:
        return Icons.help_outline;
    }
  }
}
