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
  });

  Map<String, dynamic> toMap() {
    return {
      'DarkMode': DarkMode.index,
      'DistanceUnit': DistanceUnit.index,
      'Altitude': Altitude.index,
      'Pressure': Pressure.index,
      'Temperature': Temperature.index
    };
  }
  factory Usermodel.fromMap(Map<String, dynamic> map) {
    return Usermodel(
      DarkMode: DarkLight.values[map['DarkMode'] ?? 0],
      DistanceUnit: DistanceSpeedUnit.values[map['DistanceUnit'] ?? 0],
      Altitude: AltitudeUnit.values[map['Altitude'] ?? 0],
      Pressure: PressureUnit.values[map['Pressure'] ?? 0],
      Temperature: TemperatureUnit.values[map['Temperature'] ?? 0],
    );
  }
}
