import 'dart:math';

class MetarParser {
  /// Parses a raw METAR string and returns a map of extracted aviation data.
  ///
  /// Returns:
  /// {
  ///   'temperature': double (Celsius),
  ///   'dewpoint': double (Celsius),
  ///   'windDirection': double? (Degrees, null if VRB),
  ///   'windSpeed': double (Knots),
  ///   'windGust': double (Knots, 0 if none),
  ///   'visibility': double (Statute Miles),
  ///   'visibilityRaw': String (Original string e.g. "1 1/2"),
  ///   'isVariableWind': bool,
  /// }
  static Map<String, dynamic> parse(String rawMetar) {
    // Normalize string
    final cleanMetar = rawMetar.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

    final wind = _parseWind(cleanMetar);
    final tempDew = _parseTempDewpoint(cleanMetar);
    final vis = _parseVisibility(cleanMetar);

    return {
      ...wind,
      ...tempDew,
      ...vis,
    };
  }

  // ---------------------------------------------------------------------------
  // WIND PARSING
  // ---------------------------------------------------------------------------
  // Regex: (Dir)(Speed)(G Gust)?KT
  // Examples: 36010KT, 27015G25KT, VRB05KT, 09003MPS (Europe, but prompt says KT usually)
  static final RegExp _windRegex = RegExp(r'\b(VRB|[0-9]{3})([0-9]{2,3})(?:G([0-9]{2,3}))?KT\b');

  static Map<String, dynamic> _parseWind(String metar) {
    final match = _windRegex.firstMatch(metar);

    double? direction;
    double speed = 0;
    double gust = 0;
    bool isVrb = false;

    if (match != null) {
      // Group 1: Direction (or VRB)
      final dirStr = match.group(1)!;
      if (dirStr == 'VRB') {
        isVrb = true;
        direction = null; // Variable
      } else {
        direction = double.tryParse(dirStr);
      }

      // Group 2: Speed
      final speedStr = match.group(2)!;
      speed = double.tryParse(speedStr) ?? 0;

      // Group 3: Gust (Optional)
      final gustStr = match.group(3);
      if (gustStr != null) {
        gust = double.tryParse(gustStr) ?? 0;
      }
    }

    return {
      'windDirection': direction,
      'windSpeed': speed,
      'windGust': gust,
      'isVariableWind': isVrb,
    };
  }

  // ---------------------------------------------------------------------------
  // TEMPERATURE & DEWPOINT PARSING
  // ---------------------------------------------------------------------------
  // Regex: (Temp)/(Dew) where Temp/Dew can be M05 or 12
  // Example: 20/12, M02/M05, 00/M01
  static final RegExp _tempDewRegex = RegExp(r'\b(M?[0-9]{2})/(M?[0-9]{2})\b');

  static Map<String, dynamic> _parseTempDewpoint(String metar) {
    // Find the temp/dewpoint group.
    // Caution: Sometimes date (e.g. 01/02) could match if not careful,
    // but standard format places temp/dew near the end of the body or strict 2 digits.
    final match = _tempDewRegex.firstMatch(metar);

    double temp = 0;
    double dew = 0;

    if (match != null) {
      temp = _parseMetarTemp(match.group(1)!);
      dew = _parseMetarTemp(match.group(2)!);
    }

    return {
      'temperature': temp,
      'dewpoint': dew,
    };
  }

  static double _parseMetarTemp(String s) {
    if (s.startsWith('M')) {
      return -(double.tryParse(s.substring(1)) ?? 0);
    }
    return double.tryParse(s) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // VISIBILITY PARSING
  // ---------------------------------------------------------------------------
  // Examples: 10SM, 1/2SM, 1 1/2SM, M1/4SM, 2SM
  // Regex logic:
  // 1. Optional 'M' (Minus/Less than)
  // 2. Whole number and/or Fraction
  // 3. SM suffix
  static final RegExp _visRegex = RegExp(r'\b(M)?((\d+\s)?\d+/\d+|\d+(\.\d+)?|(\d+))SM\b');

  static Map<String, dynamic> _parseVisibility(String metar) {
    final match = _visRegex.firstMatch(metar);

    double visMiles = 10.0; // Default good visibility
    String visRaw = "10+";
    bool isLessThan = false;

    if (match != null) {
      // Capture groups:
      // 1: M (optional)
      // 2: The full number part (e.g. "1 1/2", "10", "1/2")

      final mStr = match.group(1);
      final valStr = match.group(2)!;

      isLessThan = (mStr == 'M'); // M1/4SM means less than 1/4
      visRaw = isLessThan ? "<$valStr" : valStr;

      visMiles = _parseFractional(valStr);
    }

    return {
      'visibility': visMiles,
      'visibilityRaw': visRaw, // Returns "1 1/2" or "<1/4" etc
    };
  }

  static double _parseFractional(String s) {
    // Handle space (e.g. "1 1/2")
    if (s.contains(' ')) {
      final parts = s.split(' ');
      if (parts.length == 2) {
        return (double.tryParse(parts[0]) ?? 0) + _parseFractional(parts[1]);
      }
    }

    // Handle fraction (e.g. "1/2")
    if (s.contains('/')) {
      final parts = s.split('/');
      if (parts.length == 2) {
        double num = double.tryParse(parts[0]) ?? 0;
        double den = double.tryParse(parts[1]) ?? 1;
        return num / den;
      }
    }

    // Handle plain number (e.g. "10", "1.5")
    return double.tryParse(s) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  static double knotsToMph(double knots) => knots * 1.15078;

  static double knotsToKph(double knots) => knots * 1.852;
}
