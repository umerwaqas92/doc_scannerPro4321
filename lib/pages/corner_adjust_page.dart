import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/scan_pipeline_models.dart';
import '../services/open_cv_document_analyzer.dart';
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
  static const double _autoDetectMinConfidence = 0.35;
  final OpenCvDocumentAnalyzer _analyzer = OpenCvDocumentAnalyzer();
  Size? _imageSize;
  late List<ScanCorner> _corners;
  bool _loading = true;
  bool _detectingAuto = false;
  double? _lastDetectConfidence;
  bool _lastDetectFallback = false;

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
          } else {
            _corners = _normalizeCorners(_corners, _imageSize!);
          }
          _loading = false;
        });
      }
      await _runAutoDetect(showFeedback: false);
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

  List<ScanCorner> _normalizeCorners(List<ScanCorner> input, Size size) {
    final clamped = input
        .map(
          (c) => ScanCorner(
            c.x.clamp(0, size.width).toDouble(),
            c.y.clamp(0, size.height).toDouble(),
          ),
        )
        .toList(growable: false);

    final sorted = List<ScanCorner>.from(clamped)
      ..sort((a, b) => a.y.compareTo(b.y));
    final top = sorted.take(2).toList()..sort((a, b) => a.x.compareTo(b.x));
    final bottom = sorted.skip(2).toList()..sort((a, b) => a.x.compareTo(b.x));

    return [top[0], top[1], bottom[1], bottom[0]];
  }

  Future<void> _runAutoDetect({required bool showFeedback}) async {
    if (_detectingAuto || _imageSize == null) return;
    setState(() => _detectingAuto = true);
    try {
      final detected = await _analyzer.detectDocument(
        widget.imageFile,
        minConfidence: _autoDetectMinConfidence,
      );

      if (!mounted) return;

      setState(() {
        _lastDetectConfidence = detected.confidence;
        _lastDetectFallback = detected.isFallback;
      });

      if (!detected.isFallback && detected.corners.length == 4) {
        setState(() {
          _corners = _normalizeCorners(detected.corners, _imageSize!);
        });
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Corners auto-detected')),
          );
        }
      } else if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Auto detect failed. Adjust manually.')),
        );
      }
    } catch (_) {
      if (!mounted || !showFeedback) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto detect failed. Try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _detectingAuto = false);
      }
    }
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
            onPressed: _loading ? null : _applyAndClose,
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
                _buildAutoDetectStatus(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _detectingAuto
                              ? null
                              : () => _runAutoDetect(showFeedback: true),
                          icon: _detectingAuto
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_fix_high),
                          label: Text(
                            _detectingAuto ? 'Detecting...' : 'Auto Detect',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
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
                          onPressed: _applyAndClose,
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

  void _applyAndClose() {
    if (_imageSize == null) {
      Navigator.pop(context, _corners);
      return;
    }
    final normalized = _normalizeCorners(_corners, _imageSize!);
    Navigator.pop(context, normalized);
  }

  Widget _buildAutoDetectStatus() {
    if (_lastDetectConfidence == null) return const SizedBox(height: 8);
    final confidencePct = (_lastDetectConfidence! * 100).clamp(0, 100).round();
    final success = !_lastDetectFallback && _lastDetectConfidence! >= 0.55;
    final medium = !_lastDetectFallback && _lastDetectConfidence! >= 0.35;
    final color = success
        ? Colors.green
        : medium
        ? Colors.orange
        : Colors.redAccent;
    final text = success
        ? 'Auto detect: Good ($confidencePct%)'
        : medium
        ? 'Auto detect: Medium ($confidencePct%)'
        : 'Auto detect: Low ($confidencePct%) - adjust manually';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
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
