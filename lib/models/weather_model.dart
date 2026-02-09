class WeatherModel {
  final double temperature; // Celsius
  final double windSpeed; // KMH
  final double windDirection; // Degrees
  final double? pressure; // hPa
  final double? humidity; // %
  final double? dewpoint; // Celsius
  final String condition;
  final double? visibility; // Meters
  final String? flightCategory;
  
  // Ceiling split for dynamic units
  final double? ceilingHeight; // Meters
  final String? ceilingType; // "Overcast", "Broken", "Below Aircraft", etc.
  
  final double? densityAltitude; // Meters
  final String stationId;
  final double altitudeFt; // User's Altitude in Feet (Input)
  final bool isInterpolated;
  final double latitude;
  final double longitude;
  final String locationName;
  final double? precip; // mm
  final DateTime? sunrise;
  final DateTime? sunset;
  final String backgroundState;
  final bool isDay;
  final double cloudOpacity;
  final int utcOffsetSeconds; // Offset from UTC in seconds

  WeatherModel({
    required this.temperature,
    required this.windSpeed,
    required this.windDirection,
    this.pressure,
    this.humidity,
    this.dewpoint,
    this.condition = "Unknown",
    this.visibility,
    this.flightCategory,
    this.ceilingHeight,
    this.ceilingType,
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
    this.backgroundState = "day_clear",
    this.isDay = true,
    this.cloudOpacity = 0.0,
    this.utcOffsetSeconds = 0,
  });

  @override
  String toString() {
    return 'WeatherModel(station: $stationId, temp: $temperature C, densityAlt: $densityAltitude m, bg: $backgroundState)';
  }
}
