import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class TerrainService {
  // TODO: Replace with your actual Mapbox Access Token (prefer injecting via --dart-define in production)
  final String _accessToken =
      'pk.eyJ1IjoiYW5keTA4MTIyMSIsImEiOiJjbWtjMHd5MjkwYTBsM2VweGs1MGFsZDBtIn0.3rICwhZd5hKtFjRLqAWSrg';

  /// Returns terrain elevation in Feet for the given lat/lon.
  /// Returns null if an error occurs.
  Future<double?> getElevationFeet(double lat, double lon) async {
    if (_accessToken == 'YOUR_ACCESS_TOKEN' || _accessToken.isEmpty) {
      print('TerrainService: Missing Mapbox Access Token.');
      return null;
    }

    try {
      final elevationFeet =
          await _getElevationFeetFromTerrainRgb(lat, lon, zoom: 13);
      return elevationFeet;
    } catch (e) {
      print('TerrainService Exception: $e');
      return null;
    }
  }

  /// Fetches the Terrain-RGB tile for the given location and decodes elevation.
  ///
  /// Terrain-RGB decoding:
  /// meters = -10000 + (R*256*256 + G*256 + B) * 0.1
  Future<double?> _getElevationFeetFromTerrainRgb(double lat, double lon,
      {int zoom = 13}) async {
    // Convert lon/lat to tile coordinates (Web Mercator)
    final n = math.pow(2.0, zoom).toDouble();
    final xFloat = (lon + 180.0) / 360.0 * n;

    final latRad = lat * math.pi / 180.0;
    final yFloat =
        (1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
            2.0 *
            n;

    final xTile = xFloat.floor();
    final yTile = yFloat.floor();

    // Pixel within the 256x256 tile
    final px = ((xFloat - xTile) * 256).floor().clamp(0, 255);
    final py = ((yFloat - yTile) * 256).floor().clamp(0, 255);

    // Correct endpoint for Terrain-RGB raster tiles
    // Note: pngraw avoids color profile conversions
    final url = Uri.parse(
      'https://api.mapbox.com/v4/mapbox.terrain-rgb/$zoom/$xTile/$yTile.pngraw?access_token=$_accessToken',
    );

    final resp = await http.get(url);
    if (resp.statusCode != 200) {
      print('Terrain RGB HTTP Error: ${resp.statusCode} ${resp.body}');
      return null;
    }

    final image = img.decodePng(resp.bodyBytes);
    if (image == null) {
      print('TerrainService: Failed to decode PNG tile.');
      return null;
    }

    final pixel = image.getPixel(px, py);
    final r = pixel.r;
    final g = pixel.g;
    final b = pixel.b;

    final elevationMeters =
        -10000.0 + ((r * 256 * 256 + g * 256 + b) * 0.1);
    final elevationFeet = elevationMeters * 3.28084;
    return elevationFeet;
  }
}
