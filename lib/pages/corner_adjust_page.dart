import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/scan_pipeline_models.dart';
import '../theme/app_theme.dart';

class CornerAdjustPage extends StatefulWidget {
  final File imageFile;
  final List<ScanCorner> initialCorners;

  const CornerAdjustPage({
    super.key,
    required this.imageFile,
    required this.initialCorners,
  });

  @override
  State<CornerAdjustPage> createState() => _CornerAdjustPageState();
}

class _CornerAdjustPageState extends State<CornerAdjustPage> {
  Size? _imageSize;
  late List<ScanCorner> _corners;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _corners = List<ScanCorner>.from(widget.initialCorners);
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      if (mounted) {
        setState(() {
          _imageSize = Size(
            decoded.width.toDouble(),
            decoded.height.toDouble(),
          );
          if (_corners.length != 4) {
            _corners = _defaultCorners(_imageSize!);
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  List<ScanCorner> _defaultCorners(Size size) {
    final marginX = size.width * 0.08;
    final marginY = size.height * 0.1;
    return [
      ScanCorner(marginX, marginY),
      ScanCorner(size.width - marginX, marginY),
      ScanCorner(size.width - marginX, size.height - marginY),
      ScanCorner(marginX, size.height - marginY),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Adjust Corners'),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context, _corners),
            child: const Text(
              'Apply',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: _loading || _imageSize == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final imageW = _imageSize!.width;
                        final imageH = _imageSize!.height;
                        final scale = math.min(
                          constraints.maxWidth / imageW,
                          constraints.maxHeight / imageH,
                        );

                        final drawW = imageW * scale;
                        final drawH = imageH * scale;
                        final offsetX = (constraints.maxWidth - drawW) / 2;
                        final offsetY = (constraints.maxHeight - drawH) / 2;

                        Offset toView(ScanCorner c) => Offset(
                          offsetX + c.x * scale,
                          offsetY + c.y * scale,
                        );

                        ScanCorner fromView(Offset o) {
                          final vx = o.dx.clamp(offsetX, offsetX + drawW);
                          final vy = o.dy.clamp(offsetY, offsetY + drawH);
                          return ScanCorner(
                            (vx - offsetX) / scale,
                            (vy - offsetY) / scale,
                          );
                        }

                        return Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.file(
                                  widget.imageFile,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _CornerLinesPainter(
                                  points: _corners.map(toView).toList(),
                                ),
                              ),
                            ),
                            ...List.generate(_corners.length, (index) {
                              final point = toView(_corners[index]);
                              return Positioned(
                                left: point.dx - 14,
                                top: point.dy - 14,
                                child: GestureDetector(
                                  onPanUpdate: (details) {
                                    setState(() {
                                      final current = toView(_corners[index]);
                                      final moved = current + details.delta;
                                      _corners[index] = fromView(moved);
                                    });
                                  },
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: AppColors.green,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            if (_imageSize == null) return;
                            setState(() {
                              _corners = _defaultCorners(_imageSize!);
                            });
                          },
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, _corners),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.text,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Apply Crop'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _CornerLinesPainter extends CustomPainter {
  final List<Offset> points;

  const _CornerLinesPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) return;
    final paint = Paint()
      ..color = AppColors.green
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerLinesPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
