import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../Service/location_service.dart';
import '../../../weather_service.dart';
import 'package:geolocator/geolocator.dart';

class WeatherDetailsBox extends StatefulWidget {
  @override
  _WeatherDetailsBoxState createState() => _WeatherDetailsBoxState();
}

class _WeatherDetailsBoxState extends State<WeatherDetailsBox> {
  final LocationService _locationService = LocationService();
  final WeatherService _weatherService = WeatherService();
  StreamSubscription<Position>? _positionSubscription;
  Weather? _weather;
  Position? _lastPosition;
  String? _error;

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

  void _fetchWeather(double latitude, double longitude) async {
    try {
      final weather = await _weatherService.getWeather(latitude, longitude);
      if (mounted) {
        setState(() {
          _weather = weather;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          constraints: BoxConstraints(maxWidth: 1000),
          height: 200,
          padding: EdgeInsets.fromLTRB(25, 15, 25, 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors: [Colors.white.withOpacity(0.18), Colors.white.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.4),
            boxShadow: [
              BoxShadow(color: Colors.white.withOpacity(0.25), blurRadius: 25, spreadRadius: -5, offset: Offset(-4, -4)),
              BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 30, offset: Offset(6, 10)),
            ],
          ),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Error fetching weather', style: TextStyle(color: Colors.white, fontSize: 16)),
          SizedBox(height: 10),
          ElevatedButton(
            onPressed: () {
              if (_lastPosition != null) {
                _fetchWeather(_lastPosition!.latitude, _lastPosition!.longitude);
              }
            },
            child: Text("Retry"),
          ),
        ],
      );
    }

    if (_weather == null) {
      return Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        SizedBox(height: 10),
        _buildDetails(),
        Spacer(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.cloudy_snowing, color: Colors.white, size: 28),
          SizedBox(width: 8),
          Text("Weather\nDetails", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, height: 1.2)),
        ]),
      ],
    );
  }

  Widget _buildDetails() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildDetailItem("Visibility", "${_weather!.visibility.toStringAsFixed(1)} mi"),
        _buildDetailItem("Precipitation", "${_weather!.precipitation.toStringAsFixed(2)} in"),
        _buildDetailItem("Cloud Cover", _weather!.cloudCover),
      ],
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Text(value, style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
