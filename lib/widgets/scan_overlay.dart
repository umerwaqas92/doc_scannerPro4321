import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ScanOverlay extends StatelessWidget {
  final bool detected;
  final bool showGrid;
  final double padding;

  const ScanOverlay({
    super.key,
    required this.detected,
    required this.showGrid,
    this.padding = 24,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScanOverlayPainter(
        detected: detected,
        showGrid: showGrid,
        padding: padding,
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  final bool detected;
  final bool showGrid;
  final double padding;

  _ScanOverlayPainter({
    required this.detected,
    required this.showGrid,
    required this.padding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      padding,
      padding * 1.2,
      size.width - padding * 2,
      size.height - padding * 2.8,
    );

    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = 1;
      final thirdW = rect.width / 3;
      final thirdH = rect.height / 3;
      for (int i = 1; i <= 2; i++) {
        canvas.drawLine(
          Offset(rect.left + thirdW * i, rect.top),
          Offset(rect.left + thirdW * i, rect.bottom),
          gridPaint,
        );
        canvas.drawLine(
          Offset(rect.left, rect.top + thirdH * i),
          Offset(rect.right, rect.top + thirdH * i),
          gridPaint,
        );
      }
    }

    final cornerPaint = Paint()
      ..color = detected
          ? AppColors.green
          : Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    if (detected) {
      final glowPaint = Paint()
        ..color = AppColors.green.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        glowPaint,
      );
    }

    const cornerSize = 24.0;
    _drawCorner(canvas, rect.topLeft, cornerSize, cornerPaint, true, true);
    _drawCorner(canvas, rect.topRight, cornerSize, cornerPaint, false, true);
    _drawCorner(canvas, rect.bottomLeft, cornerSize, cornerPaint, true, false);
    _drawCorner(
      canvas,
      rect.bottomRight,
      cornerSize,
      cornerPaint,
      false,
      false,
    );
  }

  void _drawCorner(
    Canvas canvas,
    Offset origin,
    double size,
    Paint paint,
    bool left,
    bool top,
  ) {
    final dx = left ? 1 : -1;
    final dy = top ? 1 : -1;
    final p1 = origin;
    final p2 = Offset(origin.dx + size * dx, origin.dy);
    final p3 = Offset(origin.dx, origin.dy + size * dy);
    canvas.drawLine(p1, p2, paint);
    canvas.drawLine(p1, p3, paint);
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) {
    return detected != oldDelegate.detected ||
        showGrid != oldDelegate.showGrid ||
        padding != oldDelegate.padding;
  }
}
