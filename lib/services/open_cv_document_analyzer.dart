import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/scan_pipeline_models.dart';

/// OpenCV-style analyzer API.
/// This implementation remains pure Dart while following scanner-style steps:
/// grayscale -> contrast boost -> blur -> edge detection -> largest quad.
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

    final scaled = _resizeForAnalysis(decoded, maxDim: 1200);
    final prepared = _prepareForDetection(scaled);
    final edges = _buildEdgeMask(prepared);
    if (edges.edgeCount == 0) {
      return _fallbackForSize(decoded.width, decoded.height);
    }

    final candidates = _extractRectangleCandidates(edges);
    if (candidates.isEmpty) {
      return _fallbackForSize(decoded.width, decoded.height);
    }

    _RectCandidate best = candidates.first;
    for (final candidate in candidates.skip(1)) {
      if (candidate.score > best.score) {
        best = candidate;
      }
    }

    final corners = _scaleCorners(
      best.corners,
      fromWidth: scaled.width,
      fromHeight: scaled.height,
      toWidth: decoded.width,
      toHeight: decoded.height,
    );

    final geometryConfidence = _computeGeometryConfidence(
      corners,
      imageWidth: decoded.width,
      imageHeight: decoded.height,
      edgeCount: best.edgeCount,
      analyzedWidth: scaled.width,
      analyzedHeight: scaled.height,
    );
    final confidence = (0.68 * best.score + 0.32 * geometryConfidence).clamp(
      0.0,
      1.0,
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

  img.Image _prepareForDetection(img.Image source) {
    var working = img.grayscale(source);
    working = img.adjustColor(working, contrast: 1.35, brightness: 1.03);
    working = img.gaussianBlur(working, radius: 1);
    return working;
  }

  _EdgeMap _buildEdgeMask(img.Image gray) {
    final width = gray.width;
    final height = gray.height;
    if (width < 4 || height < 4) {
      return _EdgeMap(
        width: width,
        height: height,
        mask: Uint8List(0),
        edgeCount: 0,
      );
    }

    final magnitudes = Float64List((width - 2) * (height - 2));
    var idx = 0;
    var sum = 0.0;

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

        final mag = math.sqrt(gx * gx + gy * gy);
        magnitudes[idx++] = mag;
        sum += mag;
      }
    }

    final mean = sum / magnitudes.length;
    var variance = 0.0;
    for (final value in magnitudes) {
      final delta = value - mean;
      variance += delta * delta;
    }
    variance /= magnitudes.length;
    final std = math.sqrt(variance);
    final threshold = (mean + std * 0.95).clamp(24.0, 255.0);

    final mask = Uint8List(width * height);
    idx = 0;
    var edgeCount = 0;
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        if (magnitudes[idx++] >= threshold) {
          mask[y * width + x] = 1;
          edgeCount++;
        }
      }
    }

    return _EdgeMap(
      width: width,
      height: height,
      mask: mask,
      edgeCount: edgeCount,
    );
  }

  List<_RectCandidate> _extractRectangleCandidates(_EdgeMap edges) {
    final width = edges.width;
    final height = edges.height;
    if (width <= 0 || height <= 0) return const [];

    final visited = Uint8List(width * height);
    final minPixels = (width * height * 0.0009).round().clamp(40, 8000);
    final candidates = <_RectCandidate>[];

    final queue = <int>[];
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final startIndex = y * width + x;
        if (edges.mask[startIndex] == 0 || visited[startIndex] == 1) continue;

        queue
          ..clear()
          ..add(startIndex);
        visited[startIndex] = 1;
        var head = 0;

        var count = 0;
        var minX = x;
        var maxX = x;
        var minY = y;
        var maxY = y;

        _IntPoint topLeft = _IntPoint(x, y);
        _IntPoint topRight = _IntPoint(x, y);
        _IntPoint bottomRight = _IntPoint(x, y);
        _IntPoint bottomLeft = _IntPoint(x, y);
        var minSum = double.infinity;
        var maxSum = -double.infinity;
        var minDiff = double.infinity;
        var maxDiff = -double.infinity;

        while (head < queue.length) {
          final current = queue[head++];
          final cx = current % width;
          final cy = current ~/ width;
          count++;

          if (cx < minX) minX = cx;
          if (cx > maxX) maxX = cx;
          if (cy < minY) minY = cy;
          if (cy > maxY) maxY = cy;

          final sum = (cx + cy).toDouble();
          final diff = (cx - cy).toDouble();
          if (sum < minSum) {
            minSum = sum;
            topLeft = _IntPoint(cx, cy);
          }
          if (sum > maxSum) {
            maxSum = sum;
            bottomRight = _IntPoint(cx, cy);
          }
          if (diff > maxDiff) {
            maxDiff = diff;
            topRight = _IntPoint(cx, cy);
          }
          if (diff < minDiff) {
            minDiff = diff;
            bottomLeft = _IntPoint(cx, cy);
          }

          for (int ny = cy - 1; ny <= cy + 1; ny++) {
            if (ny < 1 || ny >= height - 1) continue;
            final rowBase = ny * width;
            for (int nx = cx - 1; nx <= cx + 1; nx++) {
              if (nx < 1 || nx >= width - 1) continue;
              final next = rowBase + nx;
              if (visited[next] == 1 || edges.mask[next] == 0) continue;
              visited[next] = 1;
              queue.add(next);
            }
          }
        }

        if (count < minPixels) continue;

        final bboxWidth = maxX - minX + 1;
        final bboxHeight = maxY - minY + 1;
        final bboxAreaRatio = (bboxWidth * bboxHeight) / (width * height);
        if (bboxAreaRatio < 0.08) continue;

        final corners = _orderCorners([
          ScanCorner(topLeft.x.toDouble(), topLeft.y.toDouble()),
          ScanCorner(topRight.x.toDouble(), topRight.y.toDouble()),
          ScanCorner(bottomRight.x.toDouble(), bottomRight.y.toDouble()),
          ScanCorner(bottomLeft.x.toDouble(), bottomLeft.y.toDouble()),
        ]);

        final area = _polygonArea(corners);
        final areaRatio = area / (width * height);
        if (areaRatio < 0.12) continue;

        final score = _scoreCandidate(
          corners: corners,
          width: width,
          height: height,
          edgePixels: count,
        );

        candidates.add(
          _RectCandidate(corners: corners, score: score, edgeCount: count),
        );
      }
    }

    return candidates;
  }

  double _scoreCandidate({
    required List<ScanCorner> corners,
    required int width,
    required int height,
    required int edgePixels,
  }) {
    final areaRatio = _polygonArea(corners) / (width * height);
    final areaScore = ((areaRatio - 0.1) / 0.7).clamp(0.0, 1.0);

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
    final geometryScore =
        ((widthConsistency + heightConsistency + angleScore) / 3.0).clamp(
          0.0,
          1.0,
        );

    final centerX =
        (corners[0].x + corners[1].x + corners[2].x + corners[3].x) / 4;
    final centerY =
        (corners[0].y + corners[1].y + corners[2].y + corners[3].y) / 4;
    final dx = centerX - width / 2;
    final dy = centerY - height / 2;
    final maxDistance = math.sqrt(
      (width / 2) * (width / 2) + (height / 2) * (height / 2),
    );
    final centerScore = (1.0 - math.sqrt(dx * dx + dy * dy) / maxDistance)
        .clamp(0.0, 1.0);

    final edgeDensityScore = (edgePixels / (width * height * 0.028)).clamp(
      0.0,
      1.0,
    );

    final borderPadX = width * 0.018;
    final borderPadY = height * 0.018;
    final touchesBorders =
        corners.where((c) {
          return c.x < borderPadX ||
              c.x > width - borderPadX ||
              c.y < borderPadY ||
              c.y > height - borderPadY;
        }).length >=
        3;
    final borderPenalty = touchesBorders ? 0.14 : 0.0;

    return (0.42 * areaScore +
            0.30 * geometryScore +
            0.16 * centerScore +
            0.12 * edgeDensityScore -
            borderPenalty)
        .clamp(0.0, 1.0);
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
    return corners
        .map(
          (c) => ScanCorner(
            (c.x * scaleX).clamp(0.0, toWidth.toDouble()),
            (c.y * scaleY).clamp(0.0, toHeight.toDouble()),
          ),
        )
        .toList(growable: false);
  }

  double _computeGeometryConfidence(
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

    return (0.44 * areaScore + 0.24 * edgeScore + 0.32 * geometricScore).clamp(
      0.0,
      1.0,
    );
  }

  double _rightAngleScore(List<ScanCorner> c) {
    final vTop = _vec(c[0], c[1]);
    final vLeft = _vec(c[0], c[3]);
    final dot = (vTop.$1 * vLeft.$1 + vTop.$2 * vLeft.$2).abs();
    final mag =
        math.sqrt(vTop.$1 * vTop.$1 + vTop.$2 * vTop.$2) *
        math.sqrt(vLeft.$1 * vLeft.$1 + vLeft.$2 * vLeft.$2);
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

class _EdgeMap {
  final int width;
  final int height;
  final Uint8List mask;
  final int edgeCount;

  const _EdgeMap({
    required this.width,
    required this.height,
    required this.mask,
    required this.edgeCount,
  });
}

class _RectCandidate {
  final List<ScanCorner> corners;
  final double score;
  final int edgeCount;

  const _RectCandidate({
    required this.corners,
    required this.score,
    required this.edgeCount,
  });
}

class _IntPoint {
  final int x;
  final int y;

  const _IntPoint(this.x, this.y);
}
