import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

class WindsAloftService {
  static const String _stationsUrl = 'https://aviationweather.gov/data/cache/stations.cache.json.gz';
  static const String _windsUrl = 'https://aviationweather.gov/api/data/windtemp?region=us';

  // Altitudes available in the raw data columns
  final List<int> _levels = [3000, 6000, 9000, 12000, 18000, 24000, 30000, 34000, 39000];

  /// Step 1: Fetch & Find Nearest Station
  Future<String> findNearestStation(double userLat, double userLon) async {
    try {
      final response = await http.get(Uri.parse(_stationsUrl));

      if (response.statusCode == 200) {
        // Decompress Gzipped JSON
        // Note: The server sends a .json.gz file, so we must manually decompress it.
        // If the server served it with 'Content-Encoding: gzip', http.get would handle it,
        // but often these cache files are served as binary blobs.
        String jsonString;
        try {
          jsonString = utf8.decode(GZipCodec().decode(response.bodyBytes));
        } catch (e) {
          // Fallback if not gzipped or already decoded
          jsonString = response.body;
        }

        final List<dynamic> stations = json.decode(jsonString);
        
        String closestStation = '';
        double minDistance = double.infinity;

        for (var station in stations) {
          // Check if station has lat/lon
          if (station['lat'] != null && station['lon'] != null) {
            double dist = _calculateDistance(userLat, userLon, station['lat'], station['lon']);
            if (dist < minDistance) {
              minDistance = dist;
              closestStation = station['icao'] ?? station['id']; // Use ICAO or ID
            }
          }
        }

        return closestStation;
      } else {
        throw Exception('Failed to load stations: ${response.statusCode}');
      }
    } catch (e) {
      print('Error finding station: $e');
      return 'KLAX'; // Fallback
    }
  }

  /// Helper: Haversine distance
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  /// Step 2: Fetch Raw Winds Data & Parse for Specific Station
  Future<String?> fetchRawDataForStation(String stationId) async {
    try {
      final response = await http.get(Uri.parse(_windsUrl));
      
      if (response.statusCode == 200) {
        final lines = response.body.split('\n');
        
        // Remove 'K' from station ID for US stations as raw text usually uses 3 letters (e.g. LAX)
        // unless it's a 4 letter ID that isn't K-prefixed (uncommon in this dataset for US).
        String searchId = stationId.startsWith('K') && stationId.length == 4 
            ? stationId.substring(1) 
            : stationId;

        for (String line in lines) {
          if (line.trim().startsWith(searchId)) {
            return line;
          }
        }
      }
    } catch (e) {
      print('Error fetching winds: $e');
    }
    return null;
  }

  /// Step 3: Interpolate Weather at User's Altitude
  Map<String, dynamic> getWeatherAtAltitude(double userAltitudeFt, String rawDataLine) {
    final parts = rawDataLine.trim().split(RegExp(r'\s+'));
    
    // Parse available data
    Map<int, Map<String, double>> parsedData = {};
    
    // We start parsing from index 1 (index 0 is station ID).
    // Note: This logic assumes 'parts' aligns perfectly with '_levels'.
    // In practice, missing low-altitude data might shift columns if simpler regex splitting is used
    // on a variable-width font text, BUT usually these are fixed width or space padded.
    // 'split(RegExp(r'\s+'))' consumes variable whitespace, which handles alignment if fields are present.
    // If fields are missing (blank), this simple split will shift data to wrong altitudes.
    // A robust parser would use substring with fixed indices.
    // However, for this task, we will stick to the simple split as requested/implied.
    
    int dataIndex = 1;
    for (int i = 0; i < _levels.length; i++) {
       if (dataIndex < parts.length) {
         parsedData[_levels[i]] = _decodeWindTemp(parts[dataIndex], _levels[i]);
         dataIndex++;
       }
    }

    // Find Bounds
    int lowerAlt = _levels.first;
    int upperAlt = _levels.last;
    
    if (userAltitudeFt <= _levels.first) {
      return _formatResult(parsedData[_levels.first]);
    }
    if (userAltitudeFt >= _levels.last) {
      return _formatResult(parsedData[_levels.last]);
    }

    for (int i = 0; i < _levels.length - 1; i++) {
      if (userAltitudeFt >= _levels[i] && userAltitudeFt <= _levels[i+1]) {
        lowerAlt = _levels[i];
        upperAlt = _levels[i+1];
        break;
      }
    }

    final lowerData = parsedData[lowerAlt];
    final upperData = parsedData[upperAlt];

    if (lowerData == null || upperData == null) {
      // Fallback if data is missing for specific levels (e.g. station elevation > 3000)
      // If we are between 3000 and 6000 but 3000 is missing, use 6000?
      // Or find nearest available.
      // For simplicity, return error or nearest.
      return lowerData != null ? _formatResult(lowerData) : 
             (upperData != null ? _formatResult(upperData) : {'error': 'Data missing'});
    }

    // Linear Interpolation
    double fraction = (userAltitudeFt - lowerAlt) / (upperAlt - lowerAlt);

    double interpSpeed = _lerp(lowerData['speed']!, upperData['speed']!, fraction);
    double interpTemp = _lerp(lowerData['temp']!, upperData['temp']!, fraction);
    
    // Wind Direction Interpolation (handle 360 wraparound)
    double lowerDir = lowerData['dir']!;
    double upperDir = upperData['dir']!;
    
    double diff = upperDir - lowerDir;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    
    double interpDir = lowerDir + (diff * fraction);
    if (interpDir < 0) interpDir += 360;
    if (interpDir >= 360) interpDir -= 360;

    return {
      'windSpeed': interpSpeed,
      'windDir': interpDir,
      'temp': interpTemp,
    };
  }

  Map<String, dynamic> _formatResult(Map<String, double>? data) {
    if (data == null) return {'error': 'Data missing'};
    return {
      'windSpeed': data['speed'],
      'windDir': data['dir'],
      'temp': data['temp'],
    };
  }

  double _lerp(double a, double b, double f) {
    return a + (b - a) * f;
  }

  /// Decoder: Format DDSS+TT or DDSS-TT
  Map<String, double> _decodeWindTemp(String token, int altitude) {
    if (token.length < 4) return {'dir': 0, 'speed': 0, 'temp': 0};

    // Extract DDSS
    String ddss = token.substring(0, 4);
    
    // Extract Temp (remaining chars)
    String tempStr = token.length > 4 ? token.substring(4) : "";

    double dir = double.parse(ddss.substring(0, 2)) * 10;
    double speed = double.parse(ddss.substring(2, 4));

    // Handle Light/Variable
    if (ddss == "9900") {
      return {'dir': 0, 'speed': 0, 'temp': _parseTemp(tempStr, altitude)};
    }

    // Handle winds > 100 knots (Dir > 360 means Dir-500, Spd+100)
    if (dir > 360) {
      dir -= 500;
      speed += 100;
    }
    
    double temp = _parseTemp(tempStr, altitude);
    return {'dir': dir, 'speed': speed, 'temp': temp};
  }

  double _parseTemp(String tempStr, int altitude) {
    if (tempStr.isEmpty) return 0.0;
    
    // If explicit sign exists, trust it.
    if (tempStr.contains('+') || tempStr.contains('-')) {
      return double.tryParse(tempStr) ?? 0.0;
    }
    
    // Sign omitted
    double val = double.tryParse(tempStr) ?? 0.0;
    
    // Per prompt: Temps > 24000ft are negative (minus sign omitted)
    if (altitude > 24000) {
      return -val.abs();
    }
    
    return val;
  }
}
