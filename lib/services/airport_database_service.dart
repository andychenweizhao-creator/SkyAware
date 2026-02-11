import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart'; // For LatLngBounds

class Airport {
  final String ident;
  final String iata;
  final String name;
  final double lat;
  final double lon;
  final int elevation;
  final String type;
  String? riskColor; // Added for AI grading integration
  String? riskReason;

  Airport({
    required this.ident,
    this.iata = 'N/A',
    required this.name,
    required this.lat,
    required this.lon,
    required this.elevation,
    required this.type,
    this.riskColor,
    this.riskReason,
  });
}

class AirportDatabaseService {
  static final AirportDatabaseService _instance = AirportDatabaseService._internal();

  factory AirportDatabaseService() {
    return _instance;
  }

  AirportDatabaseService._internal();

  final List<Airport> _allAirports = [];
  bool _isLoaded = false;

  Future<void> loadDatabase() async {
    if (_isLoaded) return;

    try {
      final String data = await rootBundle.loadString('assets/GlobalAirportDatabase.txt');
      final List<String> lines = const LineSplitter().convert(data);

      for (String line in lines) {
        if (line.trim().isEmpty) continue;
        
        final parts = line.split(':');

        if (parts.length >= 14) {
          // 1. Parse Name
          String name = parts[2].trim();
          String nameUpper = name.toUpperCase();

          // 2. Blacklist Filter
          if (nameUpper.contains("HELIPORT") || nameUpper.contains("HELIPAD") || nameUpper.contains("HELI ")) continue;
          if (nameUpper.contains("SEAPLANE") || nameUpper.contains(" SPB ") || nameUpper.contains("FLOATPLANE")) continue;
          if (nameUpper.contains("STATION") || nameUpper.contains("TRAIN")) continue;
          if (nameUpper.contains("GLIDER") || nameUpper.contains("ULTRALIGHT")) continue;

          int latDeg = int.tryParse(parts[5]) ?? 0;
          int latMin = int.tryParse(parts[6]) ?? 0;
          int latSec = int.tryParse(parts[7]) ?? 0;
          String latDir = parts[8].toUpperCase();

          int lonDeg = int.tryParse(parts[9]) ?? 0;
          int lonMin = int.tryParse(parts[10]) ?? 0;
          int lonSec = int.tryParse(parts[11]) ?? 0;
          String lonDir = parts[12].toUpperCase();

          double lat = _dmsToDecimal(latDeg, latMin, latSec, latDir);
          double lon = _dmsToDecimal(lonDeg, lonMin, lonSec, lonDir);

          // 3. Coordinate Calculation & Filter
          if (lat == 0.0 && lon == 0.0) continue; // Invalid data

          // North American Filter
          if (lat < 15.0) continue; // Region filter (Mexico/South America)
          if (lon > -50.0) continue;     
          if (lon < -180.0) continue;    
          if (lonDir != 'W' && lon != 0.0 && lon != 180.0) continue;
          if (lon > 0) continue;

          String ident = parts[0];
          String iata = parts[1];
          
          if (ident == 'N/A' && iata != 'N/A') {
             ident = iata;
          }
          if (ident == 'N/A' || ident.isEmpty) continue;

          int elevation = int.tryParse(parts[13]) ?? 0;

          _allAirports.add(Airport(
            ident: ident,
            iata: iata,
            name: name,
            lat: lat,
            lon: lon,
            elevation: elevation,
            type: "airport", 
          ));
        }
      }
      _isLoaded = true;
      print("AirportDatabaseService: Loaded ${_allAirports.length} airports (North America).");
    } catch (e) {
      print("AirportDatabaseService Error: $e");
    }
  }

  double _dmsToDecimal(int degrees, int minutes, int seconds, String direction) {
    double decimal = degrees + (minutes / 60.0) + (seconds / 3600.0);
    if (direction == 'S' || direction == 'W') {
      decimal = -decimal;
    }
    return decimal;
  }

  List<Airport> getAirportsInBounds(LatLngBounds bounds) {
    if (!_isLoaded) return [];
    return _allAirports.where((airport) {
      return bounds.contains(LatLng(airport.lat, airport.lon));
    }).toList();
  }

