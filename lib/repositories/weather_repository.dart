import '../models/weather_model.dart';
import '../services/OpenMeteoService.dart';

class WeatherRepository {
  final OpenMeteoService _service = OpenMeteoService();

  Future<WeatherModel> getWeather(double lat, double lon, double altitudeFt, {required bool useMetric}) async {
    return _service.getWeather(lat: lat, lon: lon, altitudeFt: altitudeFt, useMetric: useMetric);
  }
}
