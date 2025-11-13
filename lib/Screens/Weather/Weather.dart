import 'package:flutter/material.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../../location_service.dart';
import '../../weather_service.dart';

class Weather extends StatefulWidget {
  @override
  _WeatherState createState() => _WeatherState();
}

class _WeatherState extends State<Weather> {
  final LocationService _locationService = LocationService();
  final WeatherService _weatherService = WeatherService();

  WeatherDetails? _weatherDetails;
  Map<String, dynamic>? _windConditions;
  bool _isLoading = true;
  String? _error;

  StreamSubscription<Position>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  void _fetchInitialData() {
    _positionSubscription = _locationService.getPositionStream().listen(
      (Position position) {
        // Once we have a location, fetch the weather data and stop listening
        _fetchWeatherData(position.latitude, position.longitude);
        _positionSubscription?.cancel();
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _error = e.toString();
            _isLoading = false;
          });
        }
      },
    );
  }

  Future<void> _fetchWeatherData(double latitude, double longitude) async {
    try {
      final details = await _weatherService.getWeatherDetails(latitude, longitude);
      final wind = await _weatherService.getWindConditions(latitude, longitude);
      if (mounted) {
        setState(() {
          _weatherDetails = details;
          _windConditions = wind;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Current Weather Conditions'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    if (_weatherDetails == null || _windConditions == null) {
      return Center(child: Text('No weather data available.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Weather Details'),
          SizedBox(height: 10),
          _buildInfoCard(
            children: [
              _buildInfoRow('Visibility', '${_weatherDetails!.visibility.toStringAsFixed(1)} mi'),
              _buildInfoRow('Precipitation', _weatherDetails!.precipitation),
              _buildInfoRow('Cloud Ceiling', _weatherDetails!.cloudCeiling),
            ],
          ),
          SizedBox(height: 30),
          _buildSectionHeader('Wind Conditions'),
          SizedBox(height: 10),
          _buildInfoCard(
            children: [
              _buildInfoRow('Speed', '${_windConditions!['speed'].toStringAsFixed(0)} mph'),
              _buildInfoRow('Gust', '${_windConditions!['gust'].toStringAsFixed(0)} mph'),
              _buildInfoRow('Direction', _windConditions!['direction']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
    );
  }

  Widget _buildInfoCard({required List<Widget> children}) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 18, color: Colors.white70)),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}
