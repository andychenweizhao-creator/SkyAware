import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart' as xml;

class ParsedFlightPlan {
  final List<LatLng> path;
  final List<String> names;

  ParsedFlightPlan({required this.path, required this.names});
}

class FlightPlanParser {
  static Future<ParsedFlightPlan?> pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
      allowCompression: false,
    );

    if (result == null) return null;

    final filePath = result.files.single.path!;
    final lower = filePath.toLowerCase();

    if (!(lower.endsWith('.fpl') ||
        lower.endsWith('.xml') ||
        lower.endsWith('.pln') ||
        lower.endsWith('.fms') ||
        lower.endsWith('.txt'))) {
      throw Exception('Invalid file type.');
    }

    Uint8List? bytes = result.files.single.bytes;
    if (bytes == null && result.files.single.path != null) {
      bytes = await File(result.files.single.path!).readAsBytes();
    }
    if (bytes == null) return null;

    final content = utf8.decode(bytes);
    List<LatLng> path = [];
    List<String> names = [];
    bool parsedAsXml = false;

    try {
      final cleaned = content.replaceAll(RegExp('xmlns="[^"]*"'), '');
      final document = xml.XmlDocument.parse(cleaned);

      final Map<String, LatLng> waypointLookup = {};
      for (final wp in document.findAllElements('waypoint')) {
        final id = wp.findElements('identifier').firstOrNull?.innerText;
        final latStr = wp.findElements('lat').firstOrNull?.innerText;
        final lonStr = wp.findElements('lon').firstOrNull?.innerText;
        if (id != null && latStr != null && lonStr != null) {
          final lat = double.tryParse(latStr);
          final lon = double.tryParse(lonStr);
          if (lat != null && lon != null) {
            waypointLookup[id] = LatLng(lat, lon);
          }
        }
      }

      final routePoints = document.findAllElements('route-point');
      if (routePoints.isNotEmpty) {
        parsedAsXml = true;
        for (final rp in routePoints) {
          final id =
              rp.findElements('waypoint-identifier').firstOrNull?.innerText;
          if (id != null && waypointLookup.containsKey(id)) {
            path.add(waypointLookup[id]!);
            names.add(id);
          }
        }
      }

      final waypoints = document.findAllElements('waypoint', namespace: '*');
      final fixes = document.findAllElements('fix', namespace: '*');

      if (waypoints.isNotEmpty && !parsedAsXml) {
        parsedAsXml = true;
        for (final wp in waypoints) {
          String? latString =
              wp.findElements('lat', namespace: '*').firstOrNull?.innerText;
          String? lonString =
              wp.findElements('lon', namespace: '*').firstOrNull?.innerText;

          latString ??= wp.getAttribute('lat');
          lonString ??= wp.getAttribute('lon');

          if (latString != null && lonString != null) {
            final lat = double.tryParse(latString);
            final lon = double.tryParse(lonString);
            if (lat != null && lon != null) {
              path.add(LatLng(lat, lon));
              names.add(wp.getAttribute('id') ??
                  wp.getAttribute('name') ??
                  'WP${names.length + 1}');
            }
          }
        }
      }

      if (fixes.isNotEmpty && !parsedAsXml) {
        parsedAsXml = true;
        for (final fix in fixes) {
          final latStr = fix.findElements('lat').firstOrNull?.innerText;
          final lonStr = fix.findElements('lon').firstOrNull?.innerText;
          if (latStr != null && lonStr != null) {
            final lat = double.tryParse(latStr);
            final lon = double.tryParse(lonStr);
            if (lat != null && lon != null) {
              path.add(LatLng(lat, lon));
              names.add(fix.getAttribute('id') ??
                  fix.getAttribute('name') ??
                  'WP${names.length + 1}');
            }
          }
        }
      }

      final legs = document.findAllElements('leg');
      if (legs.isNotEmpty && !parsedAsXml) {
        parsedAsXml = true;
        for (final leg in legs) {
          final latStr = leg.getAttribute('lat');
          final lonStr = leg.getAttribute('lon');
          if (latStr != null && lonStr != null) {
            final lat = double.tryParse(latStr);
            final lon = double.tryParse(lonStr);
            if (lat != null && lon != null) {
              path.add(LatLng(lat, lon));
              names.add(leg.getAttribute('id') ??
                  leg.getAttribute('name') ??
                  'WP${names.length + 1}');
            }
          }
        }
      }
    } catch (_) {}

    if (!parsedAsXml) {
      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 3 &&
            ['AIRP', 'ADEP', 'ADES', 'WAYP', 'FIX', 'NDB', 'VOR', 'GPS']
                .contains(parts[0].toUpperCase())) {
          final lat = double.tryParse(parts[parts.length - 2]);
          final lon = double.tryParse(parts[parts.length - 1]);
          if (lat != null && lon != null) {
            path.add(LatLng(lat, lon));
            names.add('WP${names.length + 1}');
          }
        } else {
          final ll = trimmed.split(',');
          if (ll.length == 2) {
            final lat = double.tryParse(ll[0]);
            final lon = double.tryParse(ll[1]);
            if (lat != null && lon != null) {
              path.add(LatLng(lat, lon));
              names.add('WP${names.length + 1}');
            }
          }
        }
      }
    }

    if (path.isEmpty) return null;
    
    return ParsedFlightPlan(path: path, names: names);
  }
}
