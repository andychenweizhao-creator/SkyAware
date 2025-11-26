import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../../../Service/terrain_engine.dart';

class TerrainProfilePainter extends CustomPainter {
  final List<TerrainSample> samples;
  final double recommendedAltitude;

  TerrainProfilePainter(this.samples, this.recommendedAltitude);

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final paint = Paint()
      ..color = Colors.orangeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final maxElev = samples.map((e) => e.elevationFt).reduce(math.max);
    final scale = size.height / (math.max(maxElev, recommendedAltitude) * 1.2);
    final path = ui.Path();
    for (int i = 0; i < samples.length; i++) {
      final x = (i / (samples.length - 1)) * size.width;
      final y = size.height - (samples[i].elevationFt * scale);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
    canvas.drawLine(
        Offset(0, size.height - recommendedAltitude * scale),
        Offset(size.width, size.height - recommendedAltitude * scale),
        Paint()
          ..color = Colors.blue
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
