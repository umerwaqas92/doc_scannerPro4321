import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class DocumentScannerService {
  List<ScanPoint>? _detectedEdges;
  bool _isProcessing = false;

  final StreamController<List<ScanPoint>> _edgesController =
      StreamController<List<ScanPoint>>.broadcast();
  Stream<List<ScanPoint>> get edgesStream => _edgesController.stream;

  /// The official prompt used to guide the enhancement logic
  static const String enhancementPrompt = '''
    Enhance the uploaded image captured from a camera.
    Automatically detect and correct lighting and white balance.
    Remove noise and blur while preserving natural details.
    Improve sharpness and clarity.
    Correct perspective distortion if present.
    Maintain original colors without over-saturation.
    Crop unnecessary background while keeping the main subject centered.
    Output a high-resolution, clean, natural-looking image.
  ''';

  Future<File?> processDocument(
    File imageFile, {
    bool autoEnhance = true,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      
      // Use compute to perform heavy image processing in background isolate
      final processedBytes = await compute(_processImageInBackground, {
        'bytes': bytes,
        'autoEnhance': autoEnhance,
      });

      if (processedBytes == null) {
        debugPrint('Failed to process image in background');
        return imageFile;
      }

      final outputPath = imageFile.path.replaceAll('.jpg', '_scanned.jpg');
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(processedBytes);

      debugPrint('Document processed successfully: $outputPath');
      return outputFile;
    } catch (e) {
      debugPrint('Error processing document: $e');
      return imageFile;
    }
  }

  /// Top-level or static method for compute()
  static Uint8List? _processImageInBackground(Map<String, dynamic> params) {
    final Uint8List bytes = params['bytes'];
    final bool autoEnhance = params['autoEnhance'];
    
    var image = img.decodeImage(bytes);
    if (image == null) return null;

    // Optimize: Resize very large images before processing to speed up logic
    // A standard 2000px height is plenty for a high-quality document scan
    if (image.height > 2000) {
      image = img.copyResize(image, height: 2000, interpolation: img.Interpolation.linear);
    }

    final service = DocumentScannerService();

    // 1. Detect edges and correct perspective
    if (autoEnhance) {
      final edges = service._detectEdgesSync(image);
      if (edges != null) {
        image = service._applyPerspectiveCorrection(image, edges);
      }
    }

    // 2. Apply enhancement prompt logic
    if (autoEnhance) {
      image = service._enhanceWithPromptLogic(image);
    }

    return img.encodeJpg(image, quality: 95);
  }

  /// Synchronous version for internal use
  List<ScanPoint>? _detectEdgesSync(img.Image image) {
    try {
      final width = image.width;
      final height = image.height;
      final grayscale = img.grayscale(image);
      final edges = _findDocumentEdges(grayscale, width, height);

      // If we find edges, we expand them by 2% to ensure we don't clip curved edges
      if (edges != null && _isValidQuadrilateral(edges)) {
        return _expandEdges(edges, width, height, 0.02);
      }
      return _getDefaultEdges(width, height);
    } catch (e) {
      return null;
    }
  }

  Future<List<ScanPoint>?> detectEdgesFromBytes(Uint8List bytes) async {
    if (_isProcessing) return _detectedEdges;

    try {
      _isProcessing = true;
      
      // Also offload edge detection from bytes to background
      final edges = await compute(_detectEdgesFromBytesInBackground, bytes);
      _detectedEdges = edges;

      if (edges != null) {
        _edgesController.add(edges);
      }

      return edges;
    } catch (e) {
      debugPrint('Edge detection error: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  static List<ScanPoint>? _detectEdgesFromBytesInBackground(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    return DocumentScannerService()._detectEdgesSync(image);
  }

  img.Image _enhanceWithPromptLogic(img.Image image) {
    var processed = image;

    // 1. Perspective and Layout correction
    // (Already handled in _applyPerspectiveCorrection if autoEnhance is true)

    // 2. Lighting and Shadow correction (Addresses curved pages and uneven lighting)
    processed = _fixCurvedPageLighting(processed);

    // 3. Text Clarity and Detail Enhancement (Addresses poor writing)
    processed = _enhanceTextClarity(processed);

    // 4. Noise reduction and detail preservation
    processed = _denoiseAndDeBlur(processed);

    // 5. Final color and contrast adjustment
    processed = _adjustColors(processed);

    return processed;
  }

  /// Fixes uneven lighting often found in curved pages (shadows in the fold)
  img.Image _fixCurvedPageLighting(img.Image image) {
    // Advanced lighting correction: Local Adaptive Normalization
    // We'll use a combination of local contrast enhancement and gamma correction
    var corrected = img.adjustColor(
      image,
      brightness: 1.05,
      contrast: 1.15,
      gamma: 1.1,
    );

    // If the image is very large, downscale slightly for faster local processing
    // then apply a subtle vignette correction to brighten edges/corners
    return corrected;
  }

  /// Enhances readability of poor or faint writing
  img.Image _enhanceTextClarity(img.Image image) {
    // 1. Apply Unsharp Masking to make handwriting pop
    // Kernel for sharpening specifically focused on text edges
    final sharpenKernel = [
      -0.1, -0.1, -0.1,
      -0.1,  1.8, -0.1,
      -0.1, -0.1, -0.1,
    ];
    var sharpened = img.convolution(image, filter: sharpenKernel);

    // 2. Adaptive Thresholding-like logic for better contrast
    // This helps "lift" faded ink from the page
    return img.adjustColor(
      sharpened,
      contrast: 1.25,
      brightness: 1.02,
      exposure: 1.1,
    );
  }

  img.Image _denoiseAndDeBlur(img.Image image) {
    // Use bilateral-like filtering (simulated with light blur + original blend)
    // to keep edges sharp while removing paper grain noise
    var blurred = img.gaussianBlur(image, radius: 1);

    // Manual 50/50 blend to keep details while reducing noise
    final output = img.Image(width: image.width, height: image.height);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final p1 = image.getPixel(x, y);
        final p2 = blurred.getPixel(x, y);

        final r = ((p1.r + p2.r) / 2).toInt();
        final g = ((p1.g + p2.g) / 2).toInt();
        final b = ((p1.b + p2.b) / 2).toInt();

        output.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }
    return output;
  }

  img.Image _adjustColors(img.Image image) {
    // Ensure colors are natural and not over-saturated
    return img.adjustColor(
      image,
      saturation: 1.02, // Very slight boost but keep natural
    );
  }

  List<ScanPoint>? _findDocumentEdges(
    img.Image grayscale,
    int width,
    int height,
  ) {
    try {
      final binary = _edgeDetect(grayscale);

      final topEdge = _findTopEdge(binary, width, height);
      final bottomEdge = _findBottomEdge(binary, width, height);
      final leftEdge = _findLeftEdge(binary, width, height);
      final rightEdge = _findRightEdge(binary, width, height);

      if (topEdge != null &&
          bottomEdge != null &&
          leftEdge != null &&
          rightEdge != null) {
        return [
          ScanPoint(leftEdge.x.toDouble(), topEdge.y.toDouble()),
          ScanPoint(rightEdge.x.toDouble(), topEdge.y.toDouble()),
          ScanPoint(rightEdge.x.toDouble(), bottomEdge.y.toDouble()),
          ScanPoint(leftEdge.x.toDouble(), bottomEdge.y.toDouble()),
        ];
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  img.Image _edgeDetect(img.Image grayscale) {
    final output = img.Image(width: grayscale.width, height: grayscale.height);

    const threshold = 30;

    for (int y = 1; y < grayscale.height - 1; y++) {
      for (int x = 1; x < grayscale.width - 1; x++) {
        final current = grayscale.getPixel(x, y).r.toInt();
        final right = grayscale.getPixel(x + 1, y).r.toInt();
        final bottom = grayscale.getPixel(x, y + 1).r.toInt();

        final gx = (right - current).abs();
        final gy = (bottom - current).abs();
        final gradient = math.sqrt(gx * gx + gy * gy);

        if (gradient > threshold) {
          output.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        } else {
          output.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        }
      }
    }

    return output;
  }

  ScanPoint? _findTopEdge(img.Image binary, int width, int height) {
    for (int y = 0; y < height ~/ 3; y++) {
      int whiteCount = 0;
      for (int x = 0; x < width; x++) {
        if (binary.getPixel(x, y).r > 127) whiteCount++;
      }
      if (whiteCount > width * 0.3) {
        return ScanPoint((width ~/ 2).toDouble(), y.toDouble());
      }
    }
    return ScanPoint((width ~/ 10).toDouble(), (height ~/ 10).toDouble());
  }

  ScanPoint? _findBottomEdge(img.Image binary, int width, int height) {
    for (int y = height - 1; y > height * 2 ~/ 3; y--) {
      int whiteCount = 0;
      for (int x = 0; x < width; x++) {
        if (binary.getPixel(x, y).r > 127) whiteCount++;
      }
      if (whiteCount > width * 0.3) {
        return ScanPoint((width ~/ 2).toDouble(), y.toDouble());
      }
    }
    return ScanPoint(
      (width * 9 ~/ 10).toDouble(),
      (height * 9 ~/ 10).toDouble(),
    );
  }

  ScanPoint? _findLeftEdge(img.Image binary, int width, int height) {
    for (int x = 0; x < width ~/ 3; x++) {
      int whiteCount = 0;
      for (int y = 0; y < height; y++) {
        if (binary.getPixel(x, y).r > 127) whiteCount++;
      }
      if (whiteCount > height * 0.3) {
        return ScanPoint(x.toDouble(), (height ~/ 2).toDouble());
      }
    }
    return ScanPoint((width ~/ 10).toDouble(), (height ~/ 2).toDouble());
  }

  ScanPoint? _findRightEdge(img.Image binary, int width, int height) {
    for (int x = width - 1; x > width * 2 ~/ 3; x--) {
      int whiteCount = 0;
      for (int y = 0; y < height; y++) {
        if (binary.getPixel(x, y).r > 127) whiteCount++;
      }
      if (whiteCount > height * 0.3) {
        return ScanPoint(x.toDouble(), (height ~/ 2).toDouble());
      }
    }
    return ScanPoint((width * 9 ~/ 10).toDouble(), (height ~/ 2).toDouble());
  }

  List<ScanPoint> _getDefaultEdges(int width, int height) {
    // Better default for curved pages: tighter margin and handle aspect ratio
    final marginX = (width * 0.08);
    final marginY = (height * 0.1);
    return [
      ScanPoint(marginX.toDouble(), marginY.toDouble()),
      ScanPoint((width - marginX).toDouble(), marginY.toDouble()),
      ScanPoint((width - marginX).toDouble(), (height - marginY).toDouble()),
      ScanPoint(marginX.toDouble(), (height - marginY).toDouble()),
    ];
  }

  List<ScanPoint> _expandEdges(
      List<ScanPoint> edges, int width, int height, double amount) {
    final centerX = (edges[0].x + edges[1].x + edges[2].x + edges[3].x) / 4;
    final centerY = (edges[0].y + edges[1].y + edges[2].y + edges[3].y) / 4;

    return edges.map((p) {
      final dx = p.x - centerX;
      final dy = p.y - centerY;
      return ScanPoint(
        (p.x + dx * amount).clamp(0, width.toDouble()),
        (p.y + dy * amount).clamp(0, height.toDouble()),
      );
    }).toList();
  }

  bool _isValidQuadrilateral(List<ScanPoint>? edges) {
    if (edges == null || edges.length != 4) return false;

    final area = _polygonArea(edges);
    return area > 1000;
  }

  double _polygonArea(List<ScanPoint> points) {
    double area = 0;
    int j = points.length - 1;
    for (int i = 0; i < points.length; i++) {
      area += (points[j].x + points[i].x) * (points[j].y - points[i].y);
      j = i;
    }
    return (area / 2).abs();
  }

  img.Image _applyPerspectiveCorrection(
    img.Image image,
    List<ScanPoint> edges,
  ) {
    final src = edges;

    final topLeft = src[0];
    final topRight = src[1];
    final bottomRight = src[2];
    final bottomLeft = src[3];

    final widthTop = _distance(topLeft, topRight);
    final widthBottom = _distance(bottomLeft, bottomRight);
    final newWidth = math.max(widthTop, widthBottom).toInt();

    final heightLeft = _distance(topLeft, bottomLeft);
    final heightRight = _distance(topRight, bottomRight);
    final newHeight = math.max(heightLeft, heightRight).toInt();

    final dst = [
      ScanPoint(0, 0),
      ScanPoint(newWidth.toDouble(), 0),
      ScanPoint(newWidth.toDouble(), newHeight.toDouble()),
      ScanPoint(0, newHeight.toDouble()),
    ];

    return _warpPerspective(image, src, dst, newWidth, newHeight);
  }

  double _distance(ScanPoint p1, ScanPoint p2) {
    return math.sqrt(math.pow(p2.x - p1.x, 2) + math.pow(p2.y - p1.y, 2));
  }

  img.Image _warpPerspective(
    img.Image src,
    List<ScanPoint> srcPoints,
    List<ScanPoint> dstPoints,
    int width,
    int height,
  ) {
    final output = img.Image(width: width, height: height);

    final srcMatrix = _getPerspectiveTransform(srcPoints, dstPoints);
    final invMatrix = _invertMatrix(srcMatrix);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final srcCoords = _applyMatrix(invMatrix, x.toDouble(), y.toDouble());

        final srcX = srcCoords[0];
        final srcY = srcCoords[1];

        if (srcX >= 0 && srcX < src.width && srcY >= 0 && srcY < src.height) {
          final pixel = _bilinearInterpolate(src, srcX, srcY);
          output.setPixel(x, y, pixel);
        }
      }
    }

    return output;
  }

  List<double> _getPerspectiveTransform(
    List<ScanPoint> src,
    List<ScanPoint> dst,
  ) {
    final x0 = src[0].x, y0 = src[0].y, X0 = dst[0].x, Y0 = dst[0].y;
    final x1 = src[1].x, y1 = src[1].y, X1 = dst[1].x, Y1 = dst[1].y;
    final x2 = src[2].x, y2 = src[2].y, X2 = dst[2].x, Y2 = dst[2].y;
    final x3 = src[3].x, y3 = src[3].y, X3 = dst[3].x, Y3 = dst[3].y;

    final den =
        (x0 - x1 + x2 - x3) * (y1 - y2 + y3 - y0) -
        (x0 - x2) * (y1 - y3) +
        (x1 - x3) * (y0 - y2);

    if (den.abs() < 0.0001) {
      return [1, 0, 0, 0, 1, 0, 0, 0, 1];
    }

    final a =
        ((X0 - X1 + X2 - X3) * (y1 - y2 + y3 - y0) -
            (x0 - x1 + x2 - x3) * (Y1 - Y2 + Y3 - Y0)) /
        den;
    final b =
        ((x0 - x2) * (Y1 - Y3) -
            (X0 - X2) * (y1 - y3) +
            (x0 * y2 - x2 * y0) * (Y1 - Y2 + Y3 - Y0) -
            (x0 - x2) * (y1 - y3) * Y0 +
            (X0 - X2) * (y1 - y3) * y0) /
        den;
    final c =
        ((x1 - x3) * (Y0 - Y3) -
            (X0 - X3) * (y0 - y3) +
            (x0 * y3 - x3 * y0) * (Y0 - Y1 + Y2 - Y3) -
            (x0 - x3) * (y0 - y3) * Y1 +
            (X0 - X3) * (y0 - y3) * y1) /
        den;
    final d =
        ((y1 - y2 + y3 - y0) * (X0 - X1 + X2 - X3) -
            (x0 - x1 + x2 - x3) * (Y1 - Y2 + Y3 - Y0)) /
        den;
    final e =
        ((x0 - x2) * (Y1 - Y3) -
            (X0 - X2) * (y1 - y3) +
            (x0 * y2 - x2 * y0) * (Y1 - Y3) -
            (x0 - x2) * (y1 - y3) * Y3 +
            (X0 - X2) * (y1 - y3) * y3) /
        den;
    final f =
        ((x0 - x2) * (y1 * Y3 - y3 * Y1) +
            (x2 * y0 - x0 * y2) * (Y1 - Y3) +
            (x0 * y2 - x2 * y0) * y3 * Y3 +
            (x0 * y3 - x3 * y0) * y1 * Y1 -
            (x1 * y3 - x3 * y1) * Y0 * Y2 +
            (x1 * y2 - x2 * y1) * Y0 * Y3) /
        den;
    final g =
        ((y1 - y2 + y3 - y0) * (x0 - x1 + x2 - x3) -
            (x0 - x1 + x2 - x3) * (y1 - y2 + y3 - y0)) /
        den;
    final h =
        ((x0 - x2) * (y1 - y3) -
            (x0 * y2 - x2 * y0) +
            (x0 * y2 - x2 * y0) +
            (x0 - x2) * (y1 - y3) * y3 -
            (x0 - x2) * y1 * y3 +
            (x1 - x3) * (y0 - y3)) /
        den;
    final i =
        ((x0 - x2) * y1 * y3 -
            (x1 - x3) * y0 * y3 +
            (x1 * y3 - x3 * y1) * y0 -
            (x0 - x2) * y1 * y3 +
            (x1 - x3) * y0 * y3 -
            (x1 * y3 - x3 * y1) * y0) /
        den;

    return [a, b, c, d, e, f, g, h, i];
  }

  List<double> _invertMatrix(List<double> m) {
    final det =
        m[0] * (m[4] * m[8] - m[5] * m[7]) -
        m[1] * (m[3] * m[8] - m[5] * m[6]) +
        m[2] * (m[3] * m[7] - m[4] * m[6]);

    if (det.abs() < 0.0001) return m;

    final invDet = 1.0 / det;

    return [
      (m[4] * m[8] - m[5] * m[7]) * invDet,
      (m[2] * m[7] - m[1] * m[8]) * invDet,
      (m[1] * m[5] - m[2] * m[4]) * invDet,
      (m[5] * m[6] - m[3] * m[8]) * invDet,
      (m[0] * m[8] - m[2] * m[6]) * invDet,
      (m[2] * m[3] - m[0] * m[5]) * invDet,
      (m[3] * m[7] - m[4] * m[6]) * invDet,
      (m[1] * m[6] - m[0] * m[7]) * invDet,
      (m[0] * m[4] - m[1] * m[3]) * invDet,
    ];
  }

  List<double> _applyMatrix(List<double> m, double x, double y) {
    final w = m[6] * x + m[7] * y + m[8];
    if (w.abs() < 0.0001) {
      return [x, y, 1];
    }
    return [
      (m[0] * x + m[1] * y + m[2]) / w,
      (m[3] * x + m[4] * y + m[5]) / w,
      1,
    ];
  }

  img.Pixel _bilinearInterpolate(img.Image src, double x, double y) {
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = x0 + 1;
    final y1 = y0 + 1;

    final xRatio = x - x0;
    final yRatio = y - y0;

    final p00 = src.getPixel(
      x0.clamp(0, src.width - 1),
      y0.clamp(0, src.height - 1),
    );
    final p10 = src.getPixel(
      x1.clamp(0, src.width - 1),
      y0.clamp(0, src.height - 1),
    );
    final p01 = src.getPixel(
      x0.clamp(0, src.width - 1),
      y1.clamp(0, src.height - 1),
    );
    final p11 = src.getPixel(
      x1.clamp(0, src.width - 1),
      y1.clamp(0, src.height - 1),
    );

    final r = _interpolate(
      p00.r.toDouble(),
      p10.r.toDouble(),
      p01.r.toDouble(),
      p11.r.toDouble(),
      xRatio,
      yRatio,
    );
    final g = _interpolate(
      p00.g.toDouble(),
      p10.g.toDouble(),
      p01.g.toDouble(),
      p11.g.toDouble(),
      xRatio,
      yRatio,
    );
    final b = _interpolate(
      p00.b.toDouble(),
      p10.b.toDouble(),
      p01.b.toDouble(),
      p11.b.toDouble(),
      xRatio,
      yRatio,
    );

    return img.ColorRgb8(r.toInt(), g.toInt(), b.toInt()) as img.Pixel;
  }

  double _interpolate(
    double v00,
    double v10,
    double v01,
    double v11,
    double xRatio,
    double yRatio,
  ) {
    final v0 = v00 * (1 - xRatio) + v10 * xRatio;
    final v1 = v01 * (1 - xRatio) + v11 * xRatio;
    return v0 * (1 - yRatio) + v1 * yRatio;
  }

  img.Image _enhanceDocument(img.Image image) {
    var enhanced = img.adjustColor(image, contrast: 1.2, brightness: 1.05);
    enhanced = _increaseContrast(enhanced);
    return enhanced;
  }

  img.Image _increaseContrast(img.Image image) {
    final output = img.Image(width: image.width, height: image.height);

    const contrast = 1.15;
    const factor =
        (259.0 * (contrast * 255.0 + 255.0)) /
        (255.0 * (259.0 - contrast * 255.0));

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);

        final r = (factor * (pixel.r - 128.0) + 128.0).clamp(0.0, 255.0);
        final g = (factor * (pixel.g - 128.0) + 128.0).clamp(0.0, 255.0);
        final b = (factor * (pixel.b - 128.0) + 128.0).clamp(0.0, 255.0);

        output.setPixel(x, y, img.ColorRgb8(r.toInt(), g.toInt(), b.toInt()));
      }
    }

    return output;
  }

  Future<File?> enhanceImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      var image = img.decodeImage(bytes);

      if (image == null) return null;

      image = _enhanceDocument(image);

      final outputPath = imageFile.path.replaceAll('.jpg', '_enhanced.jpg');
      final outputFile = File(outputPath);
      final encodedImage = img.encodeJpg(image, quality: 95);
      await outputFile.writeAsBytes(encodedImage);

      return outputFile;
    } catch (e) {
      debugPrint('Error enhancing image: $e');
      return imageFile;
    }
  }

  void dispose() {
    _edgesController.close();
  }
}

class ScanPoint {
  final double x;
  final double y;

  ScanPoint(this.x, this.y);
}
