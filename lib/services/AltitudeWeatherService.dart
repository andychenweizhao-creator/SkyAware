import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'WindsAloftService.dart';

class WeatherData {
  final double temperature; // Celsius (Interpolated OAT)
  final double windSpeed; // Knots
  final double windDirection; // Degrees
  final double? pressure; // inHg (Altimeter)
  final double? humidity; // %
  final double? dewpoint; // Celsius (Surface)
  final String condition; // e.g., "Clear", "Cloudy"
  final String? visibility; // e.g., "10+" SM
  final String? flightCategory; // VFR, MVFR, IFR, LIFR
  final String? ceiling; // e.g. "OVC 3500" or just "3500"
  final double? densityAltitude; // Feet
  final String stationId;
  final double altitudeFt;
  final bool isInterpolated;
  final double latitude;
  final double longitude;
  final String locationName;
  final String? precip;
  final DateTime? sunrise;
  final DateTime? sunset;

  WeatherData({
    required this.temperature,
    required this.windSpeed,
    required this.windDirection,
    this.pressure,
    this.humidity,
    this.dewpoint,
    this.condition = "Unknown",
    this.visibility,
    this.flightCategory,
    this.ceiling,
    this.densityAltitude,
    required this.stationId,
    required this.altitudeFt,
    required this.latitude,
    required this.longitude,
    this.isInterpolated = false,
    this.locationName = "Unknown Location",
    this.precip,
    this.sunrise,
    this.sunset,
  });
}

class AltitudeWeatherService {
  final WindsAloftService _windsService = WindsAloftService();
  static const String _metarUrlBase = 'https://aviationweather.gov/api/data/metar';

  Future<WeatherData> getCurrentWeather() async {
    // 1. Get Device Location
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied, we cannot request permissions.');
    }

    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

