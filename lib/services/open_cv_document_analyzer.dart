import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../models/scan_pipeline_models.dart';

/// OpenCV-style analyzer API.
/// This implementation is pure Dart and keeps the interface ready for native OpenCV swap-in.
class OpenCvDocumentAnalyzer {
  Future<DetectedDocument> detectDocument(
    File input, {
    double minConfidence = 0.5,
  }) async {
    final bytes = await input.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return _fallbackForSize(1000, 1400);
    }

    final scaled = _resizeForAnalysis(decoded, maxDim: 1400);
    final gray = img.grayscale(scaled);
    final blurred = img.gaussianBlur(gray, radius: 1);

    final points = _collectStrongEdgePoints(blurred);
    if (points.isEmpty) {
      final fallback = _fallbackForSize(decoded.width, decoded.height);
      return fallback;
    }

    final cornersScaled = _cornersFromExtremePoints(points);
    final corners = _scaleCorners(
      cornersScaled,
      fromWidth: scaled.width,
      fromHeight: scaled.height,
      toWidth: decoded.width,
      toHeight: decoded.height,
    );

    final confidence = _computeConfidence(
      corners,
      imageWidth: decoded.width,
      imageHeight: decoded.height,
      edgeCount: points.length,
      analyzedWidth: scaled.width,
      analyzedHeight: scaled.height,
    );

    if (confidence < minConfidence) {
      final fallback = _fallbackForSize(decoded.width, decoded.height);
      return DetectedDocument(
        corners: fallback.corners,
        confidence: confidence,
        isFallback: true,
      );
    }

