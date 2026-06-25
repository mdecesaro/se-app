import 'dart:math' as math;
import 'package:flutter/material.dart';

class SensorDefinition {
  final int id;
  final double x;
  final double y;
  final String sector;
  final String expectedFoot;

  SensorDefinition({
    required this.id,
    required this.x,
    required this.y,
    required this.sector,
    required this.expectedFoot,
  });
}

class MatPainter extends CustomPainter {
  final List<SensorDefinition> sensors;
  final Set<int> activeTargets;
  final String correctColor;
  final Map<int, String> distractors;

  MatPainter({
    required this.sensors,
    required this.activeTargets,
    required this.correctColor,
    required this.distractors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final double scale = size.shortestSide / 75;

    final double hexSize = 7.5 * scale;
    final double rectWidth = 6.0 * scale;
    final double rectHeight = 1.2 * scale;
    final double rectOffsetDeltaY = -4.5 * scale;

    Color parseColor(String colorStr, Color fallback) {
      try {
        String hex = colorStr.replaceAll('#', '');
        if (hex.length == 6) return Color(int.parse("0xFF$hex"));
        return fallback;
      } catch (_) {
        return fallback;
      }
    }

    final Color targetColor = parseColor(correctColor, Colors.orange);

    for (var sensor in sensors) {
      final pos = Offset(center.dx + (sensor.x * scale), center.dy + (sensor.y * scale));

      bool isTarget = activeTargets.contains(sensor.id);
      bool isDistractor = distractors.containsKey(sensor.id);

      Color activeColor = isDistractor
          ? parseColor(distractors[sensor.id]!, Colors.red)
          : targetColor;

      final hexPaint = Paint()
        ..color = Colors.white.withOpacity(0.02)
        ..style = PaintingStyle.fill;

      final hexOutlinePaint = Paint()
        ..color = isTarget
            ? Colors.orangeAccent
            : isDistractor
            ? activeColor.withOpacity(0.5)
            : Colors.orange.withOpacity(0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (isTarget || isDistractor) ? 2.0 : 0.8;

      _drawHex(canvas, pos, hexSize, hexPaint, hexOutlinePaint);

      final rectPaint = Paint()
        ..color = (isTarget || isDistractor) ? activeColor : Colors.white.withOpacity(0.05)
        ..style = PaintingStyle.fill;

      final rect = Rect.fromCenter(
        center: Offset(pos.dx, pos.dy + rectOffsetDeltaY),
        width: rectWidth,
        height: rectHeight,
      );

      if (isTarget || isDistractor) {
        final shadowPaint = Paint()
          ..color = activeColor.withOpacity(0.4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 * scale);

        canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(pos.dx, pos.dy + rectOffsetDeltaY),
                width: rectWidth + (1.0 * scale),
                height: rectHeight + (1.0 * scale),
              ),
              Radius.circular(1.5 * scale),
            ),
            shadowPaint);
      }

      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(1.0 * scale)), rectPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${sensor.id}',
          style: TextStyle(
              color: Colors.white24,
              fontSize: 4.5 * scale,
              fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, pos - Offset(textPainter.width / 2, -textPainter.height / 6));
    }
  }

  void _drawHex(Canvas canvas, Offset center, double size, Paint fill, Paint stroke) {
    final path = Path();
    final double roundingDist = size * 0.1;

    List<Offset> vertices = [];
    for (int i = 0; i < 6; i++) {
      double angle = i * 60 * math.pi / 180;
      vertices.add(Offset(
        center.dx + size * math.cos(angle),
        center.dy + size * math.sin(angle),
      ));
    }

    for (int i = 0; i < 6; i++) {
      Offset pPrev = vertices[(i + 5) % 6];
      Offset pCurr = vertices[i];
      Offset pNext = vertices[(i + 1) % 6];

      Offset p1 = pCurr + (pPrev - pCurr) * (roundingDist / size);
      Offset p2 = pCurr + (pNext - pCurr) * (roundingDist / size);

      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path.quadraticBezierTo(pCurr.dx, pCurr.dy, p2.dx, p2.dy);
    }
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant MatPainter oldDelegate) {
    return oldDelegate.activeTargets != activeTargets ||
        oldDelegate.correctColor != correctColor ||
        oldDelegate.distractors != distractors ||
        oldDelegate.sensors != sensors;
  }
}