    // Reverse Geocoding
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
      print("Geocoding error: $e");
    }

    // Convert meters to feet (1 meter = 3.28084 feet)
    double altitudeFt = position.altitude * 3.28084;

    return await getWeatherAtLocation(position.latitude, position.longitude, altitudeFt, locationName: locName);
  }

  Future<WeatherData> getWeatherAtLocation(double lat, double lon, double altitudeFt, {String? locationName}) async {
    // 2. Find Nearest Station
    String stationId = await _windsService.findNearestStation(lat, lon);

    // 3. Fetch Data (Parallel for efficiency)
    final windsFuture = _windsService.fetchRawDataForStation(stationId);
    final metarFuture = _fetchMetar(stationId);

    final results = await Future.wait([windsFuture, metarFuture]);
    final String? rawWindsLine = results[0] as String?;
    final Map<String, dynamic>? metarProperties = results[1] as Map<String, dynamic>?;

    double temp = 0;
    double speed = 0;
    double dir = 0;
    bool interpolated = false;

    // 4. Process & Interpolate
    // Fallback logic: Use Surface (METAR) if < 1500ft or Winds Aloft data is missing
    bool useSurface = altitudeFt < 1500 || rawWindsLine == null;

    if (!useSurface && rawWindsLine != null) {
      // Try Interpolation
      final aloftData = _windsService.getWeatherAtAltitude(altitudeFt, rawWindsLine);
      if (aloftData.containsKey('error')) {
        useSurface = true; // Interpolation failed (e.g., out of bounds), fallback
      } else {
        temp = _toDouble(aloftData['temp']) ?? 0;
        speed = _toDouble(aloftData['windSpeed']) ?? 0;
        dir = _toDouble(aloftData['windDir']) ?? 0;
        interpolated = true;
      }
    }

    // If using surface (or fallback was triggered)
    if (useSurface) {
      if (metarProperties != null) {
        temp = _toDouble(metarProperties['temp']) ?? 0;
        speed = _toDouble(metarProperties['wspd']) ?? 0;
        dir = _toDouble(metarProperties['wdir']) ?? 0;
      }
    }

    // Extract Surface-only metrics (Pressure, Humidity, Condition, etc.)
    double? pressure;
    double? humidity;
    double? dewpoint;
    String condition = "Unknown";
    String? visibility;
    String? flightCategory;
    String? ceiling;
    double? densityAltitude;
    String? precip;

    if (metarProperties != null) {
      // Altimeter
      double? altimMb = _toDouble(metarProperties['altim']);
      if (altimMb != null) {
        pressure = altimMb * 0.02953; // Convert mb to inHg
      }

      // Dewpoint
      dewpoint = _toDouble(metarProperties['dewp']);

      // Humidity Calculation
      double? t = _toDouble(metarProperties['temp']);
      if (t != null && dewpoint != null) {
         // August-Roche-Magnus approximation
         double numer = 17.625 * dewpoint;
         double denom = 243.04 + dewpoint;
         double numer2 = 17.625 * t;
         double denom2 = 243.04 + t;
         humidity = 100 * (exp(numer / denom) / exp(numer2 / denom2));
      }

      // Condition / Cloud Cover
      String? cover = metarProperties['cover'] as String?;
      if (cover != null) {
        condition = _mapCoverToCondition(cover);
      }

      // Visibility
      final visRaw = metarProperties['visib'];
      if (visRaw != null) {
        visibility = visRaw.toString();
      }

      // Flight Category
      flightCategory = metarProperties['fltcat'] as String?;

      // Ceiling
      if (cover != null) {
        ceiling = cover;
        if (metarProperties.containsKey('ceil')) {
           final cVal = metarProperties['ceil'];
           if (cVal != null) {
              ceiling = "$cover $cVal";
           }
        }
      }

      // Density Altitude Calculation
      if (pressure != null) {
        double pressureAlt = (29.92 - pressure) * 1000 + altitudeFt;
        // ISA Temp at Altitude
        double isaTemp = 15 - (2 * (altitudeFt / 1000));
        densityAltitude = pressureAlt + (120 * (temp - isaTemp));
      }

      // Precipitation
      if (metarProperties['precip_in'] != null) {
        double? pVal = _toDouble(metarProperties['precip_in']);
        if (pVal != null && pVal > 0) {
            precip = "${pVal.toStringAsFixed(2)}\"";
        }
      }
      // Try wxString if precip_in is null
      if (precip == null && metarProperties['wxString'] != null) {
          precip = metarProperties['wxString'].toString();
      }
    }

    // Sunrise / Sunset Calculation
    final sunTimes = _calculateSunTimes(lat, lon);

    return WeatherData(
      temperature: temp,
      windSpeed: speed,
      windDirection: dir,
      pressure: pressure,
      humidity: humidity,
      dewpoint: dewpoint,
      condition: condition,
      visibility: visibility,
      flightCategory: flightCategory,
      ceiling: ceiling,
      densityAltitude: densityAltitude,
      stationId: stationId,
      altitudeFt: altitudeFt,
      latitude: lat,
      longitude: lon,
      isInterpolated: interpolated,
      locationName: locationName ?? "Lat: ${lat.toStringAsFixed(2)}, Lon: ${lon.toStringAsFixed(2)}",
      precip: precip,
      sunrise: sunTimes['sunrise'],
      sunset: sunTimes['sunset'],
    );
  }

  double? _toDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) {
      return double.tryParse(val);
    }
    return null;
  }

  Future<Map<String, dynamic>?> _fetchMetar(String stationId) async {
    try {
      String queryId = stationId;
      if (!stationId.startsWith('K') && stationId.length == 3) {
         queryId = 'K$stationId';
      }

      final uri = Uri.parse('$_metarUrlBase?ids=$queryId&format=geojson');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && (data['features'] as List).isNotEmpty) {
           return data['features'][0]['properties'];
        }
      }
    } catch (e) {
      print("Error fetching METAR: $e");
    }
    return null;
  }

  String _mapCoverToCondition(String cover) {
    switch (cover) {
      case 'CLR': return "Clear Sky";
      case 'SKC': return "Clear Sky";
      case 'FEW': return "Few Clouds";
      case 'SCT': return "Scattered Clouds";
      case 'BKN': return "Broken Clouds";
      case 'OVC': return "Overcast";
      case 'OVX': return "Obscured";
      default: return cover;
    }
  }

  Map<String, DateTime> _calculateSunTimes(double lat, double lng) {
      // Current date
      final now = DateTime.now();

      // Simple approximate calculation

      // Day of year
      final startOfYear = DateTime(now.year, 1, 1, 0, 0, 0);
      final diff = now.difference(startOfYear);
      final dayOfYear = diff.inDays + 1;

      // Convert to radians
      final rad = pi / 180.0;
      final deg = 180.0 / pi;

      // Calculate the sun's declination
      final fractionalYear = (2 * pi / 365.0) * (dayOfYear - 1 + (now.hour - 12) / 24.0);
      final eqTime = 229.18 * (0.000075 + 0.001868 * cos(fractionalYear) - 0.032077 * sin(fractionalYear) - 0.014615 * cos(2 * fractionalYear) - 0.040849 * sin(2 * fractionalYear));
      final decl = 0.006918 - 0.399912 * cos(fractionalYear) + 0.070257 * sin(fractionalYear) - 0.006758 * cos(2 * fractionalYear) + 0.000907 * sin(2 * fractionalYear) - 0.002697 * cos(3 * fractionalYear) + 0.00148 * sin(3 * fractionalYear);

      // Calculate sunrise and sunset
      // Hour angle
      final zenith = 90.833 * rad;
      final latRad = lat * rad;

      final num = cos(zenith) - sin(latRad) * sin(decl);
      final denom = cos(latRad) * cos(decl);

      double ha = 0;
      try {
        final val = num / denom;
        if (val < -1) {
            ha = pi; // Always day? No, this formula is weird
        } else if (val > 1) {
            ha = 0; // Always night?
        } else {
            ha = acos(val);
        }
      } catch (e) {
        ha = 0;
      }

      final haDeg = ha * deg;

      // UTC Sunrise/Sunset in minutes
      final timeOffset = eqTime + 4 * lng;
      final sunriseUTC = 720 - 4 * haDeg - timeOffset;
      final sunsetUTC = 720 + 4 * haDeg - timeOffset;

      // Convert to DateTime (UTC first then Local)
      DateTime toDateTime(double minutesFromMidnight) {
        // Adjust to normal range 0-1440
        while (minutesFromMidnight < 0) minutesFromMidnight += 1440;
        while (minutesFromMidnight >= 1440) minutesFromMidnight -= 1440;

        int hours = (minutesFromMidnight / 60).floor();
        int mins = (minutesFromMidnight % 60).round();
        if (mins == 60) {
            hours += 1;
            mins = 0;
        }
        if (hours == 24) hours = 0;

        // Create UTC time for today
        final utcTime = DateTime.utc(now.year, now.month, now.day, hours, mins);
        return utcTime.toLocal();
      }

      return {
        'sunrise': toDateTime(sunriseUTC),
        'sunset': toDateTime(sunsetUTC),
      };
  }
}
