import 'package:flutter_map/flutter_map.dart';

/// A data class that holds the rendered polygon and its original raw
/// properties from the GeoJSON feature. This is used for AI analysis.
class WeatherFeature {
  final Polygon polygon;
  final Map<String, dynamic> rawProperties;

  WeatherFeature({
    required this.polygon,
    this.rawProperties = const {},
  });
}
