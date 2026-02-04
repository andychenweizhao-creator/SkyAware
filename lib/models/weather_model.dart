class WeatherModel {
  final double temperature; // Celsius or Fahrenheit based on fetch
  final double windSpeed; // KMH or MPH based on fetch
  final double windDirection; // Degrees
  final String? pressure; // Pre-formatted String (e.g. "1013 hPa" or "29.92 inHg")
  final double? humidity; // %
  final double? dewpoint; // Celsius or Fahrenheit based on fetch
  final String condition;
  final String? visibility; // Pre-formatted String
  final String? flightCategory;
  final String? ceiling; // Cloud Cover %
  final double? densityAltitude; // Feet
  final String stationId;
  final double altitudeFt;
  final bool isInterpolated;
  final double latitude;
  final double longitude;
  final String locationName;
  final String? precip; // Pre-formatted String
  final DateTime? sunrise;
  final DateTime? sunset;

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

  @override
  String toString() {
    return 'WeatherModel(station: $stationId, temp: $temperature, densityAlt: $densityAltitude)';
  }
}
