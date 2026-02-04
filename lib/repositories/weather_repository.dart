import '../models/weather_model.dart';
import '../services/OpenMeteoService.dart';

class WeatherRepository {
  final OpenMeteoService _service = OpenMeteoService();

  Future<WeatherModel> getWeather(double lat, double lon, double altitudeFt, {bool forceSurface = false}) async {
    // We no longer pass useMetric; the service always returns Metric. UI handles conversion.
    return _service.getWeather(lat: lat, lon: lon, altitudeFt: altitudeFt, forceSurface: forceSurface);
  }
}