    return DetectedDocument(
      corners: corners,
      confidence: confidence,
      isFallback: false,
    );
  }

  img.Image _resizeForAnalysis(img.Image source, {required int maxDim}) {
    final maxCurrent = math.max(source.width, source.height);
    if (maxCurrent <= maxDim) return source;

    final ratio = maxDim / maxCurrent;
    return img.copyResize(
      source,
      width: (source.width * ratio).round(),
      height: (source.height * ratio).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  List<_IntPoint> _collectStrongEdgePoints(img.Image gray) {
    final width = gray.width;
    final height = gray.height;
    if (width < 4 || height < 4) return const [];

    final magnitudes = <double>[];
    magnitudes.length = (width - 2) * (height - 2);
    int idx = 0;
    double sum = 0;

    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final gx =
            -gray.getPixel(x - 1, y - 1).r +
            gray.getPixel(x + 1, y - 1).r +
            -2 * gray.getPixel(x - 1, y).r +
            2 * gray.getPixel(x + 1, y).r +
            -gray.getPixel(x - 1, y + 1).r +
            gray.getPixel(x + 1, y + 1).r;

        final gy =
            gray.getPixel(x - 1, y - 1).r +
            2 * gray.getPixel(x, y - 1).r +
            gray.getPixel(x + 1, y - 1).r +
            -gray.getPixel(x - 1, y + 1).r +
            -2 * gray.getPixel(x, y + 1).r +
            -gray.getPixel(x + 1, y + 1).r;

        final mag = math.sqrt(gx * gx + gy * gy).toDouble();
        magnitudes[idx++] = mag;
        sum += mag;
      }
    }

    final mean = sum / magnitudes.length;
    double variance = 0;
    for (final m in magnitudes) {
      final d = m - mean;
      variance += d * d;
    }
    variance /= magnitudes.length;
    final std = math.sqrt(variance);
    final threshold = mean + std * 0.95;

    final points = <_IntPoint>[];
    idx = 0;
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        if (magnitudes[idx++] >= threshold) {
          points.add(_IntPoint(x, y));
        }
      }
    }

    return points;
  }

  List<ScanCorner> _cornersFromExtremePoints(List<_IntPoint> points) {
    _IntPoint topLeft = points.first;
    _IntPoint topRight = points.first;
    _IntPoint bottomRight = points.first;
    _IntPoint bottomLeft = points.first;

    double minSum = double.infinity;
    double maxSum = -double.infinity;
    double minDiff = double.infinity;
    double maxDiff = -double.infinity;

    for (final p in points) {
      final sum = (p.x + p.y).toDouble();
      final diff = (p.x - p.y).toDouble();

      if (sum < minSum) {
        minSum = sum;
        topLeft = p;
      }
      if (sum > maxSum) {
        maxSum = sum;
        bottomRight = p;
      }
      if (diff > maxDiff) {
        maxDiff = diff;
        topRight = p;
      }
      if (diff < minDiff) {
        minDiff = diff;
        bottomLeft = p;
      }
    }

    return _orderCorners([
      ScanCorner(topLeft.x.toDouble(), topLeft.y.toDouble()),
      ScanCorner(topRight.x.toDouble(), topRight.y.toDouble()),
      ScanCorner(bottomRight.x.toDouble(), bottomRight.y.toDouble()),
      ScanCorner(bottomLeft.x.toDouble(), bottomLeft.y.toDouble()),
    ]);
  }

  List<ScanCorner> _orderCorners(List<ScanCorner> corners) {
    final sorted = List<ScanCorner>.from(corners)
      ..sort((a, b) => a.y.compareTo(b.y));
    final top = sorted.take(2).toList()..sort((a, b) => a.x.compareTo(b.x));
    final bottom = sorted.skip(2).toList()..sort((a, b) => a.x.compareTo(b.x));
    return [top[0], top[1], bottom[1], bottom[0]];
  }

  List<ScanCorner> _scaleCorners(
    List<ScanCorner> corners, {
    required int fromWidth,
    required int fromHeight,
    required int toWidth,
    required int toHeight,
  }) {
    final scaleX = toWidth / fromWidth;
    final scaleY = toHeight / fromHeight;
    return corners.map((c) => ScanCorner(c.x * scaleX, c.y * scaleY)).toList();
  }

  double _computeConfidence(
    List<ScanCorner> corners, {
    required int imageWidth,
    required int imageHeight,
    required int edgeCount,
    required int analyzedWidth,
    required int analyzedHeight,
  }) {
    final area = _polygonArea(corners);
    final areaRatio = area / (imageWidth * imageHeight);
    final areaScore = ((areaRatio - 0.1) / 0.55).clamp(0.0, 1.0);

    final edgeDensity = edgeCount / (analyzedWidth * analyzedHeight);
    final edgeScore = (edgeDensity / 0.08).clamp(0.0, 1.0);

    final topWidth = _distance(corners[0], corners[1]);
    final bottomWidth = _distance(corners[3], corners[2]);
    final leftHeight = _distance(corners[0], corners[3]);
    final rightHeight = _distance(corners[1], corners[2]);

    final widthConsistency =
        1.0 -
        ((topWidth - bottomWidth).abs() / math.max(topWidth, bottomWidth));
    final heightConsistency =
        1.0 -
        ((leftHeight - rightHeight).abs() / math.max(leftHeight, rightHeight));
    final angleScore = _rightAngleScore(corners);

    final geometricScore =
        ((widthConsistency + heightConsistency + angleScore) / 3.0).clamp(
          0.0,
          1.0,
        );

    final confidence =
        (0.45 * areaScore + 0.25 * edgeScore + 0.30 * geometricScore).clamp(
          0.0,
          1.0,
        );
    return confidence;
  }

  double _rightAngleScore(List<ScanCorner> c) {
    final v1 = _vec(c[0], c[1]);
    final v2 = _vec(c[0], c[3]);
    final dot = (v1.$1 * v2.$1 + v1.$2 * v2.$2).abs();
    final mag =
        (math.sqrt(v1.$1 * v1.$1 + v1.$2 * v1.$2) *
        math.sqrt(v2.$1 * v2.$1 + v2.$2 * v2.$2));
    if (mag == 0) return 0;
    final cosTheta = (dot / mag).clamp(0.0, 1.0);
    return 1.0 - cosTheta;
  }

  (double, double) _vec(ScanCorner a, ScanCorner b) => (b.x - a.x, b.y - a.y);

  double _distance(ScanCorner a, ScanCorner b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _polygonArea(List<ScanCorner> points) {
    double area = 0;
    int j = points.length - 1;
    for (int i = 0; i < points.length; i++) {
      area += (points[j].x + points[i].x) * (points[j].y - points[i].y);
      j = i;
    }
    return (area / 2).abs();
  }

  DetectedDocument _fallbackForSize(int width, int height) {
    final marginX = width * 0.08;
    final marginY = height * 0.1;
    return DetectedDocument(
      corners: [
        ScanCorner(marginX, marginY),
        ScanCorner(width - marginX, marginY),
        ScanCorner(width - marginX, height - marginY),
        ScanCorner(marginX, height - marginY),
      ],
      confidence: 0.2,
      isFallback: true,
    );
  }
}

class _IntPoint {
  final int x;
  final int y;

  const _IntPoint(this.x, this.y);
}
