import 'dart:ui'; // Needed for ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:skyaware/UI/theme_controller.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../../UI/AppAnimations.dart';
import '../../../UI/AirportDetailSheet.dart'; // IMPORT THIS

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
  final List<Marker> airportMarkers; // Added for AI Airport Scanner
  final Function(LatLng)? onMapTap;
  final GenerativeModel? aiModel; // AI Model for airport search

  const Maps({
    super.key,
    required this.mapController,
    this.weatherPolygons = const [],
    this.routePoints = const [],
    this.hazardMarkers = const [],
    this.airportMarkers = const [], // Default empty
    this.onMapTap,
    this.aiModel,
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
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Layer 1: The Icon
              GestureDetector(
                onTap: () {
                  // Only for valid Airport IDs (usually 3-4 chars)
                  if (routePoint.id.length >= 3 && routePoint.id.length <= 4) {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (ctx) => AirportDetailSheet(
                        icao: routePoint.id,
                        aiModel: widget.aiModel,
                      ),
                    );
                  }
                },
                child: Icon(iconData, color: iconColor, size: iconSize),
              ),

              // Layer 2: The Text Label
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
        );
      }).toList();
    }

    return Stack(
      children: [
        FlutterMap(
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

            // Draw AI Airport Markers if any
            if (widget.airportMarkers.isNotEmpty)
              MarkerLayer(markers: widget.airportMarkers),
          ],
        ),
      ],
    );
  }
}
