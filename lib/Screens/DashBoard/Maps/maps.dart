import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:skyaware/UI/theme_controller.dart';

// Consolidated RoutePoint class
class RoutePoint {
  final String id; // e.g., "KLAX"
  final LatLng point;
  final String type; // "origin", "destination", or "waypoint"
  RoutePoint({required this.id, required this.point, this.type = 'waypoint'});
}

class Maps extends StatefulWidget {
  final MapController mapController;
  final List<Polygon> weatherPolygons;
  final List<RoutePoint> routePoints;
  final List<Marker> hazardMarkers;
  final Function(LatLng)? onMapTap;

  const Maps({
    super.key,
    required this.mapController,
    this.weatherPolygons = const [],
    this.routePoints = const [],
    this.hazardMarkers = const [],
    this.onMapTap,
  });

  @override
  State<Maps> createState() => _MapsState();
}

class _MapsState extends State<Maps> {
  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final isDark = themeController.isDarkMode;

    final String tileUrl = isDark 
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
        : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

    List<Marker> buildRoutePointMarkers() {
      return widget.routePoints.map((routePoint) {
        IconData iconData;
        Color iconColor;
        double iconSize = 24.0;

        switch (routePoint.type) {
          case 'origin':
            iconData = Icons.flight_takeoff;
            iconColor = Colors.green;
            break;
          case 'destination':
            iconData = Icons.flight_land;
            iconColor = Colors.red;
            break;
          default: // 'waypoint'
            iconData = Icons.circle;
            iconColor = Colors.white;
            iconSize = 8.0;
        }

        return Marker(
          width: 80.0,
          height: 80.0,
          point: routePoint.point,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Layer 1: The Icon, centered perfectly on the coordinate
              Icon(iconData, color: iconColor, size: iconSize),

              // Layer 2: The Text Label, positioned below the icon
              Positioned(
                top: 30,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    routePoint.id,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          alignment: Alignment.center,
        );
      }).toList();
    }

    return FlutterMap(
      mapController: widget.mapController,
      options: MapOptions(
        initialCenter: const LatLng(37.09, -95.71),
        initialZoom: 4.0,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
        onTap: (_, point) => widget.onMapTap?.call(point),
      ),
      children: [
        TileLayer(
          urlTemplate: tileUrl,
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'com.andy.skyaware',
        ),

        // Draw the weather polygons
        PolygonLayer(
          polygons: widget.weatherPolygons,
        ),

        // Draw the flight route on top of the weather
        if (widget.routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.routePoints.map((rp) => rp.point).toList(),
                strokeWidth: 4.0,
                color: Colors.greenAccent, // High-visibility color
                borderColor: Colors.black.withOpacity(0.5),
                borderStrokeWidth: 1.0,
              ),
            ],
          ),

        // Draw the route points on top of everything
        if (widget.routePoints.isNotEmpty)
          MarkerLayer(
            markers: buildRoutePointMarkers(),
          ),
          
        // Draw Hazard Markers if any
        if (widget.hazardMarkers.isNotEmpty)
          MarkerLayer(markers: widget.hazardMarkers),
      ],
    );
  }
}
