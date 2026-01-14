// import 'dart:io';
// import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:flutter/material.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:xml/xml.dart';
// import 'package:latlong2/latlong.dart';
//
// class RouteImport extends StatelessWidget {
//   final Function(List<LatLng>) onRouteParsed;
//
//   const RouteImport({super.key, required this.onRouteParsed});
//
//   Future<void> pickAndParseGarminFpl(BuildContext context) async {
//     try {
//       final result = await FilePicker.platform.pickFiles(
//         type: FileType.custom,
//         allowedExtensions: ['fpl'],
//         withData: !kIsWeb, // Read bytes on web, use path on mobile
//       );
//
//       if (result == null) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('File picking cancelled.'))
//         );
//         return;
//       }
//
//       String? fileContent;
//
//       if (kIsWeb) {
//         // On Web, file bytes are available directly.
//         if (result.files.single.bytes != null) {
//           fileContent = String.fromCharCodes(result.files.single.bytes!);
//         }
//       } else {
//         // On Mobile (Android/iOS), read from the file path.
//         if (result.files.single.path != null) {
//           final filePath = result.files.single.path!;
//           fileContent = await File(filePath).readAsString();
//         }
//       }
//
//       if (fileContent != null) {
//         final document = XmlDocument.parse(fileContent);
//         final waypoints = document.findAllElements('waypoint');
//        
//         final routePoints = <LatLng>[];
//         for (final waypoint in waypoints) {
//           final latElement = waypoint.findElements('lat').singleOrNull;
//           final lonElement = waypoint.findElements('lon').singleOrNull;
//
//           if (latElement != null && lonElement != null) {
//             final lat = double.tryParse(latElement.innerText);
//             final lon = double.tryParse(lonElement.innerText);
//            
//             if (lat != null && lon != null) {
//               routePoints.add(LatLng(lat, lon));
//             }
//           }
//         }
//        
//         onRouteParsed(routePoints);
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Route with ${routePoints.length} waypoints loaded.'))
//         );
//       } else {
//          ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Could not read the selected file.'))
//         );
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Error parsing file: $e'))
//       );
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return ElevatedButton.icon(
//       icon: const Icon(Icons.file_upload),
//       label: const Text('Import Garmin .fpl Route'),
//       onPressed: () => pickAndParseGarminFpl(context),
//       style: ElevatedButton.styleFrom(
//         foregroundColor: Colors.white, 
//         backgroundColor: Colors.cyan,
//       ),
//     );
//   }
// }
