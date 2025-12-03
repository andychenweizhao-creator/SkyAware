import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../Service/location_service.dart';
import '../../../weather_service.dart';
import '../../../Service/openai_service.dart';
import 'package:geolocator/geolocator.dart';

class WindConditionsBox extends StatefulWidget {
  @override
  _WindConditionsBoxState createState() => _WindConditionsBoxState();
}

class _WindConditionsBoxState extends State<WindConditionsBox> {
  final LocationService _locationService = LocationService();
  final WeatherService _weatherService = WeatherService();
  final OpenAIService _openAIService = OpenAIService();

  StreamSubscription<Position>? _positionSubscription;
  Weather? _weather;
  String _analysisScore = "";
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
        _fetchData(position.latitude, position.longitude);
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchData(double latitude, double longitude) async {
    try {
      final weather = await _weatherService.getWeather(latitude, longitude);
      final analysis = await _openAIService.analyzeWeather(weather);
      if (mounted) {
        setState(() {
          _weather = weather;
          _analysisScore = analysis;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
      print('Failed to fetch data: $e');
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
            child: _buildContent()),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Error fetching data', style: TextStyle(color: Colors.white, fontSize: 16)),
          SizedBox(height: 10),
          ElevatedButton(
            onPressed: () {
              if (_lastPosition != null) {
                _fetchData(_lastPosition!.latitude, _lastPosition!.longitude);
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
        _buildProgressBar(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.air, color: Colors.white, size: 28),
          SizedBox(width: 8),
          Text("Wind\nConditions", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, height: 1.2)),
        ]),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: Color(0xFF2C3A4F).withOpacity(0.8), borderRadius: BorderRadius.circular(16)),
          child: Text("Score: $_analysisScore/10", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildDetailItem("Speed", _weather!.windSpeed.toStringAsFixed(0), "mph"),
        _buildDetailItem("Direction", _weather!.windDirection, null),
        _buildDetailItem("Gust", _weather!.windGust.toStringAsFixed(0), "mph"),
      ],
    );
  }

  Widget _buildDetailItem(String label, String value, String? unit) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
        SizedBox(height: 2),
        Text(value, style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
        if (unit != null) Text(unit, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
        if (unit == null) SizedBox(height: 27),
      ],
    );
  }

  Widget _buildProgressBar() {
    final score = int.tryParse(_analysisScore) ?? 0;
    return Container(
      height: 8,
      child: ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        child: Row(
          children: [
            Expanded(flex: score, child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF80E894), Color(0xFFF5E669)])))),
            Expanded(flex: 10 - score, child: Container(color: Color(0xFF3D4C63))),
          ],
        ),
      ),
    );
  }
}