  /// Finds airports within a specific radius in Nautical Miles.
  List<Airport> getAirportsWithinRadius(double lat, double lon, double radiusNm) {
    if (!_isLoaded) return [];

    final Distance distance = const Distance();
    final LatLng currentPos = LatLng(lat, lon);
    final List<MapEntry<Airport, double>> results = [];

    // Optimization: 1 degree latitude is ~60nm.
    // Use a buffer slightly larger than required radius
    double degreesBuffer = (radiusNm / 60.0) * 1.5; 

    for (final airport in _allAirports) {
      // Coarse Filter
      if ((airport.lat - lat).abs() > degreesBuffer || (airport.lon - lon).abs() > degreesBuffer) continue;

      // Exclusion Logic (Copied for consistency)
      String nameUpper = airport.name.toUpperCase();
      if (nameUpper.contains("HELIPORT") || nameUpper.contains("HELIPAD") || nameUpper.contains("HELI ")) continue;
      if (nameUpper.contains("SEAPLANE") || nameUpper.contains(" SPB ") || nameUpper.contains("FLOAT")) continue;
      if (nameUpper.contains("STATION") || nameUpper.contains("TRAIN")) continue;
      if (nameUpper.contains("OFFLINE") || nameUpper.contains("CLOSED")) continue;
      if (airport.lat == 0.0 && airport.lon == 0.0) continue;

      final double distMeters = distance.as(LengthUnit.Meter, currentPos, LatLng(airport.lat, airport.lon));
      final double distNm = distMeters / 1852.0;

      if (distNm <= radiusNm) {
        results.add(MapEntry(airport, distNm));
      }
    }

    // Sort by distance
    results.sort((a, b) => a.value.compareTo(b.value));

    return results.map((e) => e.key).toList();
  }

  /// Finds the nearest [limit] airports to the given coordinates.
  /// Uses Haversine distance.
  List<Airport> getNearestAirports(double lat, double lon, int limit) {
    if (!_isLoaded) return [];

    final Distance distance = const Distance();
    final LatLng currentPos = LatLng(lat, lon);

    // Filter roughly first to avoid expensive calcs on all airports
    // 5 degrees latitude is roughly 300nm.
    final List<MapEntry<Airport, double>> candidates = [];
    
    // First pass: Only airports with IATA codes (likely major/paved)
    for (final airport in _allAirports) {
      // STRICT EXCLUSION LIST (Double Check in Search)
      String nameUpper = airport.name.toUpperCase();
      if (nameUpper.contains("HELIPORT") || nameUpper.contains("HELIPAD") || nameUpper.contains("HELI ")) continue;
      if (nameUpper.contains("SEAPLANE") || nameUpper.contains(" SPB ") || nameUpper.contains("FLOAT")) continue;
      if (nameUpper.contains("STATION") || nameUpper.contains("TRAIN")) continue;
      if (nameUpper.contains("OFFLINE") || nameUpper.contains("CLOSED")) continue;
      
      // COORDINATE CHECK:
      if (airport.lat == 0.0 && airport.lon == 0.0) continue;

      if (airport.iata == 'N/A') continue; // Optimization: Skip non-IATA first
      
      if ((airport.lat - lat).abs() < 5.0 && (airport.lon - lon).abs() < 5.0) {
        // Calculate meters and convert to Nautical Miles (1 NM = 1852m)
        final double distMeters = distance.as(LengthUnit.Meter, currentPos, LatLng(airport.lat, airport.lon));
        final double distNm = distMeters / 1852.0;
        candidates.add(MapEntry(airport, distNm));
      }
    }

    // If we don't have enough candidates, widen search to include non-IATA
    if (candidates.length < limit) {
       for (final airport in _allAirports) {
          if (airport.iata != 'N/A') continue; // Already checked
          
          // STRICT EXCLUSION LIST (Double Check in Search)
          String nameUpper = airport.name.toUpperCase();
          if (nameUpper.contains("HELIPORT") || nameUpper.contains("HELIPAD") || nameUpper.contains("HELI ")) continue;
          if (nameUpper.contains("SEAPLANE") || nameUpper.contains(" SPB ") || nameUpper.contains("FLOAT")) continue;
          if (nameUpper.contains("STATION") || nameUpper.contains("TRAIN")) continue;
          if (nameUpper.contains("OFFLINE") || nameUpper.contains("CLOSED")) continue;
          
          if (airport.lat == 0.0 && airport.lon == 0.0) continue;
          
          if ((airport.lat - lat).abs() < 5.0 && (airport.lon - lon).abs() < 5.0) {
            final double distMeters = distance.as(LengthUnit.Meter, currentPos, LatLng(airport.lat, airport.lon));
            final double distNm = distMeters / 1852.0;
            candidates.add(MapEntry(airport, distNm));
          }
       }
    }

    // Sort by distance
    candidates.sort((a, b) => a.value.compareTo(b.value));

    // Return top N
    return candidates.take(limit).map((e) => e.key).toList();
  }
}
