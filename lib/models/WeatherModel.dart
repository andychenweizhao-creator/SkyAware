class WeatherModel {
  final double densityAltitudeFt;
  final double pressureAltitudeFt;
  final double relativeHumidityPercent;
  final String sunriseTime; // HH:mm
  final String sunsetTime; // HH:mm
  final double temperatureC;
  final double dewpointC;
  final double altimeterInHg;
  final double stationElevationFt;

  WeatherModel({
    required this.densityAltitudeFt,
    required this.pressureAltitudeFt,
    required this.relativeHumidityPercent,
    required this.sunriseTime,
    required this.sunsetTime,
    required this.temperatureC,
    required this.dewpointC,
    required this.altimeterInHg,
    required this.stationElevationFt,
  });

  @override
  String toString() {
    return 'WeatherModel(DA: ${densityAltitudeFt.toStringAsFixed(1)} ft, RH: ${relativeHumidityPercent.toStringAsFixed(1)} %, Sun: $sunriseTime - $sunsetTime)';
  }
}
