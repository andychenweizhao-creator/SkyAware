import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Enums for different unit types
enum DistanceSpeedUnit { nauticalMilesKnots, kilometersKph, milesMph }
enum AltitudeUnit { feet, meters }
enum PressureUnit { inHg, hPa }
enum TemperatureUnit { celsius, fahrenheit }

class UnitSettingsProvider with ChangeNotifier {
  static const String _distanceSpeedKey = "unit_distance_speed";
  static const String _altitudeKey = "unit_altitude";
  static const String _pressureKey = "unit_pressure";
  static const String _temperatureKey = "unit_temperature";

  DistanceSpeedUnit _distanceSpeedUnit = DistanceSpeedUnit.nauticalMilesKnots;
  AltitudeUnit _altitudeUnit = AltitudeUnit.feet;
  PressureUnit _pressureUnit = PressureUnit.inHg;
  TemperatureUnit _temperatureUnit = TemperatureUnit.celsius;

  // Getters
  DistanceSpeedUnit get distanceSpeedUnit => _distanceSpeedUnit;
  AltitudeUnit get altitudeUnit => _altitudeUnit;
  PressureUnit get pressureUnit => _pressureUnit;
  TemperatureUnit get temperatureUnit => _temperatureUnit;

  UnitSettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Distance & Speed
    final distSpeedIndex = prefs.getInt(_distanceSpeedKey);
    if (distSpeedIndex != null && distSpeedIndex < DistanceSpeedUnit.values.length) {
      _distanceSpeedUnit = DistanceSpeedUnit.values[distSpeedIndex];
    }

    // Load Altitude
    final altIndex = prefs.getInt(_altitudeKey);
    if (altIndex != null && altIndex < AltitudeUnit.values.length) {
      _altitudeUnit = AltitudeUnit.values[altIndex];
    }

    // Load Pressure
    final pressIndex = prefs.getInt(_pressureKey);
    if (pressIndex != null && pressIndex < PressureUnit.values.length) {
      _pressureUnit = PressureUnit.values[pressIndex];
    }

    // Load Temperature
    final tempIndex = prefs.getInt(_temperatureKey);
    if (tempIndex != null && tempIndex < TemperatureUnit.values.length) {
      _temperatureUnit = TemperatureUnit.values[tempIndex];
    }

    notifyListeners();
  }

  // Setters with persistence
  Future<void> setDistanceSpeedUnit(DistanceSpeedUnit unit) async {
    _distanceSpeedUnit = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_distanceSpeedKey, unit.index);
    notifyListeners();
  }

  Future<void> setAltitudeUnit(AltitudeUnit unit) async {
    _altitudeUnit = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_altitudeKey, unit.index);
    notifyListeners();
  }

  Future<void> setPressureUnit(PressureUnit unit) async {
    _pressureUnit = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pressureKey, unit.index);
    notifyListeners();
  }

  Future<void> setTemperatureUnit(TemperatureUnit unit) async {
    _temperatureUnit = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_temperatureKey, unit.index);
    notifyListeners();
  }
}
