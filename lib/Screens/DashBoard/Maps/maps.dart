import 'dart:ui'; // Needed for ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:skyaware/UI/theme_controller.dart';
import 'package:cloud_functions/cloud_functions.dart';


// Consolidated RoutePoint class
class RoutePoint {
  final String id;       // "KLAX" or "WP-1"
  final LatLng point;    // Coordinates
  final String type;     // 'origin', 'waypoint', 'destination', 'airport'
  final String? name;// Optional display name

  
  RoutePoint({required this.id, required this.point, required this.type, this.name});
}

class Maps extends StatefulWidget {
  final MapController mapController;
  final List<Polygon> weatherPolygons;
  final List<RoutePoint> routePoints;
  final List<Marker> hazardMarkers;
  final List<Marker> airportMarkers; // Added for AI Airport Scanner
  final Function(LatLng)? onMapTap;
  final Function(TapPosition, LatLng)? onMapLongPress;
  final Function(RoutePoint)? onRoutePointTap;// NEW: Callback for route point taps
  late final HttpsCallable aiCallable;
   // AI Model for airport search

 Maps({
    super.key,
    required this.mapController,
    this.weatherPolygons = const [],
    this.routePoints = const [],
    this.hazardMarkers = const [],
    this.airportMarkers = const [],
    this.onMapTap,
    this.onMapLongPress,
    this.onRoutePointTap,

  }){
   aiCallable = FirebaseFunctions.instance.httpsCallable('askGemini');
  }

  @override
  State<Maps> createState() => _MapsState();
}

class _MapsState extends State<Maps> {
  
  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final isDark = themeController.isDarkMode;

    final String tileUrl = isDark 
        ? 'https://{s}.basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png'
        : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

    // 1. Shared UI Logic for Route Markers
    List<Marker> buildRoutePointMarkers() {
      return widget.routePoints.map((routePoint) {
        return Marker(
          width: 120.0, // Wider to accommodate text
          height: 60.0,
          point: routePoint.point,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {
               if (widget.onRoutePointTap != null) {
                 widget.onRoutePointTap!(routePoint);
               }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 1. The Label
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: Text(
                    routePoint.name ?? routePoint.id, 
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                
                // 2. The Dot
                Container(
                  width: 12, 
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withOpacity(0.5), 
                        blurRadius: 6,
                        spreadRadius: 1
                      )
                    ]
                  ),
                ),
              ],
            ),
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
            onLongPress: widget.onMapLongPress,
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
                    color: Colors.cyanAccent.withOpacity(0.8), // Matches dot color
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
