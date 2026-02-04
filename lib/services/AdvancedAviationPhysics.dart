import 'dart:math';

class AdvancedAviationPhysics {
  /// Alduchov-Eskridge (1996) constants
  /// Provides < 0.4% error for water vapor pressure in range -40°C to 50°C.
  static const double _aeA = 6.1121; // hPa (or mbar)
  static const double _aeB = 17.67;
  static const double _aeC = 243.5; // °C

  /// Calculates saturation vapor pressure e(T) using Alduchov-Eskridge formula.
  /// e(T) = 6.1121 * exp((17.67 * T) / (243.5 + T))
  static double _calculateVaporPressure(double tempC) {
    return _aeA * exp((_aeB * tempC) / (_aeC + tempC));
  }

  /// Calculates precise Relative Humidity using Alduchov-Eskridge Algorithm.
  /// [tempC] - Ambient Air Temperature in Celsius.
  /// [dewpointC] - Dewpoint Temperature in Celsius.
  /// Returns RH as a percentage (0-100).
  static double calculateRelativeHumidity({
    required double tempC,
    required double dewpointC,
  }) {
    double es = _calculateVaporPressure(tempC); // Saturation vapor pressure
    double e = _calculateVaporPressure(dewpointC); // Actual vapor pressure
    
    // Avoid division by zero
    if (es == 0) return 0.0;
    
    double rh = 100.0 * (e / es);
    
    // Clamp result between 0 and 100 for safety, though physical inputs should be valid.
    return rh.clamp(0.0, 100.0);
  }

  /// Calculates Dewpoint from Temperature and Relative Humidity using inverse Alduchov-Eskridge.
  /// [tempC] - Ambient Air Temperature in Celsius.
  /// [rhPercent] - Relative Humidity in Percent (0-100).
  /// Returns Dewpoint in Celsius.
  static double calculateDewpoint({
    required double tempC,
    required double rhPercent,
  }) {
    if (rhPercent <= 0) return -273.15; // Approximate absolute zero or invalid
    
    // e = (RH / 100) * es
    double es = _calculateVaporPressure(tempC);
    double e = (rhPercent / 100.0) * es;

    // Inverse formula:
    // ln(e / 6.1121) = (17.67 * Td) / (243.5 + Td)
    // Let y = ln(e / 6.1121)
    // Td = (243.5 * y) / (17.67 - y)
    
    double y = log(e / _aeA);
    double dewpoint = (_aeC * y) / (_aeB - y);
    
    return dewpoint;
  }

  /// Calculates precise Cloud Base (Ceiling) height in feet (AGL).
  /// Uses the precise convergence rate of 2.44°C per 1000ft (approx 4.4°F/1000ft).
  /// [tempC] - Surface Temperature in Celsius.
  /// [dewpointC] - Surface Dewpoint in Celsius.
  /// Returns Cloud Base in feet. Returns 0 if T - Td < 0.2 (Fog).
  static double calculateCloudBaseFt({
    required double tempC,
    required double dewpointC,
  }) {
    double spread = tempC - dewpointC;
    
    // Fog condition
    if (spread < 0.2) {
      return 0.0;
    }
    
    // Convergence rate: 2.44°C per 1000 ft
    // Formula: ((T - Td) / 2.44) * 1000
    return (spread / 2.44) * 1000.0;
  }
}
