import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart'; // For LatLngBounds

class Airport {
  final String ident;
  final String name;
  final double lat;
  final double lon;
  final int elevation;
  final String type;
  String? riskColor; // Added for AI grading integration
  String? riskReason;

  Airport({
    required this.ident,
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
      final String csvData = await rootBundle.loadString('assets/airports.csv');
      // Split by line handles \r\n, \n, \r
      final List<String> lines = const LineSplitter().convert(csvData);

      // Skip header if present (standard usually has 'id,ident,...')
      int startIndex = 0;
      if (lines.isNotEmpty && lines[0].contains('ident')) {
        startIndex = 1;
      }

      for (int i = startIndex; i < lines.length; i++) {
        final row = _parseCsvLine(lines[i]);
        
        // Ensure we have enough columns. 
        // We need up to index 6 (elevation).
        if (row.length > 6) {
          // Mapping based on user request:
          // ident: col 1
          // type: col 2
          // name: col 3
          // lat: col 4
          // lon: col 5
          // elevation: col 6
          // gps_code: col 12 (index 12) if available
          
          String rawIdent = row[1];
          final type = row[2];
          final name = row[3];
          final latString = row[4];
          final lonString = row[5];
          final elevString = row[6];
          
          // Logic: Prioritize gps_code (col 12) > ident (col 1)
          if (row.length > 12 && row[12].trim().isNotEmpty) {
             rawIdent = row[12];
          }

          final ident = rawIdent.trim().toUpperCase();

          // Filter: If the resulting code is not 3 or 4 alphanumeric characters, skip it.
          // This filters out heliports without proper codes or private strips with weird IDs.
          if (ident.length < 3 || ident.length > 4) {
             continue;
          }

          // Basic filtering for valid types
          if (type == 'small_airport' || type == 'medium_airport' || type == 'large_airport') {
            final lat = double.tryParse(latString) ?? 0.0;
            final lon = double.tryParse(lonString) ?? 0.0;
            final elev = int.tryParse(elevString) ?? 0;

            _allAirports.add(Airport(
              ident: ident,
              name: name,
              lat: lat,
              lon: lon,
              elevation: elev,
              type: type,
            ));
          }
        }
      }
      _isLoaded = true;
      print("AirportDatabaseService: Loaded ${_allAirports.length} airports.");
    } catch (e) {
      print("AirportDatabaseService Error: $e");
    }
  }

  /// Manually parses a CSV line handling quotes and commas inside quotes.
  List<String> _parseCsvLine(String line) {
    final List<String> result = [];
    StringBuffer currentField = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        // End of field
        result.add(currentField.toString());
        currentField.clear();
      } else {
        currentField.write(char);
      }
    }
    // Add the last field
    result.add(currentField.toString());

    return result;
  }

  List<Airport> getAirportsInBounds(LatLngBounds bounds) {
    if (!_isLoaded) return [];

    // Filter airports within the visible bounds
    return _allAirports.where((airport) {
      return bounds.contains(LatLng(airport.lat, airport.lon));
    }).toList();
  }
}
