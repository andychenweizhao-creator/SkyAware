enum DistanceSpeedUnit {
  nauticalMilesKnots,
  kilometersKph,
  milesMph
}
enum DarkLight {
  Dark,
  Light
}
enum AltitudeUnit {
  feet,
  meters
}
enum PressureUnit {
  hpa,
  inHg
}
enum TemperatureUnit {
  celsius,
  fahrenheit
}


class Usermodel {
  DarkLight DarkMode;
  DistanceSpeedUnit DistanceUnit;
  AltitudeUnit Altitude;
  PressureUnit Pressure;
  TemperatureUnit Temperature;
  Usermodel({
    required this.DarkMode,
    required this.DistanceUnit,
    required this.Altitude,
    required this.Pressure,
    required this.Temperature
  }){

  }

}